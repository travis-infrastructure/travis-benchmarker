# Generate `aws ec2 run-instances` commands

## Usage

`go run userdata.go`

This will generate two files:

- `user-data.multipart.gz`
- `user-data.multipart`

And will also output an `aws ec2 run-instances` command that can be run to create the instance with the associated userdata.

## To do

- figure out how to time instance launch
- modify to use `docker load` (or import or whatever) instead of `docker pull`
- modify to use other graph drivers
