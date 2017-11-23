#!/usr/bin/env python

from flask import Flask, request
from collections import OrderedDict
import json
import os
import sys
import arrow
import click
from tabulate import tabulate

app = Flask(__name__)

@app.route("/", methods=['GET', 'POST'])
def hello():
    if request.method == 'POST':
        data = json.loads(request.data)
        write_results(data)
        return "Recorded: {}\n".format(data)

    data = read_results()
    if "table" in request.environ.get('CONTENT_TYPE', ''):
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
    headers = OrderedDict()
    headers["boot_time"] = "boot"
    headers["instance_id"] = "Instance ID"
    headers["instance_ipv4"] = "ipv4"
    headers["ci-start"] = "start"
    headers["ci-finish"] = "finish"
    headers["total"] = click.style("total", bold=True)
    headers["cohort_size"] = "count"
    headers["images"] = "img#"
    headers["OK"] = "ok?"
    headers["instance_type"] = "type"
    headers["mem"] = "mem"
    headers["volume_type"] = "volume type"
    headers["method"] = "method"

    for iid in data:
        row = {"instance_id": iid}
        row.update(data[iid])
        #row = format_row(row)
        rows.append(row)
    rows = sorted(rows, key=lambda x: x["boot_time"])
    rows = sorted(rows, key=lambda x: x.get("ci-finish", 0))
    rows = [format_row(row) for row in rows]
    return tabulate([headers] + rows + [headers], headers="firstrow", tablefmt="pipe")

def format_row(row):
    if row["OK"] == "OK":
        row["OK"] = click.style(row["OK"], fg='green')
        return row

    if row["total"]:
        row["instance_ipv4"] = click.style(row["instance_ipv4"], fg='red')
        row["OK"] = click.style(row["OK"], fg='red')
    else:
        row["OK"] = click.style(row["OK"], fg='yellow')
    return row

if __name__ == "__main__":
    setup()
    if "--show" in sys.argv:
        print(display_table())
        exit()
    app.run(debug=True, host="0.0.0.0")
