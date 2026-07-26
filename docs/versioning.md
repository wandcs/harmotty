# Versioning Policy

HarmoTTY follows Semantic Versioning 2.0.0.

## Format

```
MAJOR.MINOR.PATCH
```

| Level | When to bump | Example |
|---|---|---|
| MAJOR | Breaking changes (protocol, N-API, config format) | `1.0.0` → `2.0.0` |
| MINOR | New features (backward-compatible) | `1.0.0` → `1.1.0` |
| PATCH | Bug fixes only | `1.0.0` → `1.0.1` |

## Pre-release Versions

Before 1.0.0, development releases used `0.x.y` and could include breaking
changes.

| Version | Meaning |
|---|---|
| `0.1.0` | Initial development |
| `0.2.0` | SSH password auth + basic terminal |
| `0.3.0` | Key auth, key management, config |
| `0.4.0` | Tab system, themes, UI components |
| `0.5.0` | Split pane, Toolbar, interaction stabilization |
| `0.9.0` | Feature complete, stabilization |
| `1.0.0` | First stable release |

### Stable 1.0 releases

- HarmoTTY publishes `1.0.0` directly without a public release-candidate
  version.
- A release package must be built from an exact commit already pushed to
  `wandcs/harmotty`; local-only source is never a release input.
- Any code, dependency, resource, version or packaging change requires a new
  pushed commit and a new clean build from the isolated release checkout.
- Reliability fixes after `1.0.0` use patch versions such as `1.0.1`.
- Backward-compatible product capabilities, including a future validated
  tablet target, use a minor version such as `1.1.0`.

## Version Sources

| Component | Config File | Current |
|---|---|---|
| App (HAP) | `AppScope/app.json5` | `1.0.0` |
| Native crate | `harmotty_ssh/Cargo.toml` | `1.0.0` |
| Core crate | `harmotty_ssh/harmotty-ssh-core/Cargo.toml` | `1.0.0` |
| OHPM | `entry/oh-package.json5` | `1.0.0` |
| Native OHPM | `entry/src/main/cpp/types/libharmotty_ssh/oh-package.json5` | `1.0.0` |
| Root OHPM | `oh-package.json5` | `1.0.0` |

All version sources must stay aligned. `AppScope/app.json5` uses numeric
`versionCode` `1000000` for the 1.0.0 package and `versionName` for the
user-visible semantic version.
