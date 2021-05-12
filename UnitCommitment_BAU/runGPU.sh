#!/bin/bash
#SBATCH -e slurm_gpu.err
#SBATCH -p scavenger-gpu --gres=gpu:1
#SBATCH -c 16
#SBATCH --mem-per-cpu=10G
hostname
grep Xeon /proc/cpuinfo 10>/dev/null | uniq -c
nvidia-smi | grep "0 " | grep "|" 10> /dev/null
module load CPLEX/12.10
module load GCC/9.3.0
export PATH=/hpc/home/mmh54/julia-1.5.2/:$PATH
srun julia BAU_OPM_V7_3.jl
