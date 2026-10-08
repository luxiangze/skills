---
name: bmori-go-kegg-enrichment
description: Run Bombyx mori GO and KEGG over-representation analysis and create adaptive-height enrichment plots from DESeq2 tables or NCBI GeneID lists.
license: BSD-3-Clause
metadata:
  short-description: House silkworm GO/KEGG enrichment and plots
---

# 家蚕 GO/KEGG 富集分析

Use this skill for Bombyx mori functional enrichment when the gene identifiers are NCBI GeneID. It includes the local `org.Bmori.eg.db` 0.2 annotation, dated KEGG `bmor` mappings, environment setup, analysis, and plotting code. Read [references/usage.md](references/usage.md) for input manifests, setup commands, and output layout.

## Workflow

1. Confirm that query and background identifiers are NCBI GeneID. For DESeq2 results, use the complete tested-results table and its matching annotation table; do not use only the prefiltered significant table as the background.
2. Set up the Linux Pixi `r` environment and project-local renv library using `scripts/setup_env.sh`. The bundled KEGG snapshot makes analysis reproducible without network access.
3. Run `scripts/bmori_enrich.R` with a DESeq2 or gene-list manifest. Defaults are BH-adjusted p < 0.05 and pathway size 10–500. Results include `all/up/down` sets for DESeq2 input, complete and filtered GO/KEGG tables, summaries, figures, and KEGG threshold-sensitivity outputs.
4. To redraw saved results without recomputing enrichment, use `--redraw-existing` with the existing result-table root and figure root.
5. Inspect ID mapping rate, query/background sizes, significant-term counts, and plot heights before sharing results. Report the OrgDb and KEGG snapshot dates and note that GO annotations are expanded from direct OrgDb terms using GO.db ancestors because this OrgDb's `GOALL` is empty.

Keep the per-comparison tested-gene universe explicit. Gene-list mode requires a background file. Treat nominal p-value KEGG candidates as exploratory; they are not FDR-controlled. Record the chosen thresholds and input provenance in the output metadata.

See [references/usage.md](references/usage.md) for exact manifest columns and commands.
