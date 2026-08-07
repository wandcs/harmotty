# LeanTTY 当前工作

> 状态：唯一有效的项目 TODO
>
> 更新日期：2026-08-07
>
> 当前 milestone：[`1.2 — 终端检索与日常效率`](roadmap.md)
>
> 上位规则：[`project-principles.md`](project-principles.md)

本文件只保留尚未完成、已经授权的活动工作，并按实际依赖顺序执行。完成事实进入
`CHANGELOG.md` 和 Git 历史；WIP 技术方案、后续 milestone 和候选方向不在这里维护
第二份清单。

## 当前状态与完成定义

`v1.1.1` 对应的生产 APP 已于 2026-08-06 提交 AppGallery，当前处于审核中。1.2 可以
开发和验证，但在 1.1.1 审核进入终态前不得提交后继版本；如果 1.1.1 审核失败，先从
适当的已发布标签准备最小 1.1.2 修复，不把 1.2 功能混入该 PATCH。

1.2 只交付当前 Pane、当前 Terminal Surface 内的普通文本 scrollback 搜索：键盘打开、
输入查询、跳到下一处或上一处、关闭并恢复终端焦点，清楚显示当前匹配位置或无结果。
搜索不改变终端内容、远端输入、选择所有权或 Session 状态，不持久化、不跨 Pane/Tab，
也不扩展为命令面板、正则语言、历史或索引服务。

完成必须同时满足：交互契约确定；实现保持在 Terminal Surface 边界；自动化覆盖查询、
隔离、生命周期和终端回归；干净 ARM64 构建通过；物理 HarmonyOS PC 证明键盘、输入法、
双 Pane、焦点、选择、链接、TUI 和 renderer 重建行为；文档与发布证据完整。

## 1. 冻结最小交互与技术基线

- [x] 共同确认打开、下一处、上一处和关闭的固定快捷键，搜索条位置，Enter、
  Shift+Enter、Escape、Tab 与中英文输入法行为，以及关闭后保留当前滚动位置还是回到
  底部；核对 HarmonyOS 系统、输入法、xterm 和远端 TUI 冲突，不增加自定义快捷键设置。
  `Ctrl+Shift+F` 已被物理键盘确认触发输入法简繁切换，不能作为产品入口，也不保留为
  兼容别名。当前唯一候选改为 `Ctrl+Alt+F`，保留 F 记忆点并复用现有 Ctrl+Alt 路由族；
  HDC 三键组合和物理键盘均已通过同一物理 PC 的产品搜索路由；中英文逐字输入和完整
  TUI 冲突回归仍由第 5 节验收覆盖。
- [x] 明确普通文本的大小写规则、首尾回绕、空查询、无结果、中文/Unicode/宽字符、
  多行输出和 normal/alternate buffer 边界；不加入正则、模糊、全词或搜索历史模式。
- [x] 审计当前 xterm 6.0.0、可用 search addon/API、来源、锁定版本、许可证、包体增量和
  ARM64 ArkWeb 支持；优先复用官方稳定 addon，不能引入在线资源、通用搜索框架或跨
  Session 索引。
- [x] 结合现有 `TerminalSurfaceController`、`TerminalBridge` 和 `terminal.html` 证明
  查询、匹配、定位与高亮能够由当前 Terminal Surface 独占；Bridge 只传递确有必要的
  结构化意图或结果，不让 Session、SSH Transport、App 全局状态或持久化接触查询。
- [x] 在修改产品实现前建立当前物理 PC 的快捷键冲突、Terminal Surface 大 scrollback
  和持续输出基线，并冻结最小搜索切片落地后对打开、逐字输入和跳转使用的同机测量
  协议；记录分布和环境，不预设任意性能百分比或固定时限。
- [x] 把上述决定同步到 [`design/terminal-search.md`](design/terminal-search.md)，将仍有
  分歧或依赖不成立的部分明确裁剪；只有本节闭合后才开始产品代码实现。

## 2. 实现当前 Surface 的最小搜索路径

- [x] 如采用新 xterm addon，更新 `tools/web-terminal` 的锁定依赖、构建资产、manifest、
  公共源码策略、许可证和第三方声明；只打包 ARM64 应用实际使用的本地静态资源。
- [x] 在当前 Terminal Surface 内实现短生命周期搜索状态与紧凑搜索条，支持普通文本
  查询、下一处、上一处、首尾回绕、当前匹配位置和无结果反馈；反馈不能只依赖颜色。
- [x] 将固定快捷键接入现有精确 modifier 路由。搜索关闭时恢复原活动 Pane 的终端焦点；
  搜索打开时查询按键不得进入远端 PTY，未命中快捷键和关闭后的普通终端输入仍按原路径
  传递。
- [x] 保证每个 Pane 的搜索状态完全隔离。切换 Tab/Pane、关闭 Pane、Terminal Surface
  销毁、warm Tab 淘汰、renderer 退出或重建时按已确认契约关闭或恢复搜索，不创建
  Session 状态、跨 Surface 查询或持久化记录。
- [x] 处理搜索高亮与现有 selection、`Ctrl+C`、OSC 52、HTTP(S)/OSC 8 链接、鼠标上报、
  secondary action、主题和滚动的所有权冲突，不改变 buffer 字节、终端快照或远端程序
  输入。
- [x] 为所有新增 Bridge control/data kind 更新双向 allowlist、长度/格式校验和失败行为；
  未知、畸形、迟到或来自旧 Surface generation 的消息必须被拒绝，不能驱动错误 Pane。

## 3. 自动化与回归

- [x] 扩展 Web terminal policy 测试：普通文本、空查询、无结果、多个结果、首尾回绕、
  大小写规则、中文/Unicode/宽字符、多行、normal/alternate buffer、大 scrollback、
  持续输出和快速重复查询。
- [x] 扩展 ArkTS/Bridge 测试：精确快捷键、输入捕获与恢复、查询不进入 SSH、当前 Pane
  所有权、双 Pane/跨 Tab 隔离、关闭 Pane、warm Tab 淘汰、renderer 重建、迟到和畸形
  消息拒绝。
- [x] 回归 selection、复制粘贴、OSC 52、链接、鼠标上报、滚轮、快照恢复、字体缩放、
  resize 和普通远端输入，证明搜索没有修改终端 buffer、选择语义或 Bridge 流控。
- [x] 为新增依赖、打包资产和协议更新构建工作流测试，检查锁文件稳定、manifest 哈希、
  许可证、无在线资源、release 包不含验收专用标记，并继续只打包 `arm64-v8a`。
- [x] 每个实现切片只运行直接受影响的测试和一个快速主路径；运行 `git diff --check` 并
  记录命令、结果和证据路径，不在日常迭代运行完整发布矩阵。

## 4. 在正式候选封板前升级 russh

Dependabot 告警 [`GHSA-m65r-rprj-r5rg`](https://github.com/Eugeny/russh/security/advisories/GHSA-m65r-rprj-r5rg)
影响 `russh <= 0.62.4` 的服务端 channel 生命周期，首个修复版本为 `0.62.5`。LeanTTY
生产应用只使用客户端路径，直接受影响的是仓库专用 `russh::server` 认证 fixture；但
`0.62.5` 同时修改客户端 `Channel::data()` 背压行为，因此仍须作为产品依赖升级验证，
不能只按“测试工具修复”处理。该告警不改变已提交审核的 1.1.1，也不单独触发 1.1.2；
升级及下列证据必须在选定 1.2.0 正式候选提交、运行完整发布门禁之前闭合。

- [x] 将 `leantty_ssh/Cargo.lock` 中的 `russh 0.62.4` 精确升级到 `0.62.5`，保持现有
  `ring`、`rsa` 和 `default-features = false` 边界；核对锁文件只包含预期依赖变化，
  同步 `RUST_DEPENDENCIES.md`、开发环境、第三方声明和 `CHANGELOG.md` 中受影响的版本及
  安全记录。不修改或 vendoring russh 源码，不为此次补丁升级新增传输抽象。
- [x] 在 WSL 中完成 Rust 格式、Clippy、workspace 测试和依赖树/许可证检查；回归仓库
  fixture 的认证、允许/拒绝 channel、取消和断开路径，并验证大段粘贴、远端暂不读取、
  resize 与断开期间的客户端背压不会造成无界排队、输入丢失或 Session 卡死。
  2026-08-07 使用默认 WSL 完成 `cargo fmt --all -- --check`、workspace 全 target Clippy
  (`-D warnings`) 和 workspace 测试；fixture E2E 覆盖 8 条认证链、session channel 允许/
  拒绝、已认证 shell 取消及取消后恢复。受控 russh 回归以 16 KiB 窗口暂停远端读取，确认
  512 KiB 输入保持背压，恢复后字节与顺序完整且 `173x47` resize 未丢；经本地 TCP 转发
  强制断开后，会话在 5 秒边界内结束并中止仍等待窗口的独立 writer。ARM64 目标依赖图
  仍为 150 个 registry 包、无许可证元数据缺口，生产 feature 仍仅为 `ring`、`rsa`。
- [ ] 用升级后的同一产品树完成干净 ARM64 原生/HAP 构建和物理 HarmonyOS PC SSH
  主路径，覆盖认证、交互输入、大段粘贴、持续输出、resize、断开与重连；记录依赖版本、
  commit、构建和设备证据。构建通过或 Dependabot 告警自动关闭都不能单独完成本节。

## 5. ARM64 HarmonyOS PC 验收

- [ ] 建立可重复的命名物理机场景，复用真实搜索事件链并记录候选与 harness 身份；如需
  验收入口，只允许编译期隔离、最小触发且 release 分支裁剪的测试能力，不建立第二套
  搜索实现。
- [ ] 在物理键盘和中英文输入法下验证打开、逐字输入、下一处、上一处、关闭、焦点恢复、
  无结果和首尾回绕；确认快捷键不与 HarmonyOS、输入法或终端常用按键产生不可接受冲突。
- [ ] 验证单 Pane、双 Pane 和多 Tab 的当前 Pane 归属，切换、关闭、warm Tab 淘汰、应用
  最小化/恢复和 ArkWeb renderer 重建后不串查询、高亮、滚动位置或焦点。
- [ ] 验证普通输出、中文/宽字符、多行、大 scrollback 和持续输出；回归 tmux、vim、less
  等 alternate-screen/TUI，selection、复制粘贴、链接和鼠标上报保持原有行为。
- [ ] 用第 1 节基线比较打开、逐字查询、跳转、持续输出和关闭的耗时与资源行为；先报告
  分布、异常和设备环境，再决定是否需要局部优化，不用构建时间或单次主观感受代替真机
  体验。
- [ ] 所有物理场景记录结构化结果、截图/layout/hilog、失败域、重试次数和清理结果；安装
  启动、HAP 构建或单次搜索成功都不能单独标记本节完成。

## 6. 文档、版本与发布

- [ ] 更新用户指南中的搜索入口、快捷键、范围和关闭语义；更新架构、质量、安全或隐私
  文档中确实受影响的边界，不复制第二份实现或发布流程。
- [ ] 在 `CHANGELOG.md` → `Unreleased` 记录最终用户可见行为；实现与验收闭合后更新
  `design/terminal-search.md` 的状态、采用/裁剪决定和证据摘要。
- [ ] 准备正式 1.2.0 包时，按 `quality-strategy.md` 对精确提交运行完整软件门禁、干净
  ARM64 候选和全部适用命名物理场景，再按 `versioning.md` 与 `release-process.md`
  完成版本、生产签名、归档、不可变标签和 GitHub Release；日常开发不得提前运行这些
  完整门禁。
- [ ] 只有 1.1.1 AppGallery 审核进入终态后才提交 1.2.0。若 1.1.1 审核失败，先发布并
  提交最小 1.1.2 PATCH；1.2 继续保持独立功能线，不把高版本功能混入修复包。

## 当前不活动

- 条件 1.3 最小文件传输、拟议 1.4 HSL 入口、1.5 ProxyJump、1.6 Mosh 和 1.7 SSH
  配置/诊断/资产互操作仅存在于 [`roadmap.md`](roadmap.md) 与相应技术方案中，不是
  当前 TODO。
- HSL 当前仍通过 SSH 进入；只有 HarmonyOS 将来提供公开稳定的直接终端 API 时，
  才重新讨论 Local Transport，不为此提前建立抽象。
- SFTP 文件管理器、目录浏览/同步、后台传输、第二套 Host/Identity、自定义快捷键、
  厂商 MFA SDK、验证码种子保存和单服务器特殊分支不建立活动任务。
- 跨 Tab/Session 搜索、正则或模糊语言、搜索历史、结果索引、持久查询、远端文件或日志
  搜索、命令面板和通用覆盖层框架不进入 1.2。

## 维护规则

1. 只保留未完成且已授权工作；完成后同步更新 Changelog/Git 并从本文件删除。
2. 新的大功能先通过产品原则，进入 `roadmap.md`，再建立一份单功能 WIP 技术方案；
   milestone 与方案确认后，才把第一段可执行工作加入本文件。
3. 任务必须说明可观察完成条件；SDK 声明、构建通过、安装或启动不能替代所需的真机
   行为证据。
4. `docs/archive/`、WIP 方案、历史 checkbox 和未写入本文的候选均不授权实现。
