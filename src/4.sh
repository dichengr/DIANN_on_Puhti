#!/bin/bash
#SBATCH --job-name=diann_s4_report
#SBATCH --account=project_2000752
#SBATCH --partition=small
#SBATCH --time=1:00:00
#SBATCH --cpus-per-task=40
#SBATCH --mem=64G

source $1 # Load user config
QUANT_DIR_STEP3=$2
NEW_LIB_FILE=$3
REPORT_DIR=$4
FILE_LIST=$5
REPORT_OUT="$REPORT_DIR/final_report_$(date +%Y%m%d_%H%M%S)"

mapfile -t RAW_FILES < "$FILE_LIST"
F_ARGS=()
for r in "${RAW_FILES[@]}"; do
    F_ARGS+=( --f "$r" )
done

module load apptainer
apptainer exec -B /scratch:/scratch "$CONTAINER_SIF" "$DIANN_BIN_PATH" \
 "${F_ARGS[@]}" \
 --lib "$NEW_LIB_FILE" \
 --temp "$QUANT_DIR_STEP3" \
 --fasta "$FASTA_FILE" \
 --threads $SLURM_CPUS_PER_TASK \
 --out "$REPORT_OUT.tsv" \
 --quant-ori-names \
 --use-quant \
 --matrices \
 $DIANN_PARAMS
