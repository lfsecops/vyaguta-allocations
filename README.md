# Allocation Pipeline

Fetches employee allocations from Vyaguta and produces a consolidated `output.json` grouped by employee.

## Prerequisites

- `jq`
- `python3`
- `curl`
- A valid Vyaguta Bearer token

## Usage

```bash
VYAGUTA_TOKEN="<your-token>" ./run.sh
```

## What it does

1. Fetches all employees → `vyags.json`
2. Fetches each employee's allocations → `allocations/{id}.json`
3. Merges, filters active allocations, and injects unallocated employees (jq)
4. Restructures into final `output.json` grouped by employee (Python)

## Verify

```bash
./check.sh
```

Reports missing, empty, or malformed allocation files against `vyags.json`.

## Output format

```json
{
  "data": [
    {
      "employeeID": 1003,
      "employeeName": "user@lftechnology.com",
      "allocations": [
        {
          "allocationID": 8473,
          "startDate": "2025-07-01",
          "endDate": null,
          "potentialEndDate": "2026-05-29",
          "allocation": 35,
          "allocationType": "project",
          "projectName": "Vyaguta"
        }
      ]
    }
  ]
}
```

## Files

| File | Purpose |
|------|---------|
| `run.sh` | Main pipeline (fetch + transform) |
| `check.sh` | Validates fetched allocations against employee list |
| `transform.py` | Final restructure into grouped output |
