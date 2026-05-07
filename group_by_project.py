import json

def group_by_project(input_file, output_file):
    with open(input_file, 'r') as f:
        data = json.load(f)

    projects = {}
    areas = {}

    for employee in data['data']:
        emp_info = {
            "employeeID": employee['employeeID'],
            "employeeName": employee['employeeName'],
        }

        for alloc in employee['allocations']:
            entry = {
                **emp_info,
                "allocation": alloc['allocation'],
                "startDate": alloc['startDate'],
                "endDate": alloc['endDate'],
                "potentialEndDate": alloc['potentialEndDate'],
            }

            if alloc['allocationType'] == 'project':
                name = alloc.get('projectName') or 'Unassigned'
                projects.setdefault(name, []).append(entry)
            elif alloc['allocationType'] == 'area':
                name = alloc.get('areaName') or 'Unassigned'
                areas.setdefault(name, []).append(entry)

    result = {
        "projects": {k: {"count": len(v), "employees": v} for k, v in sorted(projects.items())},
        "areas": {k: {"count": len(v), "employees": v} for k, v in sorted(areas.items())},
        "summary": {
            "totalProjects": len(projects),
            "totalAreas": len(areas),
            "totalProjectAllocations": sum(len(v) for v in projects.values()),
            "totalAreaAllocations": sum(len(v) for v in areas.values()),
        }
    }

    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)

    print(f"Done. {len(projects)} projects, {len(areas)} areas → {output_file}")

group_by_project('output.json', 'grouped.json')
