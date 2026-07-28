pub mod keygen;
pub mod known_hosts;
pub mod utf8_decoder;

pub enum AuthMethod {
    Password(String),
    PrivateKey {
        key_path: String,
        passphrase: String,
    },
}
