# Security Policy

## Supported versions

| Version | Security support |
|---|---|
| 1.0.x | Supported |
| Older development snapshots | Not supported |

Security reports are handled on a best-effort basis. The project does not
promise a fixed response or remediation deadline.

## Reporting a vulnerability

Do not open a public issue, discussion or pull request for a suspected
vulnerability.

Use GitHub's private vulnerability-reporting form:

<https://github.com/wandcs/harmotty/security/advisories/new>

Include the affected version or commit, impact, reproduction steps and any
suggested mitigation. Remove real credentials, private keys, device identifiers
and production host information from the report.

If the form is unavailable, contact the maintainer through the private contact
method shown on the GitHub profile rather than publishing the details.

## Security boundaries

- Private keys are stored in the HarmonyOS application sandbox with restrictive
  file permissions.
- Passwords and passphrases are not intentionally persisted and sensitive Rust
  values are zeroized where supported.
- Host keys are checked against OpenSSH-compatible `known_hosts` data.
- The ArkWeb terminal uses a Content Security Policy and a validated bridge
  protocol.
- Clipboard writes and reads originate from explicit application actions.
- Signing keys and production credentials are kept outside the source
  repository.

## Known limitations

- Development builds use a local test-signing identity and are not official
  distribution artifacts.
- ArkWeb/xterm.js currently requires CSP `unsafe-eval`.
- HarmoTTY inherits security assumptions and update cadence from HarmonyOS,
  ArkWeb and its third-party dependencies.
- Terminal output and remote applications are untrusted input; bugs in parsing,
  rendering or bridge validation may still exist.

Official release provenance and hashes are published separately from the source
tree. A package obtained from an unofficial fork should not be treated as an
official HarmoTTY build.
