const MAX_INTERACTIVE_ROUNDS: u32 = 8;
const MAX_AUTH_STAGES: u32 = 8;
const MAX_PROMPTS_PER_ROUND: usize = 16;
const MAX_SERVER_FIELD_BYTES: usize = 4096;
const MAX_PROMPT_BYTES_PER_ROUND: usize = 16 * 1024;
const MAX_RESPONSE_BYTES: usize = 4096;
const MAX_RESPONSE_BYTES_PER_ROUND: usize = 16 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthMethodKind {
    PublicKey,
    Password,
    KeyboardInteractive,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AuthPrompt {
    pub text: String,
    pub echo: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AuthChallenge {
    pub round_id: u32,
    pub name: String,
    pub instructions: String,
    pub prompts: Vec<AuthPrompt>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthFailure {
    NoSupportedMethod,
    Rejected,
    UnexpectedCredential,
    UnexpectedChallenge,
    StaleChallenge,
    ResponseCountMismatch,
    ProtocolLimitExceeded,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AuthAction {
    AttemptPublicKey,
    RequestPrivateKeyPassphrase,
    RequestPassword,
    StartKeyboardInteractive,
    PresentChallenge(AuthChallenge),
    Fail(AuthFailure),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum WaitingFor {
    PrivateKeyPassphrase,
    Password,
}

#[derive(Debug)]
pub struct AuthStateMachine {
    has_private_key: bool,
    private_key_requires_passphrase: bool,
    public_key_attempted: bool,
    password_attempted: bool,
    keyboard_interactive_attempted: bool,
    any_method_attempted: bool,
    waiting_for: Option<WaitingFor>,
    pending_challenge: Option<(u32, usize)>,
    next_round_id: u32,
    interactive_rounds: u32,
    auth_stages: u32,
}

impl AuthStateMachine {
    pub fn new(has_private_key: bool, private_key_requires_passphrase: bool) -> Self {
        Self {
            has_private_key,
            private_key_requires_passphrase,
            public_key_attempted: false,
            password_attempted: false,
            keyboard_interactive_attempted: false,
            any_method_attempted: false,
            waiting_for: None,
            pending_challenge: None,
            next_round_id: 1,
            interactive_rounds: 0,
            auth_stages: 1,
        }
    }

    pub fn select_next_method(
        &mut self,
        remaining_methods: &[AuthMethodKind],
        partial_success: bool,
    ) -> AuthAction {
        if self.waiting_for.is_some() || self.pending_challenge.is_some() {
            return AuthAction::Fail(AuthFailure::UnexpectedCredential);
        }
        if partial_success {
            if self.auth_stages >= MAX_AUTH_STAGES {
                return AuthAction::Fail(AuthFailure::ProtocolLimitExceeded);
            }
            self.auth_stages += 1;
            self.public_key_attempted = false;
            self.password_attempted = false;
            self.keyboard_interactive_attempted = false;
            self.any_method_attempted = false;
        }
        self.waiting_for = None;
        self.pending_challenge = None;

        if self.has_private_key
            && !self.public_key_attempted
            && remaining_methods.contains(&AuthMethodKind::PublicKey)
        {
            if self.private_key_requires_passphrase {
                self.waiting_for = Some(WaitingFor::PrivateKeyPassphrase);
                return AuthAction::RequestPrivateKeyPassphrase;
            }
            self.public_key_attempted = true;
            self.any_method_attempted = true;
            return AuthAction::AttemptPublicKey;
        }

        if !self.keyboard_interactive_attempted
            && remaining_methods.contains(&AuthMethodKind::KeyboardInteractive)
        {
            self.keyboard_interactive_attempted = true;
            self.any_method_attempted = true;
            return AuthAction::StartKeyboardInteractive;
        }

        if !self.password_attempted && remaining_methods.contains(&AuthMethodKind::Password) {
            self.waiting_for = Some(WaitingFor::Password);
            return AuthAction::RequestPassword;
        }

        if partial_success || self.any_method_attempted {
            AuthAction::Fail(AuthFailure::Rejected)
        } else {
            AuthAction::Fail(AuthFailure::NoSupportedMethod)
        }
    }

    pub fn submit_private_key_passphrase(&mut self) -> AuthAction {
        if self.waiting_for != Some(WaitingFor::PrivateKeyPassphrase) {
            return AuthAction::Fail(AuthFailure::UnexpectedCredential);
        }
        self.waiting_for = None;
        self.public_key_attempted = true;
        self.any_method_attempted = true;
        AuthAction::AttemptPublicKey
    }

    pub fn submit_password(&mut self) -> Result<(), AuthFailure> {
        if self.waiting_for != Some(WaitingFor::Password) {
            return Err(AuthFailure::UnexpectedCredential);
        }
        self.waiting_for = None;
        self.password_attempted = true;
        self.any_method_attempted = true;
        Ok(())
    }

    pub fn present_challenge(
        &mut self,
        name: String,
        instructions: String,
        prompts: Vec<AuthPrompt>,
    ) -> AuthAction {
        if !self.keyboard_interactive_attempted || self.pending_challenge.is_some() {
            return AuthAction::Fail(AuthFailure::UnexpectedChallenge);
        }
        if self.interactive_rounds >= MAX_INTERACTIVE_ROUNDS
            || prompts.len() > MAX_PROMPTS_PER_ROUND
            || name.len() > MAX_SERVER_FIELD_BYTES
            || instructions.len() > MAX_SERVER_FIELD_BYTES
            || prompts
                .iter()
                .any(|prompt| prompt.text.len() > MAX_SERVER_FIELD_BYTES)
            || prompts
                .iter()
                .map(|prompt| prompt.text.len())
                .sum::<usize>()
                > MAX_PROMPT_BYTES_PER_ROUND
        {
            return AuthAction::Fail(AuthFailure::ProtocolLimitExceeded);
        }

        let round_id = self.next_round_id;
        let Some(next_round_id) = round_id.checked_add(1) else {
            return AuthAction::Fail(AuthFailure::ProtocolLimitExceeded);
        };
        self.next_round_id = next_round_id;
        self.interactive_rounds += 1;
        self.pending_challenge = Some((round_id, prompts.len()));
        AuthAction::PresentChallenge(AuthChallenge {
            round_id,
            name: sanitize_server_text(&name),
            instructions: sanitize_server_text(&instructions),
            prompts: prompts
                .into_iter()
                .map(|prompt| AuthPrompt {
                    text: sanitize_server_text(&prompt.text),
                    echo: prompt.echo,
                })
                .collect(),
        })
    }

    pub fn validate_responses(
        &mut self,
        round_id: u32,
        responses: &[String],
    ) -> Result<(), AuthFailure> {
        let Some((pending_round_id, prompt_count)) = self.pending_challenge else {
            return Err(AuthFailure::UnexpectedChallenge);
        };
        if round_id != pending_round_id {
            return Err(AuthFailure::StaleChallenge);
        }
        if responses.len() != prompt_count {
            return Err(AuthFailure::ResponseCountMismatch);
        }
        if responses
            .iter()
            .any(|response| response.len() > MAX_RESPONSE_BYTES)
            || responses.iter().map(String::len).sum::<usize>() > MAX_RESPONSE_BYTES_PER_ROUND
        {
            return Err(AuthFailure::ProtocolLimitExceeded);
        }
        self.pending_challenge = None;
        Ok(())
    }
}

pub fn sanitize_server_text(value: &str) -> String {
    value
        .chars()
        .filter(|character| matches!(character, '\n' | '\r' | '\t') || !character.is_control())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chooses_key_then_keyboard_interactive_then_password() {
        let methods = [
            AuthMethodKind::Password,
            AuthMethodKind::KeyboardInteractive,
            AuthMethodKind::PublicKey,
        ];
        let mut state = AuthStateMachine::new(true, false);
        assert_eq!(
            state.select_next_method(&methods, false),
            AuthAction::AttemptPublicKey
        );
        assert_eq!(
            state.select_next_method(&methods, false),
            AuthAction::StartKeyboardInteractive
        );
        assert_eq!(
            state.select_next_method(&methods, false),
            AuthAction::RequestPassword
        );
        assert_eq!(state.submit_password(), Ok(()));
        assert_eq!(
            state.select_next_method(&methods, false),
            AuthAction::Fail(AuthFailure::Rejected)
        );
    }

    #[test]
    fn requests_passphrase_before_attempting_an_encrypted_key() {
        let mut state = AuthStateMachine::new(true, true);
        assert_eq!(
            state.select_next_method(&[AuthMethodKind::PublicKey], false),
            AuthAction::RequestPrivateKeyPassphrase
        );
        assert_eq!(
            state.submit_private_key_passphrase(),
            AuthAction::AttemptPublicKey
        );
        assert_eq!(
            state.submit_private_key_passphrase(),
            AuthAction::Fail(AuthFailure::UnexpectedCredential)
        );
    }

    #[test]
    fn partial_success_starts_a_new_bounded_method_stage() {
        let mut state = AuthStateMachine::new(true, false);
        assert_eq!(
            state.select_next_method(&[AuthMethodKind::PublicKey], false),
            AuthAction::AttemptPublicKey
        );
        assert_eq!(
            state.select_next_method(&[AuthMethodKind::Password], false),
            AuthAction::RequestPassword
        );
        state.submit_password().unwrap();
        assert_eq!(
            state.select_next_method(&[AuthMethodKind::PublicKey], true),
            AuthAction::AttemptPublicKey
        );
    }

    #[test]
    fn allows_keyboard_interactive_again_after_password_partial_success() {
        let methods = [
            AuthMethodKind::Password,
            AuthMethodKind::KeyboardInteractive,
        ];
        let mut state = AuthStateMachine::new(false, false);
        assert_eq!(
            state.select_next_method(&methods, false),
            AuthAction::StartKeyboardInteractive
        );
        assert_eq!(
            state.select_next_method(&[AuthMethodKind::Password], false),
            AuthAction::RequestPassword
        );
        state.submit_password().unwrap();
        assert_eq!(
            state.select_next_method(&[AuthMethodKind::KeyboardInteractive], true),
            AuthAction::StartKeyboardInteractive
        );
    }

    #[test]
    fn bounds_partial_success_stages() {
        let mut state = AuthStateMachine::new(false, false);
        for _ in 1..MAX_AUTH_STAGES {
            assert_eq!(
                state.select_next_method(&[AuthMethodKind::Password], true),
                AuthAction::RequestPassword
            );
            state.submit_password().unwrap();
        }
        assert_eq!(
            state.select_next_method(&[AuthMethodKind::Password], true),
            AuthAction::Fail(AuthFailure::ProtocolLimitExceeded)
        );
    }

    #[test]
    fn distinguishes_no_supported_method_from_rejection() {
        let mut state = AuthStateMachine::new(false, false);
        assert_eq!(
            state.select_next_method(&[AuthMethodKind::PublicKey], false),
            AuthAction::Fail(AuthFailure::NoSupportedMethod)
        );

        let mut attempted = AuthStateMachine::new(false, false);
        assert_eq!(
            attempted.select_next_method(&[AuthMethodKind::Password], false),
            AuthAction::RequestPassword
        );
        attempted.submit_password().unwrap();
        assert_eq!(
            attempted.select_next_method(&[AuthMethodKind::Password], false),
            AuthAction::Fail(AuthFailure::Rejected)
        );
    }

    #[test]
    fn preserves_prompt_order_and_echo_while_filtering_controls() {
        let mut state = AuthStateMachine::new(false, false);
        assert_eq!(
            state.select_next_method(&[AuthMethodKind::KeyboardInteractive], false),
            AuthAction::StartKeyboardInteractive
        );
        let action = state.present_challenge(
            "Name\u{1b}]52;bad\u{7}".to_string(),
            "Line one\r\nLine two\u{85}".to_string(),
            vec![
                AuthPrompt {
                    text: "Visible:\t".to_string(),
                    echo: true,
                },
                AuthPrompt {
                    text: "Secret:\u{1b}[31m".to_string(),
                    echo: false,
                },
            ],
        );
        match action {
            AuthAction::PresentChallenge(challenge) => {
                assert_eq!(challenge.round_id, 1);
                assert_eq!(challenge.name, "Name]52;bad");
                assert_eq!(challenge.instructions, "Line one\r\nLine two");
                assert_eq!(challenge.prompts[0].text, "Visible:\t");
                assert!(challenge.prompts[0].echo);
                assert_eq!(challenge.prompts[1].text, "Secret:[31m");
                assert!(!challenge.prompts[1].echo);
            }
            _ => panic!("expected a challenge"),
        }
    }

    #[test]
    fn accepts_zero_prompt_and_multiple_rounds() {
        let mut state = AuthStateMachine::new(false, false);
        state.select_next_method(&[AuthMethodKind::KeyboardInteractive], false);
        let first = state.present_challenge("".to_string(), "".to_string(), vec![]);
        let first_round_id = match first {
            AuthAction::PresentChallenge(challenge) => challenge.round_id,
            _ => panic!("expected first challenge"),
        };
        assert_eq!(state.validate_responses(first_round_id, &[]), Ok(()));

        let second = state.present_challenge(
            "second".to_string(),
            "".to_string(),
            vec![AuthPrompt {
                text: "Code: ".to_string(),
                echo: false,
            }],
        );
        let second_round_id = match second {
            AuthAction::PresentChallenge(challenge) => challenge.round_id,
            _ => panic!("expected second challenge"),
        };
        assert_eq!(second_round_id, first_round_id + 1);
        assert_eq!(
            state.validate_responses(second_round_id, &["123456".to_string()]),
            Ok(())
        );
    }

    #[test]
    fn rejects_stale_duplicate_and_wrong_count_responses() {
        let mut state = AuthStateMachine::new(false, false);
        state.select_next_method(&[AuthMethodKind::KeyboardInteractive], false);
        let action = state.present_challenge(
            "".to_string(),
            "".to_string(),
            vec![AuthPrompt {
                text: "Code: ".to_string(),
                echo: false,
            }],
        );
        let round_id = match action {
            AuthAction::PresentChallenge(challenge) => challenge.round_id,
            _ => panic!("expected challenge"),
        };
        assert_eq!(
            state.validate_responses(round_id + 1, &["x".to_string()]),
            Err(AuthFailure::StaleChallenge)
        );
        assert_eq!(
            state.validate_responses(round_id, &[]),
            Err(AuthFailure::ResponseCountMismatch)
        );
        assert_eq!(
            state.validate_responses(round_id, &["x".to_string()]),
            Ok(())
        );
        assert_eq!(
            state.validate_responses(round_id, &["x".to_string()]),
            Err(AuthFailure::UnexpectedChallenge)
        );
    }

    #[test]
    fn enforces_round_prompt_field_and_response_limits() {
        let mut state = AuthStateMachine::new(false, false);
        state.select_next_method(&[AuthMethodKind::KeyboardInteractive], false);
        assert_eq!(
            state.present_challenge(
                "x".repeat(MAX_SERVER_FIELD_BYTES + 1),
                "".to_string(),
                vec![],
            ),
            AuthAction::Fail(AuthFailure::ProtocolLimitExceeded)
        );
        assert_eq!(
            state.present_challenge(
                "".to_string(),
                "".to_string(),
                (0..=MAX_PROMPTS_PER_ROUND)
                    .map(|_| AuthPrompt {
                        text: "x".to_string(),
                        echo: false,
                    })
                    .collect(),
            ),
            AuthAction::Fail(AuthFailure::ProtocolLimitExceeded)
        );

        let challenge = state.present_challenge(
            "".to_string(),
            "".to_string(),
            vec![AuthPrompt {
                text: "x".to_string(),
                echo: false,
            }],
        );
        let round_id = match challenge {
            AuthAction::PresentChallenge(challenge) => challenge.round_id,
            _ => panic!("expected challenge"),
        };
        assert_eq!(
            state.validate_responses(round_id, &["x".repeat(MAX_RESPONSE_BYTES + 1)]),
            Err(AuthFailure::ProtocolLimitExceeded)
        );
    }

    #[test]
    fn stops_after_the_maximum_number_of_interactive_rounds() {
        let mut state = AuthStateMachine::new(false, false);
        state.select_next_method(&[AuthMethodKind::KeyboardInteractive], false);
        for expected_round in 1..=MAX_INTERACTIVE_ROUNDS {
            let action = state.present_challenge("".to_string(), "".to_string(), vec![]);
            let round_id = match action {
                AuthAction::PresentChallenge(challenge) => challenge.round_id,
                _ => panic!("expected round {expected_round}"),
            };
            assert_eq!(round_id, expected_round);
            state.validate_responses(round_id, &[]).unwrap();
        }
        assert_eq!(
            state.present_challenge("".to_string(), "".to_string(), vec![]),
            AuthAction::Fail(AuthFailure::ProtocolLimitExceeded)
        );
    }
}
