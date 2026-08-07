# LeanTTY 最小文件传输技术方案

> 状态：WIP；产品边界已初步收敛，可靠性门禁尚未闭合，未授权实现
>
> 拟议 milestone：1.3.0；版本与范围仍须在 1.2 完成后重新确认
>
> 初稿日期：2026-07-26；最近更新：2026-08-03
>
> 上位规则：[`project-principles.md`](../project-principles.md)
>
> 版本顺序：[`roadmap.md`](../roadmap.md)
>
> 工作排期仍以 [`next-work.md`](../next-work.md) 为唯一有效 TODO。本文记录为什么值得
> 做、如何限制复杂度、已经取得的证据和后续验收门槛，不单独授权实现。
>
> 命令面治理：[`command-system.md`](command-system.md)

## 一、当前结论

LeanTTY 值得在拟议 1.3 中继续推进一个**最小、命令行式、单文件传输能力**，但不做
SFTP 文件管理器。用户命令确定为 `put` 和 `get`，分别表示上传和下载；内部使用
SSH 的 SFTP 子系统传输。

文件传输只能从当前 Pane 尚未连接服务器时的本地 `ltty>` 提示符发起，一次只传一个
文件，完成或失败后立即释放独立传输 Session。`put/get` 复用 OpenSSH SFTP 已有的
方向认知，但不是完整 SFTP 交互式命令集。

本地文件根目录固定为 HarmonyOS 向应用授权的公共 **Downloads（下载）目录本身**：

```text
用户看到：Downloads
真机路径：/storage/Users/currentUser/Download
```

不再创建或要求用户理解 `Downloads/LeanTTY` 子目录。`.` 和所有本地相对路径都
从 Downloads 解析。

文件冲突统一按最终名称的选择者处理：用户明确指定目标名时失败且不修改已有文件；
`get` 省略本地目标、由 LeanTTY 采用默认名称时，冲突自动生成 `name (n).ext` 并
保留两份。1.3 不提供覆盖选项或确认对话框。

该选择是在目标 HarmonyOS PC 上实际验证 Picker 后作出的产品决策，不是因为 Picker
不可用：

- Picker 可以在不申请 Downloads 权限的情况下选择并读取 Images 中的单个文件。
- Picker 可以创建保存目标，应用能够写入，结果在文件管理器中可见并可正常打开。
- 但 Picker 会让每次上传和下载都进入系统界面，使命令历史无法直接重放，并让 `.`
  从本地目录语义变成“打开 Picker”。
- Picker URI 还会增加 ArkTS、文件描述符与 Rust 之间的生命周期所有权；保存目标的
  冲突、删除和重命名能力也不再完全由 LeanTTY 控制。
- “上传用 Picker、下载用 Downloads”会形成两套本地文件模型，不进入 1.3。

因此 1.3 接受“上传前偶尔需要把文件移动或复制到 Downloads”的成本，换取稳定、
键盘优先、可预测且可重复执行的路径式命令。

这一结论只把最小文件传输保留为条件 1.3 候选。只有它被明确写入 `next-work.md` 后才允许
开始实现。本文后续关于临时文件和路径细节仍包含未确认候选，统一列在“后续讨论
清单与实现前门禁”中，不能因已经写入草案而视为批准。

## 二、为什么值得做

### 2.1 它服务远程终端的直接任务

远程终端用户经常需要把一个本地构建产物、配置文件或诊断材料传到服务器，或把一个
远端日志、归档和结果文件取回本地。没有文件传输时，用户只能离开 LeanTTY，再寻找
其他工具，或者在远端临时使用 HTTP、邮件、网盘等绕行方案。

单文件上传和下载不是本地 shell、文件管理器或资产管理平台；它是 SSH 日常工作中
与 `ssh`、`ssh-keygen`、`ssh-copy-id` 相邻的操作。只支持单文件交换，可以补齐
核心路径附近的真实缺口，而不改变 LeanTTY 的终端产品心智。

### 2.2 `put/get` 准确复用 SFTP 的方向认知

OpenSSH SFTP 已经使用以下交互命令：

```text
put <local-path> [remote-path]
get <remote-path> [local-path]
```

LeanTTY 复用 `put` 表示上传、`get` 表示下载，并在远端路径中补上 Host：

```text
put demo.jpeg prod:/tmp/demo.jpeg
get prod:/var/log/app.log
```

选择两个方向明确的动词，可以删除“恰好哪一端是远端”的推断，也不会让用户期待
OpenSSH `scp` 的多源、递归、远端到远端、完整选项和任意本地路径。`put/get` 虽然
是两个命令，但上传和下载本来就是两个不同方向的任务，不是同一任务的重复入口。

不再增加 `upload`、`download`、`transfer`、`copy` 或 `sftp` 等别名：

- `upload/download` 没有复用 Linux/SFTP 既有认知。
- `transfer` 仍需根据参数推断方向。
- `copy/cp` 会让 Linux 用户期待本地文件复制语义。
- `sftp` 会让用户期待进入包含 `ls`、`cd`、`rm` 等能力的交互式文件会话。
- `file put/get` 多增加一个没有真实状态所有权的命名空间。

用户输入 `scp` 时只显示迁移提示，不作为别名执行，避免保留第二套等价模型。
### 2.3 Downloads 根目录比 Downloads/LeanTTY 更易用

原方案把本地根设为 `Downloads/LeanTTY`，安全边界清楚，但增加了一层用户必须
理解和操作的目录：

- 上传前，即使文件已经在 Downloads，用户仍要把它移动到 LeanTTY 子目录。
- 下载后，用户需要在文件管理器中再进入一层目录。
- 帮助和错误信息必须反复解释 `Downloads/LeanTTY`。

直接使用 Downloads 后：

- 已经下载到 PC 的常见文件可以直接上传。
- `get prod:/path/file` 的结果就在文件管理器默认可发现的 Downloads。
- 完成提示只需说 `Open Files and go to Downloads`。
- 用户只理解 HarmonyOS 已经存在的系统目录，不学习产品专用目录。

代价是 Downloads 中更容易出现同名文件和未完成临时文件。已经确定的约束和仍待
讨论的实现门禁是：

- 永不静默覆盖已有文件。用户明确指定最终目标名时冲突失败；`get` 省略本地目标、
  由 LeanTTY 采用远端 basename 时，冲突自动生成唯一名称并保留两份。
- 最终名称不能暴露损坏内容；临时文件和最终提交方式是实现前门禁。
- 失败、取消和下次启动不得删除无法证明属于 LeanTTY 的文件；精确所有权方案仍待
  讨论。
- 不扫描、索引或展示 Downloads 的其他内容。

这些问题不改变 Downloads 与专用子目录的取舍，但必须在实现前闭合，不能用
Downloads 更易用作为降低可靠性要求的理由。

## 三、为什么不做更大的 SFTP 功能

以下方案都不进入 1.3：

| 方案 | 不采用原因 |
| --- | --- |
| SFTP 文件管理器 | 引入目录树、选择状态、多选、重命名、删除、刷新和大量错误分支，已经成为第二个产品 |
| `scp` | 会暗示多源、递归、完整选项和任意本地路径；只提供迁移提示，不作为别名 |
| `upload` / `download` | 没有复用 SFTP 的 `put/get` 方向认知，且与已选命令形成重复入口 |
| 文件选择器 | 真机已证明可选取和保存单个文件，但每次传输都会进入 GUI，破坏路径重放并增加 URI/FD 生命周期；1.3 拟采用 Downloads 单一路径模型 |
| 任意本地绝对路径 | 真机已经证明普通应用不能仅凭路径访问 Images 等公共目录 |
| 路径自动补全 | 必须枚举 Downloads 或远端目录，引入建议状态、隐私暴露和远端请求时序 |
| 连接后复用当前 SSH Session | 让交互式 PTY 与 SFTP channel 共享生命周期、取消和错误状态 |
| 自动打开文件管理器 | HarmonyOS 没有已经确认的稳定“打开并定位目录”接口，也会打断终端操作 |
| 目录、通配符和多文件 | 需要递归、批次、部分成功、冲突和恢复模型 |
| 后台队列和断点续传 | 引入跨 Pane、跨生命周期状态和持久任务管理 |

明确排除这些能力，才能使文件传输仍然是终端中的一个小型 SSH 操作，而不是 SFTP
产品的起点。

## 四、用户模型

### 4.1 唯一持久对象仍然是 Host

Host 是唯一的持久连接配置：

```text
Host prod
  HostName example.com
  User deploy
  Port 22
  IdentityFile ~/.ssh/deploy
```

`ssh prod`、`put file prod:/tmp/file` 和 `get prod:/tmp/file` 必须使用同一个解析
入口，共享：

- HostName
- User
- Port
- IdentityFile
- 主机指纹校验
- 密钥口令、密码和 `keyboard-interactive` 认证

不存在 Transfer Identity、SFTP Host、传输凭据或单独的服务器列表。

1.3 文件传输不扩展 Host 管理命令：

- 不为 `host add` 或 `host set` 增加 `-i`、`--no-identity`。
- 不为 `host list` 增加 Identity 列，也不新增 `host show`。
- 不建立新的 Identity 持久字段或迁移现有 Host 数据。
- `put/get -i <identity>` 只覆盖本次命令，不修改 Host。

SSH 配置中的 `IdentityFile` 当前存在“文件路径”和“LeanTTY key store 名称”的
语义差异。文件传输不得在内部建立一套修正规则；`put/get` 必须复用 `ssh` 的同一
解析结果和错误边界。如果该差异需要修复，应作为所有 SSH 命令共同的连接配置问题
单独决策，而不是借文件传输扩展 Host 产品面。

### 4.2 `put/get` 命令

上传语法：

```text
put [-p port] [-i identity] <local-file> <host>:<remote-file>
```

```shell
put demo.jpeg prod:/tmp/demo.jpeg
put demo.jpeg deploy@example.com:/tmp/demo.jpeg
```

下载语法：

```text
get [-p port] [-i identity] <host>:<remote-file> [local-file]
```

```shell
get prod:/var/log/app.log
get prod:/var/log/app.log app-local.log
```

带空格的路径使用 macOS/Linux 用户熟悉的引号或反斜杠：

```shell
put "Quarterly report.pdf" "prod:/tmp/Quarterly report.pdf"
put Quarterly\ report.pdf prod:/tmp/report.pdf
get "prod:/tmp/Quarterly report.pdf" "Quarterly report.pdf"
```

本地命令分词只支持完成该需求所需的单引号、双引号和反斜杠转义；不实现环境变量、
命令替换、管道、重定向、`~` 展开或通配符展开。

用户输入 `scp` 时不执行传输，只给出迁移提示：

```text
`scp` is not supported. Use:
  put <local-file> <host>:<remote-file>
  get <host>:<remote-file> [local-file]
```

不提供 `scp`、`upload`、`download` 或其他等价别名。

### 4.3 路径与目标解析

方向由命令决定，不再根据两个位置参数猜测：

- `put` 的第一个位置参数必须是 Downloads 内的本地相对文件，第二个必须是远端。
- `get` 的第一个位置参数必须是远端；第二个是可选的 Downloads 内本地相对文件。
- `get` 省略本地目标时，使用远端文件的 basename 保存到 Downloads 根。
- 远端目标必须明确到文件名；1.3 拒绝尾部 `/`，不推断远端目录和最终文件名。

- `prod:/path`：优先按现有 Host 别名解析。
- `deploy@example.com:/path`：一次性直接目标。
- 远端绝对路径保持绝对。
- 远端相对路径相对于 SFTP 登录后的初始目录。
- 1.3 不承诺远端 `~` 展开。
- 本地路径只接受相对于 Downloads 的路径，不接受 HarmonyOS 内部绝对路径。
- 目录、多个源、远端到远端和命令方向不匹配全部拒绝。

`put/get` 的连接选项与现有 LeanTTY `ssh` 和 `ssh-copy-id` 一致，使用小写 `-p`
覆盖 SSH 端口。由于命令不叫 `scp`，不继承 SCP 为避让“保留时间和权限”而使用
大写 `-P` 的历史规则。

### 4.4 Identity 优先级

`put/get -i` 与现有 `ssh -i` 使用同一个 key store 引用语义，只覆盖当前命令，
不修改 Host：

```text
命令行 -i > Host IdentityFile > 正常认证回退
```

主要帮助和示例优先使用 Host 别名。`help put` 和 `help get` 再介绍 `-p` 和 `-i`，
避免把高级覆盖呈现成第二套配置。

## 五、本地文件规则

### 5.1 唯一本地根

首次使用 `put` 或 `get` 时，LeanTTY 按需申请：

```text
ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY
```

用户允许后，通过 HarmonyOS 文件环境 API 取得公共 Download 目录。产品中统一显示
为 `Downloads`，不向用户展示 `/storage/Users/currentUser/...` 内部路径。

路径规则：

- Downloads 是唯一且隐含的本地根，不建立可切换的本地当前目录。
- `demo.jpeg` 表示 `Downloads/demo.jpeg`。
- `logs/app.log` 表示 `Downloads/logs/app.log`。
- 只允许规范化后仍位于 Downloads 内的相对路径。
- `get` 省略本地目标时，直接使用远端 basename 保存到 Downloads 根。
- 拒绝所有本地绝对路径、`..` 逃逸、符号链接逃逸、设备文件和目录源。
- 不读取目录列表来提供补全、推荐或浏览。

如果用户输入：

```text
/storage/Users/currentUser/Images/demo.jpeg
```

应提示：

```text
Local files must be in Downloads.
Move demo.jpeg to Downloads, then run:
  put demo.jpeg prod:/tmp/demo.jpeg
```

不得为完成这条命令临时弹出文件选择器或申请 Images、Documents、Desktop 权限。

### 5.2 上传

- 源必须是 Downloads 中一个明确存在、可读的普通文件。
- 远端目标必须明确，不支持目录递归和通配符。
- `put` 的远端目标始终由用户明确指定。连接并确认目标已经存在时，在传输文件数据前
  失败，不覆盖，也不擅自生成另一个远端名称。
- 上传使用目标所在远端目录中的唯一临时名称，并以
  `CREATE | EXCL | WRITE` 排他创建；不能使用会截断已有文件的高层 `create()`。
- 临时文件完整写入并成功关闭后，使用标准 `SSH_FXP_RENAME` 提交为最终名称。不能
  使用具有覆盖语义的 `posix-rename@openssh.com`。
- 失败或取消时尽力删除远端临时文件。

远端目标冲突时显示：

```text
Remote file already exists:
  prod:/tmp/demo.zip

No files were changed.
Use another remote name, or remove the existing file on the server first.
ltty>
```

预检查只用于尽早报错，不能替代最终提交时的无覆盖保证；检查与提交之间出现并发
冲突时同样失败，已有远端文件保持不变，临时文件按本次任务身份清理。服务器不能
提供可靠的无覆盖提交时安全失败，不能退化为直接写入最终名称。

完成提示：

```text
Uploaded 15.3 MiB
  demo.zip -> prod:/tmp/demo.zip
ltty>
```

### 5.3 下载

- 下载目标只能位于 Downloads。
- `get <host>:<remote-file>` 省略本地目标时，由 LeanTTY 采用远端 basename。
  如果该名称已存在，自动生成不冲突的新名称，保留已有文件和新下载。
- `get <host>:<remote-file> <local-file>` 明确指定本地目标时，如果该名称已存在，
  在传输文件数据前失败，不覆盖，也不自动改名。
- 省略本地目标且预检查发现 basename 冲突时，开始前只说明完成时将选择唯一名称，
  不提前承诺某个可能被其他 Pane 或应用抢占的最终名称。
- 先在最终目标所在目录写入 `.leantty-<random>.part` 一类 LeanTTY 可识别的唯一
  临时文件。
- 完成写入、关闭并核对已传输长度后，才以“目标存在则失败”的方式提交最终名称。
- 取消、失败和恢复清理只能删除符合本次任务身份的临时文件。

统一判断规则是：

> 用户明确选择最终目标名时，冲突失败；LeanTTY 选择默认最终名称时，冲突生成
> 唯一名称。

这不是上传和下载各自拥有一套任意策略。`put` 的远端目标和带本地参数的 `get` 目标
都由用户明确选择，因此失败；只有省略本地参数的 `get` 由 LeanTTY 负责名称，因此
自动保留两份。1.3 不弹确认对话框，也不提供 `--force`、`--overwrite` 或持久冲突
设置。

#### 5.3.1 省略本地目标时的文件名冲突规则

采用 macOS/Windows 下载器常见的扩展名前数字去重形式：

```text
<主文件名> (<序号>)<后缀>
```

序号从 `1` 开始，选择当前目录中最小的可用正整数：

| 远端 basename | 已存在 | 实际保存名称 |
| --- | --- | --- |
| `app.log` | `app.log` | `app (1).log` |
| `app.log` | `app.log`、`app (1).log` | `app (2).log` |
| `report.final.pdf` | `report.final.pdf` | `report.final (1).pdf` |
| `archive.tar.gz` | `archive.tar.gz` | `archive.tar (1).gz` |
| `README` | `README` | `README (1)` |
| `.env` | `.env` | `.env (1)` |

算法规则：

1. 临时文件完整写入并关闭后，先以无覆盖方式尝试远端 basename；提交成功就保持
   原名。
2. “后缀”定义为最后一个非首字符 `.` 开始的部分，包括点本身。序号插在它之前；
   后缀的文字、大小写和字节内容完全不变。
3. 没有后缀的文件直接在完整名称后增加 ` (n)`。只有首字符点的 Unix 隐藏文件也
   按无后缀处理，因此 `.env` 变成 `.env (1)`。
4. 不尝试解析原名称末尾已有的 `(n)`。例如请求名称本来就是 `app (1).log`，再次
   冲突时生成 `app (1) (1).log`，避免隐藏的重命名猜测。
5. basename 提交因目标存在而失败时，继续以同样的无覆盖方式依次尝试最小可用序号；
   已经下载完成的临时文件不需要重新传输。
6. 如果增加序号会超过平台文件名长度，只在 Unicode 字符边界截短主文件名，为
   ` (n)` 和原后缀保留空间；不得截短或改写后缀。
7. 从 `1` 检查到 `9999` 仍没有可用名称，或主文件名无法安全截短时，传输失败并
   提示 Downloads 中同名文件过多，不再使用时间戳或随机最终名称。

选择该规则的原因：

- Chromium 的跨平台下载模型把数字计数器放在文件扩展名前，并用最小可用序号避免
  覆盖；同一实现覆盖 Windows 和 macOS。
- Apple 的文件冲突行为同样采用保留原文件并给额外版本增加数字的心智。
- `copy`、`副本` 等文字会涉及本地化；纯数字形式稳定、短且容易预测。
- 最终文件名仍保留原后缀，文件管理器和关联应用可以继续按类型识别。

该自动改名只适用于**省略本地目标的下载**。它不适用于上传，也不适用于用户明确
输入本地目标的下载。

预检查检测到冲突后，在传输开始前显示：

```text
File already exists: Downloads/app.log
A unique name will be chosen when the download completes.
```

完成提交后才显示确定的实际名称：

```text
Downloaded 15.3 MiB
  Renamed: app.log -> app (2).log
  Saved to Downloads/app (2).log

Open Files and go to Downloads to view it.
ltty>
```

如果预检查和最终提交都没有冲突，不显示 `File already exists` 或 `Renamed`，只
显示正常保存路径。如果预检查后才发生并发冲突，开始时不补发过时提示，完成时直接
显示最终名称和 `Renamed`。冲突提示遵循以下规则：

- 使用独立完整行，不能只在进度行中短暂闪现。
- 开始提示只说明存在冲突和稍后选择唯一名称；完成提示必须包含原名称和最终名称，
  便于用户在 Downloads 中定位。
- 可以使用现有终端警告色增强识别，但文字是唯一语义来源，不能只靠颜色或图标。
- 不使用 Toast、对话框或确认按钮，不阻塞传输。
- 文件名中的控制字符必须转义或替换，远端文件名不能借提示注入终端控制序列。
- 不响铃，不制造持续通知；只有预检查已经发现冲突时才在开始和完成两个时点提示。

这种交互对应成熟下载器的“保留两个文件并显示最终名称”，但适配了终端没有常驻
下载列表的特点：用户无需干预，同时不会错过文件已经改名的事实。LeanTTY 不自动
打开文件管理器，不打开下载文件，也不增加 `open` 命令。

#### 5.3.2 明确本地目标时的冲突规则

用户输入：

```text
get prod:/var/log/app.log latest.log
```

如果 `Downloads/latest.log` 已存在，显示：

```text
Local file already exists:
  Downloads/latest.log

No files were changed.
Choose another local name:
  get prod:/var/log/app.log latest-2.log
ltty>
```

错误必须包含冲突路径和一条可以直接修改后重试的完整命令。预检查之后、最终提交
之前才出现的并发冲突使用相同错误；LeanTTY 删除本次临时文件，但不询问是否覆盖、
不删除已有文件，也不把明确目标悄悄改成 `latest (1).log`。

### 5.4 权限被拒绝

权限只在用户执行首条 `put` 或 `get` 时申请，不在应用启动时申请。拒绝后：

- 取消本次传输。
- 回到 `ltty>`。
- SSH 终端其他功能保持可用。
- 不循环弹窗。
- 用户再次执行 `put` 或 `get` 时可以重新尝试，并显示申请原因。

## 六、传输生命周期与技术边界

### 6.1 Pane 与 Session

只能从当前 Pane 的本地 `ltty>` 提示符发起。其他 Tab 或 Pane 可以保持已连接；
“未连接”不表示整个应用必须断开。

当前 Pane 在传输期间进入独占状态：

```text
IDLE
  -> CONNECTING
  -> VERIFYING_HOST
  -> AUTHENTICATING
  -> OPENING_SFTP
  -> TRANSFERRING
  -> FINALIZING
  -> COMPLETED | FAILED | CANCELLED
  -> IDLE
```

传输 Session：

- 不创建 PTY 或 shell。
- 不复用其他 Pane 的已连接 SSH Handle。
- 不保留为可重连 Session。
- 完成、失败或取消后立即释放。
- 传输期间当前 Pane 不启动第二条本地命令。
- `Ctrl+C`、关闭 Pane、超时和断网进入同一取消清理路径。

独立传输生命周期是真实状态边界，因此可以有一个局部、可测试的传输状态类型；不再
增加 TransferManager、任务队列或持久后台服务。

### 6.2 ArkTS、N-API 与 Rust

职责划分：

| 边界 | 职责 |
| --- | --- |
| `CommandParser` | `put/get` 分词、参数、方向和本地/远端位置验证 |
| `SshConfig` | HostName、User、Port、IdentityFile 的唯一解析 |
| `LocalTransferPathPolicy` | Download 授权、路径规范化、逃逸检查和本地临时文件 |
| `SessionViewModel` | 当前 Pane 的前台状态、提示、取消和完成文案 |
| Rust/russh | SSH 连接、主机校验、认证和 channel 生命周期 |
| `russh-sftp` | SFTP 文件操作和流式读写 |
| N-API | 启动、取消和节流后的结构化传输事件 |

文件字节不得经过 ArkTS、WebView H2 Bridge 或终端输出中转。Rust 从已验证的本地
受控路径流式读写；ArkTS 只接收进度、完成和安全错误类别。

当前 `russh 0.62.5` 上游示例使用 `russh-sftp 2.3.0`。它是实现候选，不是未经验证
即可加入的结论；落地前必须完成许可证、依赖、ARM64 构建和目标服务器互操作审计。

### 6.3 进度与错误

进度在同一终端行节流更新：

```text
app.log                    64%   9.8 MiB / 15.3 MiB   4.2 MiB/s
```

无法可靠取得总大小时只显示已传输字节数。不为每个数据块跨 N-API 或新增一行。

错误至少区分：

- Download 权限被拒绝。
- 本地文件不存在或在允许目录外。
- 远端上传目标已存在、明确指定的本地下载目标已存在，或省略目标时无法分配唯一
  下载名称。
- 最终提交不支持无覆盖语义，或提交期间目标被并发抢占。
- 主机指纹或 SSH 认证失败。
- 服务器不支持 SFTP。
- 远端权限拒绝。
- 本地空间不足或写入失败。
- 网络断开、超时和用户取消。
- 清理失败。

错误说明下一步，不记录文件内容、凭据或不必要的完整敏感路径。

## 七、已经完成的验证

### 7.1 验证环境

2026-07-26 在物理 HarmonyOS PC 上进行了临时文件访问探针：

| 项目 | 环境 |
| --- | --- |
| 设备 | HAD-W32 |
| CPU | ARM64 |
| 系统 | HarmonyOS 6.0.0 |
| 设备 API | API 22 |
| SDK 核对 | 本机 API 24 SDK 声明 |
| 测试文件 | `/storage/Users/currentUser/Images/demo.jpeg` |

探针使用 LeanTTY 应用身份运行，不用 HDC shell 权限代替应用权限。

### 7.2 SDK 与权限验证

本机 API 24 SDK 中确认：

- `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY` 是 `normal` 级别、
  `user_grant` 模式，从 API 11 提供。
- `Environment.getUserDownloadDir()` 需要该权限并返回公共 Download 目录。
- Documents 使用独立的普通用户授权。
- Desktop 对应权限为 `system_basic`，不适合普通三方应用。

这证明 HarmonyOS 的模型是目录级明确授权，而不是给普通应用一个可遍历全部用户
文件的全盘读写权限。

### 7.3 真机结果

| 验证项 | 结果 | 支持的结论 |
| --- | --- | --- |
| 未声明目录权限，读取 `/storage/Users/currentUser/Images/demo.jpeg` | `Operation not permitted` | 仅凭用户输入任意路径不可行 |
| 未声明目录权限，取得 Download/Documents/Desktop | 全部 `Operation not permitted` | 公共目录不是默认开放 |
| 申请 Download 权限 | 系统显示明确授权弹窗，用户选择允许 | 权限不是静默获得 |
| 获得 Download 权限后取得目录映射 | 返回 `/storage/Users/currentUser/Download` | Downloads 可以成为唯一公开本地根 |
| 在 `Download/LeanTTY` 创建、写入、关闭后重开测试文件 | 成功，测试文件随后清理 | 已授权 Download 范围可以稳定读写 |
| Download 授权后再次读取原始 Images 文件 | 仍为 `Operation not permitted` | Download 权限不会扩散到 Images |
| 用户把 `demo.jpeg` 复制到 `Download/LeanTTY` 后读取 | 成功；大小 15,682 字节，读取前 16 字节 | 用户移动到已授权 Download 范围后的上传源模型成立 |
| 应用重启和同签名覆盖安装 | 授权仍有效，没有重复弹窗 | 当前真机上授权可跨这两个生命周期保持 |

探针没有修改原始 `Images/demo.jpeg`，也没有修改或删除用户复制的
`Download/LeanTTY/demo.jpeg`。

### 7.4 Picker 真机验证

2026-07-27 又在同一物理 PC 上验证了 `DocumentViewPicker`，目的是在决定本地文件
模型前证明替代方案的真实能力，而不是只根据文档推测：

| 验证项 | 结果 | 支持的结论 |
| --- | --- | --- |
| 未声明 Downloads 权限，通过 Picker 选择 `Images/demo.jpeg` | 成功返回 `file://docs/.../Images/demo.jpeg` URI | Picker 可以提供单文件读取授权 |
| 读取所选文件 | 15,682 字节；前 16 字节为 `ff d8 ff e0 00 10 4a 46 49 46 00 01 01 00 00 01` | 选择到的是此前 JPEG/JFIF 测试文件 |
| 连续选择两次 | 文件名、大小和文件头一致 | 选择和读取行为可重复 |
| 通过系统保存界面创建副本并写入 | 文件管理器可见，用户确认可以正常打开 | Picker 保存 URI 的用户可见成功路径成立 |
| 保存测试期间的安装权限 | 未声明 `READ_WRITE_DOWNLOAD_DIRECTORY` | Picker 不依赖整个 Downloads 授权 |
| 尝试删除保存 URI | 副本仍然存在；SDK 的 `unlinkSync` 也只承诺应用沙箱路径 | 不能把 Picker URI 的删除或重命名能力当作已证明前提 |

保存探针包含写后回读比较，但对应 hilog 在应用退出后被高频设备日志覆盖，未保留可
审计的逐字节一致性记录。因此本轮只确认文件可见且可正常打开，不把“保存副本哈希
一致”列为已完成证据。该证据边界不影响 Picker 与 Downloads 的交互取舍。

Picker 探针结束后，临时代码和权限声明均已移除，正常签名 LeanTTY 已重新构建、
覆盖安装并启动。测试副本需要由用户从文件管理器删除，不能声称应用已经自动清理。

### 7.5 收尾验证

Downloads 权限探针完成后：

- 临时探针源码已恢复到测试前状态。
- 临时 Download 权限声明已撤销。
- 正常 LeanTTY 已重新构建并安装。
- 设备新进程中没有 `FILE_PROBE` 日志。
- 安装包不再声明测试权限。

Picker 探针完成后也重新执行了相同恢复流程；新的正常进程无
`PICKER_SAVE_PROBE`，安装包无 Downloads 权限，仓库无 Picker 探针源码差异。

### 7.6 证据边界

已经验证的是 HarmonyOS 的公共目录授权模型、“用户移动到 Download 后应用可读写”
路径，以及 Picker 的单文件选择与用户可见保存路径，不是完整文件传输实现。

以下内容**尚未验证**：

- 直接把 Download 根目录作为最终产品根时的完整上传/下载交互。
- `put/get` 命令解析、引号和 Host/Identity 复用。
- `russh-sftp` 在 LeanTTY ARM64 HAP 中的构建和运行。
- 与 OpenSSH 服务器的上传、下载、取消、断线和错误互操作。
- Downloads 上的 `moveFile(temp, final, 1)` 无覆盖提交。
- SFTP 排他临时文件、标准 rename 的无覆盖提交和并发抢占处理。
- 大文件流式传输、临时文件清理和崩溃清理。

此前真机实际读写发生在 `Download/LeanTTY` 子目录。改为直接使用 Download 根目录
是基于同一已授权目录映射作出的产品决策，仍须在实现验收时补一次根目录端到端测试。
由于临时探针已经移除，仓库中不保留可作为持续回归的测试代码；实现阶段必须重新
建立受控测试并保存可复现步骤。

## 八、后续讨论清单与实现前门禁

本节是后续讨论的权威清单。标记为“待讨论”的条目没有被本文其他详细候选规则自动
批准；标记为“实现前门禁”的条目必须先取得平台或协议证据，不能留到功能完成后再
补救。

### 8.1 已确认的产品决策

#### 8.1.1 Downloads 与 Picker

1. 1.3 只保留 Downloads 一个本地文件根。
2. 不采用每次传输弹出的 Picker，也不做“上传 Picker、下载 Downloads”的混合模型。
3. 选择 Downloads 的主要理由是保持路径式命令、键盘优先、历史可重放、冲突行为
   可控和 Rust 直接流式读写。
4. 已接受的代价是整个 Downloads 授权范围更大，且上传其他目录中的文件前可能需要
   用户先移动或复制。
5. Picker 的能力验证作为替代方案证据保留，但不转化为 1.3 产品入口。

#### 8.1.2 `put/get` 命令模型

1. 上传使用 `put`，下载使用 `get`，复用 OpenSSH SFTP 的既有方向认知。
2. 不把功能命名为 `scp`，避免暗示多源、递归、远端到远端、完整选项和任意本地
   路径兼容性。
3. 不增加 `upload`、`download`、`transfer`、`copy`、`sftp` 或 `file put/get`
   等价入口。
4. 用户输入 `scp` 时只显示 `put/get` 迁移提示，不作为别名执行。
5. `put/get` 使用与现有 `ssh` 一致的小写 `-p` 和 `-i` 连接选项。
6. `get` 省略本地目标时使用远端 basename；`put` 和 `get` 的远端路径都必须明确
   到文件名，1.3 不接受尾部 `/` 的远端目录目标。

#### 8.1.3 文件冲突与目标名称所有权

1. 上传和下载都不静默覆盖已有文件。
2. 用户明确选择最终目标名时冲突失败；LeanTTY 选择默认最终名称时冲突生成唯一
   名称。这是上传和下载共同使用的唯一判断规则。
3. `put` 的远端目标始终明确，因此远端同名文件存在时失败。
4. `get` 明确提供本地目标时，本地同名文件存在则失败。
5. `get` 省略本地目标时由 LeanTTY 采用远端 basename；冲突使用最小可用的
   `name (n).ext`。开始时不承诺可能被并发抢占的名称，完成时显示实际保存名称。
6. 1.3 不增加确认对话框、`--force`、`--overwrite` 或可配置冲突策略。

选择原因：

- OpenSSH SFTP、`scp` 和 `rsync` 的普通传输路径偏向更新已有目标，而 Wget、curl
  和 Transmit 也提供保留两份、跳过、询问或覆盖等不同策略；不存在必须照搬的唯一
  行业默认。
- LeanTTY 可靠性优先，不能把破坏性覆盖作为默认行为，也不在 1.3 增加覆盖能力。
- 对明确名称失败，尊重命令行用户的目标意图；对省略名称自动去重，避免用户为一次
  普通下载手工重输命令。
- 按“谁选择名称”判断比按上传/下载方向硬编码两个例外更容易解释，也不需要对话框、
  持久设置或第二套操作模式。

未采用的替代方案：

- 全部冲突失败：规则最少，但让最常见的省略目标下载产生不必要的重输。
- 所有下载都自动改名：会忽略用户明确输入本地目标名的意图。
- 每次询问：引入等待输入的额外状态，并使脚本式重复执行变得不可预测。
- 允许覆盖：既增加破坏性能力，也要求先证明原子替换、取消和崩溃恢复，不属于 1.3
  的最小可靠路径。

#### 8.1.4 Host/Identity 最小复用范围

1. `put/get` 复用现有 Host、认证、主机指纹、key store 和 `ssh` 的配置解析入口。
2. 命令级 `put/get -i <identity>` 与现有 `ssh -i` 使用相同语义，只覆盖本次传输，
   不修改 Host。
3. 1.3 不为 `host add/set` 增加 `-i` 或 `--no-identity`，不为 `host list` 增加
   Identity 列，也不新增 `host show`。
4. 不建立 Transfer Identity、SFTP Host、第二套凭据或新的持久字段。
5. `IdentityFile` 的路径与 key store 名称差异不在文件传输内部修补；若要修复，
   必须作为 `ssh`、`ssh-copy-id` 和 `put/get` 共同的连接配置问题另行决策。

选择该范围是为了让文件传输只增加一次性操作，不顺带扩大持久配置、列表界面和数据
迁移。已有 Host 可以直接复用；临时选择其他密钥时使用命令级 `-i` 已足够完成核心
路径。

### 8.2 实现前可靠性门禁

#### 8.2.1 本地与远端无覆盖提交

已确定的共同提交模型是：

```text
预检查目标
  -> 在最终目标所在目录排他创建唯一临时文件
  -> 完整传输并关闭临时文件
  -> 以“目标存在则失败”的方式提交最终名称
  -> 清理本次任务拥有的临时文件
```

预检查只用于尽早给出冲突错误；它和最终提交之间存在竞态，不能作为可靠性保证。
产品保证限定为：

- 已有目标内容绝不被修改。
- 最终名称只在完整传输成功后出现。
- 并发抢占明确目标时安全失败；省略下载目标时改试下一个唯一名称。
- 取消、失败或断线不会把不完整内容暴露为最终名称。
- 1.3 不承诺远端服务器断电后的磁盘持久化；这不是普通 SFTP 传输能够统一保证的
  能力。

本地下载的推荐实现：

1. 临时文件和最终文件位于 Downloads 的同一目录。
2. 临时文件完整写入并关闭后，候选使用 HarmonyOS
   `fs.moveFile(temp, final, 1)` 提交；API 24 SDK 声明 `mode = 1` 在目标同名文件
   存在时抛出 `File exists`，而不是覆盖。
3. 明确本地目标只尝试一次；提交冲突时删除本次临时文件并失败。
4. 省略本地目标时，在传输完成后依次尝试 basename、`name (1).ext`、
   `name (2).ext`，直到无覆盖提交成功；不提前占用或承诺最终名称。

上述 SDK 声明主要描述应用沙箱路径，尚未证明公共 Downloads 上具有相同的原子和
无覆盖行为。因此 `moveFile(..., 1)` 仍是待真机验证的实现候选，不是已经取得的
平台证据。若它不能满足要求，再评估 native `renameat2(RENAME_NOREPLACE)`；不能
直接假设 NDK 头文件中存在声明就代表目标文件系统支持。

远端上传的推荐实现：

1. 在目标目录使用 `CREATE | EXCL | WRITE` 排他创建随机临时文件；不得使用
   `russh-sftp` 会截断已有文件的高层 `create()`。
2. 完整写入并成功关闭后，使用 SFTP v3 标准 `SSH_FXP_RENAME` 提交。标准语义要求
   `newpath` 已存在时报错；不能使用具有覆盖语义的
   `posix-rename@openssh.com`。
3. 当前 OpenSSH 对普通文件的标准 rename 优先使用 link/unlink 做无竞态提交，但
   仍需用实际 `russh-sftp` 客户端和目标 OpenSSH 服务器验证协议结果、错误映射和
   临时文件清理。
4. 服务器不支持可靠无覆盖提交时，本次上传安全失败；不能退化成直接写最终名称、
   删除已有目标或覆盖 rename。

本地 Downloads 和远端 OpenSSH 两侧验证都通过前，本节保持“实现前可靠性门禁”
状态，不把推荐方案写成已验证能力。

#### 8.2.2 路径验证与打开之间的 TOCTOU

ArkTS 先验证字符串路径、Rust 再按路径重新打开，会给符号链接替换留下窗口。需要
选择并验证真正的能力边界：

- ArkTS 打开已经授权的文件，把文件描述符及明确所有权交给 Rust；或
- Rust 相对于可信 Downloads 目录句柄执行 no-follow 打开，并在打开后 `fstat`。

不能把“规范化过的字符串”当作文件访问授权，也不能让文件字节经过 WebView。

#### 8.2.3 临时文件所有权与跨重启清理

文件名符合 `.leantty-*.part` 不足以证明归 LeanTTY 所有。不得扫描 Downloads
后删除所有匹配前缀的文件。候选只有：

- 持久保存每个精确临时文件的随机 ID，只清理有记录的对象；或
- 不做启动扫描，接受极端崩溃留下隐藏临时文件。

该问题按用户当前讨论顺序暂后置，但实现前必须作出选择。

#### 8.2.4 `Ctrl+C` 与终端复制

现有终端在有选区时把 `Ctrl+C` 用于复制。传输取消应保持同一优先级：

- 有选区时复制，不取消。
- 无选区时取消当前传输。

还需要确认传输提示是否必须明确写出该规则，并在真机上验证选区、焦点和取消事件。

#### 8.2.5 生命周期、并发与迟到事件

实现前必须定义：

- 两个 Pane 同时首次申请 Downloads 权限时如何串行化。
- 关闭 Pane 是等待清理结束，还是由 native 在受控生命周期内完成。
- N-API 事件携带 `transferId + paneId + generation`，避免取消后的迟到事件写入
  新 Session。
- 最小化、休眠和系统终止时是继续、暂停还是取消。
- 强制终止不能保证执行清理，只能依靠提交模型保证半文件不暴露为最终名称。

#### 8.2.6 尚未闭合的路径语义

最小版本仍需明确：

- 远端符号链接是否跟随。
- IPv6 地址与 `host:path` 冒号如何消歧。
- 非 UTF-8 远端文件名如何处理。
- Downloads 内本地子目录不存在时是否创建。
- 空 basename 和超长名称的失败规则。

以下规则已经由 `put/get` 命令决策闭合：本地只接受 Downloads 下的相对路径，不
接受内部绝对路径；远端路径必须明确到文件名；不接受尾部 `/`；`get` 省略本地目标
时保存到 Downloads 根，不再需要 `.` 特殊目标。

### 8.3 建议讨论顺序

1. 真机验证 Downloads 的 `moveFile(temp, final, 1)` 无覆盖提交。
2. 验证 `russh-sftp` 与 OpenSSH 的排他临时文件和标准 rename。
3. FD/no-follow 路径能力边界。
4. 临时文件、生命周期和剩余路径语义。

## 九、仍需完成的验证

### 9.1 自动化

Host/Identity 用例按 8.1.4 的最小复用范围实现；冲突用例按 8.1.3 已确认的唯一
规则实现，不能额外增加 Host 扩展、对话框或覆盖分支。

- `put/get` 分词覆盖引号、反斜杠、缺少参数、未知选项和未闭合引号。
- `put` 只接受本地到远端，`get` 只接受远端到本地。
- `get` 省略本地目标时正确提取远端 basename。
- 远端尾部 `/`、目录、多个源、方向不匹配和本地绝对路径均被拒绝。
- `scp` 只返回迁移提示，不启动连接；其他别名不被接受。
- Host 与直接目标解析结果和 `ssh` 一致。
- `-i`、Host IdentityFile、默认认证回退优先级一致。
- `put/get -i` 只覆盖当前命令，不改变后续 `ssh` 或 `put/get`。
- `host add/set/list` 的语法和输出不因文件传输改变；文件传输不新增持久 Identity。
- 本地路径规范化后不能逃出 Downloads。
- 不跟随会逃逸的符号链接。
- `put` 目标已存在时在传输数据前失败，错误包含远端冲突路径，已有文件内容不变。
- `get` 明确本地目标且已存在时在传输数据前失败，错误包含冲突路径和指定新名称的
  可执行示例，已有文件内容不变。
- `get` 省略本地目标且 basename 已存在时，验证最小可用序号、后缀、隐藏文件、
  Unicode、长度、序号耗尽、并发抢占、开始时不承诺最终名称以及完成时显示实际
  名称。
- 检查与最终提交之间发生并发冲突时仍不覆盖，并返回与名称所有权一致的结果。
- 下载最终名称在临时文件完整关闭前不可见；明确目标提交冲突时只清理本次临时文件。
- 上传临时文件使用 `CREATE | EXCL | WRITE`；标准 rename 冲突不改动已有远端目标。
- 禁止使用 `russh-sftp.create()`、`posix-rename@openssh.com` 或直接写最终名称作为
  无覆盖路径的回退。
- `--force`、`--overwrite` 和任何冲突确认输入都不被接受。
- 下载临时文件成功提交；失败和取消清理。
- 小文件、空文件和大文件内容哈希一致。
- 进度事件节流，两个 Pane 的传输状态不串联。

### 9.2 物理 HarmonyOS PC

1. 在未授权状态执行首条 `put/get`，确认只出现真实系统 Download 权限弹窗。
2. 允许后直接从 `Downloads/demo.jpeg` 上传，不使用 LeanTTY 子目录。
3. 在没有同名文件时省略本地目标下载 `app.log`，从系统文件管理器确认
   `Downloads/app.log` 可见且哈希一致。
4. 拒绝权限后确认终端仍可用，再次执行时可以恢复。
5. 验证空格、Unicode、长文件名和 Downloads 内相对子目录。
6. 分别预置远端上传目标、明确指定的本地下载目标和省略目标的 basename：前两者
   必须失败且原文件哈希不变；后者必须选择最小可用的 `name (n).ext`、不修改
   后缀，开始时不承诺最终名称，完成时显示原名称与实际名称。
7. 在预检查后、最终提交前抢占目标名称：明确目标必须失败且已有文件哈希不变；
   省略下载目标必须使用下一个名称，不能重新传输文件。
8. 中途 `Ctrl+C`、断网、关闭 Pane 和关闭应用，不留下最终名称的损坏文件。
9. 如果最终选择跨重启清理，验证只删除精确记录为 LeanTTY 所有的 `.part` 文件；
   如果选择不扫描，验证启动时不会按文件名前缀触碰 Downloads 内容。
10. 使用密码、未加密密钥、加密密钥和 `keyboard-interactive` Host 各完成传输。
11. 验证 `put/get -i other` 只临时覆盖，不改变后续 `ssh prod` 或
    `put/get ... prod:...`。
12. 服务器没有 SFTP、远端权限拒绝和本地空间不足时错误清楚且可恢复。
13. 检查 hilog、命令历史和错误快照不包含凭据或文件内容。

没有完成自动化、ARM64 干净构建和上述真机矩阵前，不得把文件传输标为完成或写入
发布宣传。

## 十、如何满足产品原则

| 产品原则 | 文件传输方案如何满足 |
| --- | --- |
| 可靠是底线 | 独立短生命周期 Session；明确 `TRANSFERRING` 与 `FINALIZING`；同目录临时文件和禁止替换提交；统一取消和错误分类；真机验收 |
| 简洁是默认选择 | `put/get` 方向明确；一个 Downloads 根；按目标名称所有权使用一条冲突规则；复用现有 Host 而不扩展管理命令；单文件；无 GUI、补全、队列和后台状态 |
| 易用只优化核心路径 | 复用 SFTP 的 `put/get` 认知；省略下载目标时自动保留两份；明确目标冲突时给出可执行的改名示例 |
| 不并存等价模型 | 不提供 `scp` 等别名；`ssh` 与 `put/get` 共用 Host、Identity、主机指纹和认证解析 |
| 优先复用标准 | 用户表面复用 OpenSSH SFTP 的 `put/get` 方向；传输复用 SSH SFTP 子系统；权限复用 HarmonyOS Download 授权 |
| 明确安全边界 | 不访问任意用户路径；不扩大到 Images/Documents/Desktop；文件字节不经过 WebView；不记录秘密 |
| 不为架构而架构 | 只为真实独立生命周期增加局部传输状态；不建立 Manager、通用任务框架或插件接口 |
| 验证是设计的一部分 | 已用应用身份做真机权限探针；明确区分已验证平台事实和待验证传输实现 |

该能力与“默认不做 SFTP 文件管理器”的原则不冲突：禁止的是第二套文件管理产品，
不是通过两个方向明确的 SFTP 风格命令完成一次单文件交换。

## 十一、停止条件

出现以下任一情况时，应停止把文件传输纳入 1.3，而不是继续扩大方案：

- `russh-sftp` 不能在目标 ARM64 HAP 中可靠构建或运行。
- 复用现有认证状态机需要破坏交互式 SSH Session 的稳定性。
- HarmonyOS Download 权限在目标发布环境中无法通过普通三方应用审核或稳定使用。
- 取消和断线无法避免把损坏文件暴露为最终名称。
- 实现必须增加文件管理器、后台服务、持久队列或第二套 Host/Identity 数据。
- 真机用户路径仍然难以理解，且需要不断增加特殊规则才能工作。

届时应保留现有 SSH 终端能力并推迟文件传输，不用路线图倒逼产品原则让步。

## 十二、设计依据

- [LeanTTY 产品与技术原则](../project-principles.md)
- [LeanTTY milestones](../roadmap.md)
- [OpenSSH `sftp` 手册](https://man.openbsd.org/sftp.1)
- [OpenSSH `scp` 手册：未采用命令名的兼容性对照](https://man.openbsd.org/scp.1)
- [SFTP v3 rename：目标存在属于错误](https://datatracker.ietf.org/doc/html/draft-spaghetti-sshm-filexfer-00)
- [OpenSSH `sftp-server` 当前无覆盖 rename 实现](https://github.com/openssh/openssh-portable/blob/master/sftp-server.c)
- [rsync 官方手册：更新、跳过和备份已有目标](https://download.samba.org/pub/rsync/rsync.1)
- [GNU Wget 手册：重复下载编号与 `--no-clobber`](https://www.gnu.org/software/wget/manual/wget.pdf)
- [curl 手册：`--no-clobber` 与 `--skip-existing`](https://curl.se/docs/manpage.html)
- [Panic Transmit：上传和下载的冲突处理](https://help.panic.com/transmit/transmit5/transfers/)
- [Chromium：下载冲突使用扩展名前的数字计数器](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/download/internal/common/download_path_reservation_tracker.cc)
- [Chromium Downloads API：`uniquify` 冲突行为](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/common/extensions/api/downloads.webidl)
- [Apple：保留多个冲突版本时为额外版本增加数字](https://support.apple.com/guide/mac-help/mh40780/mac)
- [russh 0.62.5 SFTP client 示例](https://docs.rs/crate/russh/0.62.5/source/examples/sftp_client.rs)
- [`russh-sftp` 2.3.0 文档](https://docs.rs/russh-sftp/2.3.0/russh_sftp/)
- [`russh-sftp` `SftpSession`：create、open flags 与 rename](https://docs.rs/russh-sftp/2.3.0/russh_sftp/client/struct.SftpSession.html)
- [HarmonyOS 文件授权持久化](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/native-fileshare-guidelines)
- [HarmonyOS 应用隐私保护](https://developer.huawei.com/consumer/cn/doc/doccenter-architecture/bpta-app-privacy-protection)
