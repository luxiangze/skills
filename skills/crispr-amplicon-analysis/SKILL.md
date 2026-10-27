---
name: crispr-amplicon-analysis
description: Plan and run CRISPR/Cas9 amplicon editing analysis, especially CRISPResso2 workflows inside CCDS research projects.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [crispr, cas9, amplicon-seq, crispresso2, genome-editing, ccds, notebooks]
    related_skills: [ccds-research-project-init, ssh-remote-server-access, plan]
---

# CRISPR Amplicon Analysis

## When to Use

Use this skill when the user wants to analyze CRISPR/Cas9 editing, knockout amplicons, indels, guide-target outcomes, or CRISPResso2 results in a research project.

Typical prompts:

- Analyze CRISPR/Cas9 knockout status for samples.
- Run CRISPResso2 on amplicon sequencing reads.
- Compare editing rates for two or more samples sharing a gRNA.
- Create a notebook/script for amplicon editing analysis in a CCDS project.

## Core Scientific Judgment

Start with the biological/statistical interpretation before implementation.

- CRISPResso2 is appropriate for targeted amplicon sequencing reads covering the edited locus.
- Without coding-frame/exon annotation, report **editing frequency**, **indel frequency**, and **modification profiles**, not definitive protein-level **knockout frequency**.
- If the user wants true knockout interpretation, ask for or derive CDS/frame/exon context and define frameshift/in-frame criteria explicitly.
- Validate that the provided gRNA sequence occurs in the amplicon, including reverse complement. Record orientation in the notebook/report.
- For SpCas9, check for the expected PAM orientation around the guide match. Do not assume the user-provided guide is in the same orientation as the amplicon.

## Plan-First Mode

If the user asks for an execution plan before running, use the `plan` skill and do **not** modify the project until approval.

A good plan must include:

- Sample FASTQ paths needed, including single-end vs paired-end.
- Amplicon length and guide/reverse-complement match coordinates.
- Proposed notebook path.
- Proposed script path if reusable logic is needed.
- CRISPResso2 command template.
- Output directory, usually under ignored `reports/`.
- Git commit-scope warnings: do not stage `reports/`, `data/`, `.env`, `.pixi/`, runtime workflow outputs unless explicitly approved.

## CCDS Project Convention

For the user's CCDS research projects:

- Notebook should show analysis logic, sample configuration, and compact result display.
- Do not put substantial command-building, parsing, or validation logic in notebook cells if it is reusable.
- Put reusable code in the project module, following the local scaffold (`code_scaffold.py` or `code_scaffolding.py`).
- If the user requests one executable notebook, execute that notebook in place; do not create a separate executed copy unless requested.

Suggested file layout:

```text
notebooks/<project>_crispresso2_knockout.ipynb
<module_name>/crispresso2_analysis.py
reports/crispresso2_knockout_<task_name>/
```

`reports/` is the correct place for CRISPResso2 HTML/output artifacts, but it should normally remain ignored and uncommitted.

## Preflight Checklist

1. Identify exact samples:

```text
sample_name
fastq_r1
fastq_r2  # optional; empty for single-end
```

2. Validate target sequence:

- uppercase and remove whitespace
- amplicon length
- find guide exact match
- find guide reverse complement exact match
- report 1-based coordinates and local context

3. Probe CRISPResso2 without assuming PATH:

```bash
/home/gyk/miniforge3/bin/mamba run -n crispresso2 CRISPResso --version
/home/gyk/miniforge3/bin/mamba run -n crispresso2 CRISPRessoBatch --version
```

4. Check Git state and ignored outputs before editing:

```bash
git status --short --untracked-files=all
git status --ignored --short -- reports data workflow .env .pixi .ruff_cache tmp
```

## CRISPResso2 Command Template

Single-end:

```bash
/home/gyk/miniforge3/bin/mamba run -n crispresso2 CRISPResso \
  --fastq_r1 <sample.fastq.gz> \
  --amplicon_seq '<amplicon_seq>' \
  --guide_seq <guide_seq> \
  --name <sample_name> \
  --output_folder reports/crispresso2_knockout_<task_name> \
  --n_processes 8 \
  --plot_window_size 30
```

Paired-end:

```bash
/home/gyk/miniforge3/bin/mamba run -n crispresso2 CRISPResso \
  --fastq_r1 <sample_R1.fastq.gz> \
  --fastq_r2 <sample_R2.fastq.gz> \
  --amplicon_seq '<amplicon_seq>' \
  --guide_seq <guide_seq> \
  --name <sample_name> \
  --output_folder reports/crispresso2_knockout_<task_name> \
  --n_processes 8 \
  --plot_window_size 30
```

If CRISPResso2 does not annotate the guide/cut site correctly and the guide was only found as reverse-complement in the amplicon, rerun with the reverse-complement guide and document why.

## Notebook Execution

If the user asks to execute the notebook itself, prefer in-place execution with `nbclient`/`nbformat` when available. If missing, ask before adding dependencies to Pixi.

Do not silently create a second executed notebook when the user explicitly says to execute the created notebook directly.

## Validation

After running:

- Verify CRISPResso2 report HTML/output exists for each sample.
- Inspect logs for fatal errors.
- Parse or summarize quantification outputs for each sample.
- Report editing/indel metrics with sample names and output paths.
- Run project lint/tests if code was added, but distinguish pre-existing lint failures from new issues.

## References

- `references/bm_pirna_crispresso2_notes.md`: concrete session notes for a T630 `bm_pirna` CRISPResso2 planning case, including guide reverse-complement matching and commit-scope reminders.

## Pitfalls

- Do not call CRISPResso2 output “knockout rate” unless coding-frame criteria were defined.
- Do not guess sample FASTQ identity from filenames when multiple candidates exist; ask for confirmation.
- Do not commit `reports/` outputs by default.
- Do not mix unrelated dirty notebook changes into this task’s commit scope.
- For MAFFT alignment of CRISPResso2 deletion alleles against an amplicon reference, a regular MSA can inflate alignment length badly in gap-rich/repetitive regions. Also generate a reference-anchored alignment with `mafft --addfragments <deletion_sequences.fasta> --keeplength <reference_amplicon.fasta>` so the reference coordinate length is preserved.
