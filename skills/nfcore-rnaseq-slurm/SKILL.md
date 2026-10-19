---
name: nfcore-rnaseq-slurm
description: Run bulk RNA-seq from RustFS/S3 FASTQs through nf-core/rnaseq, nf-core/differentialabundance, and GO/KEGG/GSEA on Slurm. Use for end-to-end transcriptome analysis or an individual stage using existing upstream results, including 样本表、转录组、差异基因、集群运行和富集分析. Supports multiple species with a Bombyx mori annotation adapter.
license: BSD-3-Clause
metadata:
  short-description: S3 to RNA-seq, DESeq2 and enrichment on Slurm
---

# Bulk RNA-seq on Slurm

Carry the requested analysis through results, not merely submission. The helpers
prepare independent stages; Nextflow itself schedules pipeline tasks on Slurm.

## Working contract

- Use three sibling directories under the current project's `workflow/`:
  `<study>_rnaseq_<date>`, `<study>_differentialabundance_<date>`, and
  `<study>_DEG_enrich_<date>`. A stage records its upstream path and hashes; it
  can be run or resumed independently. Use `--suffix` for a distinct same-day run.
- Confirm biological identity and contrasts from study metadata. Names can identify
  FASTQ pairs, not biological replicates, genotypes, controls, or batches. Collect
  missing design information together; do not infer a control from “WT” in a name.
- Keep FASTQs in S3 and reference `s3://` in the samplesheet. Nextflow stages inputs
  in shared work storage. Do not make an extra raw-data copy or treat multipart
  ETags as MD5 checksums.
- Resolve the latest non-prerelease of both pipelines for a new analysis, then lock
  tag, commit, and Nextflow requirement. Resume the locked revision. Do not silently
  use a cached old version when release discovery fails; obtain connectivity or an
  explicit version. Check Java against the installed/required Nextflow release.
- Discover existing Nextflow global config and user profiles first. `apptainer`
  selects a container engine; it does not imply Slurm. Validate the effective
  executor, including process selectors, without printing credentials. Reuse the
  user's site config; generate a minimal Slurm fallback only if no site config was
  supplied and none is active. Keep resource caps separately configurable.
- Run computation on compute nodes. On the target cluster use `#!/bin/bash -l`,
  explicit CPU/memory/time/partition, and initially at most 32 CPU/64 GB per task.
  Apply the available cluster-usage skill when choosing resources. Larger requests
  require the user's authorization unless already provided. A small driver job
  runs Nextflow; Nextflow submits task jobs through its native Slurm executor.

## Run

Read [references/workflow.md](references/workflow.md) for commands and input
formats. Read [references/enrichment.md](references/enrichment.md) when preparing
DESeq2/GO/KEGG/GSEA, and [references/operations.md](references/operations.md) for
cluster checks, recovery, and installation updates.

1. Capture `rc ls --recursive --json`; reject truncated listings. Prepare the RNA
   stage from metadata plus the snapshot or an explicit reads manifest. Validate
   reference assembly/annotation consistency and NCBI/GTF attributes.
2. Inspect resolved config and compute-node S3 access. Run a small environment
   probe before the batch, then submit RNA-seq. Review MultiQC, sample identities,
   mapping, counts, strandedness and replicate relationships. Do not quietly label
   an undetermined library unstranded or exclude samples to improve significance.
3. Prepare differentialabundance from the chosen RNA output and explicit contrasts.
   Review design rank and confounding; configure blocking or formula explicitly
   when needed. Pass counts and corresponding transcript-length matrix together.
   Export original Wald `stat` from the saved DDS as well as shrunken effects.
4. Prepare enrichment from the chosen differential results. Use mapped, actually
   tested genes for ORA backgrounds and all finite original Wald statistics for
   GSEA; retain independently filtered genes with finite `stat`. GO/KEGG annotation
   files must use the same identifier namespace as the gene map.
5. Monitor through `squeue`, `sacct`, Nextflow logs and trace. Fix a demonstrated
   cause before `-resume`; stop automatic retries after two resumes with the same
   cause. Report running/blocked/completed accurately. Never clean work directories
   or cancel unrelated jobs automatically.
6. Collect outputs and write a Chinese summary of QC limitations, per-contrast
   up/down counts, mapping rates, annotation provenance and significant GO/KEGG/GSEA
   counts. Link tables and figures. ORA/GSEA agreement is not independent replication;
   enrichment does not establish pathway activity or causation.

## Defaults and boundaries

`star_salmon`, Apptainer, strand `auto`, DESeq2 BH < 0.05 and |log2FC| >= 1;
GO/KEGG ORA on all/up/down and both GO/KEGG GSEA, BH < 0.05, gene sets 10–500.
Plots: large fonts, no large titles, PNG at 300 dpi and vector PDF; empty results
produce labeled figures and header-only tables. Wider KEGG thresholds are optional
exploratory analyses and never replace the primary FDR results silently.

Nonstandard references, fusion/transgene quantification and complex experimental
designs need explicit study-specific configuration. This skill does not infer full
fusion transcripts from a plasmid or mix independently quantified TPM matrices.
Databases, reference genomes, private data, credentials and absolute user-specific
paths belong to generated runs, not this published skill.
