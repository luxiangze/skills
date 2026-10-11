#!/usr/bin/env bash
# Lint a batch script for this cluster's required directives.
# Usage: check_sbatch.sh script [script...]

if [[ $# -lt 1 ]]; then
  echo "usage: check_sbatch.sh script [script...]" >&2
  exit 1
fi

has_token() {
  local list="$1" tok="$2" item
  IFS=',' read -ra items <<< "$list"
  for item in "${items[@]}"; do
    item="${item// /}"
    [[ "$item" == "$tok" ]] && return 0
  done
  return 1
}

check_one() {
  local file="$1"
  local errors=0
  local shebang partition="" cpus="" mem="" tim="" name="" output="" gres="" gpus=""
  local line rest words w i

  if [[ ! -f "$file" ]]; then
    echo "$file: not a file" >&2
    return 1
  fi

  shebang=$(head -n 1 "$file")
  if [[ "$shebang" != *bash* || "$shebang" != *-l* ]]; then
    echo "$file: shebang must be #!/bin/bash -l so module is available" >&2
    errors=1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == \#SBATCH* ]] || continue
    rest=${line#\#SBATCH}
    read -ra words <<< "$rest"
    i=0
    while [[ $i -lt ${#words[@]} ]]; do
      w=${words[$i]}
      case "$w" in
        --partition=*) partition=${w#--partition=} ;;
        -p|--partition) i=$((i + 1)); partition=${words[$i]} ;;
        --cpus-per-task=*) cpus=${w#--cpus-per-task=} ;;
        -c|--cpus-per-task) i=$((i + 1)); cpus=${words[$i]} ;;
        --mem=*|--mem-per-cpu=*) mem=1 ;;
        --mem|--mem-per-cpu) mem=1; i=$((i + 1)) ;;
        --time=*) tim=${w#--time=} ;;
        -t|--time) i=$((i + 1)); tim=${words[$i]} ;;
        --job-name=*) name=${w#--job-name=} ;;
        -J|--job-name) i=$((i + 1)); name=${words[$i]} ;;
        --output=*) output=${w#--output=} ;;
        -o|--output) i=$((i + 1)); output=${words[$i]} ;;
        --gres=*) gres=${w#--gres=} ;;
        --gres) i=$((i + 1)); gres=${words[$i]} ;;
        --gpus=*|--gpus-per-task=*|--gpus-per-node=*|--gpus-per-socket=*) gpus=1 ;;
        --gpus|--gpus-per-task|--gpus-per-node|--gpus-per-socket) gpus=1; i=$((i + 1)) ;;
      esac
      i=$((i + 1))
    done
  done < "$file"

  [[ -n "$partition" ]] || { echo "$file: missing --partition" >&2; errors=1; }
  [[ -n "$cpus" ]] || { echo "$file: missing --cpus-per-task" >&2; errors=1; }
  [[ -n "$mem" ]] || { echo "$file: missing --mem or --mem-per-cpu" >&2; errors=1; }
  [[ -n "$tim" ]] || { echo "$file: missing --time" >&2; errors=1; }
  [[ -n "$name" ]] || { echo "$file: missing --job-name" >&2; errors=1; }
  [[ -n "$output" ]] || { echo "$file: missing --output" >&2; errors=1; }

  if has_token "$partition" gpu && [[ "$gres" != *gpu* && -z "$gpus" ]]; then
    echo "$file: partition gpu requires --gres=gpu:N or --gpus=N; CPU-only jobs use compute or gpu-cpu" >&2
    errors=1
  fi
  if has_token "$partition" gpu-cpu && [[ "$gres" == *gpu* || -n "$gpus" ]]; then
    echo "$file: GPU request belongs on partition gpu, not gpu-cpu" >&2
    errors=1
  fi

  return "$errors"
}

status=0
for file in "$@"; do
  check_one "$file" || status=1
done
exit "$status"
