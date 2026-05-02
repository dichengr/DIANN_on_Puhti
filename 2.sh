#!/bin/bash
#SBATCH --job-name=diann_s2_libgen
#SBATCH --account=project_2000752
#SBATCH --partition=small
#SBATCH --time=1:00:00
#SBATCH --cpus-per-task=40
#SBATCH --mem=64G

set -eo pipefail

CONFIG_FILE=$1
source "$CONFIG_FILE" # Load user config
QUANT_DIR_STEP1=$2
LIB_DIR=$3
FUll_LIB_FILE=$4

FILES_STRING=$(find "$DATA_DIR" -maxdepth 1 \( -name '*.d' -o -name '*.raw' \) -printf '--f "%p" ')
LIB_OUT="$LIB_DIR/project_lib.parquet"

module load apptainer
apptainer exec -B /scratch:/scratch "$CONTAINER_SIF" "$DIANN_BIN_PATH" \
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

# Submit Step 3 + Step 4 from here so we don't blow past AssocMaxSubmitJobLimit
# (Step 1's array slots are freed by the time Step 2 runs, leaving room for Step 3's array).
SCRIPT_DIR="/scratch/project_2000752/DIA-NN/02_scripts"
LOG_DIR="$OUTPUT_DIR/logs"
QUANT_DIR_3="$OUTPUT_DIR/step3_quant"
REPORT_DIR="$OUTPUT_DIR/step4_report"
NEW_LIB_FILE="$LIB_OUT"

FILE_COUNT=$(find "$DATA_DIR" -maxdepth 1 \( -name '*.d' -o -name '*.raw' \) | wc -l)
ARRAY_MAX=$((FILE_COUNT - 1))

STEP3_ID=$(sbatch --parsable \
    --dependency=afterok:$SLURM_JOB_ID \
    --array=0-$ARRAY_MAX \
    --output=$LOG_DIR/%x-%A_%a.out --error=$LOG_DIR/%x-%A_%a.err \
    "$SCRIPT_DIR/3.sh" "$CONFIG_FILE" "$QUANT_DIR_3" "$NEW_LIB_FILE")
echo "Step 3 (Search 2) submitted from Step 2. Job ID: $STEP3_ID"

STEP4_ID=$(sbatch --parsable \
    --dependency=afterok:$STEP3_ID \
    --output=$LOG_DIR/%x-%j.out --error=$LOG_DIR/%x-%j.err \
    "$SCRIPT_DIR/4.sh" "$CONFIG_FILE" "$QUANT_DIR_3" "$NEW_LIB_FILE" "$REPORT_DIR")
echo "Step 4 (Final Report) submitted from Step 2. Job ID: $STEP4_ID"
