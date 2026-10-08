# Usage and reproducibility

## Environment

The bundled template targets Linux x86-64 and pins R 4.5.3, Pixi's `r` environment, and renv 1.2.3. From an analysis project that does not already have a conflicting `pixi.toml`, copy `assets/pixi.toml` and `assets/pixi.lock` into its root. Keep the lockfile with the analysis. If the project already has Pixi, merge the `[feature.r]` and `r` environment sections instead of replacing its manifest.

From the project root:

```bash
pixi install -e r
bash /path/to/bmori-go-kegg-enrichment/scripts/setup_env.sh "$PWD"
pixi run -e r Rscript /path/to/bmori-go-kegg-enrichment/scripts/bmori_enrich.R --help
```

`setup_env.sh` initializes a project-local renv library, restores the pinned analysis packages, installs the bundled OrgDb source tarball, snapshots that project library, and checks `renv::status()`. Runtime libraries must resolve inside the current project; do not point `R_LIBS_USER` at another project's renv library. The direct analysis packages are `clusterProfiler` 4.18.1, `AnnotationDbi` 1.72.0, `GO.db` 3.22.0, `ggplot2` 4.0.1, `enrichplot` 1.30.3, and `org.Bmori.eg.db` 0.2. Their transitive dependencies are recorded in the bundled renv lock template.

If copying the template into an existing project with a different R setup, retain that project's Pixi and renv configuration and explicitly confirm compatible package versions before running. This skill does not require or use the bm_pirna project library.

## DESeq2 mode

Create a tab-separated manifest with one row per contrast:

| Column | Required | Meaning |
| --- | --- | --- |
| `contrast_id` | yes | Filesystem-safe ID for output folders |
| `label` | yes | Human-readable comparison label |
| `results_tsv` | yes | Complete DESeq2 result table with `gene_id`, `log2FoldChange`, and `padj` |
| `annotation_tsv` | yes | Matching gene annotation with `gene_id` and `db_xref` containing `GeneID:<number>` |
| `filtered_tsv` | no | Existing filtered table for consistency checking |

Paths may be absolute or relative to the manifest file. Query genes use `padj < 0.05` and `abs(log2FoldChange) >= 1`; positive fold change is `up`, negative is `down`. The background is all unique mapped NCBI GeneIDs in that contrast's complete DESeq2 table. IDs with a terminal `.0` are normalized before matching.

```bash
pixi run -e r Rscript /path/to/bmori-go-kegg-enrichment/scripts/bmori_enrich.R \
  --mode deseq2 --manifest enrichment_manifest.tsv --outdir results/enrichment
```

Optional arguments: `--alpha`, `--lfc`, `--min-gs-size`, `--max-gs-size`, and `--kegg-snapshot`. Defaults are 0.05, 1, 10, 500, and the bundled `assets/kegg_bmor_20260924` snapshot.

## NCBI GeneID-list mode

Create a tab-separated manifest with one row per query set:

| Column | Required | Meaning |
| --- | --- | --- |
| `contrast_id` | yes | Analysis/comparison ID |
| `label` | yes | Human-readable label |
| `gene_set` | yes | Query-set name, such as `all`, `up`, or `down` |
| `genes_tsv` | yes | Query file with an NCBI GeneID column |
| `background_tsv` | yes | Explicit tested-gene background file with the same ID column |
| `geneid_column` | no | ID column name; defaults to `GeneID`, or first column when absent |

Each query set is tested against its row's background. The script normalizes terminal `.0`, removes duplicate and missing IDs, intersects query and background with the supported annotation, and reports these counts. It does not infer a background from all genes in the OrgDb.

```bash
pixi run -e r Rscript /path/to/bmori-go-kegg-enrichment/scripts/bmori_enrich.R \
  --mode gene-list --manifest gene_lists.tsv --outdir results/enrichment
```

## Results and plotting

Each contrast and query set gets full GO and KEGG test tables, BH < alpha tables, KEGG BH < 0.10 tables, and nominal KEGG p < 0.05 exploratory tables. Figures are GO BP/MF/CC facet dot plots and KEGG dot plots, each saved as 300-dpi PNG and vector PDF. A summary records query size, mapped IDs, background size, tested terms, and significant terms. Metadata records package versions, thresholds, annotation sources, and KEGG retrieval date.

Plot height is calculated from the rows actually displayed and the number of wrapped label lines. One KEGG pathway uses a compact figure; added pathways increase height. GO height also accounts for BP/MF/CC facets. Empty results produce compact, labelled images. Figures have no large title.

For existing bm_pgel result trees, redraw only the plots with:

```bash
pixi run -e r Rscript /path/to/bmori-go-kegg-enrichment/scripts/bmori_enrich.R \
  --redraw-existing --results-root data/processed/.../go_kegg \
  --figures-root reports/figures/.../go_kegg
```

This mode reads saved tables and does not rerun enrichment. It also redraws both KEGG sensitivity folders when present. Confirm that PNG/PDF file dimensions reflect their plotted row counts and that long labels are not clipped.

The nominal KEGG p < 0.05 output is unadjusted and exploratory. The BH < 0.10 output is a relaxed FDR view; retain the default BH < 0.05 results for the primary analysis unless a different threshold was prespecified.
