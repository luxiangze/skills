#!/bin/bash -l
#SBATCH --job-name=apptainer-gpu
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x_%j.out

mkdir -p logs
export APPTAINER_TMPDIR=/tmp
export APPTAINER_CACHEDIR="/tmp/apptainer-cache-${USER}"
apptainer exec --nv /path/to/image.sif python train.py
