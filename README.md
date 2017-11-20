# Benchmark EC2 instances

## Usage

### Start the listener and ngrok

This will start a basic local webserver that will the instances will send benchmark data to:

- `docker build -t benchmarker .`
- `docker run -ti -v $PWD:/src -p "80:5000" benchmarker`
- `ngrok http 80` (replace `soulshake.ngrok.io` below with the domain ngrok provides you)

You can test the listener as follows:

- `curl -H "Content-Type: application/table" soulshake.ngrok.io`

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
- manipulate these files according to the `DOCKER_METHOD` and write to `data/user-data.multipart`
- compress `data/user-data.multipart` into `data/user-data.multipart.gz` to be passed as userdata
- spin up `COUNT` instances with the compressed userdata

Don't forget to start an ngrok listener to capture output from instances as they complete cloud-init. (This is a workaround for the unreliability of `aws ec2 get-console-output` for benchmarking purposes.)

## To do

- get `FIXME` instance types working

## See also

Potentially useful files for benchmarking purposes on EC2 instances:

- `/var/lib/cloud/data/status.json`
- `/var/lib/cloud/instance/user-data.txt`
- `/var/lib/cloud/instance/boot-finished`
