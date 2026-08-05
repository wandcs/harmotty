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

使用新增 Downloads 目录授权的生产 Profile 准备确切 1.1.1 候选，完成 GitHub Release
后再用同版本生产 APP、新应用介绍和版本更新说明提交 AppGallery；任何审核失败都顺延到
下一 PATCH 版本。

## 1. 1.1.1 发布与 AppGallery 提交

- [ ] 从已推送的确切 commit 干净构建并生产签名 1.1.1；确认签入包体的 release Profile
  属于 `com.leantty.app` / AppGallery，保留原应用标识，并同时授权
  `READ_PASTEBOARD` 与 `READ_WRITE_DOWNLOAD_DIRECTORY`；核对 APP/HAP 签名、manifest、
  ARM64 ABI、版本和全部哈希后归档新候选，不修改 1.1.0 证据。
- [ ] 在已验证 commit 上创建不可变签名标签 `v1.1.1`，发布并核对非草稿 GitHub Release。
- [ ] 确认 AppGallery 应用记录及上一版本审核已处于终态，上传与 `v1.1.1` GitHub Release
  对应的同版本生产 APP，并只更新应用介绍和版本更新说明。本次不新增或替换截图、MP4
  和提交备注；记录 GitHub Release、标签、commit、包体哈希和商店提交状态的对应关系。

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
