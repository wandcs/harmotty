use data_encoding::BASE64;
use hmac::{Hmac, KeyInit, Mac};
use leantty_ssh_core::known_hosts::{format_known_hosts_target, remove_known_host_entries};
use sha1::Sha1;

#[test]
fn formats_default_and_non_default_ports_like_openssh() {
    assert_eq!(
        format_known_hosts_target("server.example.com", 22),
        "server.example.com"
    );
    assert_eq!(
        format_known_hosts_target("server.example.com", 2222),
        "[server.example.com]:2222"
    );
    assert_eq!(
        format_known_hosts_target("2001:db8::1", 2200),
        "[2001:db8::1]:2200"
    );
}

#[test]
fn removes_only_the_exact_endpoint_across_key_algorithms() {
    let content = concat!(
        "server.example.com ssh-ed25519 AAAA-old\n",
        "server.example.com ssh-rsa AAAA-rsa\n",
        "[server.example.com]:2222 ssh-ed25519 AAAA-port\n",
        "[server.example.com]:2223 ssh-ed25519 AAAA-other-port\n",
        "other.example ssh-ed25519 AAAA-other\n",
    );

    let result = remove_known_host_entries(content, "server.example.com", 2222).unwrap();

    assert_eq!(result.removed, 1);
    assert!(!result
        .content
        .contains("[server.example.com]:2222 ssh-ed25519"));
    assert!(result
        .content
        .contains("server.example.com ssh-ed25519 AAAA-old"));
    assert!(result
        .content
        .contains("server.example.com ssh-rsa AAAA-rsa"));
    assert!(result
        .content
        .contains("[server.example.com]:2223 ssh-ed25519 AAAA-other-port"));
    assert!(result
        .content
        .contains("other.example ssh-ed25519 AAAA-other"));
}

#[test]
fn removes_all_default_port_algorithms_without_touching_other_ports() {
    let content = concat!(
        "server.example.com ssh-ed25519 AAAA-old\n",
        "server.example.com ssh-rsa AAAA-rsa\n",
        "[server.example.com]:2222 ssh-ed25519 AAAA-port\n",
    );

    let result = remove_known_host_entries(content, "server.example.com", 22).unwrap();

    assert_eq!(result.removed, 2);
    assert_eq!(
        result.content,
        "[server.example.com]:2222 ssh-ed25519 AAAA-port\n"
    );
}

#[test]
fn preserves_other_hosts_in_shared_and_hashed_records() {
    let content = concat!(
        "# retained comment\r\n",
        "server.example.com,other.example ssh-ed25519 AAAA-shared\r\n",
        "|1|O33ESRMWPVkMYIwJ1Uw+n877jTo=|nuuC5vEqXlEZ/8BXQR7m619W6Ak= ssh-rsa AAAA-hashed\r\n",
        "\r\n",
    );

    let result = remove_known_host_entries(content, "server.example.com", 22).unwrap();
    assert_eq!(result.removed, 1);
    assert!(result
        .content
        .contains("other.example ssh-ed25519 AAAA-shared\r\n"));
    assert!(result
        .content
        .contains("|1|O33ESRMWPVkMYIwJ1Uw+n877jTo=|nuuC5vEqXlEZ/8BXQR7m619W6Ak="));

    let hashed = remove_known_host_entries(&result.content, "example.com", 22).unwrap();
    assert_eq!(hashed.removed, 1);
    assert_eq!(
        hashed.content,
        "# retained comment\r\nother.example ssh-ed25519 AAAA-shared\r\n\r\n"
    );
}

#[test]
fn preserves_malformed_unrelated_hashes_and_final_lines_without_newlines() {
    let content = concat!(
        "|1|not-base64|still-not-base64 ssh-ed25519 AAAA-malformed\n",
        "server.example.com ssh-ed25519 AAAA-target"
    );

    let result = remove_known_host_entries(content, "server.example.com", 22).unwrap();

    assert_eq!(result.removed, 1);
    assert_eq!(
        result.content,
        "|1|not-base64|still-not-base64 ssh-ed25519 AAAA-malformed\n"
    );
}

#[test]
fn removes_a_hashed_non_default_port_without_matching_the_default_port() {
    let salt = b"fixed known hosts salt";
    let custom_target = "[server.example.com]:2222";
    let hashed_target = hash_target(custom_target, salt);
    let content = format!(
        "{hashed_target} ssh-ed25519 AAAA-port\nserver.example.com ssh-ed25519 AAAA-default\n"
    );

    let result = remove_known_host_entries(&content, "server.example.com", 2222).unwrap();

    assert_eq!(result.removed, 1);
    assert_eq!(
        result.content,
        "server.example.com ssh-ed25519 AAAA-default\n"
    );
}

fn hash_target(target: &str, salt: &[u8]) -> String {
    let digest = Hmac::<Sha1>::new_from_slice(salt)
        .unwrap()
        .chain_update(target)
        .finalize()
        .into_bytes();
    format!(
        "|1|{}|{}",
        BASE64.encode(salt),
        BASE64.encode(digest.as_slice())
    )
}
