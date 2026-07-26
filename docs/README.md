# HarmoTTY 文档入口

> 更新日期：2026-07-26

`docs/` 根目录只保留当前规则、唯一工作清单和稳定执行手册。已完成、被取代、暂停或只用于追溯的材料统一放入 `archive/`。

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
| [`release-process.md`](release-process.md) | 发布构建、签名、manifest 和校验程序 |
| [`open-source-publication.md`](open-source-publication.md) | 私有审计归档、干净公开基线和 GitHub 协作执行方案 |
| [`versioning.md`](versioning.md) | 版本号规则与版本来源 |
| [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) | 静态资源、Rust 和 ArkTS 依赖声明 |

`OFL-1.1.txt` 是字体许可证正文，`assets/icon.svg` 是图标源文件，必须保留。

## 文档规则

1. 未完成工作只允许写入 [`next-work.md`](next-work.md)；其他当前文档不得维护第二份 TODO 或路线图。
2. [`project-principles.md`](project-principles.md) 优先于所有专项文档、路线图和历史方案。
3. 当前手册只描述稳定事实和执行方法，不混入阶段状态。
4. 首次公开前的私有归档不进入公开仓库；此后的公开历史材料移入
   [`archive/`](archive/README.md)。
5. 归档中的复选框、TODO 和建议全部视为历史内容，不自动恢复为当前任务。
6. 移动文档时同步修正当前文档引用；归档内部的历史链接允许保留原始上下文。
