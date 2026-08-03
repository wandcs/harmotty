# Development Environment

| Component | Version | Path |
|---|---|---|
| DevEco Studio | 2026Q2 | `C:\Program Files\Huawei\DevEco Studio` |
| HarmonyOS SDK | API 6.1.1(24) | `sdk/default/openharmony` |
| OHOS NDK Clang | 15.0.4 | `native/llvm/bin/clang.exe` |
| Hvigor | bundled with DevEco | `tools/hvigor/` |
| JBR (Java) | 21.0.x | `jbr/bin/java.exe` |
| WSL | 2 | Desktop-user default distribution |
| Rust | stable 1.96+ for Linux | WSL `rustup` managed |
| Node.js | 18.20.1 | bundled with DevEco |

## Build Targets

| Target | ABI | Notes |
|---|---|---|
| `aarch64-unknown-linux-ohos` | arm64-v8a | Current HarmonyOS PC target |

## Key Dependencies

| Crate | Version | Purpose |
|---|---|---|
| russh | 0.62.4 | SSH client/server (ring backend) |
| tokio | 1.52 | Async runtime |
| napi-ohos | 1.2.0 | N-API bindings |
| xterm.js | 6.0.0 | Terminal emulator |
| hypium | 1.0.25 | Test framework |

## Environment Variables

Required for native build:
- `DEVECO_HOME` — DevEco Studio install dir
- `OHOS_NDK_HOME` — set by `build-native.ps1`
- `LEANTTY_WSL_DISTRO` — optional WSL distribution override; the default
  distribution is used when omitted

Required for HAP build:
- `DEVECO_SDK_HOME` — set by `build-all.ps1`
- `JAVA_HOME` — set by `build-all.ps1`
- `NODE_OPTIONS` — must be empty

## Build and verification workflow

All Rust formatting, tests and compilation run in WSL. `build-native.ps1`
translates repository and SDK paths, invokes WSL Cargo, and calls the Windows
OHOS Clang/LLVM archive executables only through the checked-in WSL wrappers.
Hvigor, signing and HDC remain Windows-side operations.

All repository build, verification, deployment and release-package entry
points share one lock across worktrees belonging to the same Git repository.
Starting another writer waits for the active task instead of cleaning or
rewriting Cargo, Hvigor or HAP outputs concurrently.

`tools/verify-pc.ps1` requires a clean committed tree and retains its signed test
HAP only after the gate succeeds.
Candidates are stored outside build output directories under the current
user's local application data, keyed to the Git repository. Retention has one
rule: keep the five most recently verified unique HAPs. There is no age-based
cleanup policy.

After an uninstall, install and launch the latest retained candidate without
rebuilding:

```powershell
.\tools\dev-pc.ps1 -LatestCandidate
```

The candidate manifest records its SHA-256, Git commit/tree, checkout dirty
state, monotonic verification mode and attached local JSON evidence. The
current modes are `software`, `device-deployed` and `device-behavior`; install
and launch alone never claim behavior acceptance. Formal
AppGallery production artifacts remain governed by
[`release-process.md`](release-process.md) and are never added to this
developer candidate store.
