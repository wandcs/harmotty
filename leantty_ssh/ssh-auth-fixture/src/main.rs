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
}

impl FixtureServer {
    fn new(credentials: Arc<Credentials>) -> Self {
        Self {
            credentials,
            public_key_complete: false,
            password_complete: false,
            interactive_round: InteractiveRound::NotStarted,
        }
    }

    fn reject(methods: &[MethodKind], partial_success: bool) -> Auth {
        Auth::Reject {
            proceed_with_methods: Some(MethodSet::from(methods)),
            partial_success,
        }
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
            Scenario::Password => Auth::Accept,
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
            _ => {}
        }
        Self::reject(&scenario.initial_methods(), false)
    }
}

impl Scenario {
    fn initial_methods(self) -> Vec<MethodKind> {
        match self {
            Self::Password | Self::PasswordKeyboardInteractive => vec![MethodKind::Password],
            Self::PublicKey | Self::PublicKeyPassword | Self::PublicKeyKeyboardInteractive => {
                vec![MethodKind::PublicKey]
            }
            Self::KeyboardInteractiveMultiRound => vec![MethodKind::KeyboardInteractive],
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
        session.data(channel, data.to_vec())?;
        Ok(())
    }
}

struct Arguments {
    listen: String,
    credentials_path: PathBuf,
    run_seconds: u64,
}

fn parse_arguments(mut arguments: impl Iterator<Item = String>) -> Result<Arguments, String> {
    let executable = arguments
        .next()
        .unwrap_or_else(|| "ssh-auth-fixture".to_string());
    let usage = || format!("usage: {executable} <listen-address> <credentials-file> [run-seconds]");
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
    if arguments.next().is_some() {
        return Err(usage());
    }
    Ok(Arguments {
        listen,
        credentials_path,
        run_seconds,
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
    println!(
        "LEANTTY_SSH_AUTH_FIXTURE_READY address={address} pid={}",
        std::process::id()
    );
    println!(
        "users={USER_PASSWORD},{USER_PUBLICKEY},{USER_PASSWORD_KBDINT},{USER_PUBLICKEY_PASSWORD},{USER_PUBLICKEY_KBDINT},{USER_KBDINT_MULTIROUND}"
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
