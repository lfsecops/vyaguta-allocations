#!/usr/bin/env bash
set -uo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ─── Banner ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}"
cat << 'EOF'
 __     __                    _          
 \ \   / /   _  __ _  __ _  | |_ __ _   
  \ \ / / | | |/ _` |/ _` | | __/ _` |  
   \ V /| |_| | (_| | (_| | | || (_| |  
    \_/  \__, |\__,_|\__, |  \__\__,_|  
         |___/       |___/              
     _    _ _                 _   _                 
    / \  | | | ___   ___ __ _| |_(_) ___  _ __  ___ 
   / _ \ | | |/ _ \ / __/ _` | __| |/ _ \| '_ \/ __|
  / ___ \| | | (_) | (_| (_| | |_| | (_) | | | \__ \
 /_/   \_\_|_|\___/ \___\__,_|\__|_|\___/|_| |_|___/
EOF
echo -e "${RESET}"
echo -e "${DIM}  Created for SecOps @ Leapfrog Technology${RESET}"
echo -e "${DIM}  ─────────────────────────────────────────${RESET}"
echo ""

# ─── Helpers ──────────────────────────────────────────────────────────────────
die() { echo -e "${RED}ERROR:${RESET} $*" >&2; exit 1; }

step_failed() {
  echo ""
  echo -e "${RED}─── FAILED at: $1 ───${RESET}"
  echo -e "${RED}Reason:${RESET} $2"
  echo ""
  echo -e "${YELLOW}Troubleshooting:${RESET}"
  echo "  $3"
  exit 1
}

# ─── Dependency check ─────────────────────────────────────────────────────────
for cmd in curl jq python3; do
  command -v "$cmd" &>/dev/null || die "'$cmd' is not installed. Install it and try again."
done

# ─── Configuration ────────────────────────────────────────────────────────────
WORKDIR="$(cd "$(dirname "$0")" && pwd)"
VYAGUTA_BASE="https://vyaguta.lftechnology.com"
START_DATE=$(date +%Y-%m-%d)
END_DATE=$(date -d "+18 months" +%Y-%m-%d 2>/dev/null || date -v+18m +%Y-%m-%d 2>/dev/null) \
  || die "Could not compute END_DATE. Ensure GNU or BSD 'date' is available."
ALLOC_URL="${VYAGUTA_BASE}/api/teams/allocations?startDate=${START_DATE}&endDate=${END_DATE}&page=1&size=40&sortBy=endDate&order=desc"
USERS_URL="${VYAGUTA_BASE}/api/core/users?sortBy=firstName&size=500"
ALLOC_DIR="${WORKDIR}/allocations"
DELAY=1

# ─── Token ────────────────────────────────────────────────────────────────────
if [ -z "${VYAGUTA_TOKEN:-}" ]; then
  echo -e "${RED}ERROR:${RESET} VYAGUTA_TOKEN environment variable is not set."
  echo ""
  echo -e "${BOLD}Usage:${RESET}"
  echo "  VYAGUTA_TOKEN=<your-bearer-token> ./run.sh"
  echo ""
  echo -e "${DIM}Get a token from: ${VYAGUTA_BASE} (browser DevTools → Network → copy Authorization header)${RESET}"
  exit 1
fi

echo -e "${BOLD}Pipeline started${RESET} at $(date)"
echo -e "Date range: ${CYAN}${START_DATE}${RESET} → ${CYAN}${END_DATE}${RESET}"
echo ""

# ─── Step 1: Fetch employee list ──────────────────────────────────────────────
echo -e "${BOLD}==> [1/5] Fetching employee list...${RESET}"
http_code=$(curl -s --max-time 30 \
  -o "${WORKDIR}/vyags.json" \
  -w "%{http_code}" \
  "$USERS_URL" \
  -H "Authorization: Bearer $VYAGUTA_TOKEN") || http_code="000"

if [ "$http_code" = "000" ]; then
  step_failed "Fetch employees" \
    "Network error — could not reach ${VYAGUTA_BASE}" \
    "Check your internet connection or VPN."
elif [ "$http_code" = "401" ]; then
  step_failed "Fetch employees" \
    "HTTP 401 Unauthorized — token is expired or invalid." \
    "Get a fresh token from Vyaguta and re-run: VYAGUTA_TOKEN=<new-token> ./run.sh"
elif [ "$http_code" != "200" ]; then
  step_failed "Fetch employees" \
    "HTTP $http_code from users API." \
    "Check if ${USERS_URL} is accessible. Response saved to vyags.json for inspection."
fi

emp_count=$(jq '.data | length' "${WORKDIR}/vyags.json" 2>/dev/null) || \
  step_failed "Fetch employees" \
    "vyags.json is not valid JSON." \
    "The API may have returned an error page. Check vyags.json contents."

if [ "$emp_count" -eq 0 ]; then
  step_failed "Fetch employees" \
    "vyags.json has 0 employees." \
    "The API returned an empty list. Check if the token has correct permissions."
fi

echo -e "${GREEN}    ✓${RESET} Saved vyags.json ($emp_count employees)"

# ─── Step 2: Fetch allocations per employee ───────────────────────────────────
echo -e "${BOLD}==> [2/5] Fetching allocations per employee...${RESET}"
mkdir -p "$ALLOC_DIR"

ids=$(jq -r '.data[].id' "${WORKDIR}/vyags.json")
total=$(echo "$ids" | wc -l | tr -d ' ')
count=0
failed_fetches=0

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
        echo " → FAILED (network error after 3 retries)"
        failed_fetches=$((failed_fetches + 1))
        break
      fi
      echo " → network error, retry $retries/3 in 5s..."
      sleep 5
    elif [ "$http_code" = "401" ]; then
      echo ""
      step_failed "Fetch allocations (user $id)" \
        "HTTP 401 — token expired mid-run." \
        "Get a fresh token and re-run. Already-fetched files in allocations/ are still valid."
    elif [ "$http_code" != "200" ]; then
      echo " → HTTP $http_code (skipping)"
      failed_fetches=$((failed_fetches + 1))
      break
    else
      echo " → OK"
      break
    fi
  done

  sleep "$DELAY"
done

if [ "$failed_fetches" -gt 0 ]; then
  echo ""
  echo -e "    ${YELLOW}⚠ Warning:${RESET} $failed_fetches/$total fetches failed. Results may be incomplete."
  echo "    Run ./check.sh after to see which employees are missing."
  echo ""
fi

# ─── Step 3: Merge & transform (jq pipeline) ─────────────────────────────────
echo -e "${BOLD}==> [3/5] Merging and filtering allocations...${RESET}"

# Check that allocation files exist
alloc_files=("${ALLOC_DIR}"/[0-9]*.json)
if [ ${#alloc_files[@]} -eq 0 ]; then
  step_failed "Merge allocations" \
    "No allocation files found in ${ALLOC_DIR}/" \
    "Step 2 may have failed entirely. Check network/token and re-run."
fi

if ! jq -s '.' "${alloc_files[@]}" > "${WORKDIR}/merged.json" 2>/tmp/jq_err; then
  step_failed "Merge allocations" \
    "jq failed to merge allocation files: $(cat /tmp/jq_err)" \
    "Some allocation files may be corrupt. Run ./check.sh to find malformed files."
fi

if ! jq --arg today "$START_DATE" 'map(.data |= map(select(
  .endDate == null or
  (.allocationType == "area" and .endDate >= $today)
)))' "${WORKDIR}/merged.json" > "${WORKDIR}/filtered.json" 2>/tmp/jq_err; then
  step_failed "Filter allocations" \
    "jq filter failed: $(cat /tmp/jq_err)" \
    "merged.json may have unexpected structure. Inspect it manually."
fi

if ! jq 'map(del(.meta) | .data |= map({
  allocationID: .id,
  startDate, endDate, potentialEndDate, allocation, allocationType,
  employeeID: .employee.id,
  employeeName: .employee.email,
  projectName: .project.name,
  areaName: .area.name
}))' "${WORKDIR}/filtered.json" > "${WORKDIR}/fil2.json" 2>/tmp/jq_err; then
  step_failed "Reshape allocations" \
    "jq reshape failed: $(cat /tmp/jq_err)" \
    "filtered.json may have entries with missing .employee or .project fields."
fi

if ! jq -s '
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
' "${WORKDIR}/fil2.json" "${WORKDIR}/vyags.json" > "${WORKDIR}/fil3.json" 2>/tmp/jq_err; then
  step_failed "Inject unallocated employees" \
    "jq inject failed: $(cat /tmp/jq_err)" \
    "Check fil2.json and vyags.json structure."
fi

echo -e "    ${GREEN}✓${RESET} Merged: $(jq 'length' "${WORKDIR}/fil3.json") employee groups"

# ─── Step 4: Final restructure (Python) ──────────────────────────────────────
echo -e "${BOLD}==> [4/5] Generating output.json...${RESET}"
if ! python3 "${WORKDIR}/transform.py" 2>/tmp/py_err; then
  step_failed "transform.py" \
    "Python script failed: $(cat /tmp/py_err)" \
    "Check that fil3.json exists and has the expected structure."
fi

echo -e "    ${GREEN}✓${RESET} output.json: $(jq '.data | length' "${WORKDIR}/output.json") employees"

# ─── Step 5: Group by project/area ────────────────────────────────────────────
echo -e "${BOLD}==> [5/5] Grouping by project and area...${RESET}"
if ! python3 "${WORKDIR}/group_by_project.py" 2>/tmp/py_err; then
  step_failed "group_by_project.py" \
    "Python script failed: $(cat /tmp/py_err)" \
    "Check that output.json exists and has the expected structure."
fi

echo -e "    ${GREEN}✓${RESET} grouped.json written"

# ─── Cleanup intermediates ────────────────────────────────────────────────────
rm -f "${WORKDIR}/merged.json" "${WORKDIR}/filtered.json" "${WORKDIR}/fil2.json" "${WORKDIR}/fil3.json" /tmp/jq_err /tmp/py_err
echo ""
echo -e "${GREEN}==> Pipeline complete${RESET} at $(date)"
echo -e "    Final outputs: ${BOLD}output.json${RESET}, ${BOLD}grouped.json${RESET}"
