# Versioning Policy

HarmoTTY uses `MAJOR.MINOR.PATCH`, with
[Semantic Versioning 2.0.0](https://semver.org/) as the baseline. Version
levels describe compatibility and user-visible impact, not implementation
effort or the number of changed files.

## Format

```
MAJOR.MINOR.PATCH
```

| Level | When to bump | Example |
|---|---|---|
| MAJOR | Backward-incompatible user contract change, or an explicitly declared new product generation | `1.6.3` → `2.0.0` |
| MINOR | Backward-compatible capability or significant product improvement | `1.0.7` → `1.1.0` |
| PATCH | Backward-compatible bug, security, performance, compatibility or dependency fix | `1.0.0` → `1.0.1` |

When MAJOR increases, MINOR and PATCH reset to zero. When MINOR increases,
PATCH resets to zero. For example, the feature release after `1.0.7` is
`1.1.0`, not `1.1.7`.

If a release contains changes from more than one level, the highest applicable
level wins:

- breaking change + feature + fixes: MAJOR;
- feature + fixes: MINOR;
- fixes only: PATCH.

A release does not need a minimum number of changes. One important
backward-compatible feature can justify a MINOR release, and one urgent fix can
justify a PATCH release.

## Compatibility Contract

For HarmoTTY, compatibility is evaluated against the user-facing and published
contract:

- supported product and platform scope;
- persisted settings and user data, including automatic migration;
- documented commands, shortcuts and core terminal interactions;
- documented SSH, configuration and terminal behavior;
- any external interface or data format explicitly published as supported.

Removing or changing an established command, dropping a supported environment,
or requiring users to discard configuration or data is normally a MAJOR
change. Deprecating a capability while keeping it working is a MINOR change;
removing it later is a MAJOR change.

Private ArkTS, Rust, N-API and WebView bridge boundaries, code organization and
other internal implementation details are not part of the compatibility
contract unless they are explicitly published as supported interfaces. A
renderer replacement or architecture rewrite is therefore not automatically a
MAJOR release:

- if user data, behavior and compatibility remain intact, it is normally a
  MINOR release when the improvement merits its own release;
- if it removes important behavior, breaks compatibility or defines a
  deliberately new product generation, it is a MAJOR release;
- a refactor with no independently releasable user impact does not determine
  the version level by itself.

## Change Classification

### MAJOR

Use MAJOR for backward-incompatible changes to the compatibility contract. The
release notes must identify what changed, who is affected and whether migration
is possible. A deliberately declared new product generation may also use
MAJOR, but internal change alone is insufficient.

### MINOR

Use MINOR for backward-compatible features and significant product
improvements. A MINOR release may also contain PATCH-level fixes. Marking an
existing capability as deprecated also requires at least a MINOR release.

### PATCH

Use PATCH when the release contains only backward-compatible fixes. This
includes reliability, security, performance and compatibility corrections, as
well as dependency updates made solely to correct such problems. A security
fix that breaks the compatibility contract still requires a MAJOR release.

Dependency upgrades are classified by their effect on HarmoTTY, not by the
dependency's own version number. A major xterm or russh upgrade does not by
itself require a HarmoTTY MAJOR release.

## Pre-release Identifiers

When a release needs public or controlled preview builds, append a SemVer
pre-release identifier:

| Version | Meaning |
|---|---|
| `1.1.0-alpha.1` | Early incomplete preview |
| `1.1.0-beta.1` | Feature-complete preview under validation |
| `1.1.0-rc.1` | Release candidate |
| `1.1.0` | Stable release |

Pre-release versions have lower precedence than the matching stable version.
Build metadata such as `1.1.0-rc.1+sha.abcdef0` may identify a build, but it
does not change version precedence.

HarmoTTY published `1.0.0` directly without a public release-candidate version.
This does not prevent later releases from using pre-release identifiers when
they are useful.

## Historical Development Versions

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

## Release Rules

- A release package must be built from an exact commit already pushed to
  `wandcs/harmotty`; local-only source is never a release input.
- Any code, dependency, resource, version or packaging change requires a new
  pushed commit and a new clean build from the isolated release checkout.
- Once a version is released, its source and artifacts must not be replaced.
  Any modification requires a new version.
- Reliability fixes after `1.0.0` use patch versions such as `1.0.1`.
- Backward-compatible product capabilities use a minor version such as
  `1.1.0`.

## Development and Branch Workflow

HarmoTTY uses a protected-main, short-lived-branch workflow. `main` is the
single integration branch for the next planned stable release and should remain
tested and releasable.

- Code, dependency, resource and release-document changes are developed on
  focused topic branches and merged through pull requests.
- Every merged change intended for users is recorded under `Unreleased` or the
  selected target version's `In development` section, following the changelog
  workflow below.
- An AppGallery review in progress does not by itself require a long-lived
  release branch. The submitted package is frozen by its exact pushed commit,
  manifest, artifact hashes and immutable signed tag.
- While `main` contains only backward-compatible fixes after a stable release,
  it is the integration line for the next PATCH release. A higher-version
  feature must not be merged into that line before the PATCH release is frozen.
- A `release/X.Y.Z` branch is created only for release preparation. It accepts
  version metadata and release-blocking fixes only, never new product scope.
- After the verified tag is pushed, the release branch may be deleted. The
  immutable tag, commit and archived build evidence remain the submission
  identity.

The default is to finish and submit the current release before merging work for
the next higher version. After a version is tagged and submitted, `main` may
advance. If review later requires an APP change, create the next PATCH release
from the appropriate submitted tag or current compatible `main`, apply and
verify the fix, and forward-port it wherever needed.

## Changelog Workflow

`CHANGELOG.md` describes released and pending user-visible changes:

1. Before a target version is selected, add entries below `Unreleased`.
2. Once the next target version is selected and its version sources are
   advanced, move its pending entries to `[X.Y.Z] - In development` and keep a
   new empty `Unreleased` section above it.
3. Add later changes intended for that same target to its `In development`
   section. Reserve `Unreleased` for work not yet assigned to that version.
4. At release preparation, replace `In development` with `YYYY-MM-DD`.
5. Do not mix changes for a higher MINOR or MAJOR release into a pending PATCH
   section.
6. If a change is dropped before release, remove its pending entry rather than
   documenting behavior that was never published.
7. If a tagged AppGallery submission is rejected and never distributed, retain
   its version section and mark it `AppGallery submission rejected; not
   published`.
8. Release notes for the next published version summarize all user-visible
   changes since the last version actually published to users, including
   changes carried through a rejected intermediate version.

## Store Review and Release Identity

For an update release, complete development and validation while the previous
version is under review, but do not submit its successor until that review
reaches a terminal result. Normally the previous version is `Released`. If it
is rejected and changing the APP is required, the next PATCH package may
replace it.

The release lifecycle is:

1. Prepare the target version on a release branch and merge it to `main`
   through a reviewed pull request.
2. Push and record the exact release commit.
3. Build, production-sign and verify that commit from the isolated clean
   release checkout described in [`release-process.md`](release-process.md).
4. Create and push the immutable signed `vX.Y.Z` tag on the verified commit.
   Confirm that it matches the commit and artifacts recorded by the build
   manifest.
5. Submit the signed APP and record the AppGallery submission against the tag,
   commit, manifest and artifact hashes.
6. If review succeeds, publish the matching GitHub Release on the existing tag.
7. If review fails but only store listing, screenshot, qualification or other
   external metadata changes, keep the same tag and APP and resubmit.
8. If review requires any source, resource, dependency, permission, signature,
   version or package change, keep the rejected tag immutable, advance to the
   next PATCH version, increase `versionCode`, and repeat the full release
   lifecycle with a new commit, build and tag.

A previously selected but unsubmitted development version does not consume
another version number. For example, if `1.0.0` review fails after `1.0.1`
development has started, the changed successor submission is still `1.0.1`,
not `1.0.2`.

A pushed version tag identifies one exact submission package whether review
succeeds or fails. It is never moved or reused. GitHub Release publication is
the public distribution signal and occurs only after AppGallery reports the
tagged version as `Released`.

## Version Sources

| Component | Config File | Current |
|---|---|---|
| App (HAP) | `AppScope/app.json5` | `1.0.1` |
| Native crate | `harmotty_ssh/Cargo.toml` | `1.0.1` |
| Core crate | `harmotty_ssh/harmotty-ssh-core/Cargo.toml` | `1.0.1` |
| OHPM | `entry/oh-package.json5` | `1.0.1` |
| Native OHPM | `entry/src/main/cpp/types/libharmotty_ssh/oh-package.json5` | `1.0.1` |
| Root OHPM | `oh-package.json5` | `1.0.1` |
| Release artifact default | `tools/build-all.ps1` | `1.0.1` |

All semantic version sources must stay aligned.

`AppScope/app.json5` uses:

- `versionName` for the user-visible semantic version;
- numeric `versionCode` as the app-store delivery identifier.

`versionCode` is independent of compatibility classification and must increase
monotonically whenever a newer package supersedes an earlier package. It must
not be used to infer MAJOR, MINOR or PATCH compatibility. The submitted `1.0.0`
package uses `versionCode` `1000000`; the developing `1.0.1` package uses
`1000001`.
