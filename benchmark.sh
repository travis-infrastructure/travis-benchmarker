#!/bin/bash

die() {
  echo "
USAGE:
  $0 COUNT INSTANCE_TYPE DOCKER_METHOD STORAGE_DRIVER

  Where:

  COUNT: Number of instances to create

  INSTANCE_TYPE:
    - c3.2xlarge
    - c3.8xlarge
    - r4.8xlarge
    - c5.9xlarge

  DOCKER_METHOD:
    - pull
    - import

  GRAPH_DRIVER:
    - overlay2
    - devicemapper

$(tput setaf 1) $* $(tput sgr0)" >/dev/stderr

  exit 1
}

ensure_exists() {
  filename="$1"
  msg="$2"
  [ -e "$filename" ] && return
  [ ! -z "$msg" ] && die "$msg"
  die "File does not exist: $filename"
}

make_multipart() {
  instance_type="$1"
  docker_method="$2"
  docker_graph_driver="$3"
  cohort_size="$4"

  read -r -d '' HEADER <<EOF
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

  dest="data/user-data.multipart"

  ####################
  ### cloud-config ###
  ####################
  echo "$HEADER" >"$dest"

  # # TODO: This will output a snippet on stdout
  # write_file() {
  #   local_path=$1
  #   instance_path=$2
  #   # ensure_exists $local_path
  #   cat <<EOF
  # - content: $(base64 -w0 $local_path)
  #   encoding: b64
  #   ...
  #   path: $instance_path
  # EOF
  # }

  docker_upstart_file="data/upstarts/docker.conf"
  docker_volume_setup_file="data/volume-setups/$docker_graph_driver"
  prestart_hook_file="data/prestart-hooks/docker-$docker_method.sh"

  ensure_exists "$docker_upstart_file"
  ensure_exists "$docker_volume_setup_file"
  ensure_exists "$prestart_hook_file"

  docker_upstart="$(base64 -w 0 "$docker_upstart_file")"
  docker_daemon_config="$(make_docker_daemon_json "$docker_graph_driver" "$docker_method" | base64 -w 0)"
  docker_volume_setup="$(base64 -w 0 "$docker_volume_setup_file")"
  prestart_hook="$(base64 -w 0 "$prestart_hook_file")"
  benchmark_env="$(make_benchmark_env "$docker_method" "$docker_graph_driver" "$cohort_size" | base64 -w 0)"

  # shellcheck disable=SC2129
  sed "
    s@__DOCKER_METHOD__@$prestart_hook@
    s@__BENCHMARK_ENV__@$benchmark_env@
    s@__DOCKER_UPSTART__@$docker_upstart@
    s@__DOCKER_DAEMON_JSON__@$docker_daemon_config@
    s@__DOCKER_VOLUME_SETUP__@$docker_volume_setup@
    s@__DOCKER_GRAPH_DRIVER__@$docker_graph_driver@
    " data/cloud-config.yml \
    >>"$dest"

  ##################
  ### cloud-init ###
  ##################
  echo "$BOUNDARY" >>"$dest"
  cat data/cloud-init.sh >>"$dest"
  echo "$FOOTER" >>"$dest"

  gzip -f "$dest"
}

make_docker_daemon_json() {
  docker_graph_driver="$1"
  docker_method="$2"

  docker_daemon_config='
  "data-root": "/mnt/docker",
  "hosts": [
    "tcp://127.0.0.1:4243",
    "unix:///var/run/docker.sock"
  ],
  "icc": false,
  "insecure-registries": [
    "10.0.0.0/8"
  ],
  "max-concurrent-downloads": 2,
  "registry-mirrors": ["http://registry-shared-1.aws-us-east-1.travisci.net"],
  "userns-remap": "default",
  "debug": true,
'

  case "$docker_graph_driver" in
  devicemapper)
    docker_daemon_config=''$docker_daemon_config'
  "storage-driver": "devicemapper",
  "storage-opts": [
    "dm.basesize=12G",
    "dm.datadev=/dev/direct-lvm/data",
    "dm.metadatadev=/dev/direct-lvm/metadata",
    "dm.fs=xfs"
  ]
'
    ;;
  overlay2)
    docker_daemon_config=''$docker_daemon_config'
  "storage-driver": "overlay2"
'
  ;;
  *)
    die "Couldn't make docker daemon json"
    ;;
  esac

  docker_daemon_config="{$docker_daemon_config}"

  if [[ "$docker_method" == "pull-hub" ]]; then
    docker_daemon_config="$(echo "$docker_daemon_config" | sed 's/.*registry-mirrors.*//')"
  fi

  #if [[ "$instance_type" == "" ]]; then
  #fi

  echo "$docker_daemon_config"
}

make_benchmark_env() {
  docker_method="$1"
  docker_graph_driver="$2"
  cohort_size="$3"
  docker_config_file_dest="/etc/docker/daemon-${docker_graph_driver}.json"

  sed "
    s@__DOCKER_METHOD__@$docker_method@
    s@__DOCKER_CONFIG__@$docker_config_file_dest@
    s@__COHORT_SIZE__@$cohort_size@
    s@__DOCKER_GRAPH_DRIVER__@$docker_graph_driver@
    " data/benchmark.env
}

run_instances() {
  instance_type="$1"
  docker_method="$2"
  count="$3"
  graph_driver="$4"
  # This can be gp2 for General Purpose SSD, io1 for Provisioned IOPS SSD, st1 for Throughput Optimized HDD, sc1 for Cold HDD, or standard for Magnetic volumes.
  # subnet-2e369b67 => us-east-1b
  # subnet-addd3791 => us-east-1e (io1 not supported in this AZ)
  # subnet-2f369b66 => production?

  cmd="aws ec2 run-instances \
    --region us-east-1 \
    --placement 'AvailabilityZone=us-east-1b' \
    --key-name aj \
    --count '$count' \
    --image-id ami-a43c8dde \
    --instance-type '$instance_type' \
    --security-group-ids sg-acad2ed9 sg-48d59c32 \
    --subnet-id subnet-2e369b67 \
    --user-data fileb://data/user-data.multipart.gz \
    --tag-specifications "'"ResourceType=instance,Tags=[\{Key=role,Value=aj-test\},\{Key=instance_type,Value='$instance_type'\},\{Key=docker_method,Value='$docker_method'\},\{Key=cohort_size,Value='$count'\}]"'""

  # Note: --block-device-mappings can also be provided as a file, e.g. file://${label}-mapping.json
  # To override the AMI default, use "NoDevice="
  case "$instance_type" in
  c3.2xlarge) ;;

  c3.8xlarge)
    # c3.8xlarge + instance store SSD
    # FIXME        ^
    cmd=''$cmd' --block-device-mappings "NoDevice=\"\""'
    ;;
  c5.9xlarge)
    # c5.9xlarge + ebs io1 volume
    iops=2000
    if [[ "$graph_driver" == "devicemapper" ]]; then
        device_name="xvdc"
    elif [[ "$graph_driver" == "overlay2" ]]; then
        device_name="sda1"
    else
        die "Unknown graph driver $graph_driver"
    fi
    #device_name="sda1"
    cmd=''"$cmd"' --block-device-mappings \"DeviceName=/dev/'$device_name',Ebs=\{DeleteOnTermination=true,VolumeSize=80,VolumeType=io1,Iops='$iops'\}\"'
    ;;
  r4.8xlarge)
    # r4.8xlarge + in-memory docker
    cmd=''"$cmd"' --block-device-mappings "NoDevice=\"\""'
    ;;
  *)
    die "Unknown instance type $instance_type"
    ;;
  esac

  eval "echo $cmd"
}

make_cohort() {
  cohort_size="$1"
  instance_type="$2"
  docker_method="$3"

  make_multipart "$instance_type" "$docker_method" "$docker_graph_driver" "$cohort_size"

  run_instances_cmd="$(run_instances "$instance_type" "$docker_method" "$cohort_size" "$docker_graph_driver")"
  echo "$run_instances_cmd"
  echo "$run_instances_cmd" | bash >last_instance_run.json
}

main() {
  count="$1"
  instance_type="$2"
  docker_method="$3"
  docker_graph_driver="$4"

  [ -z "$count" ] && die "Please provide a count of instances to create."
  [ -z "$instance_type" ] && die "Please provide an instance type as a second argument."
  [ -z "$docker_method" ] && die "Please provide docker method (pull, import) as third argument."
  [ -z "$docker_graph_driver" ] && die "Please provide docker graph driver as fourth argument."

  case "$docker_method" in
  pull-hub | pull-mirror | import) ;;
  *)
    die "Invalid docker method '$docker_method' (expected: pull-hub, pull-mirror, import)"
    ;;
  esac

  case "$docker_graph_driver" in
  overlay2 | devicemapper) ;;
  *)
    die "Invalid graph driver '$docker_graph_driver' (expected: overlay2, devicemapper)"
    ;;
  esac

  make_cohort "$count" "$instance_type" "$docker_method" "$docker_graph_driver"
}

main "$@"
