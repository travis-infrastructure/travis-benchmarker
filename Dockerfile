FROM python:3.6.3

WORKDIR /src
COPY requirements.txt .
RUN pip install -r requirements.txt 
COPY . /src
ENTRYPOINT ["python", "listener.py"]

# USAGE:

# Use ngrok to listen for calls home from spawned instances:
# ngrok http 80

# docker build -t benchmarker .
# docker run -ti -v $PWD:/src -p "80:5000" benchmarker
# curl -H "Content-Type: application/table" localhost
