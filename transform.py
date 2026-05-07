import json

def restructure_data(input_file, output_file):
    with open(input_file, 'r') as f:
        raw = json.load(f)

    # Flatten array of {"data": [...]} objects
    entries = [item for obj in raw for item in obj['data']]

    employees = {}

    for entry in entries:
        emp_id = entry['employeeID']

        if emp_id not in employees:
            employees[emp_id] = {
                "employeeID": emp_id,
                "employeeName": entry['employeeName'],
                "allocations": []
            }

        allocation = {
            "allocationID": entry['allocationID'],
            "startDate": entry['startDate'],
            "endDate": entry['endDate'],
            "potentialEndDate": entry['potentialEndDate'],
            "allocation": entry['allocation'],
            "allocationType": entry['allocationType'],
        }

        if entry['allocationType'] == 'project':
            allocation['projectName'] = entry['projectName']
        elif entry['allocationType'] == 'area':
            allocation['areaName'] = entry['areaName']

        employees[emp_id]['allocations'].append(allocation)

    result = {"data": list(employees.values())}

    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)

    print(f"Done. {len(employees)} employee(s) written to {output_file}")

restructure_data('fil3.json', 'output.json')