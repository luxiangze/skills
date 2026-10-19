# Differential statistics, identifiers, and enrichment

## R environment

Run environment setup and annotation generation as compute-node jobs, with
`#!/bin/bash -l`, explicit resources, and the selected `pixi` on PATH:

```bash
bash "$SKILL/scripts/setup_r.sh" /path/stage/r_env --deseq2
```

The bundled Pixi lock fixes Linux R 4.5.3 and renv 1.2.3; renv fixes the enrichment
stack. DESeq2 is added from the matching Bioconductor release and its resolved
version is saved in the stage's renv.lock. Shared package cache is allowed; another
project's R library is not. `--r-env` can explicitly reuse an already initialized,
compatible environment. Do not modify the analysis project's unrelated Pixi file.

## Original Wald statistics

`export_stats.R` reads nf-core's fitted DDS and calls
`results(dds, contrast=c(variable,target,reference), independentFiltering=FALSE)`.
It verifies matching gene IDs, contrast p-values and standard two-sided Wald
statistics. Positive stat means higher expression in target. Original `stat` and
shrunken LFC are separate outputs. Non-Wald/custom-threshold/LRT designs need a
different explicitly named ranking metric and must not pass this exporter silently.

Enrichment manifest (TSV):

```text
id  label  results_tsv  annotation_tsv  stats_tsv
```

The exported manifest has absolute file paths. `results_tsv` is the complete
DESeq2 result, not the significant subset; `annotation_tsv` has unique `gene_id`;
`stats_tsv` has `gene_id,stat,pvalue` from the matching fitted test.

## Annotation adapters

For Bombyx use the available `org.Bmori.eg.db` package, source tarball installed in
the stage's renv, or its extracted OrgDb SQLite file. Locate it from user-provided
resources; do not depend on another project's library or absolute paths.

```bash
cd /path/stage/r_env
pixi run -e r Rscript "$SKILL/scripts/annotation.R" \
  /path/org.Bmori.eg.sqlite GID bmor /path/runtime_annotation \
  /path/existing_kegg_snapshot
```

Omit the last argument to fetch a dated local mapping from official KEGG REST.
The optional existing snapshot requires `list_pathway.txt`, `link_pathway.txt`,
`conv_ncbi_geneid.txt` and a known retrieval date/provenance. Record that provenance,
not the current date as a false retrieval date. Retain KEGG's applicable terms;
do not commit snapshots to the public skill catalogue.

OrgDb direct GO associations are expanded through GO.db ancestors, including
when GOALL is empty. The helper normalizes `.0` GeneID suffixes and excludes
unresolved/obsolete ontology IDs. This Bombyx OrgDb uses **GID**, whose values are
NCBI GeneIDs; it has no ENTREZID keytype. For standard other-organism OrgDbs use
`ENTREZID` and that species' KEGG code. Verify `keytypes()` and identifier values;
custom non-NCBI keytypes require explicit common-namespace tables.

For any identifier system, supply explicit tab-delimited mapping tables:

- `go_term2gene`: columns `term,gene`.
- `go_term2name`: `term,name,ontology` (BP, MF or CC).
- `kegg_term2gene`: `term,gene`.
- `kegg_term2name`: `term,name`.

Annotation JSON has these four keys pointing to absolute file paths, plus
`id_type` and `provenance` (organism, release, retrieval date, source).
For NCBI GeneID, IDs can be extracted from `db_xref` fields. For other namespaces
add `id_map` pointing to a TSV with unique `gene_id,annotation_id`, or `id_column`
naming an existing annotation column. Never map genes from a different species by
symbol alone or invent annotations for unannotated genes.

## Interpretation and figures

- ORA background is unique mapped IDs with finite original test p-value and stat,
  restricted internally to the database. Record both tested/mapped and annotated
  background sizes. Queries meet BH < .05 and |shrunken log2FC| >= 1.
- GSEA keeps all finite original Wald stat and test p-values, including NA adjusted
  p-values from independent filtering. Duplicate annotation IDs retain largest
  absolute stat, then stable source gene ID. Exact ties are lexical and retain
  their numeric statistics; report material tie fractions rather than inventing
  random ordering. The saved ranked table is the actual submitted list.
- Full raw test-family tables come from the enrichment object's `@result`, not a
  significance-filtered `as.data.frame(result)`. Significance uses BH, not q-value.
- Defaults: set size 10–500, BH .05, deterministic fgsea seed, multilevel algorithm.
  GO plots show at most ten significant terms per ontology; KEGG at most twenty.
  Complete tables retain all tests. GSEA draws up to three representative curves.
- Inspect ID coverage and leading-edge genes, redundant GO ancestors, small
  overlaps, batch effects and QC before biological conclusions. Distinguish
  non-significance from a missing test. No universal mapping-rate cutoff excuses
  mismatched identifiers. Do not present a muscle/pathogen/longevity pathway name
  as evidence for that phenotype in silk gland tissue.

Results contain ORA all/up/down, GSEA full/significant tables, leading edges,
mapping_summary.tsv, summary.tsv, methods.json, sessionInfo.txt and PNG/PDF figures.
GSEA used here is preranked fgsea, not sample-label permutation.
