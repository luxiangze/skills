# CCDS Git Scope and Inspection Notes

Use this reference when inspecting or preparing commits in the user's CCDS research projects.

## Durable workflow preference

- Initialize Git immediately after the CCDS scaffold is generated.
- Do not use blanket staging by default.
- Before staging or committing, ask the user which folders/files are allowed and which must be excluded.
- If committing is requested, stage only the explicitly approved paths.
- If the user approves the whole tree, still check ignored/sensitive directories before `git add .`.

## Common CCDS folders to treat carefully

Default exclude unless explicitly approved:

- `reports/` — commonly overlooked result/figure/report output directory.
- `data/` — raw/interim/processed data can be huge or private.
- `workflow/*/work/`, `workflow/*/results/`, `.nextflow/`, `.nextflow.log*` — workflow runtime artifacts.
- `.env`, `.pixi/`, `.ruff_cache/`, `tmp/`, notebook checkpoints.

Usually acceptable candidates after review:

- package source directory, e.g. `<module_name>/`
- `notebooks/` if notebooks have no heavy outputs or embedded data
- `README.md`, `docs/`, `references/` metadata files without credentials
- `pixi.toml`, `pixi.lock`, `pyproject.toml`
- workflow source files or parameter files, if not runtime outputs

## Pre-commit inspection pattern

Run from project root:

```bash
git status --short --untracked-files=all
git status --ignored --short -- reports data workflow .env .pixi .ruff_cache tmp
git check-ignore -v .env data reports .pixi tmp 2>/dev/null || true
git diff --stat
git diff --name-status
```

For notebooks, check whether they contain execution output before suggesting they are safe to commit:

```bash
python - <<'PY'
from pathlib import Path
import json, subprocess
for p in sorted(Path('notebooks').glob('*.ipynb')):
    data = json.loads(p.read_text(errors='replace'))
    cells = data.get('cells', [])
    outputs = sum(len(c.get('outputs', [])) for c in cells if c.get('cell_type') == 'code')
    executed = sum(1 for c in cells if c.get('cell_type') == 'code' and c.get('execution_count') is not None)
    status = subprocess.run(['git', 'status', '--short', '--', str(p)], text=True, stdout=subprocess.PIPE).stdout.strip()
    print(f'{p}: {status or "clean"}; executed_code_cells={executed}; outputs={outputs}')
PY
```

## Commit workflow after user approves scope

```bash
git status --short --untracked-files=all
git add -- <approved-path-1> <approved-path-2>
git diff --cached --name-status
git diff --cached --stat
git commit -m "<user-approved message>"
git status --short
```

Never stage `reports/` in CCDS projects unless the user explicitly says that `reports/` is allowed for that specific commit.
