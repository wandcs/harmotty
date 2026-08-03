# Privacy Policy

> Applies to the current LeanTTY source tree. Released packages may contain an
> earlier feature set; use `CHANGELOG.md` and the matching GitHub release to
> determine the behavior of a specific version.
>
> Last updated: 2026-08-03

LeanTTY is designed as a local, account-free terminal. It does not include an
analytics SDK, advertising SDK, account system, telemetry service or LeanTTY
cloud service. The application does not intentionally upload terminal content,
credentials, host configuration or usage statistics to the maintainer.

This policy describes what the application itself does. HarmonyOS, the system
browser, an SSH server, AppGallery and software running on a remote host have
their own data practices.

## Network communication

LeanTTY initiates network communication only for actions requested by the user:

- an SSH connection to the host and port entered by the user or resolved from
  LeanTTY's OpenSSH-compatible configuration;
- opening an HTTP or HTTPS link in the system browser after the user activates
  that link; and
- distribution and update traffic handled by AppGallery or the operating
  system, outside the LeanTTY application process.

LeanTTY does not send connection metadata to a LeanTTY-operated server. The
selected SSH server necessarily receives the network address of the device and
the SSH protocol data needed to establish and use the session.

## Data stored on the device

| Data | Storage and lifetime | Purpose |
| --- | --- | --- |
| OpenSSH `config` and `known_hosts` | Encrypted persistent HarmonyOS Asset Store records, with application-private files materialized as a runtime projection | Resolve hosts and preserve host-key trust decisions |
| Verified private/public key pairs | Encrypted persistent HarmonyOS Asset Store records, with protected application-private files materialized for SSH use | Authenticate to hosts chosen by the user |
| Terminal font size and main-window rectangle | Encrypted persistent HarmonyOS Asset Store records, plus a local settings projection where needed | Restore the small set of user preferences |
| Passwords, private-key passphrases and authentication answers | Process memory only; not intentionally persisted | Complete the active authentication exchange |
| Tabs, panes, sessions, local command history and terminal screen/scrollback | Process memory only | Run the current application session and recover an ArkWeb surface rebuilt within that process |
| Exported key files | The user's Downloads directory after explicit export and permission approval | Give the user a portable copy of a selected key pair |
| Clipboard text | HarmonyOS system clipboard after copy/paste or an accepted OSC 52 clipboard write | Interoperate with the local desktop and terminal applications |
| Diagnostic logs | HarmonyOS logging facilities under system control | Diagnose lifecycle, connection and rendering failures |

Persistent records use the HarmonyOS Asset Store with encrypted attributes and
the persistent-data flag. LeanTTY splits larger values into integrity-checked
generations and switches the active manifest only after the new generation is
complete. The application does not expose this store through a cloud backup or
restore workflow.

An ordinary uninstall is not a reliable request to erase these persistent
records. They are intentionally retained so that the same application identity
can rematerialize the user's SSH assets and essential settings after reinstall.
Application-private runtime files may be removed by uninstall, but they are not
the long-term authority for retained data.

## Clipboard and terminal-controlled actions

- Pasting reads the system clipboard only as part of a user paste action.
- Copying writes selected text to the local-device system clipboard.
- Remote terminal output may request a clipboard write through OSC 52. LeanTTY
  accepts only the default/system clipboard selector, rejects clipboard reads,
  validates Base64 and UTF-8, and limits accepted content to 1 MiB.
- HTTP and HTTPS links are opened only after user activation. LeanTTY rejects
  other schemes, credential-bearing URLs and malformed destinations before
  handing a link to the system browser.

Clipboard contents and browser history are then governed by HarmonyOS and the
selected browser. LeanTTY does not upload either to the maintainer.

## Diagnostic data

LeanTTY does not intentionally log passwords, passphrases, private-key content
or terminal byte streams. Current on-device logs can contain operational
metadata such as connection endpoints, host aliases, remote-controlled terminal
titles, key fingerprints or application-private key paths, session identifiers,
window geometry, byte counts, timing and error details.

Do not share raw `hilog` output publicly. Before attaching diagnostic material,
remove usernames, hostnames, IP addresses, device identifiers, terminal
history, file paths, fingerprints, keys, passwords and tokens.

## User control and deletion

The current command surface provides scoped deletion:

- `key list` and `key rm <key-name>` list and delete verified key pairs;
- `host list` and `host rm <host-name>` list and delete Host entries created by
  LeanTTY; and
- `ssh-keygen -R <host>` or `ssh-keygen -R [<host>]:<port>` removes trusted
  host-key records for one exact endpoint.

Exported files in Downloads are user-owned and must be deleted through the
system file manager when no longer needed.

The current source does not provide one command that erases every persistent
record, including unmanaged OpenSSH configuration text, all unknown
`known_hosts` endpoints, font size and window geometry. Until a complete erasure
path is implemented and verified, do not assume that ordinary uninstall alone
removes all LeanTTY data. This limitation is part of the product's current data
lifecycle, not a promise of future behavior.

## Reports and questions

Privacy documentation problems may be reported through GitHub Issues after
removing private data. Suspected security vulnerabilities must use the private
process in [SECURITY.md](SECURITY.md).
