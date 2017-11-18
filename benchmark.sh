#!/bin/bash

make_multipart() {
  instance_type="$1"
  docker_method="$2"
  docker_volume_type="$3"
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

  ####################
  ### cloud-config ###
  ####################
  echo "$HEADER" >"$dest"
  benchmark_env="$(make_benchmark_env "$docker_method" "$docker_volume_type" | base64 -w 0)"

  docker_upstart_file="data/upstarts/docker.conf"
  ensure_exists "$docker_upstart_file"
  docker_upstart="$(base64 -w 0 "$docker_upstart_file")"

  local_daemon_config_file="data/docker-daemon-jsons/daemon-$docker_volume_type.json"
  ensure_exists "$local_daemon_config_file"
  local_daemon_config="$(base64 -w 0 "$local_daemon_config_file")"

  docker_volume_setup_file="data/volume-setups/$docker_volume_type"
  ensure_exists "$docker_volume_setup_file"
  docker_volume_setup="$(base64 -w 0 "$docker_volume_setup_file")"

  prestart_hook_file="$label/prestart-hooks/docker-$docker_method.sh"
  ensure_exists "$prestart_hook_file"
  prestart_hook="$(base64 -w 0 "$prestart_hook_file")"

  sed "s@__DOCKER_METHOD__@$(echo "$prestart_hook")@; \
    s@__BENCHMARK_ENV__@$(echo "$benchmark_env")@; \
    s@__DOCKER_UPSTART__@$(echo "$docker_upstart")@; \
    s@__DOCKER_VOLUME_SETUP__@$(echo "$docker_volume_setup")@; \
    s@__DOCKER_DAEMON_JSON__@$(echo "$local_daemon_config")@; \
    s@__DOCKER_VOLUME_TYPE__@$(echo "$docker_volume_type")@" \
    "${label}/cloud-config.yml" \
    >>"$dest"

  ##################
  ### cloud-init ###
  ##################
  echo "$BOUNDARY" >>"$dest"
  echo "$(cat "${label}/cloud-init.sh")" >>"$dest"
  echo "$FOOTER" >>"$dest"

  gzip -f "$dest"
}

make_benchmark_env() {
  docker_method="$1"
  docker_volume_type="$2"

  docker_config_file="data/docker-daemon-jsons/daemon-$docker_volume_type.json"
  docker_config_file_dest="/etc/docker/daemon-${docker_volume_type}.json"

  ensure_exists "$docker_config_file" "provided docker volume type --> config file doesn't exist: $docker_config_file"

  prestart_hook="/var/tmp/travis-run.d/travis-worker-prestart-hook"
  if [[ "$docker_method" == "import" ]]; then
    prestart_hook="/var/tmp/travis-run.d/travis-worker-prestart-hook-docker-import"
  fi

  sed "s@__DOCKER_METHOD__@$docker_method@; \
    s@__DOCKER_CONFIG__@$docker_config_file_dest@;
    s@__DOCKER_VOLUME_TYPE__@$docker_volume_type@;
    s@__PRESTART_HOOK__@$prestart_hook@" \
    "${label}/benchmark.env"
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

  make_multipart "$instance_type" "$docker_method" "$docker_volume_type"
  #stderr_echo "EXITING" && exit

  for _ in $(seq 1 "$cohort_size"); do
    run_instances_cmd="$(run_instances "$instance_type" "$docker_method")"
    echo "$run_instances_cmd"
    echo "$run_instances_cmd" | bash > last_instance.json
  done
}

ensure_exists() {
  filename="$1"
  msg="$2"
  if [ ! -e "$filename" ]; then
    [ ! -z "$msg" ] && die "$msg"
    die "File does not exist: $filename"
  fi
}

main() {
  count="$1"
  instance_type="$2"
  docker_method="$3"
  docker_volume_type="$4"

  [ -z "$count" ] && die "Please provide a count of instances to create."
  [ -z "$instance_type" ] && die "Please provide an instance type as a second argument"
  [ -z "$docker_method" ] && die "Please provide docker method (pull, import) as third argument"
  [ -z "$docker_volume_type" ] && die "Please provide docker volume type (sic) as fourth argument (direct-lvm, overlay2)"
  ensure_exists "data/docker-daemon-jsons/daemon-$docker_volume_type.json" "provided docker volume type --> config file doesn't exist: data/docker-daemon-jsons/$docker_volume_type"

  make_cohort "$count" "$instance_type" "$docker_method" "$docker_volume_type"
}

main "$@"
