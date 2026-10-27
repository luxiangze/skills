# skills

个人 Agent Skills 目录。

Personal agent-skills catalogue.

## Install

```bash
gh skill install luxiangze/skills publish-agent-skill
gh skill install luxiangze/skills bmori-go-kegg-enrichment
gh skill install luxiangze/skills slurm-cluster-usage
gh skill install luxiangze/skills --all
```

Grok, available in every project on that machine:

```bash
gh skill install luxiangze/skills publish-agent-skill --agent grok --scope user
```

## Skills

- [`r-pixi-renv`](skills/r-pixi-renv/SKILL.md)：使用 pixi 管理 R 运行时，以 pak 安装 R 包，通过 renv 隔离项目库、锁定版本和恢复环境。
- [`readme-writing`](skills/readme-writing/SKILL.md)：面向收件人的结果目录与数据包 README，提供文件索引、用途说明和可移交的阅读入口。
- [`nfcore-rnaseq-slurm`](skills/nfcore-rnaseq-slurm/SKILL.md) — RustFS/S3 到 Slurm 上的 nf-core RNA-seq、差异表达、GO/KEGG/GSEA；三个独立阶段。
- [`jev-effort-advisor`](skills/jev-effort-advisor/SKILL.md) — 用 Jev 按任务阶段与预算偏好选择推理档位，保存可追溯请求和结果。
- `publish-agent-skill`
- `slurm-cluster-usage` — 本集群的作业提交规范：分区、内存硬上限、module 和 Apptainer。
- `bmori-go-kegg-enrichment` — 家蚕 GO/KEGG 富集。KEGG `bmor` 快照取自 2026-09-24 的 REST 接口，使用仍受 [KEGG 条款](https://www.kegg.jp/kegg/legal.html) 约束。

## License

BSD-3-Clause. See [LICENSE](LICENSE). The enrichment skill keeps its own notice at [skills/bmori-go-kegg-enrichment/LICENSE](skills/bmori-go-kegg-enrichment/LICENSE).
