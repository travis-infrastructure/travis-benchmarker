#!/bin/bash

make_multipart() {
  instance_type="$1"
  docker_method="$2"
  label="data"

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

  dest="$(make_multipart_dest)"

  ##################
  ### cloud-init ###
  ##################
  echo "$HEADER" >"$dest"
  sed "s@__DOCKER_IMPORT__@$(base64 $label/prestart-hooks/docker-import.sh -w 0)@; \
    s@__DOCKER_PULL__@$(base64 $label/prestart-hooks/docker-pull.sh -w 0)@" \
    "${label}/cloud-config.yml" \
    >>"$dest"

  ####################
  ### cloud-config ###
  ####################
  echo "$BOUNDARY" >>"$dest"
  sed "s@__DOCKER_METHOD__@export DOCKER_METHOD='$docker_method'@" \
    "${label}/cloud-init.sh" \
    >>"$dest"
  echo "$FOOTER" >>"$dest"

  gzip -f "$dest"
}

make_multipart_dest() {
  label="data"
  dest="${label}/user-data.multipart"
  echo "$dest"
}

run_instances() {
  instance_type="$1"
  docker_method="$2"
  label="data"
  # This can be gp2 for General Purpose SSD, io1 for Provisioned IOPS SSD, st1 for Throughput Optimized HDD, sc1 for Cold HDD, or standard for Magnetic volumes.
  # subnet-2e369b67 => us-east-1b
  # subnet-addd3791 => us-east-1e (io1 not supported in this AZ)

  dest="$(make_multipart_dest).gz"
  cmd="echo -n aws ec2 run-instances \
    --region us-east-1 \
    --placement 'AvailabilityZone=us-east-1b' \
    --key-name aj \
    --image-id ami-a43c8dde \
    --instance-type "$instance_type" \
    --security-group-ids "sg-4e80c734" "sg-4d80c737" \
    --subnet-id subnet-2e369b67 \
    --tag-specifications '\"ResourceType=instance,Tags=[{Key=role,Value=aj-test},{Key=instance_type,Value="$instance_type"},{Key=docker_method,Value="$docker_method"}]\"' \
    --client-token '$(cat /proc/sys/kernel/random/uuid)' \
    --user-data 'fileb://'$(make_multipart_dest)'.gz '"

  # Note: --block-device-mappings can also be provided as a file, e.g. file://${label}/mapping.json
  # To override the AMI default, use "NoDevice="
  case "$instance_type" in
  c3.2xlarge)
    ;;
  c3.8xlarge)
    # c3.8xlarge + instance store SSD
    cmd="$cmd --block-device-mappings "NoDevice='""'""
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
  *)
    die "Unknown instance type $instance_type"
    ;;
  esac
  eval "$cmd"
}

stderr_echo() {
  >&2 echo "$@"
}

die() {
  usage="$0 COUNT INSTANCE_TYPE"
  stderr_echo
  stderr_echo "USAGE: "
  stderr_echo "  $usage"
  stderr_echo
  stderr_echo "$(tput setaf 1) $* $(tput sgr0)"
  exit 1
}

make_cohort() {
  cohort_size="$1"
  label="data"
  instance_type="$2"
  docker_method="$3"

  make_multipart "$instance_type" "$docker_method"

  for _ in $(seq 1 "$cohort_size"); do
    run_instances_cmd="$(run_instances "$instance_type" "$docker_method")"
    echo "$run_instances_cmd"
    result="$(echo "$run_instances_cmd" | bash)"
    instance_ip=$(echo "$result" | jq .Instances[].NetworkInterfaces[].PrivateIpAddresses[].PrivateIpAddress | tr -d '"')
    instance_id=$(echo "$result" | jq .Instances[].InstanceId | tr -d '"')
    mkdir -p "$label/instances/$instance_id"
    echo "$result" >"$label/instances/$instance_id/$instance_ip.json"
  done
}

main() {
  count="$1"
  instance_type="$2"
  docker_method="$3"

  #[ -z "$label" ] && die "Please provide a label for this test, corresponding to a directory containing LABEL/cloud-init.sh and LABEL/cloud-config.yml."
  #[ ! -d "$label" ] && die "Directory $label not found."
  [ -z "$count" ] && die "Please provide a count of instances to create."
  [ -z "$instance_type" ] && die "Please provide an instance type as a third argument"
  [ -z "$docker_method" ] && die "Please provide docker method (pull, import) as fourth rgument"

  make_cohort "$count" "$instance_type" "$docker_method"
}

main "$@"
