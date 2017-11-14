from flask import Flask, request
app = Flask(__name__)

@app.route("/", methods=['GET', 'POST'])
def hello():
    if request.method == 'POST':
        data = request.form
        print_results(data)
    return "Thanks!"

def print_results(data):
    for k in data:
        print("{}: {}".format(k, data[k]))

def write_results(data):
    with open("results.json", "a") as f:
        existing = f.read()
    current = json.loads(existing)
    instance_id = data["instance_id"]
    del(data["instance_id"])
    if instance_id not in existing:
        existing[instance_id] = {}
    for k in data:
        existing[instance_id][k] = data[k]
    with open("results.json", "a") as f:
        f.write(existing)

if __name__ == "__main__":
    app.run(debug=True)
