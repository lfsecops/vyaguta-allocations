#!/usr/bin/env bash
set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
WORKDIR="$(cd "$(dirname "$0")" && pwd)"
VYAGUTA_BASE="https://vyaguta.lftechnology.com"
# Use today as startDate and +18 months as endDate to capture all active/upcoming allocations
START_DATE=$(date +%Y-%m-%d)
END_DATE=$(date -d "+18 months" +%Y-%m-%d 2>/dev/null || date -v+18m +%Y-%m-%d)
ALLOC_URL="${VYAGUTA_BASE}/api/teams/allocations?startDate=${START_DATE}&endDate=${END_DATE}&page=1&size=40&sortBy=endDate&order=desc"
USERS_URL="${VYAGUTA_BASE}/api/core/users?sortBy=firstName&size=500"
ALLOC_DIR="${WORKDIR}/allocations"
DELAY=1

# ─── Token ────────────────────────────────────────────────────────────────────
if [ -z "${VYAGUTA_TOKEN:-}" ]; then
  echo "Error: VYAGUTA_TOKEN environment variable is not set."
  echo "Usage: VYAGUTA_TOKEN=<your-bearer-token> $0"
  exit 1
fi

# ─── Step 1: Fetch employee list ──────────────────────────────────────────────
echo "==> Fetching employee list..."
curl -sf "$USERS_URL" \
  -H "Authorization: Bearer $VYAGUTA_TOKEN" \
  -o "${WORKDIR}/vyags.json"
echo "    Saved vyags.json ($(jq '.data | length' "${WORKDIR}/vyags.json") employees)"

# ─── Step 2: Fetch allocations per employee ───────────────────────────────────
echo "==> Fetching allocations per employee..."
mkdir -p "$ALLOC_DIR"

ids=$(jq -r '.data[].id' "${WORKDIR}/vyags.json")
total=$(echo "$ids" | wc -l)
count=0

for id in $ids; do
  count=$((count + 1))
  printf "    [%d/%d] User %s" "$count" "$total" "$id"

  retries=0
  while true; do
    http_code=$(curl -s --max-time 30 \
      -o "${ALLOC_DIR}/${id}.json" \
      -w "%{http_code}" \
      "${ALLOC_URL}&userId=${id}" \
      -H "Authorization: Bearer $VYAGUTA_TOKEN") || http_code="000"

    if [ "$http_code" = "429" ]; then
      echo " → 429 rate-limited, retrying in 10s..."
      sleep 10
    elif [ "$http_code" = "000" ]; then
      retries=$((retries + 1))
      if [ "$retries" -ge 3 ]; then
        echo " → network error after 3 retries, skipping"
        break
      fi
      echo " → network error, retry $retries/3 in 5s..."
      sleep 5
    elif [ "$http_code" != "200" ]; then
      echo " → HTTP $http_code (non-200, continuing)"
      break
    else
      echo " → $http_code"
      break
    fi
  done

  sleep "$DELAY"
done

# ─── Step 3: Merge & transform (jq pipeline) ─────────────────────────────────
echo "==> Merging and filtering allocations..."

# Merge all allocation files into a single array
jq -s '.' "${ALLOC_DIR}"/[0-9]*.json > "${WORKDIR}/merged.json"

# Keep only current/active allocations (endDate null = ongoing, or area allocations ending after today)
jq --arg today "$START_DATE" 'map(.data |= map(select(
  .endDate == null or
  (.allocationType == "area" and .endDate >= $today)
)))' "${WORKDIR}/merged.json" > "${WORKDIR}/filtered.json"

# Reshape to flat structure
jq 'map(del(.meta) | .data |= map({
  allocationID: .id,
  startDate, endDate, potentialEndDate, allocation, allocationType,
  employeeID: .employee.id,
  employeeName: .employee.email,
  projectName: .project.name,
  areaName: .area.name
}))' "${WORKDIR}/filtered.json" > "${WORKDIR}/fil2.json"

# Inject employees with no allocations
jq -s '
  .[0] as $fil2 |
  .[1].data as $employees |
  ($fil2 | map(.data[].employeeID) | flatten | unique) as $seen |
  ($employees | map(select(.id | IN($seen[]) | not))) as $missing |
  $fil2 + ($missing | map({
    "data": [{
      "allocationID": null,
      "startDate": null,
      "endDate": null,
      "potentialEndDate": null,
      "allocation": null,
      "allocationType": null,
      "employeeID": .id,
      "employeeName": .email,
      "projectName": null,
      "areaName": null
    }]
  }))
' "${WORKDIR}/fil2.json" "${WORKDIR}/vyags.json" > "${WORKDIR}/fil3.json"

echo "    Intermediate: $(jq 'length' "${WORKDIR}/fil3.json") employee groups"

# ─── Step 4: Final restructure (Python) ──────────────────────────────────────
echo "==> Generating final output..."
python3 "${WORKDIR}/transform.py"

echo "==> Done. Final output: ${WORKDIR}/output.json ($(jq '.data | length' "${WORKDIR}/output.json") employees)"

# ─── Cleanup intermediates ────────────────────────────────────────────────────
rm -f "${WORKDIR}/merged.json" "${WORKDIR}/filtered.json" "${WORKDIR}/fil2.json" "${WORKDIR}/fil3.json"
echo "    Cleaned up intermediate files."
