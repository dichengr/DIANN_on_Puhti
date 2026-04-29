#!/bin/bash
#SBATCH --job-name=diann_s2_libgen
#SBATCH --account=project_2000752
#SBATCH --partition=small
#SBATCH --time=1:00:00
#SBATCH --cpus-per-task=40
#SBATCH --mem=64G

source $1 # Load user config
QUANT_DIR_STEP1=$2
LIB_DIR=$3
FUll_LIB_FILE=$4

FILES_STRING=$(find "$DATA_DIR" -maxdepth 1 \( -name '*.d' -o -name '*.raw' \) -printf '--f "%p" ')
LIB_OUT="$LIB_DIR/project_lib.parquet"

module load apptainer
apptainer exec -B /scratch:/scratch "$CONTAINER_SIF" /diann-2.2.0/diann-linux \
 $FILES_STRING \
 --lib "$FUll_LIB_FILE" \
 --temp "$QUANT_DIR_STEP1" \
 --fasta "$FASTA_FILE" \
 --threads $SLURM_CPUS_PER_TASK \
 --out-lib "$LIB_OUT" \
 --gen-spec-lib \
 --quant-ori-names \
 --use-quant \
 --matrices \
 --out "$TMPDIR/disposable_report" \
 $DIANN_PARAMS