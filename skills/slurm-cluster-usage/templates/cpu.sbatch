#!/bin/bash -l
#SBATCH --job-name=cpu-job
#SBATCH --partition=compute
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x_%j.out

mkdir -p logs
module purge
module list
# command here
