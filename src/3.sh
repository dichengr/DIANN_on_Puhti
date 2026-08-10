#!/bin/bash
#SBATCH --job-name=diann_s3_research
#SBATCH --account=project_2000752
#SBATCH --partition=small
#SBATCH --time=1:00:00
#SBATCH --cpus-per-task=40
#SBATCH --mem=128G

source $1 # Load user config
QUANT_DIR_STEP3=$2
NEW_LIB_FILE=$3
FILE_LIST=$4

mapfile -t RAW_FILES < "$FILE_LIST"
RAW_PATH="${RAW_FILES[$SLURM_ARRAY_TASK_ID]}"

# DIA-NN 2.x dropped --reuse-quant. Reproduce "skip if cached" behavior: if
# this raw already has a Step-3 .quant aligned to the current project library,
# we're done. Step 2 wipes step3_quant when the lib is rebuilt, so a stale
# .quant won't be reused.
BN=$(basename "$RAW_PATH")
QUANT_PATH="$QUANT_DIR_STEP3/${BN%.*}.quant"
if [ -f "$QUANT_PATH" ]; then
    echo "Reusing cached quant: $QUANT_PATH (skipping search for $BN)"
    exit 0
fi

module load apptainer
apptainer exec -B /scratch:/scratch "$CONTAINER_SIF" "$DIANN_BIN_PATH" \
 --f "$RAW_PATH" \
 --lib "$NEW_LIB_FILE" \
 --fasta "$FASTA_FILE" \
 --threads $SLURM_CPUS_PER_TASK \
 --temp "$QUANT_DIR_STEP3" \
 --quant-ori-names \
 --out "$TMPDIR/disposable_report" \
 $DIANN_PARAMS
