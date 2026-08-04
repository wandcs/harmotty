# LeanTTY 当前工作

> 状态：唯一有效的项目 TODO
>
> 更新日期：2026-08-03
>
> 当前 milestone：[`1.1 — 可信认证与工作连续性`](roadmap.md)
>
> 上位规则：[`project-principles.md`](project-principles.md)

本文件只保留尚未完成、已经授权的活动工作，并按实际依赖顺序执行。完成事实进入
`CHANGELOG.md` 和 Git 历史；WIP 技术方案、后续 milestone 和候选方向不在这里维护
第二份清单。

## 当前完成定义

1. 先闭合已经实现但缺少最终证据的 1.0/1.1 可靠性门禁，修复会污染验收结论的测试
   工具。
2. 再完成 1.1 发布核心 SSH `keyboard-interactive` 与多方法认证。
3. 然后实施可独立裁剪的 Tab 导航；Pane 导航必须先通过真机前置门禁。
4. 最后完成公共检查、干净 ARM64 构建和物理 HarmonyOS PC 集成矩阵。
5. 持久资产或 SSH 认证核心门禁未通过时，不进入 1.1.0 发布准备。导航失败可以裁剪，
   不能用新增设置、别名或特殊分支补救。

## 1. 收敛现有可靠性门禁

### 1.1 休眠与 renderer 重建后的终端内容

- [ ] 在物理 ARM64 HarmonyOS PC 上验证：当前 Tab 已产生 screen 与 scrollback 后，
  长时间休眠并让 SSH 断开，唤醒后旧内容、断连提示和 `ltty>` 均保留。
- [ ] 在进入后台并完成检查点后主动触发 ArkWeb renderer 重建，确认内存快照先于脱离
  期间输出恢复，没有重复 OSC 52、bell、标题或远端输入。应用终止、普通卸载重装后
  不得恢复终端内容。

### 1.2 工程 SSH smoke 输入

- [ ] 修复自动化 SSH smoke 把预期 `echo` 注入为 `eho` 的终端文本注入缺陷，并为
  注入文本本身建立可判定的回归。修复前，自动注入产生的命令文本和数据面断言不得
  作为验收证据，相关场景继续使用真机物理键盘。

### 1.3 tmux 鼠标复制真机门禁

- [ ] 在物理 ARM64 HarmonyOS PC 上开启 `set -g mouse on`，确认普通拖动后无需 Shift
  或二次右键即可由 tmux `MouseDragEnd1Pane` 完成复制，`tmux show-buffer` 与系统
  剪贴板一致。
- [ ] 同时覆盖 `set-clipboard external/on`、`Ms`、中文与多行文本，并回归 tmux
  滚动/TUI 鼠标、`Shift+拖动` 后 `Ctrl+C` 的本地复制和普通终端选区。

### 1.4 卸载重装持久资产完整矩阵

- [ ] 使用普通卸载（不得使用 `bm uninstall -k`）后，以同一正式应用身份重装，验证
  Ed25519、RSA-4096、加密/未加密私钥、OpenSSH config、`known_hosts`、字号、窗口
  和显式删除语义均自动恢复或保持删除，且没有恢复界面。
- [ ] 验证不同签名应用不可读取资产，并覆盖锁屏和系统重启。已有“同签名普通卸载后
  Host、密钥、known_hosts、字号和窗口保留”的用户确认只算部分证据，不能替代这组
  矩阵。

## 2. SSH keyboard-interactive 与多方法认证

技术边界与验收细节：
[`design/ssh-authentication.md`](design/ssh-authentication.md)。

- [ ] 建立受控 SSH 服务端基线，覆盖现有密码、未加密/加密私钥，以及
  `password,keyboard-interactive`、`publickey,password`、
  `publickey,keyboard-interactive` 和多轮 `keyboard-interactive`；测试凭据只存在于
  临时目录。
- [ ] 在 Rust Session 中建立唯一认证状态机，按 `remaining_methods` 与
  `partial_success` 处理方法和阶段；支持 authentication banner、名称、说明、零个或
  多个 prompt、逐项 echo 规则和多轮回答，不根据厂商提示文字猜测认证类型。
- [ ] 使用结构化 Rust/N-API/ArkTS 事件与
  `sessionId + generation + roundId` 传递 challenge 和回答，拒绝过期、重复、数量
  错误和跨 Session 回答；服务器显示文字按不可信输入过滤。
- [ ] 保证密码、私钥口令、OTP 和认证回答不进入日志、错误快照、命令历史、
  Preferences、持久资产或 PTY 字节流；覆盖提交、拒绝、取消、超时和断线清理。
- [ ] 自动化覆盖成功、普通失败、部分成功、不支持、零/多 prompt、多轮、混合 echo、
  回答错误、取消、超时、断线、Pane 关闭、generation 变化和并行 Session；现有密码、
  私钥、主机校验、PTY 和输出路径保持回归通过。
- [ ] 在物理 ARM64 HarmonyOS PC 上使用物理键盘验证密码问答、密码加 TOTP、私钥加
  TOTP、私钥加密码、banner、多提示、多轮、取消、错误恢复、最小化/恢复和两个 Pane
  并行认证；检查终端、历史、Preferences 与 hilog 的秘密边界。

## 3. 工作区键盘导航

技术边界与裁剪规则：
[`design/workspace-navigation.md`](design/workspace-navigation.md)。

### 3.1 Tab 导航

- [ ] 实现 `Ctrl+Tab` / `Ctrl+Shift+Tab` 按现有视觉顺序循环切换，并恢复目标 Tab
  自己的 `activePaneId`；普通 `Tab`、终端输入、选择和 Session 所有权不得改变。
- [ ] 覆盖零/单/多 Tab、首尾回绕、双 Pane 活动侧恢复、精确修饰键与事件消费；在
  ARM64 HarmonyOS PC 上验证系统、输入法、内置/外接键盘和常见 TUI。

### 3.2 Pane 导航前置门禁与条件实现

- [ ] 实现前先在物理 ARM64 HarmonyOS PC 上验证 `Ctrl+Alt+Left` /
  `Ctrl+Alt+Right` 稳定到达应用，不触发系统快捷键、输入法切换或关键终端输入。门禁
  失败时从 1.1 裁剪整个 Pane 导航，不增加别名、自定义设置或兼容分支。
- [ ] 仅在门禁通过后实现：双 Pane 状态消费固定左右组合，单 Pane 完整透传；验证
  唯一焦点、选择、复制粘贴、Shell/TUI、跨 Tab、断线和重连状态不受影响。

## 4. 1.1 集成与发布准备门禁

- [ ] 运行公共测试、Rust 格式检查、`git diff --check` 和干净 ARM64 native/debug HAP
  构建；可靠性修复、认证与导航保持可定位、可裁剪的边界。
- [ ] 在物理 ARM64 HarmonyOS PC 上完成认证、键盘、焦点、Tab、双 Pane、剪贴板、
  窗口、持久资产、密钥导出、密钥口令修改、known-hosts 查询/删除、命令错误边界、
  常见 Shell/TUI、休眠、renderer 重建、断线和重连矩阵。
- [ ] 按 [`versioning.md`](versioning.md) 与 [`release-process.md`](release-process.md)
  准备确切 1.1.0 候选；未完成生产验证前不创建或宣传已发布版本。

## 当前不活动

- 拟议 1.2 终端搜索、条件 1.3 最小文件传输、拟议 1.4 HSL 入口、1.5 ProxyJump、
  1.6 Mosh 和 1.7 SSH 配置/诊断/资产互操作仅存在于 [`roadmap.md`](roadmap.md) 与
  相应技术方案中，不是当前 TODO。
- HSL 当前仍通过 SSH 进入；只有 HarmonyOS 将来提供公开稳定的直接终端 API 时，
  才重新讨论 Local Transport，不为此提前建立抽象。
- SFTP 文件管理器、目录浏览/同步、后台传输、第二套 Host/Identity、自定义快捷键、
  厂商 MFA SDK、验证码种子保存和单服务器特殊分支不建立活动任务。

## 维护规则

1. 只保留未完成且已授权工作；完成后同步更新 Changelog/Git 并从本文件删除。
2. 新的大功能先通过产品原则，进入 `roadmap.md`，再建立一份单功能 WIP 技术方案；
   milestone 与方案确认后，才把第一段可执行工作加入本文件。
3. 任务必须说明可观察完成条件；SDK 声明、构建通过、安装或启动不能替代所需的真机
   行为证据。
4. `docs/archive/`、WIP 方案、历史 checkbox 和未写入本文的候选均不授权实现。
