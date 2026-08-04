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

1. 补齐 1.1 发布核心 SSH 认证的 Preferences 不变性证据。
2. 然后完成公共检查、干净 ARM64 构建和物理 HarmonyOS PC 集成矩阵。
3. SSH 认证核心门禁未通过时，不进入 1.1.0 发布准备；不能用新增设置、别名或
   特殊分支补救。

验收可以使用测试包中克制、明确且对应具体门禁的专用入口；入口只触发生产事件链，
并须由编译期常量控制且在正式包中完成分支裁剪。不得用模拟结果替代真机行为。

## 1. SSH keyboard-interactive 与多方法认证

技术边界与验收细节：
[`design/ssh-authentication.md`](design/ssh-authentication.md)。

- [ ] 在不读取或导出 Preferences 内容的前提下，补齐物理机认证前后不变性证据；
  已完成的静态边界、命令历史、终端、hilog、提交、拒绝、取消、超时、Pane 关闭、
  进程停止和并行 Session 证据保持通过。

## 2. 1.1 集成与发布准备门禁

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
