# Changelog

## [Unreleased]

### Development

- Added `key export <key-name> [<file-name>]` to copy a verified OpenSSH
  private/public key pair directly to Downloads under an optional basename,
  failing without overwrite when either destination name already exists.
- Serialized all build-output writers across worktrees of the same repository,
  made the native cache independent of cleaned Cargo output, and retained only
  the five most recent verified test-signed HAP candidates outside volatile
  build directories for rebuild-free device installation.
- Added owner-isolated persistent custody for SSH configuration, verified key
  pairs, trusted host keys, terminal font size and window geometry so the same
  application identity can rematerialize them after a normal uninstall and
  reinstall without exposing a backup or restore workflow.
- Added a fail-fast AppGallery release preflight and a single build, comparison
  and archive command that keeps production upload artifacts separate from the
  test-signed HAP used for device acceptance and review media.
- Removed the duplicated hard-coded release version from the build script;
  artifact naming now derives from the application version unless a formal
  release explicitly supplies and validates `-ReleaseId`.

### Documentation

- Recorded the public AppGallery release of 1.0.1 and selected the authorized
  1.1.0 authentication and workspace-navigation scope.

## [1.0.1] - 2026-07-28

### Security

- Updated `russh` to 0.62.4 to address three remote panic conditions reported
  against earlier 0.62.x releases.

### Changed

- Renamed the application from HarmoTTY to LeanTTY and replaced the application
  identity, icon, bundle name, package names, local prompt and release artifact
  names with the LeanTTY identity.
- Removed the standalone Copy action from the tool menu while keeping the
  existing keyboard and selection-aware copy paths.
- Made unknown commands at the disconnected `ltty>` prompt point to both
  `help` and the direct `ssh user@host` path.

### Fixed

- Redrew the disconnected `ltty>` command line after edits so deleting or
  moving across Chinese wide characters no longer leaves stale terminal cells.
- Asked for confirmation before closing LeanTTY while any SSH session is
  active, while avoiding a duplicate prompt after confirming closure of the
  final connected tab.
- Let the top tab strip use all remaining title-bar width after window controls,
  fixed actions and drag space instead of imposing a fixed viewport cap.
- Cleared a pane's persistent bell-attention border when the user types or
  pastes in that pane, without letting background output or automatic focus
  restoration acknowledge it.
- Kept embedded Nerd Font icons inside their terminal cells so prompt and icon
  glyphs no longer overlap adjacent text.
- Restored the complete pure-core UTF-8 burst test fixture so Linux public CI
  compiles and runs the test suite.
- Balanced terminal insets around full-screen TUIs by offsetting the scrollbar
  gutter and centering unused cell-grid height without reducing rows or columns.
- Routed HTTP(S) and OSC 8 terminal links through the HarmonyOS system browser
  with `Ctrl+Click` normally and `Ctrl+Shift+Click` while tmux or another TUI
  owns mouse reporting, without stealing ordinary TUI mouse input or leaving
  xterm in text-selection drag mode after the browser handoff.

## [1.0.0] - 2026-07-26

**AppGallery submission rejected; not published.**

First stable submission candidate for ARM64 HarmonyOS PC. The application
package and signed `v1.0.0` tag remain immutable rejection evidence; no user
received this version.

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
