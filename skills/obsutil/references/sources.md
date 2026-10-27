# 来源与交付文档差异

核对日期：2026-10-07。这里是任务所需事实的整理，命令兼容性以实际 obsutil 版本帮助及相应官方文档为准。

## 现有技能检索结论

本机技能目录、skills.sh 和公开仓库检索发现 [官方 huawei-cloud-obs-upload](https://github.com/huaweicloud/huaweicloud-skills/blob/master/skills/storage/obs/huawei-cloud-obs-upload/SKILL.md) 使用 obsutil 上传，下载与分享不在其范围。另一个 [官方 huawei-obs](https://github.com/huaweicloud/huaweicloud-devkit/blob/main/plugins/huaweicloud-core/skills/huawei-obs/SKILL.md) 使用 hcloud OBS 封装。此次可检索范围内没有找到对应 `share-cp` / `share-ls` 数据交付下载的等价技能，因此创建本技能补足此场景；不声称全网不存在其他实现。

## 一手来源

- [授权码下载对象](https://support.huaweicloud.com/utiltg-obs/obs_11_0064.html)：`share-cp`、key、范围、保存规则。
- [授权码列举对象](https://support.huaweicloud.com/utiltg-obs/obs_11_0063.html)：`share-ls`、prefix、marker、limit。
- [下载和安装 obsutil](https://support.huaweicloud.com/utiltg-obs/obs_11_0003.html)：系统包、官方校验和、版本检查。
- [利用帮助命令查找工具功能](https://support.huaweicloud.com/utiltg-obs/obs_11_0066.html)：按命令查询本地帮助。
- [利用 obsutil 进行断点续传](https://support.huaweicloud.com/intl/zh-cn/utiltg-obs/obs_11_0059.html)：分段门槛和续传。
- [下载对象](https://support.huaweicloud.com/utiltg-obs/obs_11_0018.html)：普通 `cp` 下载、长度和 MD5 核验、临时目录。

用户提供的《华为云链接下载方法说明文档V2.docx》作为数据交付场景参考。技能无需原始 Word 文件即可使用，未包含文档中的真实分享 token、提取码或截图。

## 与 Word 示例的差异

- 原文给出全量、样本目录和单个 `.fq.gz` 文件的分享下载方法。技能保留这些场景；单文件改为精确 key 且不带 `-r`，避免把文件路径当成前缀批量匹配。
- 原文批量示例使用 `-f`；技能按用户的执行方式选择它，不把跳过提示当成扩大范围的授权。
- 原文将 `threshold` 概括为续传功能；实际应区分分段门槛、断点状态和小文件直接下载。
- 原文将 `-u` 概括为不重复下载；实际按存在性、大小和修改时间判断。
- 原文说明该交付方上传时设置 MD5；这不能推广到所有链接，仍须验证元数据或使用独立校验清单。
- 官方文档目前写提取码为 8 位，原文示例为 6 位。使用用户实际收到的提取码，不能填补或截断；若当前版本拒绝则核对交付方与版本，不能凭示例猜造提取码。
- Word 中长 URL 可能有排版断行；优先取原始完整链接，不复制示例授权材料。
