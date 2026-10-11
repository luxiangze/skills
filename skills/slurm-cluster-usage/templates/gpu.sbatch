#!/bin/bash -l
#SBATCH --job-name=gpu-job
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=08:00:00
#SBATCH --output=logs/%x_%j.out

mkdir -p logs
module purge
module list
# command here
