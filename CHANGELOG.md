# Changelog

## [Unreleased]

No changes yet.

## [1.0.0] - 2026-07-26

First stable release for ARM64 HarmonyOS PC.

### Security
- SSH host key verification against known_hosts
- Private key file permissions set to 0600
- ssh-copy-id uses POSIX single-quote encoding (prevents shell injection)
- Repository-external signing configuration keeps certificates, keystores, and passwords out of source control

### Added
- SSH private key authentication (ed25519, rsa)
- Key management commands: ssh-keygen, ssh-copy-id, key list/show/rm/import
- OpenSSH-style host management
- Command history with Up/Down navigation
- Multi-tab and dual-pane terminal sessions
- Selection-aware copy actions and system clipboard integration
- HarmonyOS PC window, theme, and font-size persistence

### Changed
- Upgraded russh from 0.49.2 to 0.62.2 (CVE fixes)
- ARM64 HarmonyOS PC is the only supported build and release target
- Tab, pane, and SSH session ownership use stable pane identifiers
- Terminal output delivery drains pending data before bridge teardown
- Normal SSH exit keeps the current terminal screen and xterm scrollback visible
- Terminal spacing, scrollbar, zoom behavior, and alternate-screen wheel ownership were aligned with desktop terminal use

### Fixed
- Half-open SSH sessions are detected instead of remaining falsely connected
- UTF-8 and final terminal bytes are delivered before close/EOF notification
- Focus, Tab traversal, clipboard, resize, reconnect, and window lifecycle behavior on the target PC
- Encrypted and unencrypted private-key authentication, host-key confirmation, and connection cancellation
- Alternate-screen TUI scrolling no longer leaks into normal scrollback
- Terminal history is no longer replayed when a page resumes or a disconnected surface is recycled

### Removed
- Legacy command names (keygen, keypub, keypush, keyrm, keyimport)
- x86_64 emulator packaging from the supported 1.0 build path
- Application-level terminal history replay and its duplicate buffer

### Documentation
- Product and technical principles define the 1.0 scope
- `docs/next-work.md` is the sole active project checklist
- Release, versioning, security, and third-party notice documents are included
