# HarmoTTY

HarmoTTY is a keyboard-first, zero-configuration remote terminal for ARM64
HarmonyOS PC, inspired by [Ghostty](https://ghostty.org).

The project aims to be reliable, quiet and native to HarmonyOS PC. Ghostty is a
reference for product quality, not a feature-parity target. Scope and technical
decisions follow the [project principles](docs/project-principles.md).

## Status

Version 1.0.0 has been submitted to Huawei AppGallery Connect and is under
review. This repository is the public source baseline; AppGallery availability
will be announced only after approval.

The source mapping between the submitted 1.0.0 build and this public baseline is
documented in [source provenance](docs/source-provenance.md). No signing
credential or generated application package is stored in Git.

## Features

- SSH password and private-key authentication
- OpenSSH `known_hosts` verification
- Multi-tab terminal with at most two panes per tab
- Keyboard-first focus, selection, copy and paste
- OpenSSH-compatible host configuration and key management
- Catppuccin Mocha and Latte themes
- Rust/russh transport through napi-ohos
- xterm.js rendering in ArkWeb

## Product scope

HarmoTTY currently targets only ARM64 HarmonyOS PC with keyboard and mouse. It
is an SSH terminal, not a local shell, Linux environment, file manager or
general remote-administration suite.

## Requirements

- Windows and DevEco Studio with HarmonyOS SDK API 6.1.1 (24)
- Rust 1.96+ with the `aarch64-unknown-linux-ohos` target
- An ARM64 HarmonyOS PC for interaction and lifecycle verification

## Build and verify

```powershell
rustup target add aarch64-unknown-linux-ohos

# Build only
.\tools\build-all.ps1

# Normal maintainer loop: build, test-sign, install and launch
.\tools\dev-pc.ps1

# Important checkpoint: tests, clean ARM64 build and real-PC deployment
.\tools\verify-pc.ps1
```

Device deployment requires a local signing configuration and certificate.
Those files are deliberately excluded from the repository. See
[the release process](docs/release-process.md) for the trust boundary.

## Architecture

```text
App Shell
  └─ Tab → Pane → Session
                 ├─ SSH Transport
                 ├─ Terminal Surface
                 └─ System Services
```

- ArkTS/ArkUI owns application state, windows, tabs, panes and system services.
- Rust/russh owns SSH transport, PTY and byte streams.
- ArkWeb/xterm.js owns terminal rendering, input, selection and resize.
- The bridge carries validated protocol messages; it does not contain business
  rules.

## Contributing

Issues and pull requests are welcome under the bounded policy in
[CONTRIBUTING.md](CONTRIBUTING.md). Feature proposals are evaluated against the
project principles before implementation.

Community expectations, support boundaries and the security reporting channel
are documented in:

- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Support](SUPPORT.md)
- [Security Policy](SECURITY.md)
- [Trademark Policy](TRADEMARKS.md)

## License

HarmoTTY is licensed under Apache-2.0. See [LICENSE](LICENSE).

Third-party components remain under their own licenses; see
[THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).
