#!/bin/bash

make_multipart() {
  label="$1"
  instance_type="$2"

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
  # FIXME: add extra stuff here?
  echo "$FOOTER" >>"$dest"

  gzip -f "$dest"
}

make_token() {
  cat /proc/sys/kernel/random/uuid
}

run_instances() {
  label="$1"
  instance_type="$2"
  # This can be gp2 for General Purpose SSD, io1 for Provisioned IOPS SSD, st1 for Throughput Optimized HDD, sc1 for Cold HDD, or standard for Magnetic volumes.
  # subnet-2e369b67 => us-east-1b
  # subnet-addd3791 => us-east-1e (io1 not supported in this AZ)

  echo -n aws ec2 run-instances \
    --region us-east-1 \
    --placement 'AvailabilityZone=us-east-1b' \
    --key-name aj \
    --image-id ami-a43c8dde \
    --instance-type "$instance_type" \
    --security-group-ids "sg-4e80c734" "sg-4d80c737" \
    --subnet-id subnet-2e369b67 \
    --tag-specifications '"ResourceType=instance,Tags=[{Key=role,Value=aj-test},{Key=label,Value='$label'},{Key=instance_type,Value='$instance_type'}]"' \
    --client-token "$(make_token)" \
    --user-data 'fileb://'${label}'/user-data.'${label}'.multipart.gz '

  # Note: --block-device-mappings can also be provided as a file, e.g. file://${label}/mapping.json
  # To override the AMI default, use "NoDevice="
  case "$instance_type" in
  c3.2xlarge)
    ;;
  c3.8xlarge)
    # c3.8xlarge + instance store SSD
    echo --block-device-mappings "NoDevice=\"\""
    ;;
  c5.9xlarge)
    # c5.9xlarge + ebs io1 volume
    #echo --block-device-mappings "'DeviceName=/dev/sda1,VirtualName=/dev/xvdc,Ebs={DeleteOnTermination=true,SnapshotId=snap-05ddc125d72e3592d,VolumeSize=8,VolumeType=\"io1\",Iops=1000}'"
    echo --block-device-mappings "'DeviceName=/dev/sda1,VirtualName=/dev/xvdc,Ebs={DeleteOnTermination=true,VolumeSize=8,VolumeType=io1,Iops=100}'"
    # TODO: update docker-daemon.json because "Device /dev/xvdc not found"
    ;;
  r4.8xlarge)
    # r4.8xlarge + in-memory docker
    echo --block-device-mappings "NoDevice=\"\""
    ;;
  esac
}

die() {
  usage="$0 LABEL COUNT"
  echo "$@"
  echo "USAGE: "
  echo "  $usage"
  exit 1
}

make_cohort() {
  cohort_size="$1"
  label="$2"
  instance_type="$3"

  make_multipart "$label" "$instance_type"

  for i in $(seq 1 $cohort_size); do
    run_instances_cmd="$(run_instances "$label" "$instance_type")"
    echo "$run_instances_cmd"
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
  while true; do
    num=$(echo "$(all_ids "$label")" | wc -w)
    [ "$num" -ge "$count" ] && break
    echo "have $num instances online, want $count, sleeping 10"
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
  echo "Waiting for $count $label instances to be provisioned..."

  done=""
  done_count=0
  while true; do
    for iid in $ids; do
      [[ "$done" == *"$iid"* ]] && continue

      if vm_is_provisioned "$iid"; then
        echo "$iid is done! $(time_since_launch "$iid") since launch"
        done="$done $iid"
        done_count=$((done_count + 1))
      else
        echo "$iid not done yet"
      fi
    done

    [ "$done_count" -ge "$count" ] && break

    echo "Have $done_count provisioned, want $count, sleeping 5 (elapsed: $(date -d@$SECONDS -u +%H:%M:%S))"
    sleep 5
  done

  echo "Done!"
}

time_since_launch() {
  instance_id="$1"
  now=$(date "+%s")
  launch_time="$(aws ec2 describe-instances --instance-id "$instance_id" | jq .Reservations[].Instances[].LaunchTime | tr -d '"')"
  result=$(($now - $(date --date="$launch_time" "+%s")))
  echo "$(date -d@$result -u +%H:%M:%S)"
}

all_ids() {
  label="$1"
  instance_type="$2"
  ids=$(aws ec2 describe-instances --filters "Name=tag:role,Values=aj-test" \
    'Name=instance-state-name,Values=running' \
    "Name=tag:label,Values=$label" \
    "Name=tag:instance_type,Values=$instance_type" \
    --query 'Reservations[].Instances[?LaunchTime>=`2017-10-10`][].{id: InstanceId, launched: LaunchTime, ip: PrivateIpAddress}' \
    --output json |
    jq '.[].id' | tr -d '"' | sort)

  echo "$ids" | tee -a all_ids.asdfasdf
}

main() {
  count="$1"
  label="$2"
  instance_type="$3"


  [ -z "$label" ] && die "Please provide a label for this test, corresponding to a directory containing LABEL/cloud-init.sh and LABEL/cloud-config.yml."
  [ ! -d "$label" ] && die "Directory $label not found."
  [ -z "$count" ] && die "Please provide a count of instances to create."
  [ -z "$instance_type" ] && die "Please provide an instance type as a third argument"

  make_cohort "$count" "$label" "$instance_type"
  wait_for_cohort_running "$count" "$label"
  wait_for_cohort_provisioned "$count" "$label"
}

main "$@"
