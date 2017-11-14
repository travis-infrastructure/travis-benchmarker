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

if __name__ == "__main__":
    app.run(debug=True)
