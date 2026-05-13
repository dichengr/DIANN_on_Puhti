#!/bin/bash
#
# Master script to submit the 4-step DIA-NN workflow.
#

# --- USAGE ---
# ./submit_diann_workflow.sh /path/to/your/project/config.sh

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

FILE_COUNT=$(find "$DATA_DIR" -maxdepth 1 \( -name '*.d' -o -name '*.raw' \) | wc -l)
if [ $FILE_COUNT -eq 0 ]; then
    echo "Error: No .d or .raw files found in $DATA_DIR"
    exit 1
fi
ARRAY_MAX=$((FILE_COUNT - 1))
echo "Found $FILE_COUNT raw files. Setting SLURM array to 0-$ARRAY_MAX."

# This is the location of the central, non-editable scripts.
# IMPORTANT: Set this to the correct path on your system.
SCRIPT_DIR="/scratch/project_2000752/DIA-NN/02_scripts"

# --- Job Submission ---
#STEP1=$(sbatch --array=0-$ARRAY_MAX --output=$LOG_DIR/%x-%A_%a.out --error=$LOG_DIR/%x-%A_%a.err \
#    "$SCRIPT_DIR/1.sh" "$CONFIG_FILE" "$QUANT_DIR_1" "$LIB_FILE")
#STEP1_ID=${STEP1##* }
#echo "Step 1 (Search 1) submitted. Job ID: $STEP1_ID"

#STEP2=$(sbatch --dependency=afterok:$STEP1_ID  --output=$LOG_DIR/%x-%j.out --error=$LOG_DIR/%x-%j.err \
#    "$SCRIPT_DIR/2.sh" "$CONFIG_FILE" "$QUANT_DIR_1" "$LIB_DIR" "$LIB_FILE")
#STEP2_ID=${STEP2##* }
#echo "Step 2 (Library Gen) submitted. Job ID: $STEP2_ID"

STEP3=$(sbatch --dependency=afterok:$STEP2_ID --array=0-$ARRAY_MAX --output=$LOG_DIR/%x-%A_%a.out --error=$LOG_DIR/%x-%A_%a.err \
    "$SCRIPT_DIR/3.sh" "$CONFIG_FILE" "$QUANT_DIR_3" "$NEW_LIB_FILE")
STEP3_ID=${STEP3##* }
echo "Step 3 (Search 2) submitted. Job ID: $STEP3_ID"

STEP4=$(sbatch --dependency=afterok:$STEP3_ID --output=$LOG_DIR/%x-%j.out --error=$LOG_DIR/%x-%j.err \
    "$SCRIPT_DIR/4.sh" "$CONFIG_FILE" "$QUANT_DIR_3" "$NEW_LIB_FILE" "$REPORT_DIR")
STEP4_ID=${STEP4##* }
echo "Step 4 (Final Report) submitted. Job ID: $STEP4_ID"

echo "--- Workflow successfully submitted. ---"
