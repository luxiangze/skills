#!/bin/bash -l
# An isolated environment per stage; shared renv cache is reused, never another project's library.
set -Eeuo pipefail
skill_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stage_r_env="${1:?Usage: setup_r.sh ENV_DIR [--deseq2]}"
mkdir -p "$stage_r_env"
cd "$stage_r_env"
if [[ ! -f pixi.toml ]]; then
  cp "$skill_root/assets/pixi.toml" pixi.toml
  cp "$skill_root/assets/pixi.lock" pixi.lock
  cp "$skill_root/assets/renv.lock" renv.lock
fi
export RENV_CONFIG_SANDBOX_ENABLED=FALSE
pixi install -e r
if [[ ! -f renv/activate.R ]]; then
  pixi run -e r Rscript -e 'renv::init(project=getwd(), bare=TRUE, restart=FALSE)'
fi
# Keep this private Pixi R library visible, including packages supplied by r-pak.
# Persist the setting for later R processes, preserving other .Renviron entries.
pixi run -e r Rscript -e 'p <- ".Renviron"; x <- if (file.exists(p)) readLines(p, warn=FALSE) else character(); writeLines(c(x[!grepl("^RENV_CONFIG_SANDBOX_ENABLED=", x)], "RENV_CONFIG_SANDBOX_ENABLED=FALSE"), p); renv::settings$snapshot.type("all"); renv::restore(project=getwd(), prompt=FALSE)'
if [[ "${2:-}" == --deseq2 ]]; then
  pixi run -e r Rscript -e 'if (!requireNamespace("DESeq2", quietly=TRUE)) renv::install("bioc::DESeq2", prompt=FALSE); renv::snapshot(type="all", prompt=FALSE)'
fi
pixi run -e r Rscript -e 's <- renv::status(); if (!isTRUE(s$synchronized)) stop("renv is not synchronized"); cat(R.version.string, "\n"); print(.libPaths())'
