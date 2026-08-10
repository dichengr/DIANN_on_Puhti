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
FILE_LIST=$4

mapfile -t RAW_FILES < "$FILE_LIST"
RAW_PATH="${RAW_FILES[$SLURM_ARRAY_TASK_ID]}"

# DIA-NN 2.x dropped --reuse-quant. Reproduce that "skip if cached" behavior
# explicitly: if the .quant for this raw is already in QUANT_DIR_STEP1, exit
# cleanly and let Step 2 reuse it. Filename matches --quant-ori-names output.
BN=$(basename "$RAW_PATH")
QUANT_PATH="$QUANT_DIR_STEP1/${BN%.*}.quant"
if [ -f "$QUANT_PATH" ]; then
    echo "Reusing cached quant: $QUANT_PATH (skipping search for $BN)"
    exit 0
fi

module load apptainer
apptainer exec -B /scratch:/scratch "$CONTAINER_SIF" "$DIANN_BIN_PATH" \
 --f "$RAW_PATH" \
 --lib "$FUll_LIB_FILE" \
 --fasta "$FASTA_FILE" \
 --threads $SLURM_CPUS_PER_TASK \
 --temp "$QUANT_DIR_STEP1" \
 --quant-ori-names \
 --out "$TMPDIR/disposable_report" \
 $DIANN_PARAMS
