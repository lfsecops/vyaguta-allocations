# Vyaguta Allocations Pipeline

> Created for SecOps @ Leapfrog Technology

Fetches employee allocations from Vyaguta and produces consolidated JSON outputs grouped by employee and by project/area.

## Prerequisites

- `bash`
- `curl`
- `jq`
- `python3`
- A valid Vyaguta Bearer token

## Usage

```bash
VYAGUTA_TOKEN="<your-token>" ./run.sh
```

Get a token from [Vyaguta](https://vyaguta.lftechnology.com) → browser DevTools → Network tab → copy the `Authorization: Bearer ...` header value.

## What it does

| Step | Action | Output |
|------|--------|--------|
| 1 | Fetch all employees | `vyags.json` |
| 2 | Fetch each employee's allocations | `allocations/{id}.json` |
| 3 | Merge, filter active, inject unallocated (jq) | intermediate files |
| 4 | Restructure by employee | `output.json` |
| 5 | Group by project and area | `grouped.json` |

Date range is automatically set to today → +18 months.

## Outputs

### output.json — grouped by employee

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

### grouped.json — grouped by project/area

```json
{
  "projects": {
    "Laudio": { "count": 58, "employees": [...] }
  },
  "areas": {
    "Development": { "count": 21, "employees": [...] }
  },
  "summary": {
    "totalProjects": 45,
    "totalAreas": 28,
    "totalProjectAllocations": 427,
    "totalAreaAllocations": 123
  }
}
```

## Verify fetched data

```bash
./check.sh
```

Reports missing, empty, malformed, or orphan allocation files against the employee list.

## Files

| File | Purpose |
|------|---------|
| `run.sh` | Main pipeline script (fetch + transform + group) |
| `check.sh` | Validates fetched allocations against employee list |
| `transform.py` | Restructures into employee-grouped output |
| `group_by_project.py` | Groups employees by project and area |

## Error handling

Common issues:
- **401 Unauthorized** — token expired, get a fresh one
- **Network errors** — retries 3 times with backoff, then warns
- **Partial failures** — continues through all employees, reports count at the end
