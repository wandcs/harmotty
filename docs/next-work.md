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
`v1.1.1` 已于 2026-08-08 通过 AppGallery 审核并上架，1.2.0 已选择为当前目标版本。
1.2 已从 `origin/main` 可达的精确提交
`59a8cbfb50f7c67931881169a8695a303f22a718` 建立干净 ARM64 保留候选；HAP SHA-256 为
`3f9e20b195d1353fdd2f59eb2134dbafb018d9baeac06b775dc0f68cbbf9119b`。正式软件门禁、
SSH 主路径、保留候选搜索矩阵、窗口/UI 证据复核、BEL、五档透明和五档持续输出性能矩阵
已经完成，详情进入两份设计文档。不得在候选形成后继续加入无关功能。

完成 1.2 必须满足：所有产品改动进入精确且已推送的提交；正式软件门禁与干净 ARM64
候选通过；同一个保留候选完成全部适用的物理 HarmonyOS PC 场景；设计、版本、签名、
归档、GitHub Release 和 AppGallery 记录可追溯。安装、启动或工作树截图不能替代行为验收。

## 1. 完成不能由设备注入替代的人工验收

- [ ] 关闭鸿蒙飞书后，用真实物理键盘和中英文输入法完成搜索打开、逐字组合输入、下一处、
  上一处、首尾回绕、空查询、无结果、关闭与焦点恢复；确认 `Ctrl+Alt+F` 没有不可接受的
  系统/输入法冲突，并用 Tab/Shift+Tab 确认可见 focus ring。飞书只会抢占
  `Ctrl+Shift+W`；若按键后前台切到飞书，应关闭飞书重试，不修改 LeanTTY。
- [ ] 在用户实际 SSH 服务器上用 Medium 和 Extreme 各完成一轮 tmux、vim、less 与一个
  主流 Agent TUI，检查中文/宽字符、alternate buffer、selection、复制粘贴、OSC 52、
  HTTP(S)/OSC 8 链接、鼠标上报、滚轮和 resize，并主观确认 Extreme 可读性及 BEL 节奏。
  当前 HAD-W32 设置搜索对“减少动态效果”无结果；“动画”只返回开发者选项的过渡动画
  缩放。SDK 只提供 reduced-motion 状态读取、没有设置接口，因此当前目标系统的用户级
  reduced-motion 场景记为不适用，不改开发者倍率；静态降级仍由自动化门禁约束。

## 2. 收口与发布

- [ ] 上述两项人工场景通过后，把两份设计文档从“候选客观门禁通过”更新为 `Verified`，记录最终采用/裁剪决定、精确
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
