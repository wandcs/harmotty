# Development Environment

| Component | Version | Path |
|---|---|---|
| DevEco Studio | 2026Q2 | `C:\Program Files\Huawei\DevEco Studio` |
| HarmonyOS SDK | API 6.1.1(24) | `sdk/default/openharmony` |
| OHOS NDK Clang | 15.0.4 | `native/llvm/bin/clang.exe` |
| Hvigor | bundled with DevEco | `tools/hvigor/` |
| JBR (Java) | 21.0.x | `jbr/bin/java.exe` |
| Rust | 1.96.1 (stable-x86_64-pc-windows-gnu) | `rustup` managed |
| Node.js | 18.20.1 | bundled with DevEco |

## Build Targets

| Target | ABI | Notes |
|---|---|---|
| `aarch64-unknown-linux-ohos` | arm64-v8a | Current HarmonyOS PC target |

## Key Dependencies

| Crate | Version | Purpose |
|---|---|---|
| russh | 0.62.2 | SSH client/server (ring backend) |
| tokio | 1.52 | Async runtime |
| napi-ohos | 1.2.0 | N-API bindings |
| xterm.js | 6.0.0 | Terminal emulator |
| hypium | 1.0.25 | Test framework |

## Environment Variables

Required for native build:
- `DEVECO_HOME` — DevEco Studio install dir
- `OHOS_NDK_HOME` — set by `build-native.ps1`

Required for HAP build:
- `DEVECO_SDK_HOME` — set by `build-all.ps1`
- `JAVA_HOME` — set by `build-all.ps1`
- `NODE_OPTIONS` — must be empty
