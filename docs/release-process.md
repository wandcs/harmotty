# Release Process

This file describes the release procedure, not current task status. Outstanding
release work is tracked only in [`next-work.md`](next-work.md).

## Source Authority and Workspaces

Every release is built from source already pushed to
[`wandcs/leantty`](https://github.com/wandcs/leantty). Local-only commits,
uncommitted files and development build outputs are never release inputs.

Use two independent Git clones, plus an optional third clone when AppGallery
review evidence requires a directly installable HAP. Choose local paths
appropriate for the maintainer machine:

| Workspace | Example variable | Allowed work |
|---|---|---|
| Development | `$devCheckout` | Edit, test, test-sign, deploy and push verified commits |
| Release | `$releaseCheckout` | Fetch GitHub, check out an exact commit, clean-build, production-sign and archive |
| Review | `$reviewCheckout` | Check out the same exact commit, test-sign, install and capture screenshots/video |

Do not use `git worktree` for the release checkout. Do not edit product source
or create repair commits in the release checkout. If a release build requires a
source change, return to the development checkout, verify the change, push it,
and select the new GitHub commit.

Production certificates, keystores, profiles and passwords remain outside both
repositories. The release checkout may contain an ignored
`signing.local.json5` that references those external materials. Never copy the
development test-signing identity into the production release workflow.

The optional review checkout uses a different ignored `signing.local.json5`
and a test Profile trusted by the target PC. Its HAP is only for device
acceptance and review media. It is not an AppGallery upload artifact. Production
and review builds must have the same commit, tree, version, ABI and native
library hash.

The generated `entry/libs/arm64-v8a/libleantty_ssh.so` is ignored and must
never be tracked. A clean clone rebuilds it from the locked Rust source before
packaging; generated native output must not make the release checkout dirty.

## Select the Release Commit

In the development checkout, finish verification and push the exact source:

```powershell
git status --short
git push origin main
git rev-parse HEAD
```

Record the resulting commit SHA. In the release checkout, fetch GitHub and
detach at that exact SHA:

```powershell
git fetch --prune origin
git checkout --detach <release-commit-sha>
git rev-parse HEAD
git status --short
```

The two `git rev-parse HEAD` values must match and `git status --short` must be
empty. Do not build from an implicitly advancing branch, and do not use
`git pull` as the release identity.

For the first setup only:

```powershell
$releaseCheckout = Join-Path (Split-Path (Get-Location) -Parent) 'leantty-release'
git clone https://github.com/wandcs/leantty.git $releaseCheckout
```

## Release Gate

Before building a release:

- Run `tools/verify-pc.ps1` on the target HarmonyOS PC from the development
  checkout, then push the verified commit.
- Confirm the trusted ArkTS suite and Rust `fmt --check` pass.
- Use the clean ARM64 cross-build as the native integration gate; the current
  Windows GNU host toolchain is not a release gate for Rust linking tests.
- Confirm the release checkout is detached at the recorded GitHub commit and
  has no tracked modifications.
- Update CHANGELOG with the release date.
- Update every version source defined by [`versioning.md`](versioning.md).

LeanTTY publishes stable versions directly. Any code, dependency, resource,
version or packaging change requires a new pushed commit and a new clean build
from the release checkout.

Prepare the version metadata on a `release/X.Y.Z` branch and merge it to `main`
through a pull request. The exact pushed `main` commit after that merge is the
release commit. Do not merge work for the next higher version until that commit
has passed production verification, been tagged and been submitted. After that,
`main` may advance; the immutable tag is the recovery anchor described by
[`versioning.md`](versioning.md).

## Build

The recommended formal path is one command from the detached production
release checkout:

```powershell
.\tools\prepare-appgallery-release.ps1 `
  -ReleaseId 'X.Y.Z' `
  -ExpectedCommit '<release-commit-sha>' `
  -ReleaseRoot 'C:\path\to\LeanTTY-release' `
  -ReviewCheckout 'C:\path\to\LeanTTY-review'
```

The command performs both release preflights before compiling, builds and
verifies both checkouts, compares their source/native identity, and archives
the production upload APP separately from the review-test HAP. Omit
`-ReviewCheckout` only when no device/media build is required. `-SkipBuild`
may archive existing outputs after the same manifest and hash checks; it does
not weaken validation. If only one build needs recovery, use
`-SkipProductionBuild` or `-SkipReviewBuild` so the already successful build
is verified and reused instead of rebuilt.

The lower-level production build remains available from the release checkout:

```powershell
$releaseId = 'X.Y.Z'
.\tools\build-all.ps1 -Clean -BuildMode release -Metadata -ReleaseId $releaseId
```

Before a formal build starts, `build-all.ps1` now requires:

- a clean detached checkout whose commit is contained by a fetched `origin`
  ref;
- exact agreement between `-ReleaseId` and every semantic version source;
- an ignored signing configuration with all required fields;
- absolute certificate, Profile and keystore paths outside the checkout;
- encrypted key and keystore password values, without printing them.

Use `-PreflightOnly` with `-Metadata -BuildMode release` to run these cheap
checks without compiling.

This generates named ARM64 release artifacts:

- `build/outputs/release/LeanTTY-X.Y.Z-arm64-v8a-unsigned.hap`
- `build/outputs/release/LeanTTY-X.Y.Z-arm64-v8a-signed.hap` when production
  signing is configured
- `build/outputs/release/LeanTTY-X.Y.Z-arm64-v8a-unsigned.app`
- `build/outputs/release/LeanTTY-X.Y.Z-arm64-v8a-signed.app` when production
  signing is configured; this is the AppGallery upload artifact
- `build/outputs/release/licenses/` with the project license, third-party
  notice, complete Rust dependency inventory, OFL text, and package-specific
  Rust license files plus their generated index
- `build/outputs/metadata/build-manifest.json`

The build fails if the HAP contains an ABI other than `arm64-v8a`.

The formal archive records the roles explicitly:

| Artifact | Role |
|---|---|
| `LeanTTY-X.Y.Z-arm64-v8a-signed.app` | The only application package uploaded to AppGallery |
| Production `LeanTTY-X.Y.Z-arm64-v8a-signed.hap` | Signature and package-identity evidence; not an HDC install target |
| `LeanTTY-X.Y.Z-review-test-signed.hap` | Physical-PC acceptance, screenshots and self-test video only; never upload |

## Verify Manifest

Check `build-manifest.json` contains:

- stable release identifier
- the exact GitHub commit hash
- ARM64 `.so` SHA-256
- build mode and ARM64 ABI
- unsigned and signed HAP paths and SHA-256 values
- unsigned and signed APP paths and SHA-256 values
- successful HAP and APP digest/signature verification records
- `dirty=false`
- timestamp

After the build, confirm the checkout is still unchanged:

```powershell
git diff --exit-code
git status --short
```

## Signing

1. Keep signing certificates, keystores and passwords outside the repositories;
   do not add `signingConfigs` secrets to `build-profile.json5`.
2. Put the single production `signingConfigs` entry in the ignored
   `signing.local.json5` in the release checkout. The build script injects it
   only for the Hvigor process and restores the tracked profile byte-for-byte.
   Let DevEco Studio generate the encrypted `keyPassword` and `storePassword`
   values. Plain-text passwords are not accepted by the formal preflight.
3. Build the ARM64 release product with the stable release identifier.
4. Verify the HAP signing block with DevEco's signing tool:

   ```powershell
   java -jar "<DevEco SDK>\default\openharmony\toolchains\lib\hap-sign-tool.jar" `
     verify-app `
     -inFile "build\outputs\release\LeanTTY-X.Y.Z-arm64-v8a-signed.hap" `
     -outCertChain "build\outputs\metadata\signing-cert-chain.cer" `
     -outProfile "build\outputs\metadata\signing-profile.p7b"
   ```

   Success requires both `Digest verify result: true` and
   `verify-app success`. `keytool -printcert -jarfile` is not a valid HAP
   signature check.

## Known Failure Boundaries

| Symptom | Cause | Required response |
|---|---|---|
| HDC error `9568322`, signature verification failed, untrusted app source | The production AppGallery Profile is not trusted for direct test-PC installation | Keep the production APP/HAP unchanged; build the same commit in the review checkout with the trusted test Profile |
| Hvigor rejects the key or keystore password | Plain text or incompatible encrypted password material was placed in `signing.local.json5` | Regenerate the encrypted fields with DevEco Studio; never copy or print the clear-text password |
| Build starts and later reveals a wrong version or dirty source | Release identity was not checked before expensive compilation | Run the formal command or `build-all.ps1 ... -PreflightOnly`; do not bypass the preflight |
| Production and review HAPs cannot be confidently compared | They were built from different commits, trees, versions, ABIs or native outputs | Discard the review evidence and rebuild both through the formal command |
| It is unclear which HAP/APP to submit or install | Artifact roles were carried only in operator notes | Read the archived `artifact-roles.txt`; upload only the production signed APP |

## Submit for AppGallery Review

Only after the exact release artifact passes the final real-PC smoke test:

1. Confirm the previous AppGallery review is no longer in progress. Normally
   it is `Released`; if it was rejected and this APP supersedes it, record the
   rejection and replacement relationship.
2. Confirm the release commit and signed APP/HAP hashes match
   `build-manifest.json`.
3. Create an immutable signed tag on the verified commit:
   `git tag -s vX.Y.Z <release-commit-sha> -m "vX.Y.Z"`.
4. Confirm the tag resolves to the commit recorded by
   `build-manifest.json`, then push it: `git push origin vX.Y.Z`.
5. Upload the production signed APP and store materials to AppGallery. Do not
   attempt to install its release-Profile HAP with HDC. Use only the separately
   test-signed review HAP from the same commit/tree/native build for direct
   installation, final device acceptance, screenshots and self-test video.
6. Record the submitted version, tag, exact commit, build manifest, artifact
   hashes and AppGallery submission state.
7. Do not publish the GitHub Release while AppGallery review is pending.

If rejection can be resolved only by changing store listing text, screenshots,
qualifications or other metadata outside the APP, keep the same tag and exact
artifact and resubmit it.

If rejection requires any code, resource, dependency, permission, signature,
version or package change, the rejected tag and evidence remain immutable.
Return to the development checkout, advance to the next PATCH version, increase
`versionCode`, apply the smallest release-blocking fix, and repeat the entire
release process with a new pushed commit and tag. Never replace artifacts
recorded under an existing tag.

Do not increment twice for a development version that has not been submitted.
If `1.0.1` is already the development target when `1.0.0` review fails, the
changed replacement submission remains `1.0.1`; it does not become `1.0.2`.

## Finalize an Approved Release

Only after AppGallery reports the submitted version as `Released`:

1. Confirm the approved APP hash, existing signed tag and recorded release
   commit.
2. Create the matching GitHub Release and attach `build-manifest.json`,
   `licenses/` and the SHA-256 checksum file.
3. Update current-status documentation and remove the release branch after any
   required fixes have been forwarded to `main`.

Never move or reuse a pushed version tag, including one whose AppGallery
submission was rejected.

## Checksum Verification

```powershell
Get-FileHash -Algorithm SHA256 `
  build\outputs\release\LeanTTY-X.Y.Z-arm64-v8a-signed.app,
  build\outputs\release\LeanTTY-X.Y.Z-arm64-v8a-signed.hap,
  entry\libs\arm64-v8a\libleantty_ssh.so,
  build\outputs\metadata\build-manifest.json
```
