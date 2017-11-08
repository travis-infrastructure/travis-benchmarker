#!/bin/bash

# TODO: pull from nonexistent queue
sentinel_line="listening at localhost:6060"

run_instances_cmd="$(go run userdata.go)"

echo $run_instances_cmd

result="$(exec $run_instances_cmd)"
echo "$result"
