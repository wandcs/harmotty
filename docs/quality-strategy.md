# LeanTTY Quality and Verification Strategy

> Status: cross-version engineering baseline
>
> Last updated: 2026-08-03
>
> Product acceptance: [`vision-acceptance.md`](vision-acceptance.md)

This document defines how LeanTTY turns its reliability and trust principles
into repeatable evidence. It contains no active task list. Feature-specific
acceptance belongs in one technical design; current executable gaps belong only
in [`next-work.md`](next-work.md).

## Quality model

Every release candidate must preserve seven areas:

1. user trust and secret/data boundaries;
2. terminal input, output, resize and compatibility correctness;
3. SSH target, host-key, authentication, cancellation and recovery behavior;
4. Tab/Pane/Session ownership and isolation;
5. HarmonyOS keyboard, clipboard, window and lifecycle behavior;
6. a simple, observable and recoverable user path; and
7. exact source, artifact and release identity.

Passing a new feature scenario cannot compensate for a regression in one of
these permanent areas.

## Evidence layers

| Layer | Proves | Does not prove |
| --- | --- | --- |
| Documentation/source policy | Public tree, references and prohibited artifact rules are consistent | Runtime correctness |
| Rust pure-core tests | Key/file rules, known-host semantics, UTF-8 and other host-testable protocol policy | HarmonyOS/N-API integration |
| ArkTS unit tests | Ownership, parser, Bridge policy, interaction state, persistence format and pure UI policy | Real ArkUI/ArkWeb/device behavior |
| Web terminal policy tests | OSC 52, link, input, wheel, snapshot and xterm policy against packaged resources | HarmonyOS WebView lifecycle |
| Build-workflow tests | Locking, candidate retention and script control-flow policy | Product interaction |
| Public CI | Secret scan, public-source checks, Rust fmt/clippy/tests and Web policy on clean hosted runners | DevEco build, signing or physical-PC behavior |
| Clean ARM64 HAP build | ArkTS, N-API, Rust and packaged resources integrate for the only supported ABI | Focus, clipboard, lifecycle or SSH interoperability |
| Signed install and launch | The selected test candidate can be installed and started on the target PC | The changed behavior works |
| Physical-PC scenario | Device-visible event chain and real lifecycle behavior | Uncovered servers, networks or long-term use |
| Production manifest/signature | Exact commit, ABI, artifact hashes, signature and package identity | AppGallery approval or user outcome |
| Real-use/vision review | Sustained primary-device outcome and continued unique value | Future releases without renewed evidence |

Evidence must never be promoted across these boundaries. In particular,
`verify-pc.ps1 -SkipDevice`, a clean build, installation and application launch
are not substitutes for a physical interaction result.

## Standard commands

Public and host-testable checks:

```powershell
.\tools\check-public-source.ps1
wsl.exe --cd . -- cargo fmt --check --manifest-path ./leantty_ssh/Cargo.toml
wsl.exe --cd . -- cargo clippy --locked --manifest-path ./leantty_ssh/Cargo.toml -p leantty-ssh-core --all-targets -- -D warnings
wsl.exe --cd . -- cargo test --locked --manifest-path ./leantty_ssh/Cargo.toml -p leantty-ssh-core
node .\tools\web-terminal\test-terminal-policy.mjs
```

Maintainer loops:

```powershell
.\tools\dev-pc.ps1
.\tools\verify-pc.ps1
```

`verify-pc.ps1` performs fresh PowerShell syntax checks, build-workflow
regressions, generated-native source policy, Web terminal policy, trusted ArkTS
tests, Rust formatting, a clean ARM64 debug build and—unless `-SkipDevice` is
used—signed install and launch on a physical PC. It retains the verified HAP and
records SHA-256, Git commit/tree, dirty state and whether the device path ran.

Public CI additionally runs secret scanning, Rust clippy and pure-core tests.
Neither the script nor CI automatically proves the manual scenario matrix.

## Change-to-evidence matrix

| Change area | Minimum additional evidence |
| --- | --- |
| Parser/help/config semantics | Parser tests, help/reference update, supported/unsupported cases and no side effect before validation |
| SSH host-key/auth/session lifecycle | Controlled server, positive and negative protocol cases, cancellation/stale event cases, ARM64 build and physical keyboard/session validation |
| Terminal bytes/xterm/Bridge | Raw-byte and malformed-message tests, flow-control/snapshot regression, large TUI output and physical renderer interaction |
| Tab/Pane/focus/shortcuts | Ownership tests plus physical keyboard, system/IME conflict, selection and cross-Tab isolation |
| Clipboard or URL effects | Policy tests for allowed/denied payloads plus physical system-service behavior and privacy/security review |
| Persistent assets/migration | Format and failure-injection tests, atomic commit/delete/recovery, ordinary uninstall/reinstall, lock/reboot and different-signature physical matrix |
| Window/theme/font/lifecycle | ArkTS policy tests, clean build and physical minimize/background/restore/restart behavior |
| Dependency upgrade | Lockfile/license/source checks plus all behavior owned by that dependency; xterm/russh updates require their terminal/SSH regression areas |
| Release or signing workflow | Script regression, clean detached checkout, version alignment, signed manifest/hash verification and candidate continuity |
| Documentation-only | Link/reference, status/authority, TODO uniqueness, wording consistency and `git diff --check`; no build unless the document changes generated/package behavior |

Risk raises the gate. A tiny code diff in host trust, authentication, terminal
bytes, persistence or release identity remains high risk.

## Permanent automated regression areas

The automated suite should keep stable ownership over:

- exact known-host endpoint formatting/removal, including hashed and shared
  records;
- key name/path safety, pair verification, no-overwrite export and failure
  cleanup;
- supported command parsing and explicit rejection of unsafe/unknown syntax;
- `Tab → Pane → Session` creation, focus, close and isolation;
- cancellation and clean/unexpected close classification;
- Bridge direction/channel/kind validation, bounded payloads and ACK ordering;
- raw UTF-8 split boundaries and high-density TUI output;
- OSC 52, URL, selection, input, wheel, bell and snapshot policy;
- persistent record encoding, chunking, manifest integrity and generation
  failure; and
- build locks, candidate retention and release preflight behavior.

A test name should state the contract. Tests must avoid real credentials,
production hosts, device identifiers and unredacted logs.

## Permanent physical-PC regression areas

For a candidate whose changes can affect them, exercise on a physical ARM64
HarmonyOS PC:

- application launch, window controls, geometry, theme and font restoration;
- physical keyboard input, modifiers, IME, focus and terminal query responses;
- Tab and two-Pane isolation, focus restoration and close confirmation;
- local selection, copy, paste, tmux mouse mode, OSC 52 and URL activation;
- direct password, encrypted/unencrypted keys, host trust and changed-key
  recovery against a controlled SSH server;
- cancel, timeout, server rejection, clean exit, unexpected close, reconnect
  and two concurrent Sessions;
- UTF-8, wide characters, resize, scrollback, Shell, tmux, editor and Agent TUI;
- minimize, background, lock, sleep, network loss/change, renderer exit and
  application termination; and
- persistent asset create/update/delete, ordinary uninstall/reinstall, reboot,
  lock state and different signing identity when applicable.

The exact feature-specific subset belongs in the design and current work item.
This list defines the permanent regression domains, not a checkbox log.

## Controlled environments

Protocol claims require a controlled server configuration that records server
software/version, authentication methods, host-key algorithms, shell and test
account policy. Temporary credentials and server state belong outside the
repository and must be destroyed after the run.

Compatibility claims must identify the actual environment. “SSH-compatible”
does not mean every OpenSSH option, server product, crypto policy or enterprise
access system. User-visible supported behavior is documented in
[`user-guide.md`](user-guide.md); proposed coverage remains in the roadmap and
technical designs.

## Performance and reliability measurement

Do not choose an optimization target from intuition. First record distributions
for the relevant workload and environment, such as startup, connect time, input
latency, sustained output, renderer ACK/backpressure, memory or sleep/recovery.
Keep correctness and loss detection as hard constraints.

A measured default is not a permanent optimum. Re-run the same workload after
changes to xterm, ArkWeb, Bridge flow control, Rust/russh, buffering or lifecycle
retention. A build-only comparison is not a user-experience result.

## Evidence record

Every release-candidate conclusion must be attributable to:

- exact LeanTTY version, commit/tree and working-tree state;
- HAP/APP hash, ABI and signing role where relevant;
- device model, HarmonyOS version and connection/deployment route;
- SSH server, network and representative Shell/TUI workload;
- commands or manual actions performed;
- expected and observed results, including failures and exclusions; and
- which layer the evidence proves.

Private host, credential, signing and device details stay outside the public
repository. Public summaries must be redacted without removing the information
needed to understand the result.

Only reuse evidence when the candidate and affected event chain are unchanged.
A new package, signature, dependency, platform version or relevant source change
requires new evidence at the affected layers.

## Release and vision gates

Core quality failure blocks the release and the repair enters
`next-work.md`. A passing release gate does not prove that users can sustain
HarmonyOS PC as their primary command-line device. That longer outcome is
reviewed only through [`vision-acceptance.md`](vision-acceptance.md), using real
work cycles and the current alternative-product landscape.
