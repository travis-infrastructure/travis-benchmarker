#!/bin/bash

# TODO: pull from nonexistent queue


update() {
    instance_id="$1"
    mkdir -p "instances/$instance_id"
    log="$(aws ec2 get-console-output --instance-id $instance_id | jq '.Output' -r)"
    echo "$log" > "instances/$instance_id/$instance_id.log"
}

all_ids() {
    ids=$(aws ec2 describe-instances --filters "Name=tag:role,Values=aj-test" \
        'Name=instance-state-name,Values=running' \
        --query 'Reservations[].Instances[?LaunchTime>=`2017-10-01`][].{id: InstanceId, launched: LaunchTime, ip: PrivateIpAddress}' \
        --output json |
        jq '.[].id' | tr -d '"' | sort)

    echo "$ids"
}

all_ips() {
    ips=$(aws ec2 describe-instances --filters "Name=tag:role,Values=aj-test" \
        'Name=instance-state-name,Values=running' \
        --query 'Reservations[].Instances[?LaunchTime>=`2017-10-01`][].{id: InstanceId, launched: LaunchTime, ip: PrivateIpAddress}' \
        --output json |
        jq '.[].ip' | tr -d '"' | sort)

    echo "$ips"
}

__make_cohort() {
    for i in $(seq 1 $cohort_size); do
        run_instances_cmd="$(go run userdata.go)"
        echo "======== $i ========"
        result="$(echo $run_instances_cmd | bash)"

        instance_ip=$(echo "$result" | jq .Instances[].NetworkInterfaces[].PrivateIpAddresses[].PrivateIpAddress | tr -d '"')
        instance_id=$(echo "$result" | jq .Instances[].InstanceId | tr -d '"')

        mkdir -p "instances/$instance_id"
        echo "$result" > "instances/$instance_id/$instance_ip.json"
    done
}

__wait_for_cohort_running() {
    num=$(echo "$(all_ips)" | wc -l)
    while [ $num -lt $1 ]; do
        echo "$num instances online, sleeping 5"
        sleep 5
    done
}

__wait_for_cohort_provisioned() {
    cohort_size=$1
    ids="$(all_ids)"
    done=0
    while [ $done -lt $cohort_size ]; do
        for id in "$ids"; do
            ok=$(grep $cloud_init_sentinel instances/)
        done
    done
}

for dir in matrix/*; do
    for f in $dir/*; do
        echo $(basename $f)
        encoded=$(cat $f | base64 --wrap=0)
    done
done

#cloud_init_sentinel="d4041f41adcc: Pull complete"
#worker_sentinel="listening at localhost:6060"

main() {
    cohort_size="$1"
    [ -z "$cohort_size" ] && echo "Please provide a cohort size" && exit
    if [ "$cohort_size" -eq 0 ]; then
        ids="$(all_ids)"
        for id in $ids; do
            echo "updating $id"
            update $id
        done
        exit
    fi

    __make_cohort "$cohort_size"
    __wait_for_cohort_running "$cohort_size"
    #__wait_for_cohort_provisioned "$cohort_size"
}

main "$@"
