## Problem and scope

What problem does this solve, and how does it fit
`docs/project-principles.md`?

## Implementation

Describe the ownership boundary and any new long-lived state, dependency or
failure mode. Write “none” when applicable.

## Verification

- [ ] `tools/test-regression.ps1` passes.
- [ ] Relevant focused positive, negative and recovery tests pass.
- [ ] A clean ARM64 HAP candidate was retained when application code changed.
- [ ] A named physical scenario passed against that exact HAP when the change
      affects focus, keyboard, clipboard, windows, persistence, terminal
      interaction or SSH lifecycle.
- [ ] Required remote checks pass without administrative bypass.
- [ ] Documentation and release notes were updated when needed.

List commands and concise results:

```text

```

Candidate SHA-256 / mode / evidence file names (write “not applicable” for a
documentation-only change):

```text

```

## Privacy and licensing

- [ ] Logs and images are redacted.
- [ ] No credentials, signing files, packages, generated output, device
      identifiers or private environment paths are included.
- [ ] I have the right to submit this contribution under Apache-2.0.
