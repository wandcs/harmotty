# HarmoTTY contributor-agent instructions

## Foundational rules

- Read and follow `docs/project-principles.md` before product, architecture,
  feature or refactoring work.
- Use `docs/next-work.md` as the only source of outstanding project work.
- Files under `docs/archive/` are historical and do not authorize new work.
- Do not add concepts, dependencies or abstraction layers without passing the
  decision rules in the project principles.
- Preserve unrelated worktree changes.

## Platform scope

HarmoTTY targets only a physical ARM64 HarmonyOS PC. Do not add or validate an
x86_64 emulator target unless the product scope is explicitly changed.

## PowerShell

Use `pwsh.exe -NoProfile` when PowerShell 7 is available. Otherwise use
`powershell.exe -NoProfile`. Run repository scripts with the per-process
`-ExecutionPolicy Bypass` option when required; do not change machine-wide
execution policy.

## Development and verification

```powershell
.\tools\dev-pc.ps1
.\tools\verify-pc.ps1
```

`dev-pc.ps1` is the normal build, test-sign, install and launch loop.
`verify-pc.ps1` is the checkpoint gate for tests, Rust formatting, a clean ARM64
native/debug HAP build and real-PC deployment.

Use `-SkipDevice` only when device-visible validation is not required and no
device is available. A physical PC is required for focus, keyboard, clipboard,
window, persistence, terminal-interaction and SSH-lifecycle claims.

Signing certificates, keystores and passwords are local-only and must never be
added to the repository.

## GitHub

Use the authenticated GitHub CLI for repository, issue, pull request, release
and account operations. Confirm the active account before a write operation.

## Editing and filesystem safety

- Keep generated files inside the repository's ignored directories or the
  system temporary directory.
- Use literal paths for data-derived filesystem operations.
- Never discard or overwrite unrelated user changes.
- Run the relevant tests and `git diff --check` for edited text.
