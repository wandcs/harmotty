# LeanTTY Regression Test Standard

> Status: mandatory cross-version engineering standard
>
> Last updated: 2026-08-04
>
> Product acceptance: [`vision-acceptance.md`](vision-acceptance.md)

This document is the single authority for how every LeanTTY change is tested.
It turns the reliability and trust principles into repeatable evidence. `MUST`,
`MUST NOT`, `SHOULD` and `MAY` are normative. It contains no active task list:
feature-specific acceptance belongs in one technical design, while executable
gaps belong only in [`next-work.md`](next-work.md).

## Mandatory workflow

Every code change MUST use this sequence:

1. Before implementation, map the affected event chains to the
   [change-to-evidence matrix](#change-to-evidence-matrix). Add or update tests
   and device scenarios for every newly exposed failure mode.
2. During implementation, run focused tests as often as useful. All Rust
   formatting, compilation, clippy and tests MUST run in WSL; Windows supplies
   the OHOS SDK tools but is not a Rust build host.
3. Before committing, run `tools/test-regression.ps1`. A failed or interrupted
   run is not a pass.
4. Commit the intended change so the device candidate has an exact, clean Git
   identity. Run `tools/verify-pc.ps1` to execute the software gate again,
   perform one clean ARM64 HAP build and retain the exact signed candidate.
5. For device-visible behavior, run the applicable `verify-*-pc.ps1` scenario
   against that retained HAP without rebuilding it. The scenario MUST verify
   the changed behavior, relevant negative/recovery paths and secret/privacy
   boundaries, not merely install and launch.
6. Report the candidate SHA-256, verification mode, commands, concise results
   and evidence paths in the pull request. Required remote checks MUST pass.
   Administrative bypasses are not routine acceptance evidence.

Documentation-only changes MAY stop after the mapped documentation gate. A
design or task MUST explicitly justify any omitted layer; convenience, a small
diff or a previously successful build is not a justification.

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
| Signed install and launch | The selected test candidate can be installed and started on the target PC (`device-deployed`) | The changed behavior works |
| Physical-PC scenario | Device-visible event chain and real lifecycle behavior | Uncovered servers, networks or long-term use |
| Production manifest/signature | Exact commit, ABI, artifact hashes, signature and package identity | AppGallery approval or user outcome |
| Real-use/vision review | Sustained primary-device outcome and continued unique value | Future releases without renewed evidence |

Evidence must never be promoted across these boundaries. In particular,
`verify-pc.ps1 -SkipDevice`, a clean build, installation and application launch
are not substitutes for a physical interaction result.

## Standard commands

Mandatory software regression gate:

```powershell
.\tools\test-regression.ps1
```

Clean candidate build/deployment and current feature-specific physical scenario:

```powershell
.\tools\dev-pc.ps1
.\tools\verify-pc.ps1
.\tools\verify-key-passphrase-pc.ps1
```

`test-regression.ps1` runs public-source policy, workflow/helper tests, Web
terminal policy, trusted ArkTS tests, WSL Rust fmt/clippy/core tests and diff
checks. It writes a local JSON result under `build/verification/` even when a
check fails.

`verify-pc.ps1` reruns that gate, verifies generated-native source policy,
performs a clean ARM64 debug build and—unless `-SkipDevice` is used—installs and
launches the signed HAP on a physical PC. It retains the exact HAP outside the
volatile build tree with its SHA-256, Git identity and software evidence.

`dev-pc.ps1` is the fast development loop, not an acceptance gate.
`verify-key-passphrase-pc.ps1` is the first feature-owned physical scenario. It
installs an already retained clean candidate, drives real application state,
records JSON evidence and never rebuilds the HAP.

Public CI independently repeats the public subset. Neither CI nor a clean HAP
automatically proves a physical scenario.

## Candidate and evidence states

Retained candidates use only these monotonic modes:

| Mode | Meaning |
| --- | --- |
| `software` | Mandatory software gate and exact clean ARM64 HAP build passed |
| `device-deployed` | The same HAP was installed and launched on a physical ARM64 HarmonyOS PC |
| `device-behavior` | One or more named physical behavior scenarios passed against the same HAP |

A later lower-layer run MUST NOT downgrade a candidate. `device-deployed` MUST
NOT be described as physical behavior acceptance. Physical behavior evidence
MUST NOT promote a dirty candidate: commit first, rebuild once, then test that
unchanged HAP. Source, dependency, packaged resource, signature, HAP, relevant
platform or affected server changes invalidate the corresponding evidence.

Evidence files are machine-local and MUST NOT contain credentials, passphrases,
private keys, fixed device identifiers, private host addresses or unredacted
logs. Physical evidence MUST identify both the tested candidate and the clean
committed automation harness when they come from different commits. Public
summaries carry only the minimum redacted identity and result.

## Physical automation protocol

The maintainer agent owns routine device acceptance whenever the connected PC
and repository tools make it objectively possible. It MUST inspect device state,
drive the scenario and read logs/layouts itself. User validation is requested
only for an objective blocker such as a locked device without its dedicated
local test credential, a disconnected device, missing permission, unavailable
controlled server or a necessarily subjective judgment.

Every automated physical scenario MUST:

- resolve a ready physical ARM64 PC at runtime and never commit its identifier;
- install an exact retained candidate and record its SHA-256 before interaction;
- acquire a bounded screen-timeout override before launch and restore the prior
  device policy in `finally`, so unattended execution cannot silently relock;
- when HarmonyOS explicitly reports a locked screen, unlock only the dedicated
  test PC from a current-user plaintext credential stored outside the repository;
  inject numeric physical-key events without putting plaintext in commands,
  logs or evidence, and never type a credential on an already unlocked device;
- preflight every control and observation channel, including application PID,
  structured logs, layout capture and focused terminal input, before creating
  disposable device state;
- locate UI controls from current layout semantics and native bounds, not stale
  screenshots or Windows-scaled coordinates;
- inject terminal commands as deterministic numeric physical-key events, cover
  the complete printable-ASCII mapping, and require the command's structured
  result or actual side effect before proceeding;
- generate disposable names and secrets at runtime, keep secret input non-echoing
  and scan captured layouts/logs for disclosure;
- wait on observable state or a non-secret structured log marker; fixed sleeps
  MAY pace polling but MUST NOT decide success;
- cancel input through the application's real `Ctrl+C` state-machine path;
  ArkWeb's hidden textarea accessibility value MUST NOT be treated as the
  native local-command or secret-input buffer;
- cover the positive path plus applicable rejection, cancellation, retry,
  recovery and cleanup paths;
- report stage start/pass progress and duration so a stalled boundary is visible;
- write a machine-readable pass/fail record, including per-stage timing and the
  cleanup outcome, and capture bounded diagnostic artifacts on failure; and
- remove disposable device state in `finally`, independently verify absence in
  the application sandbox and forbid evidence promotion when cleanup fails.

Physical keyboard injection MAY be used only when the script verifies the
focused application, uses the covered numeric key mapping without an IME text
path, and verifies the resulting operation. ArkWeb's accessibility textarea is
useful for focus preflight and disclosure scans, but is not exact input evidence:
on the target PC it can omit rendered digits and diverge from the native buffer.

## Result classification

- **Pass:** every required assertion completed for one exact evidence identity.
- **Product failure:** the application produced an incorrect observable result.
- **Infrastructure failure:** the device, server, SDK, signing, transport or
  harness could not establish the required precondition.
- **Invalid/interrupted:** the candidate changed, evidence identity is missing,
  cleanup makes the result ambiguous, or the run stopped early.

Only **Pass** counts as acceptance. Infrastructure failures must be repaired and
rerun; they must not be relabeled as product passes or product regressions.

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

- exact known-host endpoint formatting/query/removal, including hashed and shared
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
