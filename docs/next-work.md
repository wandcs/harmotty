# LeanTTY 当前工作

> 状态：唯一有效的项目 TODO
>
> 更新日期：2026-08-05
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

验收可以使用测试包中克制、明确且对应具体门禁的专用入口；入口只触发生产事件链，
并须由编译期常量控制且在正式包中完成分支裁剪。不得用模拟结果替代真机行为。

## 1. 收敛现有可靠性门禁

### 1.1 卸载重装持久资产完整矩阵

- [ ] 使用普通卸载（不得使用 `bm uninstall -k`）后，以同一正式应用身份重装，验证
  Ed25519、RSA-4096、加密/未加密私钥、OpenSSH config、`known_hosts`、字号、窗口
  和显式删除语义均自动恢复或保持删除，且没有恢复界面。
- [ ] 验证不同签名应用不可读取资产，并覆盖锁屏和系统重启。已有“同签名普通卸载后
  Host、密钥、known_hosts、字号和窗口保留”的用户确认只算部分证据，不能替代这组
  矩阵。

## 2. SSH keyboard-interactive 与多方法认证

技术边界与验收细节：
[`design/ssh-authentication.md`](design/ssh-authentication.md)。

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

本节是 1.1 唯一的全量测试时点；此前各功能迭代与缺陷修复只执行改动相关验证和可快速
完成的最小主路径冒烟。

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
