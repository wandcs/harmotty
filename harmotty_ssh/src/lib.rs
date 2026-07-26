use std::collections::HashMap;
use std::future::Future;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use napi_derive_ohos::napi;
use napi_ohos::bindgen_prelude::{spawn, Function, Uint8Array};
use napi_ohos::threadsafe_function::{ThreadsafeFunction, ThreadsafeFunctionCallMode};
use napi_ohos::{Error, Result, Status};
use zeroize::Zeroize;

use harmotty_ssh_core::keygen::{self};
use harmotty_ssh_core::AuthMethod;

static NEXT_SESSION_ID: AtomicU32 = AtomicU32::new(1);

type WriteSender = tokio::sync::mpsc::Sender<Vec<u8>>;
type ResizeSender = tokio::sync::mpsc::Sender<(u32, u32)>;
type AuthSender = tokio::sync::mpsc::Sender<AuthMethod>;
type DisconnectSender = tokio::sync::mpsc::Sender<()>;
type OutputPauseSender = tokio::sync::mpsc::Sender<bool>;
type JsCallback = Arc<ThreadsafeFunction<String, (), String, Status, false, false, 64>>;
type JsDataCallback = Arc<ThreadsafeFunction<Uint8Array, (), Uint8Array, Status, false, false, 64>>;

const FINAL_DELIVERY_RETRY_ATTEMPTS: u32 = 128;
const FINAL_DELIVERY_RETRY_DELAY: Duration = Duration::from_millis(16);
const SSH_KEEPALIVE_INTERVAL: Duration = Duration::from_secs(30);
const SSH_KEEPALIVE_MAX: usize = 3;

fn build_client_config() -> russh::client::Config {
    let mut config = russh::client::Config::default();
    config.keepalive_interval = Some(SSH_KEEPALIVE_INTERVAL);
    config.keepalive_max = SSH_KEEPALIVE_MAX;
    config
}

#[derive(Default)]
struct OutputDeliveryMetrics {
    received_bytes: u64,
    napi_queued_bytes: u64,
    callback_retries: u64,
    final_delivery_failures: u64,
    final_delivery_failed_bytes: u64,
    output_batches: u64,
}

impl OutputDeliveryMetrics {
    fn record_callback_attempt(&mut self, status: Status, output_len: u64) -> bool {
        if status == Status::Ok {
            self.napi_queued_bytes += output_len;
            self.output_batches += 1;
            return true;
        }
        self.callback_retries += 1;
        false
    }

    fn record_final_delivery_failure(&mut self, output_len: u64) {
        self.final_delivery_failures += 1;
        self.final_delivery_failed_bytes += output_len;
    }

    fn event(&self, output_paused: bool, final_snapshot: bool) -> String {
        format!(
            "OUTPUT_METRICS:received={},napiQueued={},callbackRetries={},\
             finalDeliveryFailures={},finalDeliveryFailedBytes={},batches={},paused={},final={}",
            self.received_bytes,
            self.napi_queued_bytes,
            self.callback_retries,
            self.final_delivery_failures,
            self.final_delivery_failed_bytes,
            self.output_batches,
            output_paused,
            final_snapshot
        )
    }
}

struct ShellSession {
    write_tx: WriteSender,
    resize_tx: ResizeSender,
    disconnect_tx: DisconnectSender,
    auth_tx: AuthSender,
    host_key_tx: tokio::sync::mpsc::Sender<bool>,
    output_pause_tx: OutputPauseSender,
}

type SessionMap = Arc<Mutex<HashMap<u32, ShellSession>>>;

fn get_sessions() -> &'static SessionMap {
    use once_cell::sync::Lazy;
    static SESSIONS: Lazy<SessionMap> = Lazy::new(|| Arc::new(Mutex::new(HashMap::new())));
    &SESSIONS
}

fn napi_error(message: &str) -> Error {
    Error::new(Status::GenericFailure, message)
}

fn remove_session(session_id: u32) {
    if let Ok(mut sessions) = get_sessions().lock() {
        sessions.remove(&session_id);
    }
}

struct SessionCleanupGuard(u32);

impl Drop for SessionCleanupGuard {
    fn drop(&mut self) {
        remove_session(self.0);
    }
}

fn try_send_callback(callback: &JsCallback, value: String, label: &str) -> bool {
    let status = callback.call(value, ThreadsafeFunctionCallMode::NonBlocking);
    if status != Status::Ok {
        eprintln!("[HTTY_SSH] callback={} status={}", label, status);
        return false;
    }
    true
}

fn try_send_data_callback(callback: &JsDataCallback, value: Vec<u8>) -> Status {
    let status = callback.call(value.into(), ThreadsafeFunctionCallMode::NonBlocking);
    if status != Status::Ok && status != Status::QueueFull {
        eprintln!("[HTTY_SSH] callback=data status={}", status);
    }
    status
}

fn send_control(callback: &JsCallback, event: &str) {
    let _ = try_send_callback(callback, event.to_string(), "control");
}

fn should_flush_immediately(pending_empty: bool, decoded_len: usize) -> bool {
    pending_empty && decoded_len > 0 && decoded_len <= 256
}

struct ClientHandler {
    host: String,
    port: u16,
    known_hosts_path: PathBuf,
    host_key_rx: tokio::sync::mpsc::Receiver<bool>,
    connect_progress_tx: tokio::sync::mpsc::Sender<ConnectProgress>,
    control_callback: JsCallback,
}

impl russh::client::Handler for ClientHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        server_public_key: &russh::keys::ssh_key::PublicKey,
    ) -> std::result::Result<bool, Self::Error> {
        match russh::keys::known_hosts::check_known_hosts_path(
            &self.host,
            self.port,
            server_public_key,
            &self.known_hosts_path,
        ) {
            Ok(true) => Ok(true),
            Ok(false) => {
                let fingerprint = server_public_key
                    .fingerprint(russh::keys::HashAlg::Sha256)
                    .to_string();
                send_control(
                    &self.control_callback,
                    &format!(
                        "HOST_KEY_PROMPT:{} {}",
                        server_public_key.algorithm(),
                        fingerprint
                    ),
                );
                let _ = self
                    .connect_progress_tx
                    .send(ConnectProgress::WaitingForUser)
                    .await;
                let accepted = self.host_key_rx.recv().await == Some(true);
                let _ = self
                    .connect_progress_tx
                    .send(ConnectProgress::NetworkActivityResumed)
                    .await;
                if accepted {
                    if let Err(error) = russh::keys::known_hosts::learn_known_hosts_path(
                        &self.host,
                        self.port,
                        server_public_key,
                        &self.known_hosts_path,
                    ) {
                        send_control(&self.control_callback, &format!("HOST_KEY_ERROR:{}", error));
                        return Ok(false);
                    }
                    Ok(true)
                } else {
                    Ok(false)
                }
            }
            Err(error) => {
                let fingerprint = server_public_key
                    .fingerprint(russh::keys::HashAlg::Sha256)
                    .to_string();
                if matches!(error, russh::keys::Error::KeyChanged { .. }) {
                    send_control(
                        &self.control_callback,
                        &format!("HOST_KEY_CHANGED:{}", fingerprint),
                    );
                } else {
                    send_control(&self.control_callback, &format!("HOST_KEY_ERROR:{}", error));
                }
                Ok(false)
            }
        }
    }
}

struct SessionReceivers {
    write_rx: tokio::sync::mpsc::Receiver<Vec<u8>>,
    resize_rx: tokio::sync::mpsc::Receiver<(u32, u32)>,
    disconnect_rx: tokio::sync::mpsc::Receiver<()>,
    auth_rx: tokio::sync::mpsc::Receiver<AuthMethod>,
    host_key_rx: Option<tokio::sync::mpsc::Receiver<bool>>,
    output_pause_rx: tokio::sync::mpsc::Receiver<bool>,
}

enum ConnectWaitResult<T, E> {
    Connected(T),
    Failed(E),
    TimedOut,
    Cancelled,
}

#[derive(Clone, Copy)]
enum ConnectProgress {
    WaitingForUser,
    NetworkActivityResumed,
}

async fn wait_for_connect<F, T, E>(
    connect: F,
    timeout: Duration,
    disconnect_rx: &mut tokio::sync::mpsc::Receiver<()>,
    progress_rx: &mut tokio::sync::mpsc::Receiver<ConnectProgress>,
) -> ConnectWaitResult<T, E>
where
    F: Future<Output = std::result::Result<T, E>>,
{
    tokio::pin!(connect);
    let deadline = tokio::time::sleep(timeout);
    tokio::pin!(deadline);
    let mut waiting_for_user = false;

    loop {
        tokio::select! {
          biased;
          result = &mut connect => return match result {
            Ok(value) => ConnectWaitResult::Connected(value),
            Err(error) => ConnectWaitResult::Failed(error),
          },
          _ = disconnect_rx.recv() => return ConnectWaitResult::Cancelled,
          progress = progress_rx.recv() => match progress {
            Some(ConnectProgress::WaitingForUser) => waiting_for_user = true,
            Some(ConnectProgress::NetworkActivityResumed) => {
              waiting_for_user = false;
              deadline.as_mut().reset(tokio::time::Instant::now() + timeout);
            }
            None => {}
          },
          _ = &mut deadline, if !waiting_for_user => return ConnectWaitResult::TimedOut,
        }
    }
}

async fn run_session(
    session_id: u32,
    host: String,
    port: u16,
    user: String,
    known_hosts_path: String,
    connect_timeout: Duration,
    data_callback: JsDataCallback,
    close_callback: JsCallback,
    control_callback: JsCallback,
    mut receivers: SessionReceivers,
) {
    let _cleanup_guard = SessionCleanupGuard(session_id);
    eprintln!(
        "[HTTY_SSH] session={} stage=connect host={} port={}",
        session_id, host, port
    );

    let config = Arc::new(build_client_config());
    let (connect_progress_tx, mut connect_progress_rx) = tokio::sync::mpsc::channel(2);
    let handler = ClientHandler {
        host: host.clone(),
        port,
        known_hosts_path: PathBuf::from(known_hosts_path),
        host_key_rx: receivers
            .host_key_rx
            .take()
            .expect("host key receiver must exist"),
        connect_progress_tx: connect_progress_tx,
        control_callback: control_callback.clone(),
    };
    let connect = russh::client::connect(config, (host.as_str(), port), handler);
    let mut ssh = match wait_for_connect(
        connect,
        connect_timeout,
        &mut receivers.disconnect_rx,
        &mut connect_progress_rx,
    )
    .await
    {
        ConnectWaitResult::Connected(handle) => handle,
        ConnectWaitResult::Failed(error) => {
            send_control(&control_callback, &format!("CONNECT:{}", error));
            return;
        }
        ConnectWaitResult::TimedOut => {
            send_control(
                &control_callback,
                &format!(
                    "CONNECT:connection timed out after {} ms",
                    connect_timeout.as_millis()
                ),
            );
            return;
        }
        ConnectWaitResult::Cancelled => {
            eprintln!("[HTTY_SSH] session={} stage=connect_cancelled", session_id);
            return;
        }
    };

    eprintln!("[HTTY_SSH] session={} stage=kex_complete", session_id);

    loop {
        send_control(&control_callback, "PASSWORD_PROMPT");
        let auth_method = tokio::select! {
          method = receivers.auth_rx.recv() => method,
          _ = receivers.disconnect_rx.recv() => {
            let _ = ssh
              .disconnect(russh::Disconnect::ByApplication, "", "")
              .await;
            return;
          }
        };

        let auth_method = match auth_method {
            Some(value) => value,
            None => return,
        };

        match auth_method {
            AuthMethod::Password(mut password) => {
                let result = ssh.authenticate_password(&user, &password).await;
                password.zeroize();
                match result {
                    Ok(value) if value.success() => break,
                    Ok(_) => {
                        send_control(&control_callback, "AUTH:rejected");
                        return;
                    }
                    Err(error) => {
                        send_control(&control_callback, &format!("AUTH:{}", error));
                        return;
                    }
                }
            }
            AuthMethod::PrivateKey {
                key_path,
                mut passphrase,
            } => {
                let key_result = keygen::load_private_key(&key_path, &passphrase);
                passphrase.zeroize();
                match key_result {
                    Ok(key) => {
                        let wrapped =
                            russh::keys::key::PrivateKeyWithHashAlg::new(Arc::new(key), None);
                        match ssh.authenticate_publickey(&user, wrapped).await {
                            Ok(result) if result.success() => break,
                            Ok(_) => {
                                eprintln!(
                                    "[HTTY_SSH] session={} stage=key_rejected fallback=password",
                                    session_id
                                );
                            }
                            Err(error) => {
                                send_control(&control_callback, &format!("AUTH:{}", error));
                                return;
                            }
                        }
                    }
                    Err(error) => {
                        send_control(&control_callback, &format!("KEY_ERROR:{}", error));
                        return;
                    }
                }
            }
        }
    }

    let mut channel = match ssh.channel_open_session().await {
        Ok(value) => value,
        Err(error) => {
            send_control(&control_callback, &format!("CHANNEL:{}", error));
            return;
        }
    };

    if let Err(error) = channel
        .request_pty(false, "xterm-256color", 80, 24, 0, 0, &[])
        .await
    {
        send_control(&control_callback, &format!("PTY:{}", error));
        return;
    }

    if let Err(error) = channel.request_shell(true).await {
        send_control(&control_callback, &format!("SHELL:{}", error));
        return;
    }

    eprintln!("[HTTY_SSH] session={} stage=connected", session_id);
    send_control(&control_callback, "CONNECTED");

    let mut pending_output: Vec<u8> = Vec::new();
    let mut output_tick = tokio::time::interval(Duration::from_millis(16));
    output_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    output_tick.tick().await;
    let mut metrics_tick = tokio::time::interval(Duration::from_secs(1));
    metrics_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    metrics_tick.tick().await;
    let mut output_paused = false;
    let mut delivery_metrics = OutputDeliveryMetrics::default();
    let mut exit_code: i32 = -1;
    let mut connection_task_ended = false;

    loop {
        tokio::select! {
          _ = output_tick.tick() => {
            if !pending_output.is_empty() {
              let output = std::mem::take(&mut pending_output);
              let output_len = output.len() as u64;
              let status = try_send_data_callback(&data_callback, output.clone());
              if !delivery_metrics.record_callback_attempt(status, output_len) {
                pending_output = output;
              }
            }
          }
          _ = metrics_tick.tick(), if cfg!(debug_assertions) => {
            send_control(&control_callback, &delivery_metrics.event(output_paused, false));
          }
          paused = receivers.output_pause_rx.recv() => {
            output_paused = paused.unwrap_or(false);
            eprintln!("[HTTY_SSH] session={} output_paused={}", session_id, output_paused);
          }
          message = channel.wait(), if !output_paused && pending_output.len() < 512 * 1024 => {
            match message {
              Some(russh::ChannelMsg::Data { ref data }) |
              Some(russh::ChannelMsg::ExtendedData { ref data, .. }) => {
                delivery_metrics.received_bytes += data.len() as u64;
                let immediate = should_flush_immediately(pending_output.is_empty(), data.len());
                pending_output.extend_from_slice(data);
                if immediate || pending_output.len() >= 64 * 1024 {
                  let output = std::mem::take(&mut pending_output);
                  let output_len = output.len() as u64;
                  let status = try_send_data_callback(&data_callback, output.clone());
                  if !delivery_metrics.record_callback_attempt(status, output_len) {
                    pending_output = output;
                  }
                }
              }
              Some(russh::ChannelMsg::ExitStatus { exit_status }) => {
                exit_code = exit_status as i32;
                break;
              }
              Some(russh::ChannelMsg::Eof) => {}
              Some(russh::ChannelMsg::Close) => {
                break;
              }
              None => {
                connection_task_ended = true;
                break;
              }
              Some(_) => {}
            }
          }
          data = receivers.write_rx.recv() => {
            match data {
              Some(bytes) => {
                if let Err(error) = channel.data(&bytes[..]).await {
                  send_control(&control_callback, &format!("WRITE_ERROR:{}", error));
                }
              }
              None => break,
            }
          }
          size = receivers.resize_rx.recv() => {
            match size {
              Some((cols, rows)) => {
                if let Err(error) = channel.window_change(cols, rows, 0, 0).await {
                  send_control(&control_callback, &format!("RESIZE_ERROR:{}", error));
                }
              }
              None => break,
            }
          }
          _ = receivers.disconnect_rx.recv() => {
            let _ = channel.eof().await;
            let _ = ssh
              .disconnect(russh::Disconnect::ByApplication, "", "")
              .await;
            break;
          }
        }
    }

    if !pending_output.is_empty() {
        let final_output = std::mem::take(&mut pending_output);
        let output_len = final_output.len() as u64;
        let mut delivered = false;
        for attempt in 0..FINAL_DELIVERY_RETRY_ATTEMPTS {
            let status = try_send_data_callback(&data_callback, final_output.clone());
            if delivery_metrics.record_callback_attempt(status, output_len) {
                delivered = true;
                break;
            }
            if attempt + 1 < FINAL_DELIVERY_RETRY_ATTEMPTS {
                tokio::time::sleep(FINAL_DELIVERY_RETRY_DELAY).await;
            }
        }
        if !delivered {
            delivery_metrics.record_final_delivery_failure(output_len);
            eprintln!(
                "[HTTY_SSH] session={} final_delivery_failed_bytes={}",
                session_id, output_len
            );
        }
    }
    let keepalive_timed_out = if connection_task_ended {
        match ssh.await {
            Err(russh::Error::KeepaliveTimeout) => {
                eprintln!(
                    "[HTTY_SSH] session={} stage=keepalive_timeout intervalSeconds={} max={}",
                    session_id,
                    SSH_KEEPALIVE_INTERVAL.as_secs(),
                    SSH_KEEPALIVE_MAX
                );
                true
            }
            Err(error) => {
                eprintln!(
                    "[HTTY_SSH] session={} stage=connection_task_failed error={}",
                    session_id, error
                );
                false
            }
            Ok(()) => false,
        }
    } else {
        false
    };
    send_control(
        &control_callback,
        &delivery_metrics.event(output_paused, true),
    );
    let close_result = if keepalive_timed_out {
        "ERROR:SSH keepalive timed out. Check the network, then run the SSH command again."
            .to_string()
    } else {
        exit_code.to_string()
    };
    let _ = try_send_callback(&close_callback, close_result, "close");

    eprintln!("[HTTY_SSH] session={} stage=closed", session_id);
}

#[napi]
pub fn ssh_connect(
    host: String,
    port: u32,
    user: String,
    known_hosts_path: String,
    connect_timeout_ms: u32,
    on_data: Function<'_, Uint8Array, ()>,
    on_close: Function<'_, String, ()>,
    on_control: Function<'_, String, ()>,
) -> Result<String> {
    if host.trim().is_empty() {
        return Err(napi_error("host must not be empty"));
    }
    if port == 0 || port > u16::MAX as u32 {
        return Err(napi_error("port must be between 1 and 65535"));
    }
    if user.trim().is_empty() {
        return Err(napi_error("user must not be empty"));
    }
    if known_hosts_path.trim().is_empty() {
        return Err(napi_error("known_hosts path must not be empty"));
    }
    if connect_timeout_ms == 0 {
        return Err(napi_error("connect timeout must be positive"));
    }

    let data_callback = Arc::new(
        on_data
            .build_threadsafe_function::<Uint8Array>()
            .max_queue_size::<64>()
            .build()?,
    );
    let close_callback = Arc::new(
        on_close
            .build_threadsafe_function::<String>()
            .max_queue_size::<64>()
            .build()?,
    );
    let control_callback = Arc::new(
        on_control
            .build_threadsafe_function::<String>()
            .max_queue_size::<64>()
            .build()?,
    );

    let (write_tx, write_rx) = tokio::sync::mpsc::channel(4096);
    let (resize_tx, resize_rx) = tokio::sync::mpsc::channel(8);
    let (disconnect_tx, disconnect_rx) = tokio::sync::mpsc::channel(1);
    let (auth_tx, auth_rx) = tokio::sync::mpsc::channel(1);
    let (host_key_tx, host_key_rx) = tokio::sync::mpsc::channel(1);
    let (output_pause_tx, output_pause_rx) = tokio::sync::mpsc::channel(8);
    let session_id = NEXT_SESSION_ID.fetch_add(1, Ordering::SeqCst);

    get_sessions()
        .lock()
        .map_err(|_| napi_error("session map lock poisoned"))?
        .insert(
            session_id,
            ShellSession {
                write_tx,
                resize_tx,
                disconnect_tx,
                auth_tx,
                host_key_tx,
                output_pause_tx,
            },
        );

    let receivers = SessionReceivers {
        write_rx,
        resize_rx,
        disconnect_rx,
        auth_rx,
        host_key_rx: Some(host_key_rx),
        output_pause_rx,
    };

    spawn(run_session(
        session_id,
        host,
        port as u16,
        user,
        known_hosts_path,
        Duration::from_millis(connect_timeout_ms as u64),
        data_callback,
        close_callback,
        control_callback,
        receivers,
    ));

    Ok(session_id.to_string())
}

fn parse_session_id(session_id: &str) -> Result<u32> {
    session_id
        .parse::<u32>()
        .map_err(|_| napi_error("invalid session id"))
}

#[napi]
pub fn ssh_auth_password(session_id: String, password: String) -> Result<()> {
    let id = parse_session_id(&session_id)?;
    let sessions = get_sessions()
        .lock()
        .map_err(|_| napi_error("session map lock poisoned"))?;
    let session = sessions
        .get(&id)
        .ok_or_else(|| napi_error("session not found"))?;
    session
        .auth_tx
        .try_send(AuthMethod::Password(password))
        .map_err(|error| napi_error(&format!("send failed: {}", error)))
}

#[napi]
pub fn ssh_auth_private_key(
    session_id: String,
    key_path: String,
    passphrase: String,
) -> Result<()> {
    let id = parse_session_id(&session_id)?;
    let sessions = get_sessions()
        .lock()
        .map_err(|_| napi_error("session map lock poisoned"))?;
    let session = sessions
        .get(&id)
        .ok_or_else(|| napi_error("session not found"))?;
    session
        .auth_tx
        .try_send(AuthMethod::PrivateKey {
            key_path,
            passphrase,
        })
        .map_err(|error| napi_error(&format!("send failed: {}", error)))
}

#[napi]
pub fn ssh_verify_host_key(session_id: String, accepted: bool) -> Result<()> {
    let id = parse_session_id(&session_id)?;
    let sessions = get_sessions()
        .lock()
        .map_err(|_| napi_error("session map lock poisoned"))?;
    let session = sessions
        .get(&id)
        .ok_or_else(|| napi_error("session not found"))?;
    session
        .host_key_tx
        .try_send(accepted)
        .map_err(|error| napi_error(&format!("send failed: {}", error)))
}

#[napi]
pub fn ssh_write(session_id: String, data: String) -> Result<()> {
    let id = parse_session_id(&session_id)?;
    let sessions = get_sessions()
        .lock()
        .map_err(|_| napi_error("session map lock poisoned"))?;
    let session = sessions
        .get(&id)
        .ok_or_else(|| napi_error("session not found"))?;
    session
        .write_tx
        .try_send(data.into_bytes())
        .map_err(|error| napi_error(&format!("send failed: {}", error)))
}

#[napi]
pub fn ssh_resize(session_id: String, cols: u32, rows: u32) -> Result<()> {
    if cols == 0 || rows == 0 {
        return Err(napi_error("terminal size must be positive"));
    }
    let id = parse_session_id(&session_id)?;
    let sessions = get_sessions()
        .lock()
        .map_err(|_| napi_error("session map lock poisoned"))?;
    let session = sessions
        .get(&id)
        .ok_or_else(|| napi_error("session not found"))?;
    session
        .resize_tx
        .try_send((cols, rows))
        .map_err(|error| napi_error(&format!("send failed: {}", error)))
}

#[napi]
pub fn ssh_set_output_paused(session_id: String, paused: bool) -> Result<()> {
    let id = parse_session_id(&session_id)?;
    let sessions = get_sessions()
        .lock()
        .map_err(|_| napi_error("session map lock poisoned"))?;
    let session = sessions
        .get(&id)
        .ok_or_else(|| napi_error("session not found"))?;
    session
        .output_pause_tx
        .try_send(paused)
        .map_err(|error| napi_error(&format!("send failed: {}", error)))
}

#[napi]
pub fn ssh_disconnect(session_id: String) -> Result<()> {
    let id = parse_session_id(&session_id)?;
    let sessions = get_sessions()
        .lock()
        .map_err(|_| napi_error("session map lock poisoned"))?;
    let session = sessions
        .get(&id)
        .ok_or_else(|| napi_error("session not found"))?;
    session
        .disconnect_tx
        .try_send(())
        .map_err(|error| napi_error(&format!("send failed: {}", error)))
}

#[napi]
pub fn ssh_generate_key_pair(
    algorithm: String,
    passphrase: String,
    output_dir: String,
    file_name: String,
    comment: String,
) -> Result<String> {
    let result =
        keygen::generate_key_pair(&algorithm, &output_dir, &file_name, &passphrase, &comment)
            .map_err(|e| napi_error(&e))?;
    let json = format!(
        "{{\"privatePath\":\"{}\",\"publicPath\":\"{}\",\"fingerprint\":\"{}\"}}",
        result.private_path, result.public_path, result.fingerprint
    );
    Ok(json)
}

#[napi]
pub fn ssh_read_public_key(key_path: String) -> Result<String> {
    keygen::read_public_key_fingerprint(&key_path).map_err(|e| napi_error(&e))
}

#[napi]
pub fn ssh_inspect_private_key(key_path: String) -> Result<String> {
    let inspected = keygen::inspect_private_key(&key_path).map_err(|e| napi_error(&e))?;
    Ok(format!(
        "{}\n{}\n{}\n{}",
        if inspected.encrypted { "true" } else { "false" },
        inspected.algorithm,
        inspected.fingerprint,
        inspected.public_key
    ))
}

#[napi]
pub fn ssh_protect_private_key(key_path: String) -> Result<()> {
    keygen::protect_private_key(&key_path).map_err(|e| napi_error(&e))
}

#[cfg(test)]
mod tests {
    use super::{
        build_client_config, should_flush_immediately, wait_for_connect, ConnectProgress,
        ConnectWaitResult, OutputDeliveryMetrics, SSH_KEEPALIVE_INTERVAL, SSH_KEEPALIVE_MAX,
    };
    use napi_ohos::Status;
    use std::future::pending;
    use std::time::Duration;

    #[test]
    fn interactive_small_packets_flush_immediately() {
        assert!(should_flush_immediately(true, 1));
        assert!(should_flush_immediately(true, 256));
        assert!(!should_flush_immediately(true, 0));
        assert!(!should_flush_immediately(true, 257));
        assert!(!should_flush_immediately(false, 32));
    }

    #[test]
    fn callback_retry_that_later_queues_is_not_a_delivery_failure() {
        let mut metrics = OutputDeliveryMetrics {
            received_bytes: 4,
            ..OutputDeliveryMetrics::default()
        };
        assert!(!metrics.record_callback_attempt(Status::QueueFull, 4));
        assert!(metrics.record_callback_attempt(Status::Ok, 4));
        assert_eq!(metrics.callback_retries, 1);
        assert_eq!(metrics.napi_queued_bytes, 4);
        assert_eq!(metrics.final_delivery_failures, 0);
        assert_eq!(metrics.final_delivery_failed_bytes, 0);
        assert!(metrics.event(false, false).contains("callbackRetries=1"));
        assert!(metrics.event(false, false).ends_with("final=false"));
    }

    #[test]
    fn exhausted_final_delivery_records_events_and_bytes() {
        let mut metrics = OutputDeliveryMetrics {
            received_bytes: 7,
            ..OutputDeliveryMetrics::default()
        };
        assert!(!metrics.record_callback_attempt(Status::Closing, 7));
        metrics.record_final_delivery_failure(7);
        assert_eq!(metrics.callback_retries, 1);
        assert_eq!(metrics.napi_queued_bytes, 0);
        assert_eq!(metrics.final_delivery_failures, 1);
        assert_eq!(metrics.final_delivery_failed_bytes, 7);
        assert!(metrics
            .event(false, true)
            .contains("finalDeliveryFailures=1"));
        assert!(metrics
            .event(false, true)
            .contains("finalDeliveryFailedBytes=7"));
        assert!(metrics.event(false, true).ends_with("final=true"));
    }

    #[test]
    fn client_config_enables_bounded_keepalive_detection() {
        let config = build_client_config();
        assert_eq!(config.keepalive_interval, Some(SSH_KEEPALIVE_INTERVAL));
        assert_eq!(config.keepalive_max, SSH_KEEPALIVE_MAX);
        assert_eq!(SSH_KEEPALIVE_INTERVAL, Duration::from_secs(30));
        assert_eq!(SSH_KEEPALIVE_MAX, 3);
    }

    #[tokio::test]
    async fn stalled_connect_times_out() {
        let (_disconnect_tx, mut disconnect_rx) = tokio::sync::mpsc::channel(1);
        let (_progress_tx, mut progress_rx) = tokio::sync::mpsc::channel(1);
        let result = wait_for_connect(
            pending::<std::result::Result<(), ()>>(),
            Duration::from_millis(1),
            &mut disconnect_rx,
            &mut progress_rx,
        )
        .await;

        assert!(matches!(result, ConnectWaitResult::TimedOut));
    }

    #[tokio::test]
    async fn stalled_connect_can_be_cancelled() {
        let (disconnect_tx, mut disconnect_rx) = tokio::sync::mpsc::channel(1);
        let (_progress_tx, mut progress_rx) = tokio::sync::mpsc::channel(1);
        disconnect_tx.send(()).await.unwrap();
        let result = wait_for_connect(
            pending::<std::result::Result<(), ()>>(),
            Duration::from_secs(1),
            &mut disconnect_rx,
            &mut progress_rx,
        )
        .await;

        assert!(matches!(result, ConnectWaitResult::Cancelled));
    }

    #[tokio::test]
    async fn host_key_prompt_pauses_connect_timeout() {
        let (disconnect_tx, mut disconnect_rx) = tokio::sync::mpsc::channel(1);
        let (progress_tx, mut progress_rx) = tokio::sync::mpsc::channel(1);
        progress_tx
            .send(ConnectProgress::WaitingForUser)
            .await
            .unwrap();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(10)).await;
            disconnect_tx.send(()).await.unwrap();
        });

        let result = wait_for_connect(
            pending::<std::result::Result<(), ()>>(),
            Duration::from_millis(1),
            &mut disconnect_rx,
            &mut progress_rx,
        )
        .await;

        assert!(matches!(result, ConnectWaitResult::Cancelled));
    }
}
