# LeanTTY 全面更名执行与验收方案

> 状态：执行中参考方案
>
> 创建日期：2026-07-27
>
> 上位规则：[`project-principles.md`](project-principles.md)
>
> 活动任务来源：[`next-work.md`](next-work.md)

## 1. 文档用途与治理边界

本文为 LeanTTY 品牌更名提供具体操作顺序、文件范围、验证命令和完成门槛，供执行
Agent 参考。本文不是第二份活动 TODO；开始实施前，必须先在 `docs/next-work.md`
登记本次更名任务，实施状态和剩余工作只在 `docs/next-work.md` 维护。

执行时必须同时遵守：

- 先读取 `AGENTS.md`、`docs/project-principles.md`、`docs/next-work.md`、
  `docs/versioning.md` 和 `docs/release-process.md`。
- 保留用户已有且与更名无关的工作区修改。
- 不用全仓库无差别替换覆盖并行开发内容；按文件检查、按语义修改。
- 不引入旧品牌兼容层、迁移层、别名、fallback 或双写逻辑。
- 只构建和验证 ARM64 HarmonyOS PC 目标。
- 签名文件、证书、密钥和密码只保存在本地，不得提交。
- GitHub、AppGallery Connect、签名和真机操作按权限边界执行。

完成更名后，将本文移入 `docs/archive/` 并添加完成状态说明；归档材料不得继续驱动
后续实现。

## 2. 目标状态

| 项目 | 目标值 |
|---|---|
| 产品名称 | `LeanTTY` |
| 本地提示符 | `ltty>` |
| 默认 Tab/Pane 标题 | `ltty` |
| Bundle Name | `com.leantty.app` |
| Vendor | `leantty` |
| GitHub 仓库 | `wandcs/leantty` |
| Rust workspace 目录 | `leantty_ssh` |
| Rust core crate | `leantty-ssh-core` |
| Native library | `libleantty_ssh.so` |
| 应用设置存储 | `leantty_settings` |
| 图标资源名 | `leantty_icon` |
| Web 渲染进程标识 | `leantty-terminal` |
| 发布产物前缀 | `LeanTTY-1.0.1` |
| 首个公开版本 | `1.0.1` / `1000001` |
| 目标平台 | ARM64 HarmonyOS PC |

旧 1.0.0 签名包、哈希、已推送标签和审核记录保留为不可变历史，明确标注为：

> 原 HarmoTTY 1.0.0 审核包，审核未通过，从未公开发布。

不得复用、覆盖或移动旧 1.0.0 标签及其产物。

## 3. 明确不做的兼容设计

本项目没有已发布版本和存量用户，本次更名采用一次性干净切换：

- 不读取 `harmotty_settings`。
- 不同时识别 HarmoTTY 与 LeanTTY 两套 SSH managed-host 标记。
- 不保留 `.harmotty.bak` 作为备用名称。
- 不保留旧 JavaScript 全局对象别名。
- 不同时打包两套 Native library。
- 不保留旧资源键、旧图标或旧包名 fallback。
- 不接受或显示旧 `htty>` 提示符。
- 不为 `com.harmotty.app` 编写数据迁移。
- 不建立旧目录到新目录的软链接。
- 不新增只用于验证上述兼容路径的测试。

如果旧名称仍影响当前构建、运行或文档，修复引用源头，不增加转发层。

## 4. 命名规则

### 4.1 身份名称

| 旧名称 | 新名称 |
|---|---|
| `HarmoTTY` | `LeanTTY` |
| `harmotty` | `leantty` |
| `HARMOTTY` | `LEANTTY` |
| `Harmotty` | `LeanTTY` 或语义名称 |
| `htty` | `ltty` |
| `com.harmotty.app` | `com.leantty.app` |
| `harmotty_icon` | `leantty_icon` |
| `harmotty_settings` | `leantty_settings` |
| `harmotty_ssh` | `leantty_ssh` |
| `harmotty-ssh-core` | `leantty-ssh-core` |
| `libharmotty_ssh.so` | `libleantty_ssh.so` |
| `harmotty-terminal` | `leantty-terminal` |
| `HarmoTTYTerminalPolicy` | `LeanTTYTerminalPolicy` |
| `HTTY_SSH` | `LTTY_SSH` |
| `HTTY_PERF` | `LTTY_PERF` |
| `HARMOTTY_PC_READY` | `LEANTTY_PC_READY` |
| `__HTTY_KEYPUSH_*` | `__LTTY_KEYPUSH_*` |

### 4.2 应改为语义名称的内部标识

品牌前缀只用于产品身份和跨包唯一性；表达局部业务含义的标识应使用语义名称：

| 当前名称 | 目标名称 |
|---|---|
| `HarmottyTheme` | `AppTheme` |
| `harmottySecondaryAction` | `handleSecondaryAction` |
| `htty_status` | `command_status` |
| ArkTS 局部变量 `harmotty_ssh` | `sshNative` |

不为了缩短名称新增类型、接口或转发层。

## 5. 阶段一：建立实施基线

### 5.1 操作

1. 读取项目规则和当前活动任务。
2. 检查当前分支、提交和工作区：

```powershell
git status --short
git diff --stat
git diff --name-only
git log -5 --oneline
```

3. 记录旧品牌基线：

```powershell
rg -n --hidden `
  -g '!.git/**' `
  -g '!docs/archive/**' `
  -g '!build/**' `
  -g '!entry/build/**' `
  'HarmoTTY|harmotty|HARMOTTY|Harmotty|htty' .
```

4. 将命中分为：

   - 当前应用配置和资源；
   - 当前 ArkTS/WebView/Rust 代码；
   - 构建、测试和发布工具；
   - 当前文档；
   - 生成文件和锁文件；
   - 不可变历史。

5. 在 `docs/next-work.md` 登记更名任务和完成门槛。
6. 使用聚焦短期分支，例如 `codex/leantty-rebrand`。
7. 明确分类已有未提交文件：最终 `icon.svg` 和本方案属于更名输入；Logo 研究页与
   未跟踪 1.1 文档不得因批量暂存被自动带入更名提交，除非逐文件确认其发布目的。
8. 记录更名前基线决策：工具菜单物理键盘专项和普通 Shell URL 专项由用户决定接受
   当前状态并关闭，本轮没有新增真机证据；这些行为仍必须包含在 LeanTTY 最终真机
   核心路径验收中。
9. 在 AppGallery Connect 和国家知识产权局商标查询系统中执行 `LeanTTY` 精确名称
   核查并记录日期。公开查询结果只用于风险筛查，不作为法律结论。
10. 在修改 Bundle 前创建或确认 `LeanTTY` / `com.leantty.app` AGC 应用记录，并
    准备能够安装该 Bundle 的本地测试签名。无法建立新应用或签名时停止阶段二。

### 5.2 验收

- 所有现有未提交修改已识别。
- 更名与其他功能修改的重叠文件已单独列出。
- 没有覆盖或回退无关修改。
- 旧名称基线可在完成时进行逐项对照。
- AGC 已接受目标应用名称和 Bundle，新 Bundle 的测试签名路径可用。
- 旧 1.0.0 审核状态已改为“审核未通过、从未发布”。

## 6. 阶段二：应用身份与图标资源

### 6.1 主要文件

- `AppScope/app.json5`
- `AppScope/resources/base/element/string.json`
- `AppScope/resources/base/media/`
- `entry/src/main/module.json5`
- `entry/src/main/resources/base/element/string.json`
- `entry/src/main/resources/base/media/`
- `tools/generate_icons.cjs`
- 根目录 `oh-package.json5`

### 6.2 操作

设置：

```text
bundleName = com.leantty.app
vendor = leantty
app_name = LeanTTY
module_desc = LeanTTY entry module
EntryAbility_label = LeanTTY
icon resource = leantty_icon
```

将应用图标资源从 `harmotty_icon.png` 改为 `leantty_icon.png`，同步修改所有资源引用。
以 `docs/assets/icon.svg` 为唯一图标源，更新生成脚本后重新生成全部 PNG：

```powershell
node .\tools\generate_icons.cjs
```

### 6.3 验收

- 所有配置引用的图标资源真实存在。
- 不再引用 `harmotty_icon`。
- AppScope、Entry 和启动窗口图标来自同一个最终 SVG。
- 32、64、128、512、1024 像素下无裁切，`L >` 可辨识。
- 深色底、灰色顶栏和青薄荷渐变与最终设计一致。

## 7. 阶段三：Native、Rust 和 OHPM 身份

### 7.1 目标结构

```text
leantty_ssh/
  Cargo.toml
  leantty-ssh-core/
    Cargo.toml

entry/src/main/cpp/types/libleantty_ssh/
entry/libs/arm64-v8a/libleantty_ssh.so
```

ArkTS 使用：

```typescript
import sshNative from 'libleantty_ssh.so'
```

### 7.2 操作

原子更新：

- Rust workspace 目录和 manifest 路径；
- Cargo package 名称、描述、作者和 repository；
- `Cargo.lock` 中本地 package 名称；
- N-API 模块注册名；
- Native OHPM dependency key、package 和类型目录；
- ArkTS import 字符串和局部变量；
- Hvigor/CMake/构建配置；
- `.so` 复制来源与目标；
- Rust 检查、构建、license 和发布脚本；
- 当前文档中的命令和路径。

不要同时保留新旧 `.so`，也不要用旧模块转发到新模块。

### 7.3 验收

```powershell
cargo fmt --check --manifest-path .\leantty_ssh\Cargo.toml

cargo clippy --locked `
  --manifest-path .\leantty_ssh\Cargo.toml `
  -p leantty-ssh-core `
  --all-targets -- `
  -D warnings

cargo test --locked `
  --manifest-path .\leantty_ssh\Cargo.toml `
  -p leantty-ssh-core
```

同时确认：

- ARM64 `.so` 成功生成。
- ArkTS 编译能解析 `libleantty_ssh.so`。
- HAP 内只有新 Native library。
- 构建脚本不再查找旧目录或旧 `.so`。

## 8. 阶段四：用户可见名称

### 8.1 操作

覆盖所有用户可见路径：

- 初始本地提示符；
- 命令完成、失败和补全后的提示符；
- 默认 Tab/Pane 名称；
- 未连接 Session 标题；
- 帮助、Key store 和 SSH 示例；
- 主机和密钥管理输出；
- 空状态和错误信息。

统一使用：

```text
LeanTTY
ltty
ltty>
```

### 8.2 验收场景

逐项触发：

1. 应用首次打开；
2. 空输入；
3. 未知命令；
4. `help` 及具体帮助主题；
5. 命令补全和历史；
6. 密钥生成、列出和删除；
7. 主机添加、列出和删除；
8. SSH 连接成功；
9. SSH 连接失败；
10. SSH 断开并返回本地状态。

预期：

- 只出现 `LeanTTY` 和 `ltty>`。
- Tab、Pane、Session 和终端内容命名一致。
- 不出现 `Leantty`、`LeanTty` 等非标准写法。

## 9. 阶段五：内部标识和诊断

### 9.1 操作

同步更新：

- `HarmoTTYTerminalPolicy` 及 HTML 调用点；
- `HarmottyTheme` 的定义、类型和 import；
- `harmottySecondaryAction`；
- WebView shared render process token；
- Rust/ArkTS 日志标签；
- 性能测量标记；
- 真机连通探针；
- key-push marker；
- 测试断言和日志过滤规则；
- Shell 命令退出状态变量。

### 9.2 验收

- `terminal-policy.js` 和 `terminal.html` 使用同一全局名称。
- Web 终端测试不依赖旧别名。
- 日志脚本可以过滤 `LeanTTY`、`LTTY_SSH` 和必要平台标签。
- `LEANTTY_PC_READY` 探针工作正常。
- `command_status` 的 Shell 引用和转义正确。
- 不存在只为旧名称服务的分支。

## 10. 阶段六：本地持久化与 SSH 文件

### 10.1 Preferences

直接使用：

```typescript
const PREFERENCES_NAME: string = 'leantty_settings'
```

不读取或迁移旧 Preferences。

### 10.2 SSH managed hosts

直接使用：

```text
# >>> LeanTTY managed hosts >>>
# <<< LeanTTY managed hosts <<<
```

不识别旧标记。

### 10.3 SSH config 备份

直接使用：

```text
.leantty.bak
```

密钥文件名安全校验同步保护 `.leantty.bak`，不继续为 `.harmotty.bak` 增加特殊规则。

### 10.4 验收

- 干净环境首次启动能够创建新 Preferences。
- 字号、主题和窗口状态能在重启后保存。
- `host add` 只写入 LeanTTY managed-host 标记。
- 修改已有 SSH config 时创建 `.leantty.bak`。
- 不产生旧名称文件。
- 测试中没有双格式兼容场景。

## 11. 阶段七：构建、验证和发布工具

### 11.1 主要范围

- `tools/dev-pc.ps1`
- `tools/dev-build.ps1`
- `tools/verify-pc.ps1`
- `tools/build-all.ps1`
- `tools/check-ssh-auth-flow.ps1`
- `tools/check-public-source.ps1`
- 图标、Web 资源、license 和 notice 生成工具
- Native 和发布产物路径

### 11.2 目标

统一使用：

```text
LeanTTY
com.leantty.app
libleantty_ssh.so
LeanTTY-1.0.1-arm64-v8a-unsigned.hap
LeanTTY-1.0.1-arm64-v8a-signed.hap
```

设备命令使用：

```text
aa start -a EntryAbility -b com.leantty.app
pidof com.leantty.app
```

### 11.3 验收

- 开发构建成功。
- Native 构建输出被正确找到和复制。
- HAP/APP 文件名、manifest 路径和哈希一致。
- public-source 检查不含旧仓库或旧本地路径规则。
- 日志过滤匹配新标签。
- 生成文件由工具重新生成，不保留手工不一致。

## 12. 阶段八：当前文档和版本记录

### 12.1 更新范围

- `AGENTS.md`、`.gitignore`、`.gitleaks.toml` 和 `.github/**`；
- `LICENSE`、`TRADEMARKS.md`、`CODE_OF_CONDUCT.md`、`CONTRIBUTING.md`、
  `SECURITY.md` 和 `SUPPORT.md`；
- 根目录项目说明和社区文件；
- `CHANGELOG.md`；
- `docs/README.md`；
- `docs/project-principles.md`；
- `docs/next-work.md`；
- `docs/coding-guide.md`；
- `docs/versioning.md`；
- `docs/release-process.md`；
- 当前 1.1 方案；
- 当前依赖、许可证和来源说明；
- GitHub Issue/PR 模板及当前链接。

### 12.2 CHANGELOG

在 `1.0.1 - In development` 中记录：

```markdown
- Rename the application from HarmoTTY to LeanTTY.
- Replace the application identity, icon, bundle name, package names,
  local prompt and release artifacts with the LeanTTY identity.
```

同时明确 1.0.0 审核未通过且从未公开发布。

### 12.3 历史边界

以下事实不改写：

- 旧 1.0.0 HAP/APP 文件名；
- 旧产物哈希；
- 已推送标签；
- 原审核意见；
- 原提交时产品名称。

这些内容应集中在明确的历史或归档材料中，不参与当前实现说明。
`docs/open-source-publication.md` 和 `docs/source-provenance.md` 等完成态历史材料
应移入 `docs/archive/` 并修复引用。`CHANGELOG.md` 允许保留以下两类精确历史命中：

- 1.0.0 被拒绝且从未发布的旧产品名称；
- 1.0.1 从旧名称更名为 LeanTTY 的事实。

除此之外，当前产品说明、命令、配置和用户文档不得继续使用旧品牌。

### 12.4 验收

- 当前文档中的命令与新目录、新包名一致。
- 当前仓库链接指向 `wandcs/leantty`。
- 所有本地 Markdown 链接有效。
- `docs/next-work.md` 仍是唯一活动任务清单。
- 归档文档不会产生当前实施任务。

## 13. 阶段九：AppGallery Connect 应用完善与生产签名

华为平台中的应用包名创建后不可修改。为了使用 `com.leantty.app`，需创建新的应用
记录，不继续使用原被拒绝应用记录。

AGC 应用记录和可安装新 Bundle 的测试签名必须已在阶段一完成。本阶段补齐生产签名、
商店资料和最终提交所需配置；不得把首次发现 Bundle 无法签名推迟到代码替换完成后。

### 13.1 外部操作

创建：

```text
应用名称：LeanTTY
应用包名：com.leantty.app
平台：HarmonyOS
设备：HarmonyOS PC
```

然后：

1. 建立与 `com.leantty.app` 匹配的签名配置。
2. 获取所需 profile/certificate。
3. 只将配置保存在本地忽略文件中。
4. 不提交证书、密钥、密码或签名注入文件。
5. 原 HarmoTTY 应用记录停止提交，保留审核事实。

### 13.2 验收

- AGC 应用名称为 LeanTTY。
- AGC 包名与 `AppScope/app.json5` 完全一致。
- 签名 profile 覆盖 `com.leantty.app`。
- 签名 HAP 通过官方签名校验。
- 没有复用旧 Bundle 的签名配置。

## 14. 阶段十：自动化验证

### 14.1 旧名称扫描

实施过程中使用：

```powershell
rg -n --hidden `
  -g '!.git/**' `
  -g '!docs/archive/**' `
  -g '!build/**' `
  -g '!entry/build/**' `
  'HarmoTTY|harmotty|HARMOTTY|Harmotty|htty' .
```

本计划在执行阶段必然包含新旧名称映射，因此最终扫描前应先将本计划移入
`docs/archive/`。完成态历史方案、来源映射和旧公开计划也应归档。

最终扫描分为两类：

1. 当前代码、配置、构建工具、社区入口和用户文档：必须无旧品牌输出。
2. 明确历史材料：只允许 `CHANGELOG.md` 中的拒审/更名事实、`docs/archive/**`
   中的历史记录和不可变 Git 标签；命中必须逐行人工核对，不使用宽泛目录豁免掩盖
   当前引用。

当前身份零命中检查应明确排除历史材料：

```powershell
rg -n --hidden `
  -g '!.git/**' `
  -g '!docs/archive/**' `
  -g '!CHANGELOG.md' `
  -g '!build/**' `
  -g '!entry/build/**' `
  'HarmoTTY|harmotty|HARMOTTY|Harmotty|htty' .
```

预期无输出。随后单独检查 `CHANGELOG.md` 和 `docs/archive/**`，确认每条命中都描述
不可变历史，不参与当前构建、操作说明或产品身份。

单独检查关键旧身份：

```powershell
rg -n --hidden `
  -g '!.git/**' `
  -g '!docs/archive/**' `
  'com\.harmotty\.app|libharmotty_ssh|harmotty_settings|harmotty-terminal' .
```

预期无输出。

### 14.2 新名称一致性

```powershell
rg -n --hidden `
  -g '!.git/**' `
  'LeanTTY|leantty|LTTY|ltty' .
```

人工检查：

- 产品名只写作 `LeanTTY`；
- 短名称只写作 `ltty`；
- Bundle、crate、library、resource 和 repository 名称一致；
- 没有 `Leantty`、`LeanTty` 或重复前缀。

### 14.3 项目门禁

运行 Web 终端现有测试和资源完整性检查，然后运行：

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\verify-pc.ps1
```

最终验收不能使用 `-SkipDevice`，因为 Bundle、桌面图标、窗口身份、Preferences、
本地提示符和 SSH 文件行为需要真实 HarmonyOS PC 证明。

文本质量检查：

```powershell
git diff --check
```

## 15. 阶段十一：ARM64 HarmonyOS PC 真机验收

### 15.1 安装前

1. 如果测试机旧应用中仍保存需要的 Host 或 Key，不得先卸载
   `com.harmotty.app`。
2. 安装本轮固定的 `com.leantty.app` 签名 HAP，让两个 Bundle 暂时共存。
3. 按本机私有恢复记录恢复并验证 Host/Key；不迁移 `known_hosts`。私有恢复记录和
   密钥备份不得加入 Git。
4. 只有恢复、实际 SSH 连接和临时私钥清理全部完成后，才卸载旧应用。
5. 确认旧进程和旧图标不再参与最终验收。

### 15.2 可见身份

验证：

- 桌面/启动器显示 LeanTTY；
- 使用最终青薄荷 `L >` 图标；
- 窗口和任务栏图标正确；
- `com.leantty.app` 可启动；
- 进程包名为 `com.leantty.app`；
- 首屏显示 `ltty>`；
- 默认 Tab/Pane 标题为 `ltty`；
- 帮助信息显示 LeanTTY。

### 15.3 核心行为

验证：

- 字号、主题和窗口状态重启后保存；
- SSH 密码连接；
- SSH 密钥连接；
- 主机指纹接受和拒绝；
- 连接取消；
- 断开连接并返回 `ltty>`；
- `host add/list/rm`；
- SSH config 使用 LeanTTY 标记；
- `.leantty.bak` 正确生成；
- 日志只使用 LeanTTY/LTTY 标签；
- 单/双 Pane 基本输入、输出和焦点没有因更名回归。

### 15.4 审核录屏

从 HarmonyOS PC 桌面开始录制，使用最终签名候选，至少覆盖：

1. 桌面图标和启动；
2. LeanTTY 主界面；
3. 本地 `ltty>` 和帮助；
4. 发起 SSH 连接；
5. 认证和主机校验；
6. 远端命令输入输出；
7. Tab/双 Pane 核心操作；
8. 断开及恢复路径。

录屏作为 AppGallery Connect 的“自测文件”上传，必须与最终候选包一致。

## 16. 阶段十二：发布包验收

版本保持：

```text
versionName = 1.0.1
versionCode = 1000001
```

目标产物：

```text
LeanTTY-1.0.1-arm64-v8a-signed.hap
```

检查：

- Bundle 为 `com.leantty.app`；
- Label 为 `LeanTTY`；
- ABI 符合 ARM64 目标范围；
- Native library 为 `libleantty_ssh.so`；
- 图标为最终青薄荷版本；
- versionName/versionCode 正确；
- 生产签名验证通过；
- manifest 中 SHA-256 与实际文件一致；
- 构建来源 commit 明确；
- 发布工作区满足 `docs/release-process.md`；
- 不包含秘密和本机绝对路径。

选定后冻结这一份签名候选及哈希。上架资料、真机验证和审核录屏均使用同一个候选，
不得无代码变更重新构建并替换。

## 17. 阶段十三：GitHub 仓库更名

GitHub 更名放在本地代码、自动化、签名和真机验证通过以后。

### 17.1 操作顺序

1. 在当前仓库完成更名分支。
2. 通过 PR 合并更名。
3. 确认 GitHub CLI 当前账户为 `wandcs`。
4. 将仓库从 `wandcs/harmotty` 改为 `wandcs/leantty`。
5. 更新本地 remote：

```powershell
git remote set-url origin https://github.com/wandcs/leantty.git
git remote -v
git fetch
```

6. 检查：

   - Actions；
   - 分支保护和 rulesets；
   - Dependabot；
   - Issue/PR 模板；
   - Security 设置；
   - Release 页面；
   - 仓库描述和社交预览。

当前文档不得依赖旧仓库地址的自动重定向。

## 18. 本地工作区目录更名

仓库和外部配置完成后，将本地工作目录从：

```text
%REPO_PARENT%\harmotty
```

迁移为：

```text
%REPO_PARENT%\leantty
```

这是最后操作之一。迁移前关闭占用仓库的 DevEco Studio、终端和 Agent 任务，重新打开
新目录后检查：

```powershell
git status --short
git remote -v
```

不保留旧目录软链接。固定本机路径检查也应只接受新路径。

## 19. 停止条件和失败处理

出现以下情况时停止进入下一阶段，先修复当前层：

- 发现会覆盖用户无关修改；
- 新 Bundle 尚未建立可用签名；
- Native 新名称无法被 ArkTS/Hvigor 正确解析；
- 自动化测试失败；
- HAP 内仍包含旧包名、旧资源或旧 `.so`；
- 真机出现旧产品名或旧提示符；
- 签名候选与录屏使用的包不一致；
- 发布 manifest 与实际文件哈希不一致。

失败时不要通过以下方式绕过：

- 恢复旧 Bundle；
- 同时打包新旧 Native library；
- 增加旧名称 alias；
- 跳过失败测试；
- 用 `-SkipDevice` 代替最终真机验收；
- 重建一个未重新验证的“同版本”签名包。

技术回退以 Git 分支和提交为边界。外部 GitHub 仓库更名安排在最后，以降低回退成本。

## 20. 提交建议

建议使用同一短期分支和同一个 PR，分为两个可审查提交：

1. `Rename application identity to LeanTTY`
2. `Update LeanTTY documentation and release metadata`

若文件重命名和内容修改过多，可以增加一个纯路径重命名提交，但不得让主分支长期
停留在一半 HarmoTTY、一半 LeanTTY 的状态。

暂存前检查变更范围，不得整批带入无关工作区修改。

## 21. 最终完成门槛

以下条件必须全部满足：

- [ ] `docs/next-work.md` 中的更名任务及验收项全部完成。
- [ ] 当前代码、配置、构建工具、社区入口和用户文档旧品牌命中为零。
- [ ] `CHANGELOG.md` 只保留拒审与更名事实，其他旧品牌命中只存在于
  `docs/archive/**` 和不可变 Git 历史，并已逐行核对。
- [ ] 没有旧 Preferences、SSH 标记、资源键或 Native 名称兼容代码。
- [ ] Bundle 已切换为 `com.leantty.app`。
- [ ] Rust、Web、ArkTS 和 ARM64 构建验证全部通过。
- [ ] 新签名配置和签名校验通过。
- [ ] 测试机所需 Host/Key 已恢复，`known_hosts` 未迁移。
- [ ] 真机可见身份与核心 SSH 路径通过。
- [ ] GitHub 仓库和当前链接全部切换。
- [ ] `LeanTTY-1.0.1` 签名候选及哈希已固定。
- [ ] AppGallery 自测录屏对应同一候选。
- [ ] 旧名称只存在于明确的不可变历史证据和归档材料中。
- [ ] 本文已移入 `docs/archive/` 并标记完成。

最终原则：

> 当前项目只认识 LeanTTY；旧名称只存在于不可变历史中。
