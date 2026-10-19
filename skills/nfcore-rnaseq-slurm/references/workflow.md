# Stage commands and input contract

Set `SKILL` to the installed skill directory (the directory containing SKILL.md).
All relative input paths are resolved against the invoking working directory.
Helpers use Python 3 standard library; run `workflow.py --help` for flags.

## Inputs

- `metadata.tsv`: one biological sample per row, columns `sample,condition` plus
  optional `strain,genotype,replicate,batch,subject`. Tab or comma delimiters work.
  Do not put one row per lane in biological metadata.
- `contrasts.csv`: `id,variable,reference,target,blocking`. `variable=condition`
  usually; `blocking` names a metadata column, not a sample ID. Every pair must be
  represented in both groups. Reviewed complex models can be supplied through
  pipeline parameters; adapt the validator explicitly rather than pretending a
  confounded simple contrast is valid.
- Optional `reads.csv`: `sample,fastq_1,fastq_2,strandedness`. Repeated sample IDs
  mean lanes/technical resequencing and are merged by rnaseq. Leave fastq_2 empty
  for single-end. Automatic parsing supports `_R1`, `_1`, `_R1_001` and analogous
  R2 patterns; use the explicit manifest for ambiguous delivery names. Verify
  explicit S3 reads against a complete inventory before submission.

## RNA-seq

```bash
python3 "$SKILL/scripts/workflow.py" inventory \
  --source rustfs/bucket/delivery/rawdata/ --out /tmp/reads.json
python3 "$SKILL/scripts/workflow.py" prepare --stage rnaseq \
  --project "$PWD" --study bm --date 20261019 \
  --metadata metadata.tsv --source rustfs/bucket/delivery/rawdata/ \
  --listing /tmp/reads.json --fasta /path/reference.fa --gtf /path/reference.gtf
python3 "$SKILL/scripts/workflow.py" inspect-config \
  --run-dir workflow/bm_rnaseq_20261019
python3 "$SKILL/scripts/workflow.py" submit \
  --run-dir workflow/bm_rnaseq_20261019
```

Use `--profiles site,apptainer --config /path/site.config` to reuse site settings;
otherwise the helper tests existing global settings before creating a minimal
Slurm fallback. Do not specify a fictional built-in `slurm` profile. Profiles must
exist in the resolved configuration. differentialabundance additionally needs its
`rnaseq` analysis profile (`--profiles rnaseq,site,apptainer`). Resource caps live
in `resources.config`, loaded before user configs; inspect effective values and
selectors. Pass an explicitly authorized higher cap with
`--max-memory-gb N --authorized-large-resources`.

Use `--java-home /path/to/compatible/jdk` only if necessary. `--clear-proxy`
removes proxy variables in the task process; keep proxies when needed for public
downloads and configure endpoint bypass according to the actual environment.

New stages resolve stable GitHub Releases and exact commits; `versions.json`
records the requirement from `nextflow.config`. Use `--pipeline-version TAG` when
the user explicitly chooses a release. Check that the installed Nextflow and Java
meet that requirement before execution. Release discovery failure is an error.

Before full analysis, run a small Slurm environment probe using a login shell:
check Java/Nextflow, shared directories, Apptainer, and Nextflow S3 metadata/small
object access. This verifies Nextflow's credentials, not just rc's credentials.
Check all GTF sequence names against FASTA/.fai on a compute node; the helper's
limited GTF scan is a quick input sanity check, not full reference validation.

## Differentialabundance

```bash
python3 "$SKILL/scripts/workflow.py" prepare --stage differentialabundance \
  --study bm --date 20261019 --metadata metadata.tsv --contrasts contrasts.csv \
  --upstream workflow/bm_rnaseq_20261019 --gtf /path/reference.gtf
python3 "$SKILL/scripts/workflow.py" submit \
  --run-dir workflow/bm_differentialabundance_20261019
```

The input is a separate biological metadata CSV, not a multi-lane FASTQ sheet.
The helper finds exactly one merged Salmon counts/length matrix, checks sample
columns, and records hashes. Supply `--matrix` and `--lengths` for external results
or when upstream contains several matrices. Inspect reference feature IDs,
confounders, replicate relationships and paired design before submitting.
`--params FILE.json` supplies reviewed additional pipeline parameters without
overriding input/output paths. Defaults are simple pairwise, subset-to-contrast
DESeq2 comparisons. GTF metadata columns are selected from available attributes.

After Nextflow succeeds, the driver initializes a local R environment, recovers
original Wald statistics from fitted DDS objects and draws volcano plots. Outputs
include `results/original_stats/enrichment_manifest.tsv`, `DEG_summary.tsv`, raw
statistics and `results/figures/`. If pipeline output naming changes in a new
release, inspect its output/schema and narrowly update the exporter; preserve the
completed pipeline and resume the export without rerunning upstream FASTQs.

## Enrichment and monitoring

Prepare annotation tables as described in [enrichment.md](enrichment.md), then:

```bash
python3 "$SKILL/scripts/workflow.py" prepare --stage enrich \
  --study bm --date 20261019 --metadata metadata.tsv \
  --upstream workflow/bm_differentialabundance_20261019 \
  --enrichment-manifest workflow/bm_differentialabundance_20261019/results/original_stats/enrichment_manifest.tsv \
  --annotation-config /path/runtime_annotation/annotation.json
python3 "$SKILL/scripts/workflow.py" submit --run-dir workflow/bm_DEG_enrich_20261019
python3 "$SKILL/scripts/workflow.py" status --run-dir workflow/bm_DEG_enrich_20261019
python3 "$SKILL/scripts/workflow.py" collect --run-dir workflow/bm_DEG_enrich_20261019
```

Enrichment is a separate Slurm R job; it does not need a Nextflow executor.
Each stage snapshots its helpers under `runtime/` for reproducibility. A stage's
small helpers and parameters can be reviewed without loading FASTQs. Inputs are
referenced in place; keep upstream results available.

`submit --resume` reuses the recorded commit and Nextflow work directory. It refuses
an active driver or more than two failed resumes. It never cancels a job. Compare
the actual failure cause before retrying; after a genuinely different corrected
failure, document it and deliberately reset the retry counter in stage.json.
R postprocessing can be rerun directly with its saved scripts; it has no Nextflow
cache. `collect` writes an artifact index and Chinese report scaffold: complete its
QC interpretation before handing results to the user.
