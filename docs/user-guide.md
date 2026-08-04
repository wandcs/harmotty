# LeanTTY User Guide

> Status: current-source user contract
>
> Last updated: 2026-08-03
>
> Applies to: the current repository `main`/`Unreleased` behavior. The public
> 1.0.1 release may not contain every command described here; check the matching
> GitHub Release and `CHANGELOG.md` before relying on a capability.

LeanTTY is a keyboard-first SSH terminal for a physical ARM64 HarmonyOS PC. It
provides the TTY entry point; the shell, tmux, editor and Agent TUI continue to
run in the selected execution environment.

## Product model

- The application starts at a local `ltty>` prompt.
- A tab owns one or two panes.
- Each pane owns one independent SSH session and terminal surface.
- Closing a connected pane disconnects its SSH session.
- Closing the application with active sessions asks for confirmation and then
  disconnects those sessions.
- LeanTTY does not provide a local shell, Linux distribution, package manager,
  file manager, background session service or account/cloud workspace.

The only supported application target is a physical ARM64 HarmonyOS PC used
with a keyboard and mouse. Other device classes and an x86_64 emulator are not
part of the product contract.

## First connection

At `ltty>`, connect directly with a username and host:

```text
ssh user@example.com
ssh -p 2222 user@example.com
ssh -i id_work user@example.com
```

IPv6 literals can be written in brackets. A non-default port can use `-p`; the
`user@[address]:port` form is also accepted by the current parser.

On the first connection to an endpoint, LeanTTY displays the received host-key
fingerprint and waits for the explicit trust decision. Verify the fingerprint
through a channel you already trust before accepting it. A later host-key
change stops the connection and shows the exact cleanup command; LeanTTY does
not automatically delete or replace the old trust record.

Current source authentication supports a direct password, an unencrypted
private key, or an encrypted private key with an interactive passphrase. SSH
`keyboard-interactive`, authentication banners and multi-method authentication
are part of the 1.1 work in progress and must not be treated as delivered until
the matching release says so.

## Saved hosts and OpenSSH configuration

Create a short Host name with:

```text
host add work user@example.com
host add lab user@example.com:2222
host set work user@new.example.com:2222
host list
host rm work
```

Then connect with:

```text
ssh work
```

`host rm` removes only Host entries created inside LeanTTY's managed section.
It does not silently rewrite unrelated OpenSSH configuration.

The current documented `ssh_config` subset is:

| Directive | Current behavior |
| --- | --- |
| `Host` | Literal names plus `*`, `?` and `!` pattern matching |
| `HostName` | Resolves the network destination |
| `User` | Required when connecting by Host name |
| `Port` | Defaults to 22 |
| `IdentityFile` | Selects a verified LeanTTY key by supported reference |

OpenSSH first-value behavior is preserved for these fields. An unknown or
unsupported directive in a matching Host block causes `ssh` and `ssh -G` to
fail with the directive and line number before a connection starts. Because
LeanTTY does not yet evaluate `Match` conditions, any `Match` block is rejected
instead of being silently ignored. Unsupported directives in unrelated Host
blocks do not block the selected Host, and LeanTTY preserves their source text
when it edits its own managed Host section.

Inspect the effective supported fields without connecting:

```text
ssh -G work
```

## Key management

Generate a key pair:

```text
ssh-keygen -t ed25519 -f id_work -C work
ssh-keygen -t rsa -f id_rsa_work -C work
```

The generation command creates Ed25519 or RSA-4096 keys and refuses to overwrite
an existing private or public file. It does not currently ask for a new key
passphrase. An encrypted OpenSSH private key can be imported and will request
its passphrase when used.

Change, add or remove the passphrase of a verified private key:

```text
ssh-keygen -p -f id_work
```

LeanTTY asks for the old passphrase, the new passphrase and confirmation through
non-echoing terminal input. Leave the old passphrase empty for an unencrypted
key, or leave the new passphrase empty to remove encryption. `Ctrl+C`, a wrong
old passphrase, a confirmation mismatch or a commit failure leaves the existing
key active. Passphrases are not accepted through command options.

Inspect and manage verified keys:

```text
key list
ssh-keygen -y -f id_work
ssh-keygen -l -f id_work
key import <accessible-path> id_imported
key export id_work
key export id_work id_work_copy
key rm id_work
```

Important behavior:

- Import accepts a private-key file path available to the application, derives
  and verifies the matching public key, and rejects an incomplete or invalid
  pair.
- Export requests access to the HarmonyOS Downloads directory and writes both
  the private key and `<name>.pub`.
- Export never overwrites either destination. Choose another basename when one
  already exists.
- Exported private keys are sensitive user-owned files. Move or delete them as
  soon as the intended transfer is complete.
- Deleting a key requires confirmation and removes both its persistent record
  and application-private projection.

Install a public key on a server through the existing SSH path:

```text
ssh-copy-id -i id_work user@example.com
ssh-copy-id -i id_work -p 2222 user@example.com
```

The command installs one public-key line and does not duplicate an identical
existing line. It is a bounded helper, not a general remote file editor.

## Host-key maintenance

Find every matching algorithm record for one exact endpoint without changing
the trust store:

```text
ssh-keygen -F example.com
ssh-keygen -F [example.com]:2222
```

Remove every matching algorithm record for one exact endpoint:

```text
ssh-keygen -R example.com
ssh-keygen -R [example.com]:2222
```

Default port 22 uses the plain host target. Non-default ports must use the
OpenSSH `[host]:port` form. After removal, reconnect and verify the new
fingerprint before accepting it.

## Current local command reference

| Command | Purpose |
| --- | --- |
| `help`, `?`, `help <command>`, `<command> --help` | Show local help |
| `ssh [-p port] [-i identity] user@host` | Connect directly |
| `ssh [-p port] [-i identity] host-name` | Connect through saved configuration |
| `ssh -G host-name` | Show the supported effective configuration |
| `ssh-keygen -t ...`, `-y`, `-l`, `-p`, `-F`, `-R` | Generate, inspect or maintain SSH assets |
| `ssh-copy-id -i ...` | Install one public key |
| `key list/import/export/rm` | Manage LeanTTY key pairs |
| `host add/set/list/rm` | Manage LeanTTY Host entries |
| `exit` | Close the current idle pane or tab path |

Legacy `alias` and `keys` spellings remain temporarily accepted but are not the
recommended command surface.

## Keyboard and mouse interaction

| Action | Current interaction |
| --- | --- |
| New tab | `Ctrl+Shift+T` |
| Split the current tab | `Ctrl+Shift+D` |
| Close the active pane | `Ctrl+Shift+W` |
| Increase/decrease/reset font size | `Ctrl+=`, `Ctrl+-`, `Ctrl+0` |
| Copy a local selection | `Ctrl+C`; without a selection it remains terminal `Ctrl+C` |
| Paste | `Ctrl+V` or secondary click when no selection exists |
| Secondary-click with a selection | Copy the selection |
| Open an HTTP(S) or OSC 8 link | Hold `Ctrl` and left-click |
| Open a link while a TUI owns the mouse | `Ctrl+Shift+Left Click` |
| Force local selection while a TUI owns the mouse | Hold `Shift` and drag |

With tmux mouse mode enabled, an ordinary drag belongs to tmux. Releasing its
selection can copy through the standard OSC 52 system-clipboard path. LeanTTY
does not support OSC 52 clipboard reads.

The split divider can be dragged. When it has keyboard focus, Left/Right adjust
the ratio and Enter resets the split to equal widths.

## Data retention and uninstall

LeanTTY keeps OpenSSH config, trusted host keys, verified key pairs, terminal
font size and the main-window rectangle in encrypted persistent HarmonyOS Asset
Store records. They are configured to survive a normal uninstall and be
rematerialized for the same application identity after reinstall; the complete
asset/signature/lifecycle matrix remains a physical-device release gate.

Passwords, passphrases, authentication answers, command history, tabs, panes,
sessions and terminal screen/scrollback are not intentionally persisted across
application termination or reinstall. A terminal snapshot used to rebuild an
ArkWeb surface exists only in the running process.

Ordinary uninstall is not a complete data-erasure command. Before uninstall,
use `key rm`, `host rm` and `ssh-keygen -R` for assets you can identify. The
current source has no single supported command that removes every retained
record. See [the privacy policy](../PRIVACY.md) for the exact boundary.

## Recovery and troubleshooting

- **Connection appears stuck:** press `Ctrl+C`. Connecting and authentication
  prompts have an explicit cancellation path and return to `ltty>`.
- **Host key changed:** do not bypass the warning. Verify the change, run the
  exact `ssh-keygen -R` command shown by LeanTTY, reconnect and inspect the new
  fingerprint.
- **Password keeps being requested:** confirm that the Host resolves a `User`
  and that `IdentityFile` names a key shown by `key list`.
- **Key export failed:** grant Downloads access and make sure neither the
  private basename nor its `.pub` partner already exists.
- **Renderer was rebuilt:** the in-process terminal framebuffer and output
  received while detached are restored before new interaction. This is not a
  persistent shell session; use remote tmux or screen for durable work.
- **SSH disconnected after sleep or network change:** use the visible reconnect
  path. LeanTTY does not claim transparent SSH session roaming.

For a reproducible product defect, follow [SUPPORT.md](../SUPPORT.md). Remove
private data from screenshots and logs. Security vulnerabilities must use the
private process in [SECURITY.md](../SECURITY.md).
