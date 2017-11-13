#!/bin/bash

make_multipart() {
  label="$1"
  read -r -d '' HEADER <<-EOF
Content-Type: multipart/mixed; boundary="MIMEBOUNDARY"
MIME-Version: 1.0
--MIMEBOUNDARY
Content-Disposition: attachment; filename="cloud-config"
Content-Transfer-Encoding: 7bit
Content-Type: text/cloud-config
Mime-Version: 1.0
#cloud-config
# vim:filetype=yaml
EOF

  read -r -d '' BOUNDARY <<EOF
--MIMEBOUNDARY
Content-Disposition: attachment; filename="cloud-init"
Content-Transfer-Encoding: 7bit
Content-Type: text/x-shellscript
Mime-Version: 1.0
EOF

  read -r -d '' FOOTER <<EOF
--MIMEBOUNDARY--
EOF

  dest="${label}/user-data.${label}.multipart"
  echo "$HEADER" >"$dest"
  cat "${label}/cloud-config.yml" >>"$dest"
  echo "$BOUNDARY" >>"$dest"
  cat "${label}/cloud-init.sh" >>"$dest"
  echo "$FOOTER" >>"$dest"

  gzip -f "$dest"
}

make_token() {
  cat /proc/sys/kernel/random/uuid
}

run_instances() {
  label="$1"
  echo aws ec2 run-instances \
    --region us-east-1 \
    --key-name aj \
    --image-id ami-a43c8dde \
    --instance-type c3.2xlarge \
    --security-group-ids "sg-4e80c734" "sg-4d80c737" \
    --subnet-id subnet-addd3791 \
    --tag-specifications "'ResourceType=instance,Tags=[{Key=role,Value=aj-test},{Key=label,Value='$label'}]'" \
    --client-token "$(make_token)" \
    --user-data 'fileb://'${label}'/user-data.'${label}'.multipart.gz' \
    --block-device-mappings "'DeviceName=/dev/sda1,VirtualName=/dev/xvdc,Ebs={DeleteOnTermination=true,SnapshotId=snap-05ddc125d72e3592d,VolumeSize=8,VolumeType=gp2}'"
}

die() {
  usage="$0 LABEL COUNT"
  echo "$@"
  echo "$usage"
  exit 1
}

make_cohort() {
  cohort_size="$1"
  label="$2"

  make_multipart "$label"

  for i in $(seq 1 $cohort_size); do
    run_instances_cmd="$(run_instances "$label")"
    result="$(echo "$run_instances_cmd" | bash)"
    instance_ip=$(echo "$result" | jq .Instances[].NetworkInterfaces[].PrivateIpAddresses[].PrivateIpAddress | tr -d '"')
    instance_id=$(echo "$result" | jq .Instances[].InstanceId | tr -d '"')
    mkdir -p "$label/instances/$instance_id"
    echo "$result" >"$label/instances/$instance_id/$instance_ip.json"
  done
}

get_instance_log() {
  instance_id="$1"
  aws ec2 get-console-output --instance-id "$instance_id" | jq '.Output' -r
}

wait_for_cohort_running() {
  echo "Waiting for cohort to be running"
  count="$1"
  label="$2"
  num=0
  while [ "$num" -lt "$count" ]; do
    num=$(echo "$(all_ids "$label")" | wc -l)
    echo "have $num instances online, want $count, sleeping 5"
    sleep 5
  done
}

vm_is_provisioned() {
  instance_id="$1"
  sentinel="d4041f41adcc: Pull complete"
  if [[ "$(get_instance_log "$instance_id")" == *"$sentinel"* ]]; then
    return 0
  fi
  return 1
}

wait_for_cohort_provisioned() {
  count="$1"
  label="$2"
  ids="$(all_ids "$label")"
  num=0

  done=""
  done_count=0
  while true; do
    for iid in $ids; do
      [[ "$done" == *"$iid" ]] && continue

      if ! vm_is_provisioned "$iid"; then
        echo "$iid not done yet"
      else
        echo "$iid is done! $(time_since_launch "$iid") since launch"
        done="$done $iid"
        done_count=$((done_count + 1))
      fi
    done

    if [ "$done_count" -ge "$count" ]; then
      break
    fi

    echo "Have $done_count provisioned, want $count, sleeping 5 (elapsed: $(date -d@$SECONDS -u +%H:%M:%S))"
    sleep 5
  done

  echo "Done!"
}

time_since_launch() {
  now=$(date "+%s")
  launch_time="$(aws ec2 describe-instances --instance-id "$1" | jq .Reservations[].Instances[].LaunchTime | tr -d '"')"
  result=$(($now - $(date --date="$launch_time" "+%s")))
  echo "$(date -d@$result -u +%H:%M:%S)"
}

get_instance_launch_time() {

  aws ec2 describe-instances --instance-id "$1" | jq .Reservations[].Instances[].LaunchTime | tr -d '"'
  # date --date="$x" "+%s"
}

all_ids() {
  label="$1"
  ids=$(aws ec2 describe-instances --filters "Name=tag:role,Values=aj-test" \
    'Name=instance-state-name,Values=running' \
    "Name=tag:label,Values=$label" \
    --query 'Reservations[].Instances[?LaunchTime>=`2017-10-10`][].{id: InstanceId, launched: LaunchTime, ip: PrivateIpAddress}' \
    --output json |
    jq '.[].id' | tr -d '"' | sort)

  echo "$ids"
}

main() {
  count="$1"
  label="$2"
  [ -z "$label" ] && die "Please provide a label for this test, corresponding to a directory containing LABEL/cloud-init.sh and LABEL/cloud-config.yml."
  [ ! -d "$label" ] && die "Directory $label not found."
  [ -z "$count" ] && die "Please provide a count of instances to create."

  make_cohort "$count" "$label"
  wait_for_cohort_running "$count" "$label"
  wait_for_cohort_provisioned "$count" "$label"
}

#run_instances standard
main "$@"
#!/bin/bash
