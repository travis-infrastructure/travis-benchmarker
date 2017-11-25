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
    if "json" in request.environ.get('CONTENT_TYPE', ''):
        return json.dumps(data)
    sort_keys = request.environ.get('HTTP_X_SORT_KEYS', '').split(",")
    return display_table(sort_keys=sort_keys) if sort_keys != [""] else display_table()

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

def display_table(sort_keys=["boot_time"]):
    data = read_results()
    rows = []

    # Define header aliases to save screen space when printing table
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
    headers["method"] = "method"
    headers["instance_type"] = "type"
    headers["mem"] = "mem"
    headers["graphdriver"] = "graphdriver"
    headers["volume_type"] = "volume type"
    headers["filesystem"] = "filesystem"

    for iid in data:
        row = {"instance_id": iid}
        row.update(data[iid])
        rows.append(row)

    # Sort by X_SORT_KEYS header, if present
    for key in sort_keys:
        # Allow sorting by column alias
        if key in headers.values():
            key = headers.keys()[headers.values().index(key)]
        if key in headers.keys():
            rows = sorted(rows, key=lambda x: x.get(key, ''))
        else:
            print("can't sort by {}, not in {}".format(key, headers))
    rows = [format_row(row) for row in rows]
    return tabulate([headers] + rows + [headers], headers="firstrow", tablefmt="pipe")

def format_row(row):
    # row["OK"] will be "NOK" until we've determined the instance was successfully bootstrapped
    # So a value of "OK" means bootstrap succeeded.
    if row["OK"] == "OK":
        row["OK"] = click.style(row["OK"], fg='green')
        return row

    # If row["OK"] is still "NOK", it means bootstrap is either incomplete or failed somehow.
    # If row["total"] is present, it means bootstrap has finished, so mark it as failed.
    if row["total"]:
        row["instance_ipv4"] = click.style(row["instance_ipv4"], fg='red')
        row["OK"] = click.style(row["OK"], fg='red')
    # Otherwise, mark it as pending.
    else:
        row["OK"] = click.style(row["OK"], fg='yellow')
    return row

if __name__ == "__main__":
    setup()
    if "--show" in sys.argv:
        print(display_table())
        exit()
    app.run(debug=True, host="0.0.0.0")
