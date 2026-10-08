#!/usr/bin/env bash
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_root="${1:-$PWD}"
project_root="$(cd "$project_root" && pwd)"
cd "$project_root"

if [[ ! -f pixi.toml ]]; then
  cp "$skill_dir/assets/pixi.toml" pixi.toml
  cp "$skill_dir/assets/pixi.lock" pixi.lock
elif ! grep -q '^\[feature\.r\.dependencies\]' pixi.toml; then
  echo "Existing pixi.toml has no [feature.r.dependencies] section; merge the skill's R feature before continuing." >&2
  exit 2
fi

mkdir -p data/external
cp "$skill_dir/assets/org.Bmori.eg.db_0.2.tar.gz" data/external/org.Bmori.eg.db_0.2.tar.gz
if [[ ! -f renv.lock ]]; then cp "$skill_dir/assets/renv.lock" renv.lock; fi

pixi install -e r
if [[ ! -f renv/activate.R ]]; then
  pixi run -e r Rscript -e 'renv::init(project=getwd(), bare=TRUE, restart=FALSE)'
fi
pixi run -e r Rscript -e 'renv::restore(project=getwd(), packages=c("clusterProfiler", "AnnotationDbi", "GO.db", "ggplot2", "enrichplot"), prompt=FALSE)'
pixi run -e r Rscript -e 'renv::install("data/external/org.Bmori.eg.db_0.2.tar.gz", project=getwd(), prompt=FALSE); renv::snapshot(project=getwd(), type="implicit", prompt=FALSE); s <- renv::status(project=getwd()); if (!isTRUE(s$synchronized)) { print(s); quit(status=1) }; message("renv status synchronized")'
pixi run -e r Rscript -e 'stopifnot(!any(grepl("/bm_pirna/", .libPaths()))); stopifnot(requireNamespace("org.Bmori.eg.db", quietly=TRUE)); cat("R:", R.version.string, "\nlibPaths:\n"); print(.libPaths()); cat("renv library:", renv::paths$library(), "\nOrgDb:", find.package("org.Bmori.eg.db"), "\n")'
