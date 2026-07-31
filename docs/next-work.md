# LeanTTY 当前工作

> 状态：唯一有效的项目 TODO
>
> 更新日期：2026-07-30
>
> 上位规则：[`project-principles.md`](project-principles.md)

## 当前结论

LeanTTY `1.0.1` / `1000001` 已于 2026-07-28 通过 AppGallery 审核并公开发布，
是首个实际公开版本。发布对应不可变签名标签 `v1.0.1`、提交
`690a6bdb2b55e51e98a22fc6b69e46a2051592ad` 和仓库外私有发布证据；已完成事实
记录在 `CHANGELOG.md`、Git 历史、GitHub Release 和发布归档中，不在本文件维护
第二份历史清单。

当前开发目标选择为 `1.1.0`。已授权的版本核心是 SSH
`keyboard-interactive` 与多方法认证，以及应用卸载重装后的 SSH 核心资产与必要
设置持久保管；Tab 键盘导航可以进入本版本，Pane 快捷键必须先通过 ARM64
HarmonyOS PC 的系统和输入法冲突门禁。最小 `put/get` 文件传输仍是独立候选，
不在当前实现范围。

## P0：休眠恢复保留终端内容

- [ ] 在物理 ARM64 HarmonyOS PC 上验证：当前 Tab 已产生屏幕与 scrollback 后，
  长时间休眠并让 SSH 断开，唤醒后旧内容、断连提示和 `ltty>` 均保留；同时主动
  在进入后台并完成检查点后触发 ArkWeb renderer 重建，确认内存快照先于脱离
  期间输出恢复，没有重复 OSC 52、bell、标题或远端输入。应用终止、卸载重装后
  仍不得恢复终端内容。

## P0：修复工程验证工具

- [ ] 修复自动化 SSH smoke 的终端文本注入。当前工具曾把预期的 `echo` 注入为
  `eho`；同一版本使用物理键盘手动输入完整、远端输出正常，因此该现象归类为测试
  工具缺陷，不是 LeanTTY 键盘输入缺陷。修复前，自动注入产生的命令文本和数据面
  断言不得作为验收证据，相关场景继续以真机物理键盘验证为准。

## P0：修复 tmux 鼠标模式下的选区复制

- [x] 保持 tmux 对普通鼠标拖动的所有权，不用 LeanTTY 本地选区截获或模拟：
  tmux 默认 `MouseDragEnd1Pane` 在松开鼠标时执行
  `copy-pipe-and-cancel`，选区高亮随 copy-mode 退出而消失是标准行为。
- [x] 接受 tmux 复制时发送的空目标 OSC 52（`OSC 52 ; ; <base64>`），将其与明确
  的系统剪贴板目标 `c` 一样写入 HarmonyOS 系统剪贴板；继续拒绝剪贴板读取、非
  系统剪贴板目标、非法 Base64、非法 UTF-8 和超过 1 MiB 的内容，并用策略测试覆盖
  tmux 空目标回归。
- [ ] 在物理 ARM64 HarmonyOS PC 上开启 `set -g mouse on`，确认普通拖动后无需
  Shift 或二次右键即可由 `MouseDragEnd1Pane` 完成复制，`tmux show-buffer` 与系统
  剪贴板内容一致；同时覆盖 `set-clipboard external/on`、`Ms` 能力、中文和多行
  文本，并回归 tmux 滚动/TUI 鼠标、`Shift+拖动`后 `Ctrl+C` 的本地复制及普通终端
  选区。

## P0：SSH 主机指纹变化恢复

- [x] 主机密钥变化时立即中止连接，显示实际 `HostName`、有效端口、旧/新指纹及
  精确的 OpenSSH `ssh-keygen -R <host>|[<host>]:<port>` 清理指令，然后返回
  `ltty>`；不得等待确认、忽略警告、自动删除、自动信任或自动重连。
- [x] 提供只操作 LeanTTY 唯一权威 `known_hosts` 的 `ssh-keygen -R`，按 OpenSSH
  endpoint 精确删除全部算法记录，覆盖普通、散列、逗号字段、IPv4、IPv6 和非默认
  端口并保留无关内容；删除必须通过持久提交入口，成功后由用户重新连接并按现有
  未知主机流程确认新指纹。
- [x] 在 ARM64 HarmonyOS PC 上使用物理键盘验证直接地址、带端口地址和
  `.ssh/config` Host 别名：轮换受控服务器主机密钥后警告与删除指令必须使用实际
  `HostName + Port`，执行指令、重新连接、确认新指纹及卸载重装后的删除语义均正确。

## P0：卸载重装后的持久资产

- [x] 使用 HarmonyOS Asset Store Kit 的属主隔离持久资产作为唯一长期权威来源，
  无用户选择、备份或恢复流程；保持应用数据备份恢复能力关闭，并移除无效的
  `BackupExtensionAbility` 路径。
- [x] 持久保管 OpenSSH `config`、`known_hosts`、所有已验证私钥/公钥对、终端
  字号和窗口位置尺寸；密码、私钥口令、OTP、认证回答、命令历史、Tab、Pane、
  Session、终端内容、日志、缓存和临时文件不得进入持久资产。
- [x] 以版本化 manifest 和小于 1 KiB 的分块记录覆盖 RSA-4096、加密私钥及可增长
  的 OpenSSH 文件；新 generation 全部分块验证成功后才能切换 manifest，文件运行
  副本必须从持久资产原子生成，失败时不得静默回退为空状态或覆盖旧数据。
- [x] 将 `host add/set/rm`、密钥生成/导入/删除、主机信任写入、字号和窗口状态统一
  接入持久提交入口；Rust 不得绕过该入口直接学习 `known_hosts`，持久提交完成前
  不得向用户报告成功或继续已接受的新主机连接。
- [x] 从 1.0.1 的 Preferences 与应用私有 `.ssh` 无感迁移，保留 OpenSSH 文件格式
  而不新增第二套 Host/Identity 模型；已显式删除的 Host、Key 和主机信任在后续
  卸载重装后不得复活。
- [ ] 验证普通卸载（不得使用 `bm uninstall -k`）后，同一正式应用身份重装能够
  自动读取持久资产且不出现恢复界面；不同签名应用不可读取。真机覆盖 Ed25519、
  RSA-4096、加密/未加密私钥、`known_hosts`、字号、窗口、删除语义、锁屏和重启。
  - 2026-07-28 阶段证据：物理 ARM64 HarmonyOS PC 上使用普通卸载后，同一签名
    身份重装能够自动查询加密持久资产并正常启动，全程没有恢复界面；用户确认
    Host、密钥、`known_hosts`、字号和窗口状态均已保留。不同签名隔离与完整密钥、
    删除、锁屏、重启矩阵仍待验证，因此本项保持未完成。

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
  `git diff --check`；持久资产、认证与导航分别保留可裁剪边界。
- [ ] 在物理 HarmonyOS PC 上完成认证、键盘、焦点、Tab、双 Pane、剪贴板、窗口、
  持久资产、密钥导出、常见 TUI、断线和重连矩阵。未通过持久资产与 SSH 认证核心
  门禁时不得准备 1.1.0 发布。

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
