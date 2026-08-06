use std::borrow::Cow;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use russh::keys::{Algorithm, PrivateKey, PublicKey};
use russh::server::{Auth, Handler, Msg, Response, Server, Session};
use russh::{Channel, ChannelId, MethodKind, MethodSet};
use tokio::net::TcpListener;
use zeroize::{Zeroize, Zeroizing};

const USER_PASSWORD: &str = "password";
const USER_PUBLICKEY: &str = "publickey";
const USER_PASSWORD_KBDINT: &str = "password-kbdint";
const USER_PUBLICKEY_PASSWORD: &str = "publickey-password";
const USER_PUBLICKEY_KBDINT: &str = "publickey-kbdint";
const USER_KBDINT_MULTIROUND: &str = "kbdint-multiround";
const USER_KBDINT_ZERO: &str = "kbdint-zero";
const USER_UNSUPPORTED: &str = "unsupported";
const USER_NAVIGATION: &str = "navigation";
const USER_NAVIGATION_TWO: &str = "navigation-two";
const USER_NAVIGATION_THREE: &str = "navigation-three";
const PERF_PREPARE_COMMAND: &str = "ltty-perf-prepare";
const PERF_RUN_COMMAND: &str = "ltty-perf-run";
const PERF_MAX_CASE_ID_LENGTH: usize = 24;
const PERF_MAX_LINES: usize = 12_000;
const PERF_MIN_LINE_WIDTH: usize = 48;
const PERF_MAX_LINE_WIDTH: usize = 160;
const PERF_OUTPUT_CHUNK_BYTES: usize = 16 * 1024;

#[derive(Clone)]
struct Credentials {
    password: String,
    account: String,
    token: String,
    second_token: String,
}

impl Drop for Credentials {
    fn drop(&mut self) {
        self.password.zeroize();
        self.account.zeroize();
        self.token.zeroize();
        self.second_token.zeroize();
    }
}

impl Credentials {
    fn load(path: &Path) -> Result<Self, String> {
        let contents = Zeroizing::new(
            fs::read_to_string(path)
                .map_err(|error| format!("unable to read credentials file: {error}"))?,
        );
        let mut entries = HashMap::new();
        for (index, line) in contents.lines().enumerate() {
            let (name, value) = line
                .split_once('=')
                .ok_or_else(|| format!("credentials line {} is malformed", index + 1))?;
            if !matches!(name, "password" | "account" | "token" | "second_token") {
                return Err(format!("credentials line {} has an unknown key", index + 1));
            }
            if value.is_empty() {
                return Err(format!("credentials line {} has an empty value", index + 1));
            }
            if entries
                .insert(name.to_string(), Zeroizing::new(value.to_string()))
                .is_some()
            {
                return Err(format!("credentials key {name} is duplicated"));
            }
        }

        let mut take = |name: &str| {
            entries
                .remove(name)
                .map(|value| value.to_string())
                .ok_or_else(|| format!("credentials key {name} is missing"))
        };
        Ok(Self {
            password: take("password")?,
            account: take("account")?,
            token: take("token")?,
            second_token: take("second_token")?,
        })
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Scenario {
    Password,
    PublicKey,
    PasswordKeyboardInteractive,
    PublicKeyPassword,
    PublicKeyKeyboardInteractive,
    KeyboardInteractiveMultiRound,
    KeyboardInteractiveZeroPrompt,
    UnsupportedMethod,
    Navigation,
}

impl Scenario {
    fn for_user(user: &str) -> Option<Self> {
        match user {
            USER_PASSWORD => Some(Self::Password),
            USER_PUBLICKEY => Some(Self::PublicKey),
            USER_PASSWORD_KBDINT => Some(Self::PasswordKeyboardInteractive),
            USER_PUBLICKEY_PASSWORD => Some(Self::PublicKeyPassword),
            USER_PUBLICKEY_KBDINT => Some(Self::PublicKeyKeyboardInteractive),
            USER_KBDINT_MULTIROUND => Some(Self::KeyboardInteractiveMultiRound),
            USER_KBDINT_ZERO => Some(Self::KeyboardInteractiveZeroPrompt),
            USER_UNSUPPORTED => Some(Self::UnsupportedMethod),
            USER_NAVIGATION | USER_NAVIGATION_TWO | USER_NAVIGATION_THREE => Some(Self::Navigation),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum InteractiveRound {
    NotStarted,
    WaitingForSecond,
}

#[derive(Clone)]
struct FixtureServer {
    credentials: Arc<Credentials>,
    public_key_complete: bool,
    password_complete: bool,
    interactive_round: InteractiveRound,
    session_scenario: Option<Scenario>,
    shell_input: Vec<u8>,
    pending_perf_request: Option<PerfStreamRequest>,
}

impl FixtureServer {
    fn new(credentials: Arc<Credentials>) -> Self {
        Self {
            credentials,
            public_key_complete: false,
            password_complete: false,
            interactive_round: InteractiveRound::NotStarted,
            session_scenario: None,
            shell_input: Vec::new(),
            pending_perf_request: None,
        }
    }

    fn take_perf_command(&mut self, data: &[u8]) -> Option<PerfCommand> {
        let mut command = None;
        for byte in data {
            if matches!(*byte, b'\r' | b'\n') {
                if command.is_none() {
                    command = parse_perf_command(&self.shell_input);
                }
                self.shell_input.clear();
            } else if byte.is_ascii() && !byte.is_ascii_control() {
                if self.shell_input.len() < 256 {
                    self.shell_input.push(*byte);
                } else {
                    self.shell_input.clear();
                }
            }
        }
        command
    }

    fn reject(methods: &[MethodKind], partial_success: bool) -> Auth {
        Auth::Reject {
            proceed_with_methods: Some(MethodSet::from(methods)),
            partial_success,
        }
    }

    fn none(&self, user: &str) -> Auth {
        if Scenario::for_user(user) == Some(Scenario::UnsupportedMethod) {
            eprintln!("auth method=none scenario=UnsupportedMethod result=reject");
            return Self::reject(&[MethodKind::HostBased], false);
        }
        Auth::reject()
    }

    fn password(&mut self, user: &str, password: &str) -> Auth {
        let Some(scenario) = Scenario::for_user(user) else {
            eprintln!("auth method=password scenario=unknown result=reject");
            return Self::reject(&[], false);
        };
        if password != self.credentials.password {
            eprintln!("auth method=password scenario={scenario:?} result=reject");
            return Self::reject(&[MethodKind::Password], self.public_key_complete);
        }

        eprintln!("auth method=password scenario={scenario:?} result=matched");
        match scenario {
            Scenario::Password | Scenario::Navigation => {
                self.session_scenario = Some(scenario);
                Auth::Accept
            }
            Scenario::PasswordKeyboardInteractive => {
                self.password_complete = true;
                Self::reject(&[MethodKind::KeyboardInteractive], true)
            }
            Scenario::PublicKeyPassword if self.public_key_complete => Auth::Accept,
            Scenario::PublicKeyPassword => Self::reject(&[MethodKind::PublicKey], false),
            _ => Self::reject(&scenario.initial_methods(), false),
        }
    }

    fn public_key(&mut self, user: &str) -> Auth {
        let Some(scenario) = Scenario::for_user(user) else {
            eprintln!("auth method=publickey scenario=unknown result=reject");
            return Self::reject(&[], false);
        };
        eprintln!("auth method=publickey scenario={scenario:?} result=verified");
        match scenario {
            Scenario::PublicKey => Auth::Accept,
            Scenario::PublicKeyPassword => {
                self.public_key_complete = true;
                Self::reject(&[MethodKind::Password], true)
            }
            Scenario::PublicKeyKeyboardInteractive => {
                self.public_key_complete = true;
                Self::reject(&[MethodKind::KeyboardInteractive], true)
            }
            _ => Self::reject(&scenario.initial_methods(), false),
        }
    }

    fn keyboard_interactive(&mut self, user: &str, answers: Option<Vec<Vec<u8>>>) -> Auth {
        let Some(scenario) = Scenario::for_user(user) else {
            eprintln!("auth method=keyboard-interactive scenario=unknown result=reject");
            return Self::reject(&[], false);
        };
        let answer_count = answers.as_ref().map_or(0, Vec::len);
        eprintln!(
            "auth method=keyboard-interactive scenario={scenario:?} answers={answer_count} password_complete={} publickey_complete={} round={:?}",
            self.password_complete, self.public_key_complete, self.interactive_round
        );
        match scenario {
            Scenario::PasswordKeyboardInteractive if !self.password_complete => {
                return Self::reject(&[MethodKind::Password], false);
            }
            Scenario::PublicKeyKeyboardInteractive if !self.public_key_complete => {
                return Self::reject(&[MethodKind::PublicKey], false);
            }
            Scenario::PasswordKeyboardInteractive | Scenario::PublicKeyKeyboardInteractive => {
                if let Some(answers) = answers {
                    if answers
                        == [
                            self.credentials.account.as_bytes(),
                            self.credentials.token.as_bytes(),
                        ]
                    {
                        return Auth::Accept;
                    }
                    return Self::reject(&[MethodKind::KeyboardInteractive], true);
                }
                return interactive_prompt(
                    "LeanTTY controlled authentication",
                    "Enter both temporary fixture values.",
                    &[("Account label: ", true), ("One-time code: ", false)],
                );
            }
            Scenario::KeyboardInteractiveMultiRound => match answers {
                None if self.interactive_round == InteractiveRound::NotStarted => {
                    return interactive_prompt(
                        "LeanTTY round one",
                        "The first response is visible.",
                        &[("Account label: ", true)],
                    );
                }
                Some(answers)
                    if self.interactive_round == InteractiveRound::NotStarted
                        && answers == [self.credentials.account.as_bytes()] =>
                {
                    self.interactive_round = InteractiveRound::WaitingForSecond;
                    return interactive_prompt(
                        "LeanTTY round two",
                        "The second response is secret.",
                        &[("Second one-time code: ", false)],
                    );
                }
                None if self.interactive_round == InteractiveRound::WaitingForSecond => {
                    return interactive_prompt(
                        "LeanTTY round two",
                        "The second response is secret.",
                        &[("Second one-time code: ", false)],
                    );
                }
                Some(answers)
                    if self.interactive_round == InteractiveRound::WaitingForSecond
                        && answers == [self.credentials.second_token.as_bytes()] =>
                {
                    return Auth::Accept;
                }
                _ => {
                    self.interactive_round = InteractiveRound::NotStarted;
                    return Self::reject(&[MethodKind::KeyboardInteractive], false);
                }
            },
            Scenario::KeyboardInteractiveZeroPrompt => match answers {
                None => {
                    return interactive_prompt(
                        "LeanTTY zero-prompt authentication",
                        "No response value is required.",
                        &[],
                    );
                }
                Some(answers) if answers.is_empty() => return Auth::Accept,
                Some(_) => {
                    return Self::reject(&[MethodKind::KeyboardInteractive], false);
                }
            },
            _ => {}
        }
        Self::reject(&scenario.initial_methods(), false)
    }
}

impl Scenario {
    fn initial_methods(self) -> Vec<MethodKind> {
        match self {
            Self::Password | Self::PasswordKeyboardInteractive | Self::Navigation => {
                vec![MethodKind::Password]
            }
            Self::PublicKey | Self::PublicKeyPassword | Self::PublicKeyKeyboardInteractive => {
                vec![MethodKind::PublicKey]
            }
            Self::KeyboardInteractiveMultiRound | Self::KeyboardInteractiveZeroPrompt => {
                vec![MethodKind::KeyboardInteractive]
            }
            Self::UnsupportedMethod => vec![MethodKind::HostBased],
        }
    }
}

fn interactive_prompt(
    name: &'static str,
    instructions: &'static str,
    prompts: &[(&'static str, bool)],
) -> Auth {
    Auth::Partial {
        name: Cow::Borrowed(name),
        instructions: Cow::Borrowed(instructions),
        prompts: Cow::Owned(
            prompts
                .iter()
                .map(|(prompt, echo)| (Cow::Borrowed(*prompt), *echo))
                .collect(),
        ),
    }
}

impl Server for FixtureServer {
    type Handler = Self;

    fn new_client(&mut self, _: Option<SocketAddr>) -> Self {
        Self::new(Arc::clone(&self.credentials))
    }

    fn handle_session_error(&mut self, error: <Self::Handler as Handler>::Error) {
        eprintln!("SSH fixture session failed: {error}");
    }
}

impl Handler for FixtureServer {
    type Error = russh::Error;

    async fn auth_none(&mut self, user: &str) -> Result<Auth, Self::Error> {
        Ok(self.none(user))
    }

    async fn auth_password(&mut self, user: &str, password: &str) -> Result<Auth, Self::Error> {
        Ok(self.password(user, password))
    }

    async fn auth_publickey(
        &mut self,
        user: &str,
        _public_key: &PublicKey,
    ) -> Result<Auth, Self::Error> {
        Ok(self.public_key(user))
    }

    async fn auth_keyboard_interactive<'a>(
        &'a mut self,
        user: &str,
        _submethods: &str,
        response: Option<Response<'a>>,
    ) -> Result<Auth, Self::Error> {
        let answers = response.map(|values| values.map(|value| value.to_vec()).collect());
        Ok(self.keyboard_interactive(user, answers))
    }

    async fn authentication_banner(&mut self) -> Result<Option<String>, Self::Error> {
        Ok(Some(
            "LeanTTY controlled SSH acceptance fixture — temporary credentials only\r\n"
                .to_string(),
        ))
    }

    async fn channel_open_session(
        &mut self,
        _channel: Channel<Msg>,
        reply: russh::server::ChannelOpenHandle,
        _session: &mut Session,
    ) -> Result<(), Self::Error> {
        reply.accept().await;
        Ok(())
    }

    async fn pty_request(
        &mut self,
        channel: ChannelId,
        _term: &str,
        _col_width: u32,
        _row_height: u32,
        _pix_width: u32,
        _pix_height: u32,
        _modes: &[(russh::Pty, u32)],
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        session.channel_success(channel)?;
        Ok(())
    }

    async fn shell_request(
        &mut self,
        channel: ChannelId,
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        session.channel_success(channel)?;
        session.data(channel, b"LEANTTY_AUTH_FIXTURE_OK\r\nfixture> ".as_slice())?;
        Ok(())
    }

    async fn exec_request(
        &mut self,
        channel: ChannelId,
        _data: &[u8],
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        session.channel_success(channel)?;
        session.data(channel, b"LEANTTY_AUTH_FIXTURE_OK\n".as_slice())?;
        session.exit_status_request(channel, 0)?;
        session.eof(channel)?;
        session.close(channel)?;
        Ok(())
    }

    async fn data(
        &mut self,
        channel: ChannelId,
        data: &[u8],
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        if data.contains(&0x04) {
            session.data(channel, b"logout\r\n".as_slice())?;
            session.exit_status_request(channel, 0)?;
            session.eof(channel)?;
            session.close(channel)?;
            return Ok(());
        }
        if self.session_scenario == Some(Scenario::Navigation) {
            let captured = format!(
                "\r\nLEANTTY_INPUT_HEX:{}\r\nfixture> ",
                format_input_hex(data)
            );
            session.data(channel, captured.into_bytes())?;
            return Ok(());
        }
        session.data(channel, data.to_vec())?;
        match self.take_perf_command(data) {
            Some(PerfCommand::Prepare(request)) => {
                let expected_bytes = perf_stream_expected_bytes(&request);
                let begin = format!(
                    "\x1b]0;LTTY_PERF_BEGIN__:{}:{}\x07\r\nfixture> ",
                    request.case_id, expected_bytes
                );
                self.pending_perf_request = Some(request);
                session.data(channel, begin.into_bytes())?;
            }
            Some(PerfCommand::Run(case_id)) => {
                let Some(request) = self.pending_perf_request.take() else {
                    return Ok(());
                };
                if request.case_id != case_id {
                    self.pending_perf_request = Some(request);
                    return Ok(());
                }
                let payload = build_perf_stream_payload(&request);
                let end = format!(
                    "\x1b]0;LTTY_PERF_END__:{}\x07\r\nfixture> ",
                    request.case_id
                );
                let handle = session.handle();
                tokio::spawn(async move {
                    for chunk in payload.chunks(PERF_OUTPUT_CHUNK_BYTES) {
                        if handle.data(channel, chunk.to_vec()).await.is_err() {
                            return;
                        }
                        tokio::time::sleep(Duration::from_millis(5)).await;
                    }
                    let _ = handle.data(channel, end.into_bytes()).await;
                });
            }
            None => {}
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct PerfStreamRequest {
    case_id: String,
    lines: usize,
    line_width: usize,
}

#[derive(Debug, Eq, PartialEq)]
enum PerfCommand {
    Prepare(PerfStreamRequest),
    Run(String),
}

fn is_valid_perf_case_id(case_id: &str) -> bool {
    !case_id.is_empty()
        && case_id.len() <= PERF_MAX_CASE_ID_LENGTH
        && case_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
}

fn parse_perf_command(input: &[u8]) -> Option<PerfCommand> {
    let command = std::str::from_utf8(input).ok()?;
    let mut parts = command.split_ascii_whitespace();
    let kind = parts.next()?;
    let case_id = parts.next()?;
    if !is_valid_perf_case_id(case_id) {
        return None;
    }
    if kind == PERF_RUN_COMMAND {
        return (parts.next().is_none()).then(|| PerfCommand::Run(case_id.to_string()));
    }
    if kind != PERF_PREPARE_COMMAND {
        return None;
    }
    let lines = parts.next()?.parse::<usize>().ok()?;
    let line_width = parts.next()?.parse::<usize>().ok()?;
    if parts.next().is_some()
        || !(1..=PERF_MAX_LINES).contains(&lines)
        || !(PERF_MIN_LINE_WIDTH..=PERF_MAX_LINE_WIDTH).contains(&line_width)
    {
        return None;
    }
    Some(PerfCommand::Prepare(PerfStreamRequest {
        case_id: case_id.to_string(),
        lines,
        line_width,
    }))
}

fn build_perf_stream_payload(request: &PerfStreamRequest) -> Vec<u8> {
    let mut payload = Vec::with_capacity((request.line_width + 2) * request.lines);
    for line in 0..request.lines {
        let prefix = format!("LTTY_PERF_{}_{line:05} ", request.case_id);
        payload.extend_from_slice(prefix.as_bytes());
        payload.resize(payload.len() + request.line_width - prefix.len(), b'X');
        payload.extend_from_slice(b"\r\n");
    }
    payload
}

fn perf_stream_expected_bytes(request: &PerfStreamRequest) -> usize {
    let prefix = format!("LTTY_PERF_{}_{:05} ", request.case_id, 0);
    (request.line_width - prefix.len()) * request.lines
}

fn format_input_hex(data: &[u8]) -> String {
    data.iter()
        .map(|value| format!("{value:02x}"))
        .collect::<Vec<_>>()
        .join(" ")
}

struct Arguments {
    listen: String,
    credentials_path: PathBuf,
    run_seconds: u64,
    ready_path: Option<PathBuf>,
}

fn parse_arguments(mut arguments: impl Iterator<Item = String>) -> Result<Arguments, String> {
    let executable = arguments
        .next()
        .unwrap_or_else(|| "ssh-auth-fixture".to_string());
    let usage = || {
        format!(
            "usage: {executable} <listen-address> <credentials-file> [run-seconds] [ready-file]"
        )
    };
    let listen = arguments.next().ok_or_else(&usage)?;
    let credentials_path = PathBuf::from(arguments.next().ok_or_else(&usage)?);
    let run_seconds = arguments
        .next()
        .map(|value| {
            value
                .parse::<u64>()
                .map_err(|_| "run-seconds must be an unsigned integer".to_string())
        })
        .transpose()?
        .unwrap_or(900);
    if run_seconds == 0 {
        return Err("run-seconds must be greater than zero".to_string());
    }
    let ready_path = arguments.next().map(PathBuf::from);
    if arguments.next().is_some() {
        return Err(usage());
    }
    Ok(Arguments {
        listen,
        credentials_path,
        run_seconds,
        ready_path,
    })
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let arguments = parse_arguments(env::args()).map_err(|error| error.to_string())?;
    let credentials = Arc::new(
        Credentials::load(&arguments.credentials_path).map_err(|error| error.to_string())?,
    );
    let socket = TcpListener::bind(&arguments.listen).await?;
    let address = socket.local_addr()?;
    let config = Arc::new(russh::server::Config {
        inactivity_timeout: Some(Duration::from_secs(arguments.run_seconds)),
        auth_rejection_time: Duration::from_millis(50),
        auth_rejection_time_initial: Some(Duration::ZERO),
        keys: vec![PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519)?],
        ..Default::default()
    });
    let mut fixture = FixtureServer::new(credentials);
    let running = fixture.run_on_socket(config, &socket);
    let handle = running.handle();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(arguments.run_seconds)).await;
        handle.shutdown("fixture lifetime expired".into());
    });
    if let Some(ready_path) = arguments.ready_path {
        fs::write(
            ready_path,
            format!("address={address}\npid={}\n", std::process::id()),
        )?;
    }
    println!(
        "LEANTTY_SSH_AUTH_FIXTURE_READY address={address} pid={}",
        std::process::id()
    );
    println!(
        "users={USER_PASSWORD},{USER_PUBLICKEY},{USER_PASSWORD_KBDINT},{USER_PUBLICKEY_PASSWORD},{USER_PUBLICKEY_KBDINT},{USER_KBDINT_MULTIROUND},{USER_KBDINT_ZERO},{USER_UNSUPPORTED},{USER_NAVIGATION},{USER_NAVIGATION_TWO},{USER_NAVIGATION_THREE}"
    );
    running.await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn credentials() -> Arc<Credentials> {
        Arc::new(Credentials {
            password: "password-value".to_string(),
            account: "account-value".to_string(),
            token: "token-value".to_string(),
            second_token: "second-token-value".to_string(),
        })
    }

    fn assert_accept(auth: Auth) {
        assert!(matches!(auth, Auth::Accept));
    }

    fn assert_reject(auth: Auth, expected: &[MethodKind], partial_success: bool) {
        match auth {
            Auth::Reject {
                proceed_with_methods: Some(methods),
                partial_success: actual_partial,
            } => {
                assert_eq!(methods, MethodSet::from(expected));
                assert_eq!(actual_partial, partial_success);
            }
            _ => panic!("expected rejection"),
        }
    }

    #[test]
    fn accepts_single_password_and_public_key_scenarios() {
        let mut fixture = FixtureServer::new(credentials());
        assert_accept(fixture.password(USER_PASSWORD, "password-value"));

        let mut fixture = FixtureServer::new(credentials());
        assert_accept(fixture.public_key(USER_PUBLICKEY));

        let mut fixture = FixtureServer::new(credentials());
        assert_accept(fixture.password(USER_NAVIGATION, "password-value"));
        assert_eq!(fixture.session_scenario, Some(Scenario::Navigation));

        let mut fixture = FixtureServer::new(credentials());
        assert_accept(fixture.password(USER_NAVIGATION_TWO, "password-value"));
        let mut fixture = FixtureServer::new(credentials());
        assert_accept(fixture.password(USER_NAVIGATION_THREE, "password-value"));
    }

    #[test]
    fn formats_navigation_input_as_lowercase_hex() {
        assert_eq!(format_input_hex(b"\x1b[1;7D"), "1b 5b 31 3b 37 44");
        assert_eq!(format_input_hex(b"\t"), "09");
    }

    #[test]
    fn parses_only_bounded_perf_stream_commands() {
        assert_eq!(
            parse_perf_command(b"ltty-perf-prepare baseline_01 12000 80"),
            Some(PerfCommand::Prepare(PerfStreamRequest {
                case_id: "baseline_01".to_string(),
                lines: 12_000,
                line_width: 80,
            }))
        );
        assert_eq!(
            parse_perf_command(b"ltty-perf-run baseline_01"),
            Some(PerfCommand::Run("baseline_01".to_string()))
        );
        assert_eq!(
            parse_perf_command(b"ltty-perf-prepare baseline:01 100 80"),
            None
        );
        assert_eq!(
            parse_perf_command(b"ltty-perf-prepare baseline 12001 80"),
            None
        );
        assert_eq!(
            parse_perf_command(b"ltty-perf-prepare baseline 100 47"),
            None
        );
        assert_eq!(parse_perf_command(b"ltty-perf-run baseline extra"), None);
        assert_eq!(parse_perf_command(b"help"), None);
    }

    #[test]
    fn builds_exact_width_perf_stream_payload() {
        let request = PerfStreamRequest {
            case_id: "sample01".to_string(),
            lines: 3,
            line_width: 64,
        };
        let payload = build_perf_stream_payload(&request);
        assert_eq!(payload.len(), (64 + 2) * 3);
        assert_eq!(
            payload.iter().filter(|byte| **byte == b'X').count(),
            perf_stream_expected_bytes(&request)
        );
        for (index, line) in payload.chunks_exact(66).enumerate() {
            assert_eq!(&line[64..], b"\r\n");
            assert!(line.starts_with(format!("LTTY_PERF_sample01_{index:05} ").as_bytes()));
        }
    }

    #[test]
    fn enforces_password_then_keyboard_interactive_with_mixed_echo() {
        let mut fixture = FixtureServer::new(credentials());
        assert_reject(
            fixture.keyboard_interactive(USER_PASSWORD_KBDINT, None),
            &[MethodKind::Password],
            false,
        );
        assert_reject(
            fixture.password(USER_PASSWORD_KBDINT, "password-value"),
            &[MethodKind::KeyboardInteractive],
            true,
        );
        match fixture.keyboard_interactive(USER_PASSWORD_KBDINT, None) {
            Auth::Partial { prompts, .. } => {
                assert_eq!(prompts.len(), 2);
                assert!(prompts[0].1);
                assert!(!prompts[1].1);
            }
            _ => panic!("expected interactive prompts"),
        }
        assert_accept(fixture.keyboard_interactive(
            USER_PASSWORD_KBDINT,
            Some(vec![b"account-value".to_vec(), b"token-value".to_vec()]),
        ));
    }

    #[test]
    fn enforces_public_key_then_password() {
        let mut fixture = FixtureServer::new(credentials());
        assert_reject(
            fixture.password(USER_PUBLICKEY_PASSWORD, "password-value"),
            &[MethodKind::PublicKey],
            false,
        );
        assert_reject(
            fixture.public_key(USER_PUBLICKEY_PASSWORD),
            &[MethodKind::Password],
            true,
        );
        assert_accept(fixture.password(USER_PUBLICKEY_PASSWORD, "password-value"));
    }

    #[test]
    fn enforces_public_key_then_keyboard_interactive() {
        let mut fixture = FixtureServer::new(credentials());
        assert_reject(
            fixture.public_key(USER_PUBLICKEY_KBDINT),
            &[MethodKind::KeyboardInteractive],
            true,
        );
        assert_accept(fixture.keyboard_interactive(
            USER_PUBLICKEY_KBDINT,
            Some(vec![b"account-value".to_vec(), b"token-value".to_vec()]),
        ));
    }

    #[test]
    fn rejects_wrong_answer_and_restarts_multi_round_exchange() {
        let mut fixture = FixtureServer::new(credentials());
        assert!(matches!(
            fixture.keyboard_interactive(USER_KBDINT_MULTIROUND, None),
            Auth::Partial { .. }
        ));
        assert!(matches!(
            fixture.keyboard_interactive(
                USER_KBDINT_MULTIROUND,
                Some(vec![b"account-value".to_vec()])
            ),
            Auth::Partial { .. }
        ));
        assert_reject(
            fixture.keyboard_interactive(USER_KBDINT_MULTIROUND, Some(vec![b"wrong".to_vec()])),
            &[MethodKind::KeyboardInteractive],
            false,
        );
        assert_eq!(fixture.interactive_round, InteractiveRound::NotStarted);
    }

    #[test]
    fn accepts_two_round_keyboard_interactive_exchange() {
        let mut fixture = FixtureServer::new(credentials());
        assert!(matches!(
            fixture.keyboard_interactive(USER_KBDINT_MULTIROUND, None),
            Auth::Partial { .. }
        ));
        assert!(matches!(
            fixture.keyboard_interactive(
                USER_KBDINT_MULTIROUND,
                Some(vec![b"account-value".to_vec()])
            ),
            Auth::Partial { .. }
        ));
        assert_accept(fixture.keyboard_interactive(
            USER_KBDINT_MULTIROUND,
            Some(vec![b"second-token-value".to_vec()]),
        ));
    }

    #[test]
    fn accepts_zero_prompt_and_exposes_only_hostbased_for_unsupported_user() {
        let mut fixture = FixtureServer::new(credentials());
        match fixture.keyboard_interactive(USER_KBDINT_ZERO, None) {
            Auth::Partial { prompts, .. } => assert!(prompts.is_empty()),
            _ => panic!("expected zero-prompt interactive request"),
        }
        assert_accept(fixture.keyboard_interactive(USER_KBDINT_ZERO, Some(Vec::new())));

        let fixture = FixtureServer::new(credentials());
        assert_reject(
            fixture.none(USER_UNSUPPORTED),
            &[MethodKind::HostBased],
            false,
        );
    }

    #[test]
    fn credential_file_rejects_unknown_duplicate_and_missing_values() {
        let temp = env::temp_dir().join(format!("leantty-fixture-{}", std::process::id()));
        fs::create_dir_all(&temp).unwrap();
        let path = temp.join("credentials");

        fs::write(&path, "password=x\naccount=y\ntoken=z\nunknown=q\n").unwrap();
        assert!(Credentials::load(&path)
            .err()
            .unwrap()
            .contains("unknown key"));
        fs::write(
            &path,
            "password=x\npassword=y\naccount=a\ntoken=z\nsecond_token=q\n",
        )
        .unwrap();
        assert!(Credentials::load(&path)
            .err()
            .unwrap()
            .contains("duplicated"));
        fs::write(&path, "password=x\naccount=y\ntoken=z\n").unwrap();
        assert!(Credentials::load(&path).err().unwrap().contains("missing"));

        fs::remove_dir_all(temp).unwrap();
    }
}
