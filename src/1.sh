#!/bin/bash
#SBATCH --job-name=diann_s1_search
#SBATCH --account=project_2000752
#SBATCH --partition=small
#SBATCH --time=4:00:00
#SBATCH --cpus-per-task=40
#SBATCH --mem=300G

source $1 # Load user config
QUANT_DIR_STEP1=$2
FUll_LIB_FILE=$3

shopt -s nullglob
RAW_FILES=("$DATA_DIR"/*.d "$DATA_DIR"/*.raw)
RAW_PATH="${RAW_FILES[$SLURM_ARRAY_TASK_ID]}"

module load apptainer
apptainer exec -B /scratch:/scratch "$CONTAINER_SIF" /diann-2.2.0/diann-linux \
 --f "$RAW_PATH" \
 --lib "$FUll_LIB_FILE" \
 --fasta "$FASTA_FILE" \
 --threads $SLURM_CPUS_PER_TASK \
 --temp "$QUANT_DIR_STEP1" \
 --quant-ori-names \
 --out "$TMPDIR/disposable_report" \
 $DIANN_PARAMS
