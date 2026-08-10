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
FILE_LIST=$5

mapfile -t RAW_FILES < "$FILE_LIST"
F_ARGS=()
for r in "${RAW_FILES[@]}"; do
    F_ARGS+=( --f "$r" )
done
LIB_OUT="$LIB_DIR/project_lib.parquet"

module load apptainer || true
apptainer exec -B /scratch:/scratch "$CONTAINER_SIF" "$DIANN_BIN_PATH" \
 "${F_ARGS[@]}" \
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

# If the raw-file set has changed since the previous lib build, the old
# step3_quant/.quant files were aligned to a now-stale library. Wipe them so
# step 3 re-quantifies all samples against the new project_lib.parquet.
LIB_INPUTS_RECORD="$LIB_DIR/.lib_inputs"
if ! cmp -s "$FILE_LIST" "$LIB_INPUTS_RECORD" 2>/dev/null; then
    echo "Raw file set changed since previous lib build — wiping $OUTPUT_DIR/step3_quant"
    rm -f "$OUTPUT_DIR/step3_quant"/*.quant
    cp "$FILE_LIST" "$LIB_INPUTS_RECORD"
fi

# Submit Step 3 + Step 4 from here so we don't blow past AssocMaxSubmitJobLimit
# (Step 1's array slots are freed by the time Step 2 runs, leaving room for Step 3's array).
# Step 3 itself is chunked the same way Step 1 is — see submit_step3_chunk.sh.
SCRIPT_DIR="/scratch/project_2000752/DIA-NN/02_scripts"
LOG_DIR="$OUTPUT_DIR/logs"
QUANT_DIR_3="$OUTPUT_DIR/step3_quant"
REPORT_DIR="$OUTPUT_DIR/step4_report"
NEW_LIB_FILE="$LIB_OUT"

FILE_COUNT=${#RAW_FILES[@]}
ARRAY_MAX=$((FILE_COUNT - 1))

CHUNK_SIZE="${CHUNK_SIZE:-350}"
NCHUNKS_3=$(( (FILE_COUNT + CHUNK_SIZE - 1) / CHUNK_SIZE ))
CHUNK_IDS_FILE_3="$LOG_DIR/.step3_chunk_ids"
: > "$CHUNK_IDS_FILE_3"
CHUNKS_TSV="$LOG_DIR/chunks.tsv"

END0=$((CHUNK_SIZE - 1))
if [ "$END0" -gt "$ARRAY_MAX" ]; then END0=$ARRAY_MAX; fi

STEP3_C0_ID=$(sbatch --parsable \
    --dependency=afterok:$SLURM_JOB_ID \
    --array=0-$END0 \
    --output=$LOG_DIR/%x-%A_%a.out --error=$LOG_DIR/%x-%A_%a.err \
    "$SCRIPT_DIR/3.sh" "$CONFIG_FILE" "$QUANT_DIR_3" "$NEW_LIB_FILE" "$FILE_LIST")
if [ -z "$STEP3_C0_ID" ]; then
    echo "Error: sbatch did not return a Job ID for Step 3 chunk 0. Aborting."
    exit 1
fi
echo "Step 3 chunk 0/$((NCHUNKS_3-1)) (array 0-$END0) submitted from Step 2. Job ID: $STEP3_C0_ID"
echo "$STEP3_C0_ID" >> "$CHUNK_IDS_FILE_3"
printf 'step3\t0\t0-%d\t%s\t%s\n' "$END0" "$STEP3_C0_ID" "$(date -Iseconds)" >> "$CHUNKS_TSV"

if [ "$NCHUNKS_3" -eq 1 ]; then
    STEP4_ID=$(sbatch --parsable \
        --dependency=afterok:$STEP3_C0_ID \
        --output=$LOG_DIR/%x-%j.out --error=$LOG_DIR/%x-%j.err \
        "$SCRIPT_DIR/4.sh" "$CONFIG_FILE" "$QUANT_DIR_3" "$NEW_LIB_FILE" "$REPORT_DIR" "$FILE_LIST")
    echo "Step 4 (Final Report) submitted from Step 2. Job ID: $STEP4_ID"
    printf 'step4\t-\t-\t%s\t%s\n' "$STEP4_ID" "$(date -Iseconds)" >> "$CHUNKS_TSV"
else
    NEXT_START=$CHUNK_SIZE
    NEXT_END=$((CHUNK_SIZE * 2 - 1))
    if [ "$NEXT_END" -gt "$ARRAY_MAX" ]; then NEXT_END=$ARRAY_MAX; fi
    SHIM_ID=$(sbatch --parsable --dependency=afterok:$STEP3_C0_ID \
        --output=$LOG_DIR/%x-%j.out --error=$LOG_DIR/%x-%j.err \
        "$SCRIPT_DIR/submit_step3_chunk.sh" \
        "1" "$NCHUNKS_3" "$NEXT_START" "$NEXT_END" "$CONFIG_FILE")
    echo "Step 3 chunks 1-$((NCHUNKS_3-1)) and Step 4 will be queued by shim jobs. Shim 1 ID: $SHIM_ID"
fi
