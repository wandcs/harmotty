use data_encoding::BASE64;
use hmac::{Hmac, KeyInit, Mac};
use sha1::Sha1;

#[derive(Debug, Eq, PartialEq)]
pub struct KnownHostsRemoval {
    pub content: String,
    pub removed: u32,
}

#[derive(Debug, Eq, PartialEq)]
pub struct KnownHostsQuery {
    pub output: String,
    pub found: u32,
}

pub fn format_known_hosts_target(host: &str, port: u16) -> String {
    if port == 22 {
        host.to_string()
    } else {
        format!("[{host}]:{port}")
    }
}

pub fn remove_known_host_entries(
    content: &str,
    host: &str,
    port: u16,
) -> Result<KnownHostsRemoval, String> {
    validate_host(host)?;

    let target = format_known_hosts_target(host, port);
    let mut output = String::with_capacity(content.len());
    let mut removed = 0_u32;

    for complete_line in content.split_inclusive('\n') {
        let (line, ending) = split_line_ending(complete_line);
        match remove_target_from_line(line, &target) {
            LineEdit::Unchanged => output.push_str(complete_line),
            LineEdit::Removed => removed += 1,
            LineEdit::Replaced(replacement) => {
                removed += 1;
                output.push_str(&replacement);
                output.push_str(ending);
            }
        }
    }

    Ok(KnownHostsRemoval {
        content: output,
        removed,
    })
}

pub fn find_known_host_entries(
    content: &str,
    host: &str,
    port: u16,
) -> Result<KnownHostsQuery, String> {
    validate_host(host)?;

    let target = format_known_hosts_target(host, port);
    let mut output = String::new();
    let mut found = 0_u32;
    for (index, complete_line) in content.split_inclusive('\n').enumerate() {
        let (line, _) = split_line_ending(complete_line);
        if !line_matches_target(line, &target) {
            continue;
        }
        found += 1;
        output.push_str(&format!("# Host {target} found: line {}\n", index + 1));
        output.push_str(line);
        output.push('\n');
    }

    Ok(KnownHostsQuery { output, found })
}

fn validate_host(host: &str) -> Result<(), String> {
    if host.is_empty() || host.chars().any(char::is_control) {
        return Err("invalid known_hosts host".to_string());
    }
    Ok(())
}

enum LineEdit {
    Unchanged,
    Removed,
    Replaced(String),
}

fn remove_target_from_line(line: &str, target: &str) -> LineEdit {
    let Some((start, end)) = host_field_bounds(line) else {
        return LineEdit::Unchanged;
    };
    let host_field = &line[start..end];
    let mut retained = Vec::new();
    let mut matched = false;
    for pattern in host_field.split(',') {
        if pattern_matches(target, pattern) {
            matched = true;
        } else {
            retained.push(pattern);
        }
    }
    if !matched {
        return LineEdit::Unchanged;
    }
    if retained.is_empty() {
        return LineEdit::Removed;
    }
    LineEdit::Replaced(format!(
        "{}{}{}",
        &line[..start],
        retained.join(","),
        &line[end..]
    ))
}

fn line_matches_target(line: &str, target: &str) -> bool {
    let Some((start, end)) = host_field_bounds(line) else {
        return false;
    };
    line[start..end]
        .split(',')
        .any(|pattern| pattern_matches(target, pattern))
}

fn host_field_bounds(line: &str) -> Option<(usize, usize)> {
    let bytes = line.as_bytes();
    let mut offset = skip_ascii_whitespace(bytes, 0);
    if offset >= bytes.len() || bytes[offset] == b'#' {
        return None;
    }

    let first_start = offset;
    offset = skip_ascii_non_whitespace(bytes, offset);
    let first_end = offset;
    if line[first_start..first_end].starts_with('@') {
        offset = skip_ascii_whitespace(bytes, offset);
        if offset >= bytes.len() {
            return None;
        }
        let host_start = offset;
        let host_end = skip_ascii_non_whitespace(bytes, offset);
        Some((host_start, host_end))
    } else {
        Some((first_start, first_end))
    }
}

fn skip_ascii_whitespace(bytes: &[u8], mut offset: usize) -> usize {
    while offset < bytes.len() && bytes[offset].is_ascii_whitespace() {
        offset += 1;
    }
    offset
}

fn skip_ascii_non_whitespace(bytes: &[u8], mut offset: usize) -> usize {
    while offset < bytes.len() && !bytes[offset].is_ascii_whitespace() {
        offset += 1;
    }
    offset
}

fn pattern_matches(target: &str, pattern: &str) -> bool {
    if !pattern.starts_with("|1|") {
        return target == pattern;
    }

    let mut parts = pattern.split('|').skip(2);
    let Some(salt) = parts.next().and_then(decode_base64) else {
        return false;
    };
    let Some(expected) = parts.next().and_then(decode_base64) else {
        return false;
    };
    if parts.next().is_some() {
        return false;
    }
    let Ok(mac) = Hmac::<Sha1>::new_from_slice(&salt) else {
        return false;
    };
    mac.chain_update(target).verify_slice(&expected).is_ok()
}

fn decode_base64(value: &str) -> Option<Vec<u8>> {
    BASE64.decode(value.as_bytes()).ok()
}

fn split_line_ending(line: &str) -> (&str, &str) {
    if let Some(body) = line.strip_suffix("\r\n") {
        (body, "\r\n")
    } else if let Some(body) = line.strip_suffix('\n') {
        (body, "\n")
    } else {
        (line, "")
    }
}
