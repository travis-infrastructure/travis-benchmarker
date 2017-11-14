from flask import Flask, request
import json
import os
app = Flask(__name__)

@app.route("/", methods=['GET', 'POST'])
def hello():
    if request.method == 'POST':
        data = json.loads(request.data)
        write_results(data)
    return "Recorded: {}\n".format(data)

def write_results(new):
    with open("results.json", "r") as f:
        existing = f.read()
    existing = json.loads(existing)

    instance_id = new.pop("instance_id")
    if instance_id in existing:
        existing[instance_id].update(new)
    else:
        existing[instance_id] = new

    with open("results.json", "w") as f:
        f.write(json.dumps(existing, indent=4))

def setup(results_filename="results.json"):
    if not os.path.isfile(results_filename):
        with open(results_filename, "a") as f:
            f.write("{}")

if __name__ == "__main__":
    setup()
    app.run(debug=True)
