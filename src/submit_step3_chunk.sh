#!/bin/bash
#SBATCH --job-name=diann_s3_chunk_submit
#SBATCH --account=project_2000752
#SBATCH --partition=small
#SBATCH --time=00:05:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G

# Mirror of submit_step1_chunk.sh but for Step 3 (final quant).
# Final shim submits Step 4 with afterok on every Step 3 chunk array.

set -eo pipefail

CHUNK_IDX=$1
TOTAL_CHUNKS=$2
START=$3
END=$4
CONFIG_FILE=$5

source "$CONFIG_FILE"
CHUNK_SIZE="${CHUNK_SIZE:-350}"

LOG_DIR="$OUTPUT_DIR/logs"
QUANT_DIR_3="$OUTPUT_DIR/step3_quant"
LIB_DIR="$OUTPUT_DIR/step2_lib"
REPORT_DIR="$OUTPUT_DIR/step4_report"
FILE_LIST="$OUTPUT_DIR/file_list.txt"
NEW_LIB_FILE="$LIB_DIR/project_lib.parquet"
SCRIPT_DIR="/scratch/project_2000752/DIA-NN/02_scripts"

CHUNK_IDS_FILE="$LOG_DIR/.step3_chunk_ids"
CHUNKS_TSV="$LOG_DIR/chunks.tsv"

MY_ID=$(sbatch --parsable \
    --array=${START}-${END} \
    --output=$LOG_DIR/%x-%A_%a.out --error=$LOG_DIR/%x-%A_%a.err \
    "$SCRIPT_DIR/3.sh" "$CONFIG_FILE" "$QUANT_DIR_3" "$NEW_LIB_FILE" "$FILE_LIST")
if [ -z "$MY_ID" ]; then
    echo "submit_step3_chunk[$CHUNK_IDX]: sbatch returned empty Job ID for array $START-$END. Aborting chain."
    exit 1
fi
echo "submit_step3_chunk[$CHUNK_IDX/$((TOTAL_CHUNKS-1))]: Step 3 array $START-$END submitted as $MY_ID"

echo "$MY_ID" >> "$CHUNK_IDS_FILE"
printf 'step3\t%d\t%d-%d\t%s\t%s\n' "$CHUNK_IDX" "$START" "$END" "$MY_ID" "$(date -Iseconds)" >> "$CHUNKS_TSV"

NEXT_IDX=$((CHUNK_IDX + 1))
if [ "$NEXT_IDX" -lt "$TOTAL_CHUNKS" ]; then
    FILE_COUNT=$(wc -l < "$FILE_LIST")
    LAST_INDEX=$((FILE_COUNT - 1))
    NEXT_START=$((NEXT_IDX * CHUNK_SIZE))
    NEXT_END=$((NEXT_START + CHUNK_SIZE - 1))
    if [ "$NEXT_END" -gt "$LAST_INDEX" ]; then NEXT_END=$LAST_INDEX; fi
    NEXT_SHIM=$(sbatch --parsable \
        --dependency=afterok:$MY_ID \
        --output=$LOG_DIR/%x-%j.out --error=$LOG_DIR/%x-%j.err \
        "$SCRIPT_DIR/submit_step3_chunk.sh" \
        "$NEXT_IDX" "$TOTAL_CHUNKS" "$NEXT_START" "$NEXT_END" "$CONFIG_FILE")
    echo "submit_step3_chunk[$CHUNK_IDX]: queued shim for chunk $NEXT_IDX as $NEXT_SHIM"
else
    # Depend only on the chunk we just submitted; shim chain already gates earlier
    # chunks via afterok, and Puhti's MinJobAge=300s purges older job records.
    STEP4_ID=$(sbatch --parsable \
        --dependency=afterok:$MY_ID \
        --output=$LOG_DIR/%x-%j.out --error=$LOG_DIR/%x-%j.err \
        "$SCRIPT_DIR/4.sh" "$CONFIG_FILE" "$QUANT_DIR_3" "$NEW_LIB_FILE" "$REPORT_DIR" "$FILE_LIST")
    if [ -z "$STEP4_ID" ]; then
        echo "submit_step3_chunk[$CHUNK_IDX]: sbatch returned empty Job ID for Step 4."
        exit 1
    fi
    echo "submit_step3_chunk[$CHUNK_IDX]: all Step 3 chunks queued. Step 4 submitted as $STEP4_ID with afterok:$MY_ID"
    printf 'step4\t-\t-\t%s\t%s\n' "$STEP4_ID" "$(date -Iseconds)" >> "$CHUNKS_TSV"
fi
