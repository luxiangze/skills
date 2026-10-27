---
name: ccds-research-project-init
description: Use when initializing a new research/data-science project for the user with CCDS on R940xa/T630. Uses the user's custom luxiangze Cookiecutter Data Science template, English-only project metadata, Pixi, and post-creation verification.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [ccds, cookiecutter, research-project, pixi, ssh, reproducibility]
    related_skills: [ssh-remote-server-access]
---

# CCDS Research Project Initialization

## Overview

Use this skill when the user asks to create or re-create a research/data-science project with CCDS, especially on `T630` or `R940xa`.

The user's preferred template is not the upstream DrivenData template. Use the customized repository:

```text
https://github.com/luxiangze/cookiecutter-data-science
```

Project-facing metadata, documentation, code comments, docstrings, notebooks, analysis notes, and figure text should be written in English by default so the project can feed directly into manuscript preparation.

## When to Use

Use this skill when the user says things like:

- Create a new CCDS project.
- Initialize a research project folder.
- Re-create a project scaffold on T630 or R940xa.
- Set up a project for sequencing/genomics/protein/design analysis.
- Make project information, code, and comments English-only.

Do not use this for generic Python packages unrelated to the user's research project layout.

## Server Paths

- T630 project parent: `/home/gyk/project`
- R940xa project parent: `/home/gyk/projects`
- T630 CCDS path: `/home/gyk/.local/bin/ccds`
- T630 Pixi path: `/home/gyk/.pixi/bin/pixi`

Use absolute paths in non-interactive SSH commands because batch SSH `PATH` may not include `~/.local/bin` or `~/.pixi/bin`.

## Important CCDS Quirk

`ccds` from `cookiecutter-data-science 2.3.0` defaults `--checkout` to `v2.3.0`. The user's customized repository may not have that tag. Therefore the direct command often needs an explicit branch:

```bash
/home/gyk/.local/bin/ccds \
  --checkout master \
  --no-input \
  --output-dir /home/gyk/project \
  --accept-hooks yes \
  https://github.com/luxiangze/cookiecutter-data-science \
  project_name=<project_name> \
  repo_name=<project_name> \
  module_name=<project_name> \
  author_name='Guo Yongkang' \
  description='<English project description>' \
  python_version_number=3.11 \
  environment_manager=pixi \
  dependency_file=pixi.toml \
  pydata_packages=basic \
  testing_framework=pytest \
  linting_and_formatting=ruff \
  open_source_license='No license file' \
  docs=mkdocs \
  include_code_scaffold=Yes
```

If GitHub access from the server times out, clone the template once and generate from the local clone while recording the remote and commit:

```bash
git clone --depth 1 https://github.com/luxiangze/cookiecutter-data-science.git /tmp/luxiangze-cookiecutter-data-science
cd /home/gyk/project
/home/gyk/.local/bin/ccds \
  --no-input \
  --output-dir /home/gyk/project \
  --accept-hooks yes \
  /tmp/luxiangze-cookiecutter-data-science \
  project_name=<project_name> \
  repo_name=<project_name> \
  module_name=<project_name> \
  author_name='Guo Yongkang' \
  description='<English project description>' \
  python_version_number=3.11 \
  environment_manager=pixi \
  dependency_file=pixi.toml \
  pydata_packages=basic \
  testing_framework=pytest \
  linting_and_formatting=ruff \
  open_source_license='No license file' \
  docs=mkdocs \
  include_code_scaffold=Yes
```

## Re-Creation Safety

Only delete an existing project directory when the user explicitly asks to delete or re-create it. Before deletion, verify the exact target path and show the size in tool output:

```bash
du -sh /home/gyk/project/<project_name>
rm -rf -- /home/gyk/project/<project_name>
```

Do not delete parent directories such as `/home/gyk/project` or `/home/gyk/projects`.

## Git Version Control

Detailed commit-scope and inspection checklist: `references/git-scope-and-inspection.md`.

Immediately after the CCDS scaffold is generated, initialize Git in the project root before making post-creation edits:

```bash
cd /home/gyk/project/<project_name>
git init
git status --short
```

Keep all post-creation documentation, code, test, and Pixi compatibility edits visible under Git status.

After lint, tests, and documentation build pass, report the final working tree status:

```bash
git status --short
```

Before staging or committing, ask the user which folders/files are allowed to be committed and which folders/files must be excluded. Only stage the explicitly allowed paths, and never use blanket `git add .` unless the user explicitly approves the entire working tree.

When inspecting an existing CCDS project before commit, check both visible and ignored state:

```bash
git status --short --untracked-files=all
git status --ignored --short -- reports data workflow .env .pixi .ruff_cache tmp
git diff --stat
git diff --name-status
```

For notebooks, check whether code cells have execution counts or outputs before treating them as commit candidates.

For CCDS projects, proactively remind the user that `reports/` is a commonly overlooked folder that should not be staged or committed unless the user explicitly approves it for that project.

Recommended commit workflow after the user defines allowed/excluded scope:

```bash
git status --short
git add -- <user-approved-path-1> <user-approved-path-2>
git diff --cached --name-status
git commit -m "<user-approved commit message>"
git status --short
```

Never add credentials, access keys, tokens, raw private data, or other secrets to the repository.

## Post-Creation English Project Notes

After generation, add or update English documentation:

- `README.md`: purpose, data source, project rules, environment commands.
- `docs/docs/project-design.md`: scientific scope, template source, analysis architecture, decision record.
- `docs/docs/coding-and-documentation-standards.md`: English-only code/comment/notebook/figure policy.
- `docs/docs/analysis-log.md`: chronological design and analysis decisions.
- `references/data-sources.md`: data source registry without credentials.
- `lineage_tracing/data_sources.py`: non-secret metadata for data locations.
- `tests/test_data.py`: non-failing metadata/path tests replacing template placeholder tests.

Never store credentials, access keys, tokens, or secrets in the project repository.

## Notebook-Orchestrated Analysis Convention

For this user's research projects, notebooks should primarily show the high-level analysis logic and configuration. Do not put substantial analysis code inside notebooks. Put reusable executable code in the CCDS module folder (for example, `<module_name>/crispresso_analysis.py`) following the style of `<module_name>/code_scaffold.py`, then call those module scripts from notebooks with minimal command cells.

Recommended notebook pattern:

- Markdown cells: scientific goal, dataset, parameters, expected outputs.
- Small configuration cell: paths and command names only.
- Execution cells: `run_cmd(...)` calls to `pixi run python -m <module_name>.<script>`.
- Result cells: compact table/figure display only; heavy parsing remains in module scripts.

## Pixi Compatibility

If generated `pixi.toml` starts with deprecated `[project]`, replace it with `[workspace]` before running checks:

```text
[workspace]
name = "<project_name>"
description = "<English project description>"
```

## Verification Checklist

Run these from the project root on T630:

```bash
/home/gyk/.pixi/bin/pixi run ruff check <module_name> tests
/home/gyk/.pixi/bin/pixi run pytest -q
/home/gyk/.pixi/bin/pixi run mkdocs build --config-file docs/mkdocs.yml --site-dir /tmp/<project_name>_mkdocs_site --strict
```

A project initialization is not complete until lint, tests, and documentation build pass with real tool output.

## Reporting Back

Report:

- Final project path.
- Template remote, branch, and commit if available.
- Whether direct URL generation succeeded or local-clone fallback was used.
- Files added or edited for English project policy.
- Exact verification outputs.
