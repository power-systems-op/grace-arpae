#!/bin/bash
#SBATCH --error=slurm.err
#SBATCH --mem=40G
module load CPLEX/12.10
module load GCC/9.3.0
export PATH=/hpc/home/mmh54/julia-1.5.2/:$PATH
srun julia measure_performance.jl
