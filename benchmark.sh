#!/bin/bash

# TODO: pull from nonexistent queue



for dir in matrix/*; do
    for f in $dir/*; do
        echo $(basename $f)
        encoded=$(cat $f | base64 --wrap=0)
        echo "$encoded"
    done
done

exit
cloud_init_sentinel="d4041f41adcc: Pull complete"
worker_sentinel="listening at localhost:6060"

run_instances_cmd="$(go run userdata.go)"

#result="$(echo $run_instances_cmd | bash)"
result="$(cat instance.json)"

instance_ip=$(echo "$result" | jq .Instances[].NetworkInterfaces[].PrivateIpAddresses[].PrivateIpAddress | tr -d '"')
instance_id=$(echo "$result" | jq .Instances[].InstanceId | tr -d '"')

mkdir -p "instances/$instance_ip"
echo "$result" > "instances/$instance_ip/$instance_ip.json"

log="$(aws ec2 get-console-output --instance-id $instance_id | jq '.Output' -r)"
echo "$log" > "instances/$instance_ip/$instance_ip.log"

all_ips=$(aws ec2 describe-instances --filters "Name=tag:role,Values=aj-test" \
    'Name=instance-state-name,Values=running' \
    --query 'Reservations[].Instances[?LaunchTime>=`2017-10-01`][].{id: InstanceId, launched: LaunchTime, ip: PrivateIpAddress}' \
    --output json |
    jq '.[].ip' | tr -d '"' | sort)

echo "$all_ips"
