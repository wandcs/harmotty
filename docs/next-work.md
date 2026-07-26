# HarmoTTY 当前工作

> 状态：唯一有效的项目 TODO
>
> 更新日期：2026-07-26
>
> 上位规则：[`project-principles.md`](project-principles.md)

## 当前结论

HarmoTTY 1.0.0 已提交 Huawei AppGallery Connect 审核。提审源码、产物哈希、
签名校验和完整私有 Git 历史已在仓库外冻结并完成恢复验证。

“建立可信公开源码基线”已完成。公开没有改变 1.0.0 提审产物；公开后的产品开发
从本仓库继续。签名标签 `v1.0.0` 已固定到首次公开根提交；AppGallery Connect
审核状态仍为审核中，审核通过前不创建对应的 GitHub Release。

当前补丁开发目标为 `1.0.1`。版本元数据已前移到 `1.0.1` / `1000001`，待发布修复
记录在 `CHANGELOG.md` 的 `1.0.1 - In development` 下。`Unreleased` 保持为空，
用于尚未归入目标版本的后续工作；1.1 功能规划不进入本补丁分支。

## P0：公开源码

### A. 提审证据和历史

- [x] 冻结 1.0.0 提审源码 commit、tree、APP/HAP/native/manifest 哈希与签名结果。
- [x] 创建包含全部私有 refs 的离线 Git bundle，并从 bundle 恢复准确提审源码。
- [x] 保存公开前 GitHub 仓库设置、Actions、Issue、PR 和 Release 状态。

### B. 干净公开基线

- [x] 从提审源码建立不含私有历史的新 Git 根提交。
- [x] 删除缓存、生成物、旧 x86_64/模拟器入口、机器路径和内部调查流水。
- [x] 记录提审源码与首次公开基线的来源映射和差异分类。
- [x] 完成源码策略、敏感信息、许可证和第三方资源审计。

### C. 社区与自动化

- [x] 补齐 README、贡献、安全、支持、行为准则和商标边界。
- [x] 启用 Issue 和 Fork；接受 PR，但不承诺合并、响应时限或功能实现。
- [x] 建立不接触秘密和个人设备的公共 CI。
- [x] 配置 Issue/PR 模板、Dependabot、私密漏洞报告和合并策略。

### D. 公开与验收

- [x] 使用官方地址 `wandcs/harmotty` 发布干净公开历史。
- [x] 公开后从匿名干净 clone 运行公共检查并核对仓库页面。
- [x] 验证 Fork、Issue、PR、安全报告和 Actions 权限符合执行方案。
- [x] 将首次公开 commit 写入来源记录和 1.0.0 发布证据。

## P0 完成记录

- 官方公开仓库：`https://github.com/wandcs/harmotty`
- 首次公开根提交：`93ce79d80533f37ccc7501897d4e92f8549c25de`
- 来源映射：[`source-provenance.md`](source-provenance.md)
- 主分支保护：ruleset `19762483`，要求四项公共检查通过、线性历史和 PR 合并
- 公共 CI：Actions run `30198342930` 的四项检查全部通过
- 安全状态：Secret scanning、Push protection 和私密漏洞报告已开启；公开的
  Dependabot 安全告警已清零
- 外部验收：关闭凭据后完成匿名 HTTPS clone，并通过源码策略、Web 终端策略、
  Rust 格式及公开历史秘密扫描
- 私有历史：已迁移到只读私有仓库 `wandcs/harmotty-private-archive`；仓库外
  Git bundle 和 1.0.0 证据仍可独立恢复

## 公开后的维护记录

- 正式开发基线已迁移到官方公开仓库的干净 clone；私有归档只用于审计和恢复，
  不再作为后续产品开发工作区。
- 公共仓库移除内部性能脚本后遗留的真机部署辅助依赖，已由 PR #6 修复；源码策略
  现在会拒绝引用未跟踪 PowerShell helper 的提交。
- Tokio 已由 1.52.3 升级到 1.53.1（PR #3）。公共 CI 四项检查、ARM64 干净构建、
  签名安装启动、SSH 连接认证和真机物理键盘命令验证均完成。
- russh 保持 0.62.4。2026-07-26 核对时它仍是
  [官方最新稳定版](https://github.com/Eugeny/russh/releases/tag/v0.62.4)，并已包含
  当前公开的 malformed PTY 和 Curve25519 消息安全修复；暂不切换到 git/master
  或预发布版本。

## P1：工程验证工具可靠性

- [ ] 修复自动化 SSH smoke 的终端文本注入。当前工具曾把预期的 `echo` 注入为
  `eho`；同一版本使用物理键盘手动输入完整、远端输出正常，因此该现象归类为测试
  工具缺陷，不是 HarmoTTY 键盘输入缺陷。修复前，自动注入产生的命令文本和数据面
  断言不得作为验收证据，相关场景继续以真机物理键盘验证为准。

## 完成定义

只有在以下条件同时满足后，P0 才完成：

- AGC 证据仍可独立恢复和核验；
- 公开仓库不包含秘密、个人环境、内部历史或不支持的平台产物；
- 公开 CI 运行真实检查，不使用假成功；
- 外部参与者能够安全提交 Issue 和 PR；
- 官方包、源码、Fork 和第三方构建的边界清楚；
- 匿名干净 clone 的公共检查通过。

完成 P0 后，新的产品工作必须依据
[`project-principles.md`](project-principles.md) 重新进入本文件；历史材料不自动
成为路线图。
