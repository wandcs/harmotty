# LeanTTY 文档入口

> 更新日期：2026-07-28

`docs/` 根目录只保留当前规则、唯一工作清单和稳定执行手册。已完成或被取代的公开方案
从当前树删除，通过 Git 历史追溯；私有证据和机器记录不进入仓库。

## 阅读顺序

| 顺序 | 文档 | 用途 |
|---:|---|---|
| 1 | [`project-principles.md`](project-principles.md) | 最高层产品定位、功能边界和技术规则 |
| 2 | [`next-work.md`](next-work.md) | 唯一有效的 TODO、优先级和当前完成定义 |
| 3 | [`coding-guide.md`](coding-guide.md) | 当前架构、协议、API 和编码约束 |

## 稳定手册与合规文件

| 文档 | 用途 |
|---|---|
| [`dev-environment.md`](dev-environment.md) | 工具链、SDK、依赖和目标环境 |
| [`release-process.md`](release-process.md) | 发布分支、构建、签名、提审、tag 和校验程序 |
| [`versioning.md`](versioning.md) | 版本号、分支、Unreleased 和商店审核规则 |
| [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) | 静态资源、Rust 和 ArkTS 依赖声明 |

`OFL-1.1.txt` 是字体许可证正文，`assets/icon.svg` 是图标源文件，必须保留。
被拒绝且未发布的 1.0.0 历史由根 `README.md`、`CHANGELOG.md`、不可变标签和仓库外
私有发布证据共同记录。

## 文档规则

1. 未完成工作只允许写入 [`next-work.md`](next-work.md)；其他当前文档不得维护第二份 TODO 或路线图。
2. [`project-principles.md`](project-principles.md) 优先于所有专项文档、路线图和历史方案。
3. 当前手册只描述稳定事实和执行方法，不混入阶段状态。
4. 首次公开前的私有归档不进入公开仓库；完成或被取代的公开方案通常从当前树
   删除，通过 Git 历史追溯。
5. [`archive/`](archive/README.md) 只保留归档政策和确有长期证据价值的例外材料；
   归档内容不自动恢复为当前任务。
6. 删除或移动文档时同步修正当前文档引用。
