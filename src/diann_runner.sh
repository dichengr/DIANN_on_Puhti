#!/bin/bash
#
# Master script to submit the 4-step DIA-NN workflow.
# Usage: ./diann_runner.sh /path/to/your/config.sh

if [ -z "$1" ]; then
    echo "Error: Please provide the path to your config.sh file."
    echo "Usage: $0 /path/to/your/config.sh"
    exit 1
fi

CONFIG_FILE=$(realpath $1)
source $CONFIG_FILE

echo "--- Starting DIA-NN Workflow ---"
echo "Project config: $CONFIG_FILE"
echo "Output will be saved in: $OUTPUT_DIR"

# --- Setup ---
LOG_DIR="$OUTPUT_DIR/logs"
QUANT_DIR_1="$OUTPUT_DIR/step1_quant"
QUANT_DIR_3="$OUTPUT_DIR/step3_quant"
LIB_DIR="$OUTPUT_DIR/step2_lib"
REPORT_DIR="$OUTPUT_DIR/step4_report"
NEW_LIB_FILE="$LIB_DIR/project_lib.parquet"

mkdir -p $LOG_DIR $QUANT_DIR_1 $QUANT_DIR_3 $LIB_DIR $REPORT_DIR

if [[ -z "${DATA_DIRS+x}" || ${#DATA_DIRS[@]} -eq 0 ]]; then
    echo "Error: DATA_DIRS is empty. Set DATA_DIRS=(...) in your config.sh."
    exit 1
fi

FILE_LIST="$OUTPUT_DIR/file_list.txt"
: > "$FILE_LIST"
for d in "${DATA_DIRS[@]}"; do
    if [ ! -d "$d" ]; then
        echo "Error: DATA_DIRS entry is not a directory: $d"
        exit 1
    fi
    find "$d" -maxdepth 1 \( -name '*.d' -o -name '*.raw' \)
done | sort -u > "$FILE_LIST"

FILE_COUNT=$(wc -l < "$FILE_LIST")
if [ $FILE_COUNT -eq 0 ]; then
    echo "Error: No .d or .raw files found in any DATA_DIRS entry:"
    printf '  %s\n' "${DATA_DIRS[@]}"
    exit 1
fi

DUP_BASENAMES=$(awk -F/ '{print $NF}' "$FILE_LIST" | sort | uniq -d)
if [ -n "$DUP_BASENAMES" ]; then
    echo "Error: duplicate raw-file basenames across DATA_DIRS — .quant files would collide:"
    echo "$DUP_BASENAMES"
    exit 1
fi

ARRAY_MAX=$((FILE_COUNT - 1))

# Per-account MaxSubmit on Puhti is 400. Split Step 1's array into chunks so
# we never queue more than CHUNK_SIZE + 1 jobs at once. Chunks are chained
# via shim jobs (afterok), so chunk N+1 only sbatches after chunk N's slots
# are freed. CHUNK_SIZE may be overridden in config.sh.
CHUNK_SIZE="${CHUNK_SIZE:-350}"
NCHUNKS=$(( (FILE_COUNT + CHUNK_SIZE - 1) / CHUNK_SIZE ))

echo "Found $FILE_COUNT raw files across ${#DATA_DIRS[@]} folder(s). Manifest: $FILE_LIST"
if [ "$NCHUNKS" -eq 1 ]; then
    echo "Setting SLURM array to 0-$ARRAY_MAX (single chunk)."
else
    echo "Splitting into $NCHUNKS chunks of up to $CHUNK_SIZE tasks each."
fi

# This is the location of the central, non-editable scripts.
# IMPORTANT: Set this to the correct path on your system.
SCRIPT_DIR="/scratch/project_2000752/DIA-NN/02_scripts"

CHUNK_IDS_FILE="$LOG_DIR/.step1_chunk_ids"
: > "$CHUNK_IDS_FILE"
CHUNKS_TSV="$LOG_DIR/chunks.tsv"
printf 'step\tchunk_idx\tarray_range\tjobid\tsubmitted_at\n' > "$CHUNKS_TSV"

# --- Job Submission ---
# Submit chunk 0 of Step 1 immediately. If only one chunk, also submit Step 2
# directly (preserves pre-chunking behavior bit-for-bit). Otherwise queue a
# shim that, once chunk 0 finishes, sbatches chunk 1 (and so on); the final
# shim submits Step 2 with afterok on every chunk's job ID.
END0=$((CHUNK_SIZE - 1))
if [ "$END0" -gt "$ARRAY_MAX" ]; then END0=$ARRAY_MAX; fi

STEP1_C0_ID=$(sbatch --parsable --array=0-$END0 \
    --output=$LOG_DIR/%x-%A_%a.out --error=$LOG_DIR/%x-%A_%a.err \
    "$SCRIPT_DIR/1.sh" "$CONFIG_FILE" "$QUANT_DIR_1" "$LIB_FILE" "$FILE_LIST")
if [ -z "$STEP1_C0_ID" ]; then
    echo "Error: sbatch did not return a Job ID for Step 1 chunk 0. See sbatch error output above."
    exit 1
fi
echo "Step 1 chunk 0/$((NCHUNKS-1)) (array 0-$END0) submitted. Job ID: $STEP1_C0_ID"
echo "$STEP1_C0_ID" >> "$CHUNK_IDS_FILE"
printf 'step1\t0\t0-%d\t%s\t%s\n' "$END0" "$STEP1_C0_ID" "$(date -Iseconds)" >> "$CHUNKS_TSV"

if [ "$NCHUNKS" -eq 1 ]; then
    STEP2_ID=$(sbatch --parsable --dependency=afterok:$STEP1_C0_ID \
        --output=$LOG_DIR/%x-%j.out --error=$LOG_DIR/%x-%j.err \
        "$SCRIPT_DIR/2.sh" "$CONFIG_FILE" "$QUANT_DIR_1" "$LIB_DIR" "$LIB_FILE" "$FILE_LIST")
    if [ -z "$STEP2_ID" ]; then
        echo "Error: sbatch did not return a Job ID for Step 2. Step 1 chunk 0 was queued as $STEP1_C0_ID; cancel it with: scancel $STEP1_C0_ID"
        exit 1
    fi
    echo "Step 2 (Library Gen) submitted. Job ID: $STEP2_ID"
    printf 'step2\t-\t-\t%s\t%s\n' "$STEP2_ID" "$(date -Iseconds)" >> "$CHUNKS_TSV"
    echo "Their job IDs will appear in: $LOG_DIR/diann_s2_libgen-$STEP2_ID.out"
else
    NEXT_START=$CHUNK_SIZE
    NEXT_END=$((CHUNK_SIZE * 2 - 1))
    if [ "$NEXT_END" -gt "$ARRAY_MAX" ]; then NEXT_END=$ARRAY_MAX; fi
    SHIM_ID=$(sbatch --parsable --dependency=afterok:$STEP1_C0_ID \
        --output=$LOG_DIR/%x-%j.out --error=$LOG_DIR/%x-%j.err \
        "$SCRIPT_DIR/submit_step1_chunk.sh" \
        "1" "$NCHUNKS" "$NEXT_START" "$NEXT_END" "$CONFIG_FILE")
    if [ -z "$SHIM_ID" ]; then
        echo "Error: sbatch did not return a Job ID for the chunk-1 shim. Step 1 chunk 0 was queued as $STEP1_C0_ID; cancel it with: scancel $STEP1_C0_ID"
        exit 1
    fi
    echo "Step 1 chunks 1-$((NCHUNKS-1)) and Step 2 will be queued by shim jobs. Shim 1 ID: $SHIM_ID"
    echo "Track all chunk job IDs in: $CHUNKS_TSV"
fi

echo "Step 3 and Step 4 will be submitted automatically by Step 2 once the library is built."
echo "--- Workflow successfully submitted. ---"
