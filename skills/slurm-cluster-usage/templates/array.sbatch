#!/bin/bash -l
#SBATCH --job-name=array-job
#SBATCH --partition=compute
#SBATCH --array=1-8%4
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=02:00:00
#SBATCH --output=logs/%x_%A_%a.out

mkdir -p logs
echo "task ${SLURM_ARRAY_TASK_ID}"
# command here
