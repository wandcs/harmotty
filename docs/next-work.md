# LeanTTY 当前工作

> 状态：唯一有效的项目 TODO
>
> 更新日期：2026-07-27
>
> 上位规则：[`project-principles.md`](project-principles.md)

## 当前结论

原产品身份下的 1.0.0 Huawei AppGallery Connect 审核已结束。审核因应用名称包含
“Harmony”商标且未提供授权而未通过，该版本从未向用户发布。提审源码、产物哈希、
签名校验和完整私有 Git 历史已在仓库外冻结并完成恢复验证。

“建立可信公开源码基线”已完成。公开没有改变 1.0.0 提审产物；公开后的产品开发
从本仓库继续。签名标签 `v1.0.0` 已固定到首次公开根提交，作为被拒绝提交的不可变
历史；不为该标签创建 GitHub Release。

当前补丁开发目标为 `1.0.1`。版本元数据已前移到 `1.0.1` / `1000001`，待发布修复
记录在 `CHANGELOG.md` 的 `1.0.1 - In development` 下。`Unreleased` 保持为空，
用于尚未归入目标版本的后续工作。工具菜单精简和未连接状态帮助提示已明确提前到
`1.0.1`。本版本同时以一次性干净切换方式将产品全面更名为 LeanTTY，并作为首个
实际公开发布候选；其他 1.1 功能规划不进入本补丁分支。

## P0：1.0.1 终端字形正确性

- [x] 将内嵌 JetBrains Mono Nerd Font 切换为相同 `3.3.0` 版本的单格 Mono
  变体，修复 PUA 图标越过 xterm 单元格并与相邻文本重叠的问题。
- [x] 为用户样例 `XXXXXXXXX` 建立字体轮廓与 advance
  宽度回归测试；完整 PC 门禁通过，并在 ARM64 HarmonyOS PC 上由用户独立复现
  和真机截图共同确认图标不再与相邻 `X` 重叠。

## P0：1.0.1 Bell 注意状态确认

- [x] 保持 `PaneInfo.needsAttention` 为黄框的唯一权威状态，由对应 xterm 的真实
  键盘输入或用户粘贴发送一次性确认事件；程序自动恢复焦点不再静默清除状态，
  其他 Pane 的操作也不会串清黄框。
- [x] 在 ARM64 HarmonyOS PC 上验证：BEL 后在对应 Pane 使用物理键盘输入会清除
  黄框；仅有远端输出、程序恢复焦点和其他 Pane 输入不会清除；确认后新的 BEL
  能再次显示黄框。

## P0：1.0.1 工具菜单与未连接提示精简

- [x] 删除工具菜单中的 **Copy**，保留 New Tab、Split Pane、Close Pane 和三项字号
  操作；同步调整菜单上下循环、Enter 分派和动态禁用索引，不改动既有键盘与选择感知
  复制路径。
- [x] 将未连接 `ltty>` 提示符的未知顶层命令反馈统一为
  `Unknown command. Type 'help' for commands, or use: ssh user@host`；空输入、具体
  Usage、帮助主题、命令历史和远端输入行为保持不变。
- [x] 在 ARM64 HarmonyOS PC 上验证六项菜单顺序和鼠标操作：单 Pane 的 Close、
  双 Pane 的 Split 均保持禁用且不关闭菜单；Split/Close 往返后 Web 终端数量正确，
  菜单始终不包含 Copy。
- [x] 在 ARM64 HarmonyOS PC 的未连接 Pane 验证：未知命令显示新的统一引导，空
  Enter 只产生下一个提示符，已识别但缺参数的 `ssh` 仍显示具体错误。
- [x] 按更名前基线决策关闭物理键盘菜单回绕、禁用项跳过、Enter 分派、复制和远端
  未知命令专项复测；本项记录用户接受当前状态并不再单独执行，不代表本轮新增真机
  证据。相关行为仍纳入 LeanTTY 最终真机核心路径验收。

## P0：1.0.1 终端 URL 点击

- [x] 第一阶段：在终端鼠标上报关闭时，普通 HTTP(S) 文本和 OSC 8 链接平时不
  改变指针或增加链接装饰；按住且仅按住 `Ctrl` 后立即显示手形指针、下划线和真实
  目标，`Ctrl+左键单击` 经 Native 校验后交给 HarmonyOS 系统浏览器。普通单击、
  拖动、其他修饰键、非 HTTP(S) 和失效 Pane 都不得打开，也不得向 SSH 写入字节。
- [x] 按更名前基线决策关闭普通 Shell URL/OSC 8、修饰键反馈、单/双 Pane 来源、
  浏览器往返焦点、失败提示和 WebGL/DOM fallback 专项复测；本项记录用户接受当前
  状态并不再单独执行，不代表本轮新增真机证据。相关行为仍纳入 LeanTTY 最终真机
  核心路径验收。
- [x] 第二阶段：tmux/TUI 鼠标上报开启时，普通点击和 `Ctrl+左键单击` 仍归远端
  应用，`Shift` 保留为 xterm 本地选择绕过键；按住且仅按住 `Ctrl+Shift` 后显示
  链接反馈，`Ctrl+Shift+左键单击` 打开链接，拖动不得打开或写入 SSH 鼠标字节。
- [x] 在 ARM64 HarmonyOS PC 的 `set -g mouse on` tmux 中验证第二阶段：普通点击、
  `Ctrl+点击`、Pane/边框/滚轮仍由 tmux 处理，`Shift+拖动` 可本地选择，
  `Ctrl+Shift+点击` 打开普通 URL 与可用 OSC 8 链接，拖动不误开，浏览器往返后
  不残留选择拖动状态，并覆盖单/双 Pane。

## P0：1.0.1 LeanTTY 全面更名

- [x] 产品名称、短提示符、Bundle、Native/OHPM/Rust 身份、GitHub 仓库名和青薄荷
  `L >` 图标目标已确定；不设计旧品牌兼容、迁移、别名或双写路径。
- [x] 建立 [`leantty-rebrand-execution-plan.md`](leantty-rebrand-execution-plan.md)
  作为执行参考，并建立本机私有 Host/Key 恢复记录；恢复不包含 `known_hosts`。
- [x] 从 `main` 提交 `69a2f60` 创建聚焦分支 `codex/leantty-rebrand`，识别并保留
  当前工作区中更名资产、设计研究页和未跟踪 1.1 文档。
- [x] 已在 AppGallery Connect 建立 `LeanTTY` / `com.leantty.app` 应用记录；
  发布 Profile 经官方工具验证为 `release` / `app_gallery`，Bundle 和既有发布证书
  均匹配，有效期至 2029-07-26。
- [x] 为 `com.leantty.app` 生成本地测试签名并完成签名安装；测试 Profile 经官方
  工具验证为 `debug` 且 Bundle 匹配，签名 HAP/APP 的摘要与内嵌 Profile 校验通过，
  完整 PC 门禁已通过 USB 安装并启动新 Bundle。生产发布 Profile
  只证明 Bundle 和生产签名链成立，不代替真机开发签名。
- [x] 原子替换应用身份、用户可见名称、Native/Rust/OHPM、持久化键、SSH 文件标记、
  诊断标识、构建工具、资源和当前文档，不保留旧品牌运行时兼容路径。
- [x] 当前代码、配置、构建工具和用户文档中的旧运行时身份清零；旧 1.0.0 名称只
  保留在 `CHANGELOG.md` 的拒审/更名事实、不可变标签和 `docs/archive/` 历史材料。
- [x] Web、ArkTS、Rust 格式、OHOS ARM64 Clippy、WSL 纯 Rust 单元测试和干净
  ARM64 HAP/APP 构建通过；生成包内 Bundle 为 `com.leantty.app`，版本为 `1.0.1`。
- [ ] 完成真机可见身份、Preferences、SSH 文件、Host/Key 恢复和核心交互人工验收；
  最终验收不得只用自动安装启动或
  `-SkipDevice` 代替 Bundle、图标、提示符、Preferences、SSH 文件和交互验证。
- [x] 在新应用恢复并核对 Host/Key，分别连接 `dev` 和 `wsl`，重新核对服务器指纹，
  未迁移旧 `known_hosts`；清理时确认旧应用已不存在，并永久删除本机明文私钥备份。
- [ ] 冻结同一份 `LeanTTY-1.0.1` 生产签名候选、哈希和构建来源，使用该候选完成
  AppGallery 自测录屏及提交材料。
- [ ] 通过 PR 合并更名，最后再完成 GitHub 仓库和本地工作目录更名；归档执行方案，
  确认 `docs/next-work.md` 仍是唯一活动任务清单。

## P0：公开源码

### A. 提审证据和历史

- [x] 冻结 1.0.0 提审源码 commit、tree、APP/HAP/native/manifest 哈希与签名结果。
- [x] 创建包含全部私有 refs 的离线 Git bundle，并从 bundle 恢复准确提审源码。
- [x] 保存公开前 GitHub 仓库设置、Actions、Issue、PR 和 Release 状态。

### B. 干净公开基线

- [x] 从提审源码建立不含私有历史的新 Git 根提交。
- [x] 删除缓存、生成物、旧 x86_64/模拟器入口、机器路径和内部调查流水。
- [x] 记录提审源码与首次公开基线的来源映射和差异分类。
- [x] 完成源码策略、敏感信息、许可证和第三方资源审计。

### C. 社区与自动化

- [x] 补齐 README、贡献、安全、支持、行为准则和商标边界。
- [x] 启用 Issue 和 Fork；接受 PR，但不承诺合并、响应时限或功能实现。
- [x] 建立不接触秘密和个人设备的公共 CI。
- [x] 配置 Issue/PR 模板、Dependabot、私密漏洞报告和合并策略。

### D. 公开与验收

- [x] 发布干净公开历史并完成公开后的匿名验收。
- [x] 公开后从匿名干净 clone 运行公共检查并核对仓库页面。
- [x] 验证 Fork、Issue、PR、安全报告和 Actions 权限符合执行方案。
- [x] 将首次公开 commit 写入来源记录和 1.0.0 发布证据。

## P0 完成记录

- 官方公开仓库：更名收尾阶段切换至 `https://github.com/wandcs/leantty`
- 首次公开根提交：`93ce79d80533f37ccc7501897d4e92f8549c25de`
- 来源映射：[`archive/source-provenance.md`](archive/source-provenance.md)
- 主分支保护：ruleset `19762483`，要求四项公共检查通过、线性历史和 PR 合并
- 公共 CI：Actions run `30198342930` 的四项检查全部通过
- 安全状态：Secret scanning、Push protection 和私密漏洞报告已开启；公开的
  Dependabot 安全告警已清零
- 外部验收：关闭凭据后完成匿名 HTTPS clone，并通过源码策略、Web 终端策略、
  Rust 格式及公开历史秘密扫描
- 私有历史：已迁移到只读私有归档；仓库外 Git bundle 和 1.0.0 证据仍可独立恢复

## 公开后的维护记录

- 正式开发基线已迁移到官方公开仓库的干净 clone；私有归档只用于审计和恢复，
  不再作为后续产品开发工作区。
- 公共仓库移除内部性能脚本后遗留的真机部署辅助依赖，已由 PR #6 修复；源码策略
  现在会拒绝引用未跟踪 PowerShell helper 的提交。
- Tokio 已由 1.52.3 升级到 1.53.1（PR #3）。公共 CI 四项检查、ARM64 干净构建、
  签名安装启动、SSH 连接认证和真机物理键盘命令验证均完成。
- russh 保持 0.62.4。2026-07-26 核对时它仍是
  [官方最新稳定版](https://github.com/Eugeny/russh/releases/tag/v0.62.4)，并已包含
  当前公开的 malformed PTY 和 Curve25519 消息安全修复；暂不切换到 git/master
  或预发布版本。

## P1：工程验证工具可靠性

- [ ] 修复自动化 SSH smoke 的终端文本注入。当前工具曾把预期的 `echo` 注入为
  `eho`；同一版本使用物理键盘手动输入完整、远端输出正常，因此该现象归类为测试
  工具缺陷，不是 LeanTTY 键盘输入缺陷。修复前，自动注入产生的命令文本和数据面
  断言不得作为验收证据，相关场景继续以真机物理键盘验证为准。

## 完成定义

只有在以下条件同时满足后，P0 才完成：

- AGC 证据仍可独立恢复和核验；
- 公开仓库不包含秘密、个人环境、内部历史或不支持的平台产物；
- 公开 CI 运行真实检查，不使用假成功；
- 外部参与者能够安全提交 Issue 和 PR；
- 官方包、源码、Fork 和第三方构建的边界清楚；
- 匿名干净 clone 的公共检查通过。

完成 P0 后，新的产品工作必须依据
[`project-principles.md`](project-principles.md) 重新进入本文件；历史材料不自动
成为路线图。
