# Generate `aws ec2 run-instances` commands

## Usage

`./benchmark.sh 5 standard`

This will:

- look in the `standard/` subdirectory for `cloud-config.yml` and `cloud-init.sh`
- compress these into a file to be passed as userdata
- spin up 5 instances with the compressed userdata
- (TODO) start an ngrok listener to capture output from instances as they complete cloud-init (because the output of `aws ec2 get-console-output` is not reliable).

## To do

- finish `listener.py`
- modify to use `docker import` (or load or whatever) instead of `docker pull`
- modify to use other graph drivers
