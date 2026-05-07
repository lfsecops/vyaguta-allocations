#!/usr/bin/env bash
set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
WORKDIR="$(cd "$(dirname "$0")" && pwd)"
JSON_FILE="${WORKDIR}/vyags.json"
OUTPUT_DIR="${WORKDIR}/allocations"

# ─── Validate inputs ─────────────────────────────────────────────────────────
if [ ! -f "$JSON_FILE" ]; then
  echo "Error: $JSON_FILE not found. Run the pipeline first."
  exit 1
fi

if [ ! -d "$OUTPUT_DIR" ]; then
  echo "Error: $OUTPUT_DIR directory not found. Run the pipeline first."
  exit 1
fi

# ─── Counters ─────────────────────────────────────────────────────────────────
total=0
ok=0
empty=0
missing=0
malformed=0

# ─── Lists for summary ───────────────────────────────────────────────────────
missing_list=()
empty_list=()
malformed_list=()

echo "Checking allocation responses against $(basename "$JSON_FILE")..."
echo "Source: $JSON_FILE"
echo "Target: $OUTPUT_DIR/"
echo "────────────────────────────────────────────────────"

# ─── Iterate source IDs + emails ─────────────────────────────────────────────
while IFS=$'\t' read -r id email; do
  total=$((total + 1))
  file="${OUTPUT_DIR}/${id}.json"

  if [ ! -f "$file" ]; then
    missing_list+=("$id ($email)")
    missing=$((missing + 1))
    continue
  fi

  # Check if file is valid JSON
  if ! jq empty "$file" 2>/dev/null; then
    malformed_list+=("$id ($email)")
    malformed=$((malformed + 1))
    continue
  fi

  # Check if .data exists and is a non-empty array
  data_length=$(jq '.data | length' "$file" 2>/dev/null)

  if [ -z "$data_length" ] || [ "$data_length" -eq 0 ]; then
    empty_list+=("$id ($email)")
    empty=$((empty + 1))
  else
    ok=$((ok + 1))
  fi

done < <(jq -r '.data[] | [.id, .email] | @tsv' "$JSON_FILE")

# ─── Check for orphan files (in allocations/ but not in vyags.json) ──────────
known_ids=$(jq -r '.data[].id' "$JSON_FILE" | sort -n)
orphan_count=0
orphan_list=()

for file in "${OUTPUT_DIR}"/[0-9]*.json; do
  [ -f "$file" ] || continue
  basename_id=$(basename "$file" .json)
  if ! echo "$known_ids" | grep -qx "$basename_id"; then
    orphan_list+=("$basename_id")
    orphan_count=$((orphan_count + 1))
  fi
done

# ─── Report ──────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
echo "  SUMMARY"
echo "════════════════════════════════════════════════════"
printf "  Total employees in vyags.json:  %d\n" "$total"
printf "  ✓ OK (have allocations):        %d\n" "$ok"
printf "  ○ Empty (data=[]):              %d\n" "$empty"
printf "  ✗ Missing (no file):            %d\n" "$missing"
printf "  ! Malformed (invalid JSON):     %d\n" "$malformed"
printf "  ? Orphan files (not in vyags):  %d\n" "$orphan_count"
echo "════════════════════════════════════════════════════"

# ─── Detail sections (only if issues found) ──────────────────────────────────
if [ "$missing" -gt 0 ]; then
  echo ""
  echo "── MISSING ($missing) ──────────────────────────────"
  printf '  %s\n' "${missing_list[@]}"
fi

if [ "$malformed" -gt 0 ]; then
  echo ""
  echo "── MALFORMED ($malformed) ──────────────────────────"
  printf '  %s\n' "${malformed_list[@]}"
fi

if [ "$empty" -gt 0 ]; then
  echo ""
  echo "── EMPTY ($empty) ──────────────────────────────────"
  printf '  %s\n' "${empty_list[@]}"
fi

if [ "$orphan_count" -gt 0 ]; then
  echo ""
  echo "── ORPHANS ($orphan_count) ─────────────────────────"
  printf '  %s.json\n' "${orphan_list[@]}"
fi

# ─── Exit code reflects health ───────────────────────────────────────────────
if [ "$missing" -gt 0 ] || [ "$malformed" -gt 0 ]; then
  exit 1
fi
exit 0
