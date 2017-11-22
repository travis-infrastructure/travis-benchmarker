#!/usr/bin/env python

from flask import Flask, request
from collections import OrderedDict
import json
import os
import sys
import arrow
from tabulate import tabulate

app = Flask(__name__)

@app.route("/", methods=['GET', 'POST'])
def hello():
    if request.method == 'POST':
        data = json.loads(request.data)
        write_results(data)
        return "Recorded: {}\n".format(data)

    """
<<<<<<< Updated upstream
    if request.method == 'GET':
        data = read_results()
        if "table" in request.environ['CONTENT_TYPE']:
            return display_table()
        if "spreadsheet" in request.environ['CONTENT_TYPE']:
            return display_table().replace("|", "\t")
        return json.dumps(data)
=======
    """
    data = read_results()
    # FIXME: reverse logic here to show table by default
    if "table" in request.environ['CONTENT_TYPE']:
        return display_table()
    return json.dumps(data)

def read_results():
    with open("results.json", "r") as f:
        return json.load(f)

def write_results(new):
    existing = read_results()

    instance_id = new.pop("instance_id")
    if instance_id in existing:
        existing[instance_id].update(new)
    else:
        existing[instance_id] = new

    with open("results.json", "w") as f:
        json.dump(existing, f, indent=4, sort_keys=True)

def setup(results_filename="results.json"):
    if not os.path.isfile(results_filename):
        with open(results_filename, "a") as f:
            f.write("{}")

"""
In [59]: print(tabulate.tabulate([yoyo] + people, headers="firstrow"))
  Age  Name
-----  -------
   12  bob
   15  charles
   20  diana
   10  alice

In [60]: [yoyo] + people
Out[60]:
[OrderedDict([('age', 'Age'), ('name', 'Name')]),
 {'age': 12, 'name': 'bob'},
 {'age': 15, 'name': 'charles'},
 {'age': 20, 'name': 'diana'},
 {'age': 10, 'name': 'alice'}]

"""
def display_table():
    data = read_results()
    rows = []
    for iid in data:
        row = OrderedDict()
        row["Instance ID"] = iid
        row["instance_ipv4"] = ""
        row["mem"] = ""
        row["method"], row["total"] = "", ""
        row["instance_type"] = ""
        row["ci-start"], row["ci-finish"] = "", ""
        row["volume_type"] = ""
        row.update(data[iid])
        rows.append(row)
    rows = sort_rows(rows)
    return tabulate(rows, headers='keys', tablefmt="pipe")

def sort_rows(rows):
    times = [r['boot_time'] for r in rows]
    ret_rows = []
    times = [arrow.get(time, 'MM/DD HH:mm:ss') for time in times]
    times.sort()
    # sorted(people, key=lambda p: p['age'])
    for time in times:
        result = [x for x in rows if arrow.get(x['boot_time'], 'MM/DD HH:mm:ss') == time]
        ret_rows.append(result[0])
        rows.remove(result[0])
    return ret_rows

if __name__ == "__main__":
    setup()
    if "--show" in sys.argv:
        print(display_table())
        exit()
    app.run(debug=True, host="0.0.0.0")
