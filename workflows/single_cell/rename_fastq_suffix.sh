#!/usr/bin/env bash
set -euo pipefail

# --- EDIT ME (if your env differs) ---
PROJ="terra-e7f1f090"
BUCKET="fc-4a07fe94-bf2c-47a7-88f1-6354d058909d"
FLOWCELL="bone10x/2025-07-17-sctask0376378-o"
BASE="gs://$BUCKET/$FLOWCELL"

# Map: folder_with_suffix -> base_prefix_without_suffix
declare -A MAP=(
  ["1303F1A_Trab_10x_idxSI-GA-D6"]="1303F1A_Trab_10x"
  ["1303F1A_Cartilage_10x_idxSI-GA-D5"]="1303F1A_Cartilage_10x"
  ["1112-cort_cart_10x_idxSI-GA-E9"]="1112-cort_cart_10x"
)

DRY_RUN=0   # set to 0 to actually rename

echo "Renaming FASTQs by inserting folder suffix after sample prefix (before _S...)."
for FOLDER in "${!MAP[@]}"; do
  BASEPREFIX="${MAP[$FOLDER]}"                 # e.g., 1112-cort_cart_10x
  SUFFIX="${FOLDER#${BASEPREFIX}_}"            # e.g., idxSI-GA-E9
  SRC_PREFIX="$BASE/$FOLDER"

  echo "== Sample folder: $FOLDER (base prefix: $BASEPREFIX ; suffix: $SUFFIX)"

  # List FASTQs that begin with the base prefix and contain _S... (10x convention)
  while IFS= read -r SRC; do
    FILE="${SRC##*/}"

    # Only operate on files whose name STARTS with the base prefix + underscore
    # and has the canonical 10x segments after it.
    if [[ "$FILE" =~ ^${BASEPREFIX}_.+\.fastq\.gz$ ]]; then
      # Insert _${SUFFIX}_ immediately after the base prefix
      NEWFILE="${FILE/${BASEPREFIX}_/${BASEPREFIX}_${SUFFIX}_}"
      DST="$SRC_PREFIX/$NEWFILE"

      if [[ "$FILE" == "$NEWFILE" ]]; then
        echo "  • already has suffix: $FILE"
        continue
      fi

      echo "  mv: $FILE  →  $NEWFILE"
      if [[ $DRY_RUN -eq 0 ]]; then
        gsutil -m -u "$PROJ" mv "$SRC" "$DST"
      fi
    else
      echo "  • skip (does not match base prefix): $FILE"
    fi
  done < <(gsutil -u "$PROJ" ls "$SRC_PREFIX/${BASEPREFIX}_S"*.fastq.gz)
done

if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY-RUN only (no changes made). Set DRY_RUN=0 and re-run to apply."
fi

# Post-rename sanity checks (run after DRY_RUN=0)
# For each sample, ensure R1 and R2 exist with the NEW prefix
echo "Run these after applying to validate:"
for FOLDER in "${!MAP[@]}"; do
  BASEPREFIX="${MAP[$FOLDER]}"
  SUFFIX="${FOLDER#${BASEPREFIX}_}"
  NEWPFX="${BASEPREFIX}_${SUFFIX}"
  echo "  gsutil -u \"$PROJ\" ls \"$BASE/$FOLDER/${NEWPFX}_S*_L*_R1_*.fastq.gz\""
  echo "  gsutil -u \"$PROJ\" ls \"$BASE/$FOLDER/${NEWPFX}_S*_L*_R2_*.fastq.gz\""
done