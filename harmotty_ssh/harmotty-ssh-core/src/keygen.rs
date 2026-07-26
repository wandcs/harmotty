use russh::keys::ssh_key::private::PrivateKey;

pub fn load_private_key(
    key_path: &str,
    passphrase: &str,
) -> std::result::Result<PrivateKey, String> {
    if passphrase.is_empty() {
        russh::keys::load_secret_key(key_path, None).map_err(|e| format!("Cannot load key: {}", e))
    } else {
        russh::keys::load_secret_key(key_path, Some(passphrase))
            .map_err(|e| format!("Cannot load key: {}", e))
    }
}

pub struct KeyGenResult {
    pub private_path: String,
    pub public_path: String,
    pub fingerprint: String,
}

pub struct KeyInspection {
    pub algorithm: String,
    pub public_key: String,
    pub fingerprint: String,
    pub encrypted: bool,
}

pub fn inspect_private_key(key_path: &str) -> Result<KeyInspection, String> {
    let content =
        std::fs::read_to_string(key_path).map_err(|e| format!("read private key failed: {}", e))?;
    let private_key = PrivateKey::from_openssh(&content)
        .map_err(|e| format!("parse private key failed: {}", e))?;
    let public_key = private_key.public_key();
    let algorithm = public_key.algorithm().as_str().to_string();
    if algorithm != "ssh-ed25519" && algorithm != "ssh-rsa" {
        return Err(format!("unsupported private key type: {}", algorithm));
    }
    Ok(KeyInspection {
        algorithm,
        public_key: public_key.to_string(),
        fingerprint: private_key
            .fingerprint(russh::keys::HashAlg::Sha256)
            .to_string(),
        encrypted: private_key.is_encrypted(),
    })
}

pub fn protect_private_key(key_path: &str) -> Result<(), String> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(key_path, std::fs::Permissions::from_mode(0o600))
            .map_err(|e| format!("chmod private key failed: {}", e))?;
    }
    Ok(())
}

pub fn generate_key_pair(
    algorithm: &str,
    output_dir: &str,
    file_name: &str,
    passphrase: &str,
    comment: &str,
) -> Result<KeyGenResult, String> {
    use russh::keys::ssh_key::{private::PrivateKey, Algorithm, LineEnding};

    let algo: Algorithm = if algorithm.to_lowercase().contains("rsa") {
        Algorithm::Rsa { hash: None }
    } else {
        Algorithm::Ed25519
    };
    let algo_name: &str = if algorithm.to_lowercase().contains("rsa") {
        "rsa"
    } else {
        "ed25519"
    };
    let file_name: String = if file_name.is_empty() {
        format!("id_{}", algo_name)
    } else {
        validate_key_name(file_name)?;
        file_name.to_owned()
    };
    let priv_path: String = format!("{}/{}", output_dir, file_name);
    let pub_path: String = format!("{}/{}.pub", output_dir, file_name);

    let mut keypair: PrivateKey =
        PrivateKey::random(&mut rand::rng(), algo).map_err(|e| format!("key gen failed: {}", e))?;
    if !comment.is_empty() {
        keypair.set_comment(comment);
    }
    let stored_key = if passphrase.is_empty() {
        keypair.clone()
    } else {
        keypair
            .encrypt(&mut rand::rng(), passphrase)
            .map_err(|e| format!("key encryption failed: {}", e))?
    };

    let openssh_pem: String = stored_key
        .to_openssh(LineEnding::LF)
        .map_err(|e| format!("pem encode failed: {}", e))?
        .to_string();

    std::fs::create_dir_all(&output_dir).map_err(|e| format!("mkdir failed: {}", e))?;

    if std::path::Path::new(&priv_path).exists() || std::path::Path::new(&pub_path).exists() {
        return Err(format!("key already exists: {}", file_name));
    }

    {
        use std::io::Write;
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&priv_path)
            .map_err(|e| format!("create key failed: {}", e))?;
        f.write_all(openssh_pem.as_bytes())
            .map_err(|e| format!("write key failed: {}", e))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&priv_path, std::fs::Permissions::from_mode(0o600))
                .map_err(|e| format!("chmod key failed: {}", e))?;
        }
    }

    let pub_text: String = keypair.public_key().to_string();
    let public_result = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&pub_path)
        .and_then(|mut file| {
            use std::io::Write;
            file.write_all(pub_text.as_bytes())
        });
    if let Err(error) = public_result {
        let _ = std::fs::remove_file(&priv_path);
        return Err(format!("write pub failed: {}", error));
    }

    let fingerprint: String = keypair
        .fingerprint(russh::keys::HashAlg::Sha256)
        .to_string();

    Ok(KeyGenResult {
        private_path: priv_path,
        public_path: pub_path,
        fingerprint,
    })
}

fn validate_key_name(file_name: &str) -> Result<(), String> {
    if file_name.is_empty() || file_name == "." || file_name == ".." {
        return Err("invalid key name".to_string());
    }
    if file_name.ends_with(".pub")
        || !file_name
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '-'))
    {
        return Err("invalid key name".to_string());
    }
    let lower = file_name.to_ascii_lowercase();
    for reserved in [
        "config",
        "known_hosts",
        "authorized_keys",
        "rc",
        "environment",
        "moduli",
    ] {
        if lower == reserved || lower.starts_with(&format!("{}.", reserved)) {
            return Err("key name conflicts with SSH control file".to_string());
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{generate_key_pair, inspect_private_key};

    #[test]
    fn uses_requested_name_and_refuses_overwrite() {
        let dir = std::env::temp_dir().join(format!("harmotty-keygen-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let dir_text = dir.to_string_lossy().to_string();

        let generated = generate_key_pair("ed25519", &dir_text, "deploy_key", "", "").unwrap();
        assert!(generated.private_path.ends_with("deploy_key"));
        assert!(generate_key_pair("ed25519", &dir_text, "deploy_key", "", "").is_err());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn rejects_unsafe_requested_name() {
        let dir = std::env::temp_dir().to_string_lossy().to_string();
        assert!(generate_key_pair("ed25519", &dir, "../escape", "", "").is_err());
    }

    #[test]
    fn rejects_reserved_ssh_file_names() {
        let dir = std::env::temp_dir().to_string_lossy().to_string();
        assert!(generate_key_pair("ed25519", &dir, "config", "", "").is_err());
        assert!(generate_key_pair("ed25519", &dir, "known_hosts.old", "", "").is_err());
    }

    #[test]
    fn inspects_generated_private_key() {
        let dir = std::env::temp_dir().join(format!("harmotty-inspect-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let dir_text = dir.to_string_lossy().to_string();
        let generated =
            generate_key_pair("ed25519", &dir_text, "inspect_key", "", "test@host").unwrap();
        let inspected = inspect_private_key(&generated.private_path).unwrap();
        assert_eq!(inspected.algorithm, "ssh-ed25519");
        assert_eq!(inspected.fingerprint, generated.fingerprint);
        assert!(!inspected.encrypted);
        assert!(inspected.public_key.ends_with("test@host"));
        let _ = std::fs::remove_dir_all(&dir);
    }
}

pub fn read_public_key_fingerprint(key_path: &str) -> Result<String, String> {
    let content: String =
        std::fs::read_to_string(key_path).map_err(|e| format!("read failed: {}", e))?;

    let public_key: russh::keys::ssh_key::PublicKey = content
        .parse()
        .map_err(|e| format!("parse public key failed: {}", e))?;

    let fingerprint: String = public_key
        .fingerprint(russh::keys::HashAlg::Sha256)
        .to_string();
    Ok(fingerprint)
}
