#!/bin/bash
#SBATCH --job-name=diann_s1_chunk_submit
#SBATCH --account=project_2000752
#SBATCH --partition=small
#SBATCH --time=00:05:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G

# Tiny shim that submits one Step 1 chunk array, then either chains the next
# shim or submits Step 2 with an afterok dependency on every chunk's array.
# Chains run strictly sequentially via afterok, so queue depth never exceeds
# one chunk worth of jobs (+1 shim) at a time, staying under MaxSubmit=400.

set -eo pipefail

CHUNK_IDX=$1
TOTAL_CHUNKS=$2
START=$3
END=$4
CONFIG_FILE=$5

source "$CONFIG_FILE"
CHUNK_SIZE="${CHUNK_SIZE:-350}"

LOG_DIR="$OUTPUT_DIR/logs"
QUANT_DIR_1="$OUTPUT_DIR/step1_quant"
LIB_DIR="$OUTPUT_DIR/step2_lib"
FILE_LIST="$OUTPUT_DIR/file_list.txt"
SCRIPT_DIR="/scratch/project_2000752/DIA-NN/02_scripts"

CHUNK_IDS_FILE="$LOG_DIR/.step1_chunk_ids"
CHUNKS_TSV="$LOG_DIR/chunks.tsv"

MY_ID=$(sbatch --parsable \
    --array=${START}-${END} \
    --output=$LOG_DIR/%x-%A_%a.out --error=$LOG_DIR/%x-%A_%a.err \
    "$SCRIPT_DIR/1.sh" "$CONFIG_FILE" "$QUANT_DIR_1" "$LIB_FILE" "$FILE_LIST")
if [ -z "$MY_ID" ]; then
    echo "submit_step1_chunk[$CHUNK_IDX]: sbatch returned empty Job ID for array $START-$END. Aborting chain."
    exit 1
fi
echo "submit_step1_chunk[$CHUNK_IDX/$((TOTAL_CHUNKS-1))]: Step 1 array $START-$END submitted as $MY_ID"

echo "$MY_ID" >> "$CHUNK_IDS_FILE"
printf 'step1\t%d\t%d-%d\t%s\t%s\n' "$CHUNK_IDX" "$START" "$END" "$MY_ID" "$(date -Iseconds)" >> "$CHUNKS_TSV"

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
        "$SCRIPT_DIR/submit_step1_chunk.sh" \
        "$NEXT_IDX" "$TOTAL_CHUNKS" "$NEXT_START" "$NEXT_END" "$CONFIG_FILE")
    echo "submit_step1_chunk[$CHUNK_IDX]: queued shim for chunk $NEXT_IDX as $NEXT_SHIM"
else
    # Depend only on the chunk we just submitted. The shim chain (each shim
    # waits for its chunk via afterok) already guarantees all earlier chunks
    # succeeded, and Puhti's MinJobAge=300s purges queued state for older
    # chunks — so an afterok list referencing them gets rejected.
    STEP2_ID=$(sbatch --parsable \
        --dependency=afterok:$MY_ID \
        --output=$LOG_DIR/%x-%j.out --error=$LOG_DIR/%x-%j.err \
        "$SCRIPT_DIR/2.sh" "$CONFIG_FILE" "$QUANT_DIR_1" "$LIB_DIR" "$LIB_FILE" "$FILE_LIST")
    if [ -z "$STEP2_ID" ]; then
        echo "submit_step1_chunk[$CHUNK_IDX]: sbatch returned empty Job ID for Step 2."
        exit 1
    fi
    echo "submit_step1_chunk[$CHUNK_IDX]: all Step 1 chunks queued. Step 2 submitted as $STEP2_ID with afterok:$MY_ID"
    printf 'step2\t-\t-\t%s\t%s\n' "$STEP2_ID" "$(date -Iseconds)" >> "$CHUNKS_TSV"
fi
