# skills

个人 Agent Skills 目录。

Personal agent-skills catalogue.

## Install

```bash
gh skill install luxiangze/skills publish-agent-skill
gh skill install luxiangze/skills bmori-go-kegg-enrichment
gh skill install luxiangze/skills --all
```

Grok, available in every project on that machine:

```bash
gh skill install luxiangze/skills publish-agent-skill --agent grok --scope user
```

## Skills

- `publish-agent-skill`
- `bmori-go-kegg-enrichment` — 家蚕 GO/KEGG 富集。KEGG `bmor` 快照取自 2026-09-24 的 REST 接口，使用仍受 [KEGG 条款](https://www.kegg.jp/kegg/legal.html) 约束。

## License

BSD-3-Clause. See [LICENSE](LICENSE). The enrichment skill keeps its own notice at [skills/bmori-go-kegg-enrichment/LICENSE](skills/bmori-go-kegg-enrichment/LICENSE).
