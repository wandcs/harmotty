# Release Process

This file describes the release procedure, not current task status. Outstanding
release work is tracked only in [`next-work.md`](next-work.md).

## Source Authority and Workspaces

Every release is built from source already pushed to
[`wandcs/harmotty`](https://github.com/wandcs/harmotty). Local-only commits,
uncommitted files and development build outputs are never release inputs.

Use two independent Git clones. Choose local paths appropriate for the
maintainer machine:

| Workspace | Example variable | Allowed work |
|---|---|---|
| Development | `$devCheckout` | Edit, test, test-sign, deploy and push verified commits |
| Release | `$releaseCheckout` | Fetch GitHub, check out an exact commit, clean-build, production-sign and archive |

Do not use `git worktree` for the release checkout. Do not edit product source
or create repair commits in the release checkout. If a release build requires a
source change, return to the development checkout, verify the change, push it,
and select the new GitHub commit.

Production certificates, keystores, profiles and passwords remain outside both
repositories. The release checkout may contain an ignored
`signing.local.json5` that references those external materials. Never copy the
development test-signing identity into the production release workflow.

The generated `entry/libs/arm64-v8a/libharmotty_ssh.so` is ignored and must
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
$releaseCheckout = Join-Path (Split-Path (Get-Location) -Parent) 'harmotty-release'
git clone https://github.com/wandcs/harmotty.git $releaseCheckout
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

HarmoTTY publishes stable versions directly. Any code, dependency, resource,
version or packaging change requires a new pushed commit and a new clean build
from the release checkout.

## Build

Run only from the release checkout:

```powershell
.\tools\build-all.ps1 -Clean -BuildMode release -Metadata -ReleaseId 1.0.0
```

This generates named ARM64 release artifacts:

- `build/outputs/release/HarmoTTY-1.0.0-arm64-v8a-unsigned.hap`
- `build/outputs/release/HarmoTTY-1.0.0-arm64-v8a-signed.hap` when production
  signing is configured
- `build/outputs/release/HarmoTTY-1.0.0-arm64-v8a-unsigned.app`
- `build/outputs/release/HarmoTTY-1.0.0-arm64-v8a-signed.app` when production
  signing is configured; this is the AppGallery upload artifact
- `build/outputs/release/licenses/` with the project license, third-party
  notice, complete Rust dependency inventory, OFL text, and package-specific
  Rust license files plus their generated index
- `build/outputs/metadata/build-manifest.json`

The build fails if the HAP contains an ABI other than `arm64-v8a`.

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
3. Build the ARM64 release product with the stable release identifier.
4. Verify the HAP signing block with DevEco's signing tool:

   ```powershell
   java -jar "<DevEco SDK>\default\openharmony\toolchains\lib\hap-sign-tool.jar" `
     verify-app `
     -inFile "build\outputs\release\HarmoTTY-1.0.0-arm64-v8a-signed.hap" `
     -outCertChain "build\outputs\metadata\signing-cert-chain.cer" `
     -outProfile "build\outputs\metadata\signing-profile.p7b"
   ```

   Success requires both `Digest verify result: true` and
   `verify-app success`. `keytool -printcert -jarfile` is not a valid HAP
   signature check.

## Publish

Only after the exact release artifact passes the final real-PC smoke test:

1. Create an immutable signed tag on the recorded commit:
   `git tag -s v1.0.0 <release-commit-sha> -m "v1.0.0"`.
2. Confirm the tag resolves to the release manifest commit.
3. Push the tag: `git push origin v1.0.0`.
4. Upload the signed APP and store materials to AppGallery. Use the signed HAP
   from the same build only for direct installation and final device smoke.
5. Attach `build-manifest.json`, `licenses/` and the SHA-256 checksum file to
   the matching GitHub Release when the repository is made public.

Never move or reuse a published version tag.

## Checksum Verification

```powershell
Get-FileHash -Algorithm SHA256 `
  build\outputs\release\HarmoTTY-1.0.0-arm64-v8a-signed.app,
  build\outputs\release\HarmoTTY-1.0.0-arm64-v8a-signed.hap,
  entry\libs\arm64-v8a\libharmotty_ssh.so,
  build\outputs\metadata\build-manifest.json
```
