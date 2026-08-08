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
scrollback 搜索，以及桌面终端 Chrome/Surface 的界面与交互收敛。离线 User Guide 已获
当前版本实现授权；第三个受控切片的产品实现和物理机验收已完成。
已完成实现包括：

- `Ctrl+Alt+F` 和四点菜单 Search 进入当前 Surface 搜索；查询不进入 Session、SSH 或持久化；
- 固定 172vp Tab、有限 BEL Tab 提示、紧凑搜索、成组 Previous/Next 与独立 Close 边界、
  双 Pane 边界和可见键盘焦点；
- Off/Low/Medium/High/Extreme 五档非循环透明度，Content 为
  `1.00/0.90/0.82/0.72/0.60`，Chrome 为 `1.00/0.94/0.88/0.80/0.70`；
- 字号 `Ctrl+-` / `Ctrl+=` 与透明度 `Ctrl+Alt+-` / `Ctrl+Alt+=` 成组全局快捷键，四个菜单
  步进按钮使用原生 hover Tips 显示对应键位；
- 非 Off 档只在窗口根固定一次 `BlurStyle.BACKGROUND_REGULAR`，不提供材质设置、自定义
  Gaussian、CSS/WebGL blur 或逐 Pane 模糊；
- 顶层帮助保留原文并在末尾生成唯一 OSC 8 离线指南链接；中文默认/完整英文
  HTML 进入包内 rawfile，Download 同步按逐字节版本、所有权和固定 URI 白名单闭合。

已完成的实现、裁剪决定和定向证据分别记录在
[`design/terminal-search.md`](design/terminal-search.md)、
[`design/ui-interaction-polish.md`](design/ui-interaction-polish.md) 和 `CHANGELOG.md`。
`v1.1.1` 已于 2026-08-08 通过 AppGallery 审核并上架；1.2.0 已成为当前 GitHub Release，
正在等待 AppGallery 提交。
2026-08-08，用户确认 1.2 全部测试完成，最后的指南短文件名链接与其他收口优化补齐后
未发现问题。最终精确提交 `90c20cacf47ac620ccc89d21e70b6cdbbfeb0a68` 已通过正式软件
门禁、干净 ARM64 构建和 HAD-W32 部署；production/review checkout 记录同一 tree
`e5aa6598141e3ad5b79475fd30bdaeb864f07b2c` 与原生 SHA-256
`65489761ce6b4da77cbc6df30a6537c70e5c38b93b5f55ac2a48e4ac0dcf8f3f`。
production APP SHA-256 为
`2a5bf97856c0915325abc4ebe5acd1acd6c6c142141e278a9d34f4c6c3505233`；同源 review-test
HAP SHA-256 为 `b6fc3578e6707bd4813b2faa392715de2ef7163bbfbbac44abbb61f2e161b5ab`，
且已完成最终物理机安装、启动和可见终端 smoke。签名标签 `v1.2.0` 与
[GitHub Release](https://github.com/wandcs/leantty/releases/tag/v1.2.0) 已发布并核对 3 个
归档附件摘要。版本号和发布资产现已不可复用；不得借 AppGallery 提交加入无关功能。

完成 1.2 必须满足：所有产品改动进入精确且已推送的提交；正式软件门禁与干净 ARM64
候选通过；同一个保留候选完成全部适用的物理 HarmonyOS PC 场景；设计、版本、签名、
归档、GitHub Release 和 AppGallery 记录可追溯。安装、启动或工作树截图不能替代行为验收。

## 1. AppGallery 提交

- [ ] 将与 `v1.2.0` GitHub Release 对应、SHA-256 为
  `2a5bf97856c0915325abc4ebe5acd1acd6c6c142141e278a9d34f4c6c3505233` 的 production signed
  APP 和已审定商店材料提交 AppGallery，并记录标签、commit、包体哈希和审核状态的对应关系。
  若审核失败，1.2.0 已消耗，必须递增 PATCH 并重新执行完整流程，不移动标签或替换 Release。

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
