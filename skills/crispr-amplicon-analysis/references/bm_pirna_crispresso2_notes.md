# CRISPResso2 in `bm_pirna` — Session Notes

This is a compact reference from the T630 `bm_pirna` planning session. It is not a project progress log; it captures reusable checks and decisions for similar CRISPR amplicon workflows.

## Context

Project path:

```text
/home/gyk/project/bm_pirna
```

Detected CRISPResso2 environment:

```bash
/home/gyk/miniforge3/bin/mamba run -n crispresso2 CRISPResso --version
/home/gyk/miniforge3/bin/mamba run -n crispresso2 CRISPRessoBatch --version
```

Observed versions:

```text
CRISPResso 2.3.3
CRISPRessoBatch 2.3.3
```

## Amplicon / gRNA Orientation Example

Given amplicon length:

```text
426 bp
```

Biological gRNA:

```text
AATCTGCTTTGAGTACAAGA
```

Reverse complement:

```text
TCTTGTACTCAAAGCAGATT
```

The reverse complement matched the provided forward amplicon at 1-based positions 272-291.

Local context:

```text
TATTTGCTCTTGTTTTGTCATTTGAGCCCA[TCTTGTACTCAAAGCAGATT]TGTTCTTTACATCTTTATTTTGAATAGTGT
```

Reusable lesson: always search both guide and reverse-complement guide in the amplicon before running CRISPResso2. If CRISPResso2 fails to annotate the guide/cut site using the biological guide sequence, rerun with the amplicon-orientation reverse complement and document that choice in the notebook.

## Notebook/Script Pattern for This User

The user prefers CCDS notebooks to show the high-level analysis flow and configuration. If reusable logic is needed, create a module script following the project scaffold (`code_scaffold.py` or `code_scaffolding.py`) and call it from the notebook.

For this task shape, use:

```text
notebooks/bm_pirna_crispresso2_knockout.ipynb
bm_pirna/crispresso2_analysis.py
reports/crispresso2_knockout_<task_name>/
```

If the user says to execute the created notebook directly, do not create a separate executed notebook copy.

## Commit Scope Reminder

Default exclusions for CCDS CRISPResso2 analyses:

```text
reports/
data/
.env
.pixi/
.ruff_cache/
tmp/
workflow/ runtime outputs
```

Before staging/committing, ask which files/folders may be committed. `reports/` is a common accidental inclusion and should be excluded unless explicitly approved.
