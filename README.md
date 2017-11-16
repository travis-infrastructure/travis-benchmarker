# Benchmark EC2 instances

## Usage

### Start the listener and ngrok

This will start a basic local webserver that will the instances will send benchmark data to:

- `python listener.py`
- `ngrok http --subdomain soulshake 5000`

You can test the listener as follows:

- `curl -H "Content-Type: application/json" -X POST -d '{"instance_id": "i-foo", "finished": "mraaa"}' http://soulshake.ngrok.io`
- `python listener.py --show`

Note: `soulshake.ngrok.io` is currently hardcoded.

### Run the benchmark

`./benchmark.sh COUNT standard INSTANCE_TYPE DOCKER_METHOD`

Where:

`COUNT` is the number of instances to create

`INSTANCE_TYPE` is one of:
- `c3.2xlarge`
- `c3.8xlarge`
- `c5.9xlarge` (FIXME)
- `r4.8xlarge` (FIXME)

`DOCKER_METHOD` is one of:
- `pull`
- `import`

This will:

- look in the `standard/` subdirectory for `cloud-config.yml` and `cloud-init.sh`
- manipulate these files according to the `DOCKER_METHOD` provided
- compress these into a file to be passed as userdata
- spin up `COUNT` instances with the compressed userdata

Don't forget to start an ngrok listener to capture output from instances as they complete cloud-init. (This is a workaround for the unreliability of `aws ec2 get-console-output` for benchmarking purposes.)

## To do

- modify to use other graph drivers
- get `FIXME` instance types working

## See also

Potentially useful files for benchmarking purposes:

- `/var/lib/cloud/data/status.json`
- `/var/lib/cloud/instance/user-data.txt`
- `/var/lib/cloud/instance/boot-finished`
