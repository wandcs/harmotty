# LeanTTY coding guide

This guide describes the stable implementation boundaries and verification
rules for the current ARM64 HarmonyOS PC product.

Read [`architecture.md`](architecture.md) for the current event chains and
persistence model, [`security-model.md`](security-model.md) for trust
boundaries, and [`quality-strategy.md`](quality-strategy.md) for the complete
evidence mapping. This guide remains the concise coding discipline.

## Start with ownership

The domain model is:

```text
App Shell
  └─ Tab → Pane → Session
                 ├─ SSH Transport
                 ├─ Terminal Surface
                 └─ System Services
```

- A tab owns one or two panes.
- Each pane owns one session through a stable identifier.
- A session owns connection lifecycle and terminal interaction.
- Mutable state has one authoritative owner.
- Array adjacency, selected indices, WebView instances and UI labels must not
  stand in for ownership.

The older `Page → ViewModel → Model → Common` direction is a useful dependency
hint, not a reason to obscure state ownership.

## Responsibility boundaries

- **App Shell** owns windows, tabs, panes, focus and global preferences.
- **Session** owns connect, authenticate, host-key, cancel, disconnect and
  reconnect state.
- **SSH Transport** owns russh, PTY and byte streams; it does not decide UI text.
- **Terminal Surface** owns xterm display, input, selection and resize; it does
  not own business state.
- **System Services** wrap HarmonyOS clipboard, preferences and window APIs.
- **Bridge** carries validated structured messages and no business rules.
- **UI** renders state and sends user intent without coordinating several lower
  layers directly.

Add a type or layer only when it owns a real lifecycle, encapsulates a testable
policy, isolates a platform/protocol boundary, or materially simplifies the
core state machine.

## Repository map

| Path | Purpose |
|---|---|
| `AppScope/` | Application-level HarmonyOS resources and configuration |
| `entry/src/main/ets/` | ArkUI application, state and platform integration |
| `entry/src/main/resources/` | HarmonyOS resources and ArkWeb terminal assets |
| `entry/src/test/` | Trusted ArkTS logic tests |
| `leantty_ssh/` | napi-ohos binding and SSH transport |
| `leantty_ssh/leantty-ssh-core/` | Host-testable pure Rust policies |
| `tools/web-terminal/` | xterm source assembly and policy tests |
| `tools/` | ARM64 build, deployment and verification scripts |
| `docs/` | Product governance, user contract, architecture, quality, current work and stable manuals |

Generated native libraries, HAP/APP packages, caches and signing material are
not source and must remain untracked.

## ArkTS and ArkWeb

- Follow the repository linter; do not bypass type restrictions with `any`,
  `unknown` or broad casts.
- Use structured events and explicit state instead of inferring state from UI
  text, output fragments or timing.
- Keep one implementation entry for each behavior; do not patch the same rule
  independently in ArkUI, WebView and Rust.
- Validate every bridge message's version, direction, channel, kind and payload
  before dispatch.
- Treat terminal output and remote-controlled titles as untrusted data.
- Preserve runtime-measured xterm dimensions; fitting must account for actual
  container padding and WebView size.

## Rust transport

- Keep transport concerns below the N-API boundary.
- Never log passwords, passphrases, private keys or unredacted host material.
- Preserve deterministic cancellation and disconnect behavior.
- Keep pure policy in `leantty-ssh-core` when it can be tested without
  HarmonyOS or N-API.
- Run formatting on the whole workspace and clippy/tests on the pure core.

## Verification

Public checks:

```powershell
.\tools\check-public-source.ps1
cargo fmt --check --manifest-path .\leantty_ssh\Cargo.toml
cargo clippy --locked --manifest-path .\leantty_ssh\Cargo.toml -p leantty-ssh-core --all-targets -- -D warnings
cargo test --locked --manifest-path .\leantty_ssh\Cargo.toml -p leantty-ssh-core
node .\tools\web-terminal\test-terminal-policy.mjs
```

The pinned Rust channel is Windows-specific. On a Windows host without MinGW
GCC, run the pure-core test from a WSL shell at the mounted checkout with
`cargo +stable test`; keep OHOS N-API and HAP verification on the Windows
DevEco toolchain.

Maintainer application gate:

```powershell
.\tools\dev-pc.ps1
.\tools\verify-pc.ps1
```

Automated tests prove pure logic and protocol behavior. ARM64 builds prove
target integration. Only a physical HarmonyOS PC proves focus, keyboard,
clipboard, windows, persistence, terminal interaction and SSH lifecycle.

## Change discipline

- Outstanding work belongs only in `docs/next-work.md`.
- Product, feature and refactoring decisions must pass
  `docs/project-principles.md`.
- Do not add unsupported device layouts, x86_64 emulator paths, local shells,
  plugin systems or speculative compatibility layers.
- Preserve unrelated worktree changes.
- Keep credentials, certificates, device identifiers and private environment
  data out of source, tests, screenshots and logs.
