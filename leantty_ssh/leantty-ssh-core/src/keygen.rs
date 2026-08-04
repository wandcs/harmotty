use russh::keys::ssh_key::private::PrivateKey;
use std::path::{Path, PathBuf};

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

pub fn change_private_key_passphrase(
    key_path: &str,
    old_passphrase: &str,
    new_passphrase: &str,
) -> Result<(), String> {
    change_private_key_passphrase_with_replace(
        key_path,
        old_passphrase,
        new_passphrase,
        |temporary_path, target_path| {
            std::fs::rename(temporary_path, target_path)
                .map_err(|error| format!("replace private key failed: {}", error))
        },
    )
}

fn change_private_key_passphrase_with_replace<F>(
    key_path: &str,
    old_passphrase: &str,
    new_passphrase: &str,
    replace: F,
) -> Result<(), String>
where
    F: FnOnce(&Path, &Path) -> Result<(), String>,
{
    use russh::keys::ssh_key::LineEnding;
    use std::fs::OpenOptions;
    use std::io::Write;

    let target_path = Path::new(key_path);
    let original = std::fs::read_to_string(target_path)
        .map_err(|error| format!("read private key failed: {}", error))?;
    let parsed = PrivateKey::from_openssh(&original)
        .map_err(|error| format!("parse private key failed: {}", error))?;
    let private_key = if parsed.is_encrypted() {
        parsed
            .decrypt(old_passphrase)
            .map_err(|_| "old passphrase is incorrect".to_string())?
    } else {
        if !old_passphrase.is_empty() {
            return Err("old passphrase is incorrect".to_string());
        }
        parsed
    };

    let original_fingerprint = private_key
        .fingerprint(russh::keys::HashAlg::Sha256)
        .to_string();
    let original_public_key = private_key.public_key().to_string();
    let stored_key = if new_passphrase.is_empty() {
        private_key
    } else {
        private_key
            .encrypt(&mut rand::rng(), new_passphrase)
            .map_err(|error| format!("key encryption failed: {}", error))?
    };
    let encoded = stored_key
        .to_openssh(LineEnding::LF)
        .map_err(|error| format!("private key encoding failed: {}", error))?;

    let temporary_path = create_passphrase_temporary_path(target_path)?;
    let write_result = (|| -> Result<(), String> {
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options
            .open(&temporary_path)
            .map_err(|error| format!("create temporary private key failed: {}", error))?;
        file.write_all(encoded.as_bytes())
            .map_err(|error| format!("write temporary private key failed: {}", error))?;
        file.flush()
            .map_err(|error| format!("flush temporary private key failed: {}", error))?;
        file.sync_all()
            .map_err(|error| format!("sync temporary private key failed: {}", error))?;
        drop(file);

        let written = std::fs::read_to_string(&temporary_path)
            .map_err(|error| format!("verify temporary private key failed: {}", error))?;
        let written_key = PrivateKey::from_openssh(&written)
            .map_err(|error| format!("verify temporary private key failed: {}", error))?;
        let verified_key = if written_key.is_encrypted() {
            written_key
                .decrypt(new_passphrase)
                .map_err(|error| format!("verify temporary private key failed: {}", error))?
        } else {
            written_key
        };
        if verified_key
            .fingerprint(russh::keys::HashAlg::Sha256)
            .to_string()
            != original_fingerprint
            || verified_key.public_key().to_string() != original_public_key
        {
            return Err("temporary private key changed key identity or comment".to_string());
        }

        replace(&temporary_path, target_path)?;
        let _ = sync_parent_directory(target_path);
        Ok(())
    })();
    if write_result.is_err() {
        let _ = std::fs::remove_file(&temporary_path);
    }
    write_result
}

fn create_passphrase_temporary_path(target_path: &Path) -> Result<PathBuf, String> {
    let parent = target_path
        .parent()
        .ok_or_else(|| "private key path has no parent directory".to_string())?;
    let file_name = target_path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| "private key path has an invalid file name".to_string())?;
    for attempt in 0..100_u32 {
        let candidate = parent.join(format!(
            ".{}.ltty-passphrase-{}-{}.tmp",
            file_name,
            std::process::id(),
            attempt
        ));
        if !candidate.exists() {
            return Ok(candidate);
        }
    }
    Err("cannot allocate temporary private key path".to_string())
}

fn sync_parent_directory(target_path: &Path) -> Result<(), String> {
    #[cfg(unix)]
    {
        let parent = target_path
            .parent()
            .ok_or_else(|| "private key path has no parent directory".to_string())?;
        std::fs::File::open(parent)
            .and_then(|directory| directory.sync_all())
            .map_err(|error| format!("sync private key directory failed: {}", error))?;
    }
    Ok(())
}

pub fn export_key_pair(
    private_path: &str,
    public_path: &str,
    output_dir: &str,
    file_name: &str,
) -> Result<(), String> {
    use std::fs::{File, OpenOptions};
    use std::io::{self, Write};
    use std::path::Path;

    validate_export_file_name(file_name)?;

    let output_dir_path = Path::new(output_dir);
    if !output_dir_path.is_dir() {
        return Err("Downloads directory is unavailable".to_string());
    }

    let private_destination = output_dir_path.join(file_name);
    let public_destination = output_dir_path.join(format!("{}.pub", file_name));
    if private_destination.exists() || public_destination.exists() {
        return Err(format!("destination already exists: {}", file_name));
    }

    let mut private_source =
        File::open(private_path).map_err(|e| format!("open private key failed: {}", e))?;
    let mut public_source =
        File::open(public_path).map_err(|e| format!("open public key failed: {}", e))?;

    let mut private_options = OpenOptions::new();
    private_options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        private_options.mode(0o600);
    }
    let mut private_destination_file = private_options
        .open(&private_destination)
        .map_err(|e| format!("create export failed: {}", e))?;

    let public_result = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&public_destination);
    let mut public_destination_file = match public_result {
        Ok(file) => file,
        Err(error) => {
            drop(private_destination_file);
            let _ = std::fs::remove_file(&private_destination);
            return Err(format!("create public export failed: {}", error));
        }
    };

    let copy_result = (|| -> io::Result<()> {
        io::copy(&mut private_source, &mut private_destination_file)?;
        private_destination_file.flush()?;
        private_destination_file.sync_all()?;
        io::copy(&mut public_source, &mut public_destination_file)?;
        public_destination_file.flush()?;
        public_destination_file.sync_all()?;
        Ok(())
    })();
    if let Err(error) = copy_result {
        drop(private_destination_file);
        drop(public_destination_file);
        let _ = std::fs::remove_file(&private_destination);
        let _ = std::fs::remove_file(&public_destination);
        return Err(format!("write export failed: {}", error));
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

    std::fs::create_dir_all(output_dir).map_err(|e| format!("mkdir failed: {}", e))?;

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

fn validate_export_file_name(file_name: &str) -> Result<(), String> {
    if file_name.is_empty() || file_name == "." || file_name == ".." {
        return Err("invalid export file name".to_string());
    }
    if file_name.to_ascii_lowercase().ends_with(".pub")
        || !file_name
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '-'))
    {
        return Err("invalid export file name".to_string());
    }
    Ok(())
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

#[cfg(test)]
mod tests {
    use super::{
        change_private_key_passphrase, change_private_key_passphrase_with_replace, export_key_pair,
        generate_key_pair, inspect_private_key, load_private_key,
    };

    #[test]
    fn uses_requested_name_and_refuses_overwrite() {
        let dir = std::env::temp_dir().join(format!("leantty-keygen-{}", std::process::id()));
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
        let dir = std::env::temp_dir().join(format!("leantty-inspect-{}", std::process::id()));
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

    #[test]
    fn exports_key_pair_without_overwriting() {
        let root = std::env::temp_dir().join(format!("leantty-export-{}", std::process::id()));
        let source_dir = root.join("source");
        let downloads_dir = root.join("Downloads");
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&source_dir).unwrap();
        std::fs::create_dir_all(&downloads_dir).unwrap();

        let source_dir_text = source_dir.to_string_lossy().to_string();
        let downloads_dir_text = downloads_dir.to_string_lossy().to_string();
        let generated =
            generate_key_pair("ed25519", &source_dir_text, "deploy", "", "test@host").unwrap();
        export_key_pair(
            &generated.private_path,
            &generated.public_path,
            &downloads_dir_text,
            "deploy",
        )
        .unwrap();

        assert_eq!(
            std::fs::read(&generated.private_path).unwrap(),
            std::fs::read(downloads_dir.join("deploy")).unwrap()
        );
        assert_eq!(
            std::fs::read(&generated.public_path).unwrap(),
            std::fs::read(downloads_dir.join("deploy.pub")).unwrap()
        );
        assert!(export_key_pair(
            &generated.private_path,
            &generated.public_path,
            &downloads_dir_text,
            "deploy",
        )
        .is_err());
        export_key_pair(
            &generated.private_path,
            &generated.public_path,
            &downloads_dir_text,
            "deploy-backup",
        )
        .unwrap();
        assert_eq!(
            std::fs::read(&generated.private_path).unwrap(),
            std::fs::read(downloads_dir.join("deploy-backup")).unwrap()
        );
        assert_eq!(
            std::fs::read(&generated.public_path).unwrap(),
            std::fs::read(downloads_dir.join("deploy-backup.pub")).unwrap()
        );

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn public_name_conflict_leaves_no_partial_private_export() {
        let root =
            std::env::temp_dir().join(format!("leantty-export-conflict-{}", std::process::id()));
        let source_dir = root.join("source");
        let downloads_dir = root.join("Downloads");
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&source_dir).unwrap();
        std::fs::create_dir_all(&downloads_dir).unwrap();

        let source_dir_text = source_dir.to_string_lossy().to_string();
        let downloads_dir_text = downloads_dir.to_string_lossy().to_string();
        let generated = generate_key_pair("ed25519", &source_dir_text, "work", "", "").unwrap();
        std::fs::write(downloads_dir.join("work.pub"), "existing").unwrap();

        let error = export_key_pair(
            &generated.private_path,
            &generated.public_path,
            &downloads_dir_text,
            "work",
        )
        .unwrap_err();
        assert!(error.contains("destination already exists"));
        assert!(!downloads_dir.join("work").exists());
        assert_eq!(
            std::fs::read_to_string(downloads_dir.join("work.pub")).unwrap(),
            "existing"
        );

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn changes_passphrase_without_changing_key_identity_or_comment() {
        let root =
            std::env::temp_dir().join(format!("leantty-change-passphrase-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let root_text = root.to_string_lossy().to_string();
        let generated =
            generate_key_pair("ed25519", &root_text, "deploy", "old-secret", "test@host").unwrap();
        let before = inspect_private_key(&generated.private_path).unwrap();
        let before_bytes = std::fs::read(&generated.private_path).unwrap();
        let before_public = std::fs::read(&generated.public_path).unwrap();

        change_private_key_passphrase(&generated.private_path, "old-secret", "new-secret").unwrap();

        let after = inspect_private_key(&generated.private_path).unwrap();
        assert_eq!(after.fingerprint, before.fingerprint);
        assert_eq!(after.public_key, before.public_key);
        assert!(after.encrypted);
        assert_ne!(
            std::fs::read(&generated.private_path).unwrap(),
            before_bytes
        );
        assert_eq!(
            std::fs::read(&generated.public_path).unwrap(),
            before_public
        );
        assert!(load_private_key(&generated.private_path, "old-secret").is_err());
        let loaded = load_private_key(&generated.private_path, "new-secret").unwrap();
        assert_eq!(loaded.comment().as_str().unwrap(), "test@host");

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn supports_adding_and_removing_a_passphrase() {
        let root = std::env::temp_dir().join(format!(
            "leantty-add-remove-passphrase-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let root_text = root.to_string_lossy().to_string();
        let generated = generate_key_pair("ed25519", &root_text, "deploy", "", "").unwrap();

        change_private_key_passphrase(&generated.private_path, "", "new-secret").unwrap();
        assert!(
            inspect_private_key(&generated.private_path)
                .unwrap()
                .encrypted
        );
        change_private_key_passphrase(&generated.private_path, "new-secret", "").unwrap();
        assert!(
            !inspect_private_key(&generated.private_path)
                .unwrap()
                .encrypted
        );
        assert!(load_private_key(&generated.private_path, "").is_ok());

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn changes_rsa_passphrase_without_changing_the_public_key() {
        let root = std::env::temp_dir().join(format!(
            "leantty-rsa-change-passphrase-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let root_text = root.to_string_lossy().to_string();
        let generated =
            generate_key_pair("rsa", &root_text, "deploy_rsa", "old-secret", "rsa@host").unwrap();
        let public_before = std::fs::read(&generated.public_path).unwrap();

        change_private_key_passphrase(&generated.private_path, "old-secret", "new-secret").unwrap();

        let loaded = load_private_key(&generated.private_path, "new-secret").unwrap();
        assert_eq!(loaded.comment().as_str().unwrap(), "rsa@host");
        assert_eq!(
            std::fs::read(&generated.public_path).unwrap(),
            public_before
        );

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn wrong_old_passphrase_leaves_private_key_unchanged() {
        let root = std::env::temp_dir().join(format!(
            "leantty-wrong-old-passphrase-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let root_text = root.to_string_lossy().to_string();
        let generated =
            generate_key_pair("ed25519", &root_text, "deploy", "old-secret", "").unwrap();
        let before = std::fs::read(&generated.private_path).unwrap();

        let error =
            change_private_key_passphrase(&generated.private_path, "wrong-secret", "new-secret")
                .unwrap_err();

        assert!(error.contains("old passphrase is incorrect"));
        assert_eq!(std::fs::read(&generated.private_path).unwrap(), before);
        assert!(load_private_key(&generated.private_path, "old-secret").is_ok());

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn replacement_failure_leaves_private_key_unchanged_and_removes_temporary_file() {
        let root = std::env::temp_dir().join(format!(
            "leantty-passphrase-commit-failure-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let root_text = root.to_string_lossy().to_string();
        let generated = generate_key_pair("ed25519", &root_text, "deploy", "", "").unwrap();
        let before = std::fs::read(&generated.private_path).unwrap();

        let error = change_private_key_passphrase_with_replace(
            &generated.private_path,
            "",
            "new-secret",
            |_, _| Err("forced replacement failure".to_string()),
        )
        .unwrap_err();

        assert!(error.contains("forced replacement failure"));
        assert_eq!(std::fs::read(&generated.private_path).unwrap(), before);
        assert_eq!(std::fs::read_dir(&root).unwrap().count(), 2);

        let _ = std::fs::remove_dir_all(&root);
    }
}
