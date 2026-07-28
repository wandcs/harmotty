# LeanTTY 当前工作

> 状态：唯一有效的项目 TODO
>
> 更新日期：2026-07-28
>
> 上位规则：[`project-principles.md`](project-principles.md)

## 当前结论

LeanTTY `1.0.1` / `1000001` 已于 2026-07-28 通过 AppGallery 审核并公开发布，
是首个实际公开版本。发布对应不可变签名标签 `v1.0.1`、提交
`690a6bdb2b55e51e98a22fc6b69e46a2051592ad` 和仓库外私有发布证据；已完成事实
记录在 `CHANGELOG.md`、Git 历史、GitHub Release 和发布归档中，不在本文件维护
第二份历史清单。

当前开发目标选择为 `1.1.0`。已授权的版本核心是 SSH
`keyboard-interactive` 与多方法认证；Tab 键盘导航可以进入本版本，Pane 快捷键
必须先通过 ARM64 HarmonyOS PC 的系统和输入法冲突门禁。最小 `put/get` 文件传输
仍是独立候选，不在当前实现范围。

## P0：修复工程验证工具

- [ ] 修复自动化 SSH smoke 的终端文本注入。当前工具曾把预期的 `echo` 注入为
  `eho`；同一版本使用物理键盘手动输入完整、远端输出正常，因此该现象归类为测试
  工具缺陷，不是 LeanTTY 键盘输入缺陷。修复前，自动注入产生的命令文本和数据面
  断言不得作为验收证据，相关场景继续以真机物理键盘验证为准。

## P0：SSH keyboard-interactive 与多方法认证

- [ ] 先建立受控 SSH 服务端基线，覆盖现有密码、未加密/加密私钥以及
  `password,keyboard-interactive`、`publickey,password`、
  `publickey,keyboard-interactive` 和多轮 `keyboard-interactive`；测试凭据只
  存在于临时目录。
- [ ] 按服务器返回的 `remaining_methods` 和 `partial_success` 建立唯一认证状态
  机，支持 RFC 4256 名称、说明、一个或多个提示、逐项回显规则和多轮回答；不增加
  厂商认证模式、验证码生成或秘密持久化。
- [ ] 使用结构化 Rust/N-API/ArkTS 事件传递认证 Banner 与挑战，以
  `sessionId + roundId + generation` 拒绝过期、重复和跨 Session 回答；过滤控制
  字符，并确保密码、私钥口令和验证码不进入日志、历史、Preferences 或终端字节流。
- [ ] 覆盖成功、拒绝、部分成功、不支持方法、回答数量错误、取消、超时、断线、
  Pane 关闭和并行 Session；现有密码、私钥、主机指纹、PTY 与终端输出路径必须保持
  回归通过。
- [ ] 在 ARM64 HarmonyOS PC 上使用物理键盘验证密码问答、密码加动态验证码、
  私钥加动态验证码、取消、错误恢复和并行 Session。自动化、构建、安装或启动不能
  替代真机认证交互验收。

## P1：工作区键盘导航

- [ ] 实现 `Ctrl+Tab` / `Ctrl+Shift+Tab` 按现有 Tab 顺序循环切换，并恢复目标
  Tab 自己的 `activePaneId`；普通 `Tab`、终端输入、选择和 Session 所有权不得被
  改变。
- [ ] 在实现 Pane 导航前，先在 ARM64 HarmonyOS PC 上验证
  `Ctrl+Alt+Left` / `Ctrl+Alt+Right` 能稳定到达应用，不触发系统快捷键或输入法
  切换。门禁失败时从 1.1 裁剪 Pane 快捷键，不增加别名、自定义设置或兼容分支。
- [ ] 门禁通过后，只在当前 Tab 的双 Pane 状态消费左右 Pane 快捷键；单 Pane 时
  完整透传，并验证焦点、选择、TUI、复制粘贴和跨 Tab 状态不受影响。

## P1：1.1 集成门禁

- [ ] 运行公共测试、Rust 格式检查、干净 ARM64 native/debug HAP 构建和
  `git diff --check`；认证与导航分别保留可裁剪边界。
- [ ] 在物理 HarmonyOS PC 上完成认证、键盘、焦点、Tab、双 Pane、剪贴板、窗口、
  常见 TUI、断线和重连矩阵。未通过 SSH 认证核心门禁时不得准备 1.1.0 发布。

## 需要深入讨论的候选

- [ ] 最小 `put/get` 文件传输只有在以下可靠性门禁闭合并再次明确写入本文件后才
  能实现：公共 Downloads 上的无覆盖提交、OpenSSH SFTP 排他临时文件与标准
  rename、FD/no-follow 路径边界、临时文件所有权、生命周期、取消和剩余路径语义。

## 不符合当前产品原则的范围

以下内容不建立活动任务：SFTP 文件管理器、目录浏览/同步、后台传输、第二套
Host/Identity、可自定义快捷键、厂商 MFA SDK、验证码种子保存，以及为单一服务器
增加认证特殊分支。

## 文档规则

- 本文件是唯一活动任务清单，只保留未完成工作。
- `project-principles.md` 是产品和技术决策的最高规则。
- 已完成工作进入 `CHANGELOG.md` 和 Git 历史，不在此保留大段完成记录。
- 历史方案、归档材料和未写入本文件的候选不自动授权实现。
