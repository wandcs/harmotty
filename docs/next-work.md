# LeanTTY 当前工作

> 状态：唯一有效的项目 TODO
>
> 更新日期：2026-08-08
>
> 当前 milestone：[`1.2 — 终端检索与日常效率`](roadmap.md)
>
> 上位规则：[`project-principles.md`](project-principles.md)

本文件只保留尚未完成、已经授权的活动工作，并按实际依赖顺序执行。完成事实进入
`CHANGELOG.md`、设计文档和 Git 历史；旧 checkbox、定向实现证据、WIP 技术方案及后续
milestone 不在这里维护第二份清单。

## 当前状态与完成定义

1.2 的产品实现已闭合两个受控切片：当前 Pane、当前 Terminal Surface 内的普通文本
scrollback 搜索，以及桌面终端 Chrome/Surface 的界面与交互收敛。当前实现包括：

- `Ctrl+Alt+F` 和四点菜单 Search 进入当前 Surface 搜索；查询不进入 Session、SSH 或持久化；
- 固定 172vp Tab、有限 BEL Tab 提示、紧凑搜索、双 Pane 边界和可见键盘焦点；
- Off/Low/Medium/High/Extreme 五档非循环透明度，Content 为
  `1.00/0.90/0.82/0.72/0.60`，Chrome 为 `1.00/0.94/0.88/0.80/0.70`；
- 非 Off 档只在窗口根固定一次 `BlurStyle.BACKGROUND_REGULAR`，不提供材质设置、自定义
  Gaussian、CSS/WebGL blur 或逐 Pane 模糊。

已完成的实现、裁剪决定和定向证据分别记录在
[`design/terminal-search.md`](design/terminal-search.md)、
[`design/ui-interaction-polish.md`](design/ui-interaction-polish.md) 和 `CHANGELOG.md`。
当前剩余工作只有精确候选、最终物理机矩阵和发布；不得在候选形成后继续加入无关功能。

完成 1.2 必须满足：所有产品改动进入精确且已推送的提交；正式软件门禁与干净 ARM64
候选通过；同一个保留候选完成全部适用的物理 HarmonyOS PC 场景；设计、版本、签名、
归档、GitHub Release 和 AppGallery 记录可追溯。安装、启动或工作树截图不能替代行为验收。

## 1. 准备精确 1.2.0 正式候选

- [ ] 确认 1.1.1 AppGallery 审核已经进入终态。若失败，先从适当已发布标签准备最小 1.1.2，
  不混入 1.2；若仍在审核，1.2 可继续代码审查，但不得发布后继版本或提前消耗 1.2.0。
- [ ] 按 [`versioning.md`](versioning.md) 选择并准备 1.2.0：更新 `versionName`、递增
  `versionCode`，把 Changelog 的 1.2 内容移入 `1.2.0 — In development`，提交并推送精确
  候选源。版本、依赖、资源、ArkTS、Rust 或其他打包输入变化都必须重新形成候选。
- [ ] 从精确已推送提交运行 `tools/verify-pc.ps1` 正式门禁：完成完整软件回归、Rust
  format/Clippy/tests、干净 ARM64 原生与测试签名 HAP 构建、安装和启动；保留同一 HAP，记录
  commit/tree、ABI、资产、签名、SHA-256 和机器可读 manifest。此项只建立候选，不声称行为通过。

## 2. 对同一候选执行最终物理机矩阵

- [ ] 搜索输入与冲突：使用真实物理键盘和中英文输入法验证打开、逐字输入、下一处、上一处、
  首尾回绕、空查询、无结果、关闭和焦点恢复；确认 `Ctrl+Alt+F` 不与 HarmonyOS、输入法或
  常见终端/TUI 按键产生不可接受冲突。
- [ ] 搜索正确性与终端兼容：覆盖普通输出、中文/Unicode/宽字符、多行、大 scrollback、
  持续输出、normal/alternate buffer、tmux、vim、less 和主流 Agent TUI；回归 selection、
  复制粘贴、OSC 52、HTTP(S)/OSC 8 链接、鼠标上报、滚轮、resize 与 renderer 重建。
- [ ] UI 与窗口矩阵：在当前产品深色主题及普通/最大化/窄窗口下验证多 Tab 边界与溢出、固定 `+`、
  拖拽空白区、四点菜单、系统按钮、双 Pane、搜索条、全高分隔和 focus ring。确认 Tab 间
  无竖线但表面差异清楚；自动化继续约束未暴露的浅色 token，不为验收增加主题入口，也不
  实现 Tab 拖动排序、自适应 Tab 宽度或新的外观设置。
- [ ] BEL 矩阵：验证活动 Pane 一次呼吸、非活动 Tab 两次呼吸与静态标记、当前 Tab 非焦点
  Pane 局部来源、连续 BEL 合并、清除、销毁和系统 reduced-motion；证明无整 Pane 黄框、
  无限动画、串状态或终端输入延迟。
- [ ] 透明与材质矩阵：对不透明基线和五档记录同机分布，验证重启持久化、边界不循环、
  Chrome/Content 派生 alpha、根级 Regular、窗口活动态、已挂载双 Pane、最小化/
  恢复和 renderer 重建；覆盖 Shell、TUI、selection、搜索高亮、链接、大持续输出与 resize。
  若可读性、正确性、帧响应、GPU/内存或生命周期不成立，先撤 Regular，再按证据回退透明。
- [ ] 性能基线：比较搜索打开、逐字查询、跳转、持续输出和关闭，以及不透明/五档透明下的
  帧响应、GPU、内存和异常分布；先报告分布和设备环境，不用构建时间或单次主观感受替代测量。
- [ ] 所有物理场景记录候选和干净 harness 身份、结构化结果、截图/录屏、layout/hilog、
  阶段耗时、失败域、重试和清理结果。候选变化、身份缺失或资源未清理时不得提升为通过。

## 3. 收口与发布

- [ ] 所有候选场景通过后，把两份设计文档更新为 `Verified`，记录最终采用/裁剪决定、精确
  commit、HAP/APP 哈希和证据索引；把 Changelog 的 `In development` 日期替换为发布日期。
- [ ] 按 [`release-process.md`](release-process.md) 在隔离的 production/review checkout
  构建同 commit/tree/version/ABI/native 输出的生产 APP/HAP 与 review-test HAP，验证签名、
  manifest、artifact roles 和 clean tree；只用 review-test HAP 做最终真机 smoke 和商店媒体。
- [ ] 创建不可变签名标签并发布匹配的非草稿 GitHub Release；确认 release、tag、commit 和
  归档资产一致后，才把同版本 production APP 与商店材料提交 AppGallery。若审核失败，版本
  已消耗，必须递增 PATCH 并重新执行完整流程，不移动标签或替换 Release。

## 当前不活动与明确非目标

- Tab 拖动排序、Tab 分组/固定/拖出窗口、自适应 Tab 宽度不进入 1.2；只有出现持续的核心
  场景证据后，才按产品原则重新评估。
- 跨 Tab/Session 搜索、正则或模糊语言、搜索历史、结果索引、持久查询、远端文件/日志搜索、
  命令面板和通用覆盖层框架不进入 1.2。
- 连续透明度滑杆、独立材质/Chrome 设置、自定义 Gaussian、CSS/WebGL blur、逐 Pane 动态
  blur、桌面截图、新图标或动画依赖和通用设计系统不进入 1.2。
- 条件 1.3 最小文件传输、拟议 1.4 HSL、1.5 ProxyJump、1.6 Mosh 和 1.7 SSH 配置/诊断/
  资产互操作只存在于 [`roadmap.md`](roadmap.md)，不是当前 TODO。

## 维护规则

1. 只保留未完成且已授权工作；完成后把事实同步到 Changelog、设计文档和 Git 历史，并从
   本文件删除。
2. 每项任务必须说明可观察完成条件；SDK 声明、构建、安装或启动不能替代真实行为证据。
3. `docs/archive/`、历史 checkbox、WIP 方案和未写入本文的候选不授权实现。
