# Benchmark EC2 instances

This script automates starting a few EC2 instances that will pull two big
(~10GB) Docker images. The goal is to find which combination of instance
type/storage driver / etc. yields the faster setup time.

The instances will report benchmark results to a local web server.

## Usage

### Start the listener and ngrok

This will start a basic local webserver to which the instances will send benchmark data:

- `docker-compose up`

You can test the listener in the following ways:

- `curl soulshake.ngrok.io`
- For JSON: `curl -H "Content-Type: application/json" soulshake.ngrok.io`

`soulshake.ngrok.io` is hardcoded in `docker-compose.yml`. Remove or replace with your own ngrok subdomain.

### Run the benchmark

`./benchmark.sh <COUNT> <INSTANCE_TYPE> <DOCKER_METHOD> <STORAGE_DRIVER>`

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

`STORAGE_DRIVER` is one of:
- `devicemapper`
- `overlay2`

This will:

- look in the `data/` subdirectory for `cloud-config.yml` and `cloud-init.sh`
- manipulate these files and generate a Docker config json according to the `DOCKER_METHOD` and write to `data/user-data.multipart`
- compress `data/user-data.multipart` into `data/user-data.multipart.gz` to be passed as userdata
- spin up `COUNT` instances with the compressed userdata

Don't forget to run `docker-compose up` to start an ngrok listener to capture output from instances as they complete cloud-init. (This is a workaround for the unreliability of `aws ec2 get-console-output` for benchmarking purposes.)

## To do

- get `FIXME` instance types working

## See also

Potentially useful files for benchmarking purposes on EC2 instances:

- `/var/lib/cloud/data/status.json`
- `/var/lib/cloud/instance/user-data.txt`
- `/var/lib/cloud/instance/boot-finished`
