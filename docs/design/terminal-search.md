# 终端 scrollback 搜索技术方案

> 状态：WIP；仅建立讨论边界，尚未授权实现
>
> 拟议 milestone：1.2.0
>
> 更新日期：2026-08-03
>
> 上位规则：[`project-principles.md`](../project-principles.md)
>
> 实现授权：未进入 [`next-work.md`](../next-work.md)

## 用户问题与目标

开发和运维用户经常需要在当前终端输出与 scrollback 中定位错误、命令结果、路径或
标识符。LeanTTY 当前没有搜索路径，用户只能滚动目视查找或依赖远端工具；对于已经
输出但仍在当前内存缓冲区中的内容，这是桌面终端自身应提供的高频能力。

目标是在当前 Pane 的 Terminal Surface 内提供一个短生命周期、键盘优先的搜索交互，
不改变 Session、远端字节流、终端内容或其他 Pane 的状态。

## 拟议最小范围

- 打开搜索、输入普通文本、跳到下一处/上一处、关闭并恢复终端焦点。
- 搜索当前 Terminal Surface 的可见内容和内存 scrollback。
- 显示查询、当前匹配位置或无结果状态；反馈不能只依赖颜色。
- 搜索状态只属于当前 Pane/Terminal Surface，不持久化、不跨 Session 共享。
- 支持中文、Unicode、宽字符、多行输出和有界的大 scrollback。

## 非目标

- 跨 Tab、跨 Session、跨重启或远端文件搜索。
- 正则表达式、模糊搜索、搜索历史、结果列表、索引服务或遥测。
- 搜索命令历史、日志、已销毁 Session 或应用持久快照以外的数据。
- 命令面板、自定义快捷键或为了搜索建立通用覆盖层框架。

## 初步所有权

```text
App Shell: 打开/关闭意图与焦点恢复
  → Terminal Surface: 查询、匹配、定位、高亮
  → xterm buffer/search capability
```

Session 和 SSH Transport 不参与搜索，也不接收查询。WebView Bridge 只在必须跨现有
ArkTS/ArkWeb 边界时传递结构化搜索意图与结果，不保存业务状态。查询和匹配状态应跟随
Terminal Surface 销毁，避免把一次 UI 操作变成 Session 长期状态。

## 待共同确认

### 交互

- 打开、下一处、上一处、关闭的固定快捷键；需要先核对 HarmonyOS 系统、输入法、
  xterm/远端程序的冲突，不能仅照搬其他终端。
- 搜索条放在 Terminal Surface 内、Pane chrome 还是 App Shell；应以不遮挡内容、
  双 Pane 清楚归属和最少焦点切换为准。
- Enter、Shift+Enter、Escape、Tab 与输入法组合期间的具体行为。
- 关闭后是保留当前滚动位置，还是回到底部；应以用户可预测且不丢失定位结果为准。

### 技术

- 当前打包的 xterm 版本是否已有满足范围的稳定 search addon/API，新增依赖的体积、
  许可证和 ARM64 ArkWeb 行为如何。
- normal/alternate buffer 的搜索边界；全屏 TUI 退出后哪些内容仍属于可搜索缓冲区。
- renderer 重建与已存在内存检查点发生时，搜索 UI 应直接关闭还是在同一 Surface
  generation 内恢复。
- 极大 scrollback、持续输出和快速重复查询下的延迟与内存基线。
- 匹配高亮如何与现有选择、链接、鼠标上报和终端主题共存。

## 初步验证门禁

### 自动化

- 普通文本、无结果、多个结果、首尾回绕、大小写规则、Unicode 与宽字符。
- 打开/关闭、下一处/上一处、焦点恢复和查询不进入 SSH。
- Tab/Pane 隔离、Surface 销毁、renderer 重建和持续输出期间的确定行为。
- 搜索高亮不改变终端 buffer、selection、OSC/link 处理或远端输入。

### ARM64 构建与物理 PC

- 干净 ARM64 HAP 集成新增前端能力，无隐式在线资源。
- 物理键盘与中英文输入法输入、双 Pane 归属、焦点恢复、复制选择、链接、tmux/vim/
  less 等 TUI 回归。
- 大 scrollback 的打开、逐字输入、跳转和关闭保持及时；先建立基线再确定性能门槛。

## 进入 milestone 的条件

1. 1.1 已冻结或发布，当前可靠性门禁不再与新交互并行竞争。
2. 快捷键、布局和关闭语义已经共同确认。
3. 证明可以局部留在 Terminal Surface 边界，不增加跨 Session 索引或持久状态。
4. 新依赖（如有）通过来源、许可证、体积和目标 ArkWeb 验证。

如果最小搜索仍要求通用命令面板、跨 Session 索引或高成本前端替换，应停止该方案并
重新评估问题，而不是为了维持 1.2 版本号扩大架构。
