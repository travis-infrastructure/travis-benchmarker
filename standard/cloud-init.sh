#!/usr/bin/env bash
# vim:filetype=sh
# set -o errexit
set -o pipefail
shopt -s nullglob
#set -x

__extra() {
  run_d="$1"
  # Remove 'set -o errexit' so we can see if something goes wrong
  sed -i 's/set -o errexit//g' "${run_d}/travis-worker-prestart-hook"
  sed -i 's/set -o errexit//g' "${run_d}/travis-worker-prestart-hook-docker-import"

  # Use a fake queue
  sed -i 's/builds.ec2/builds.fake/' "/etc/default/travis-worker"

  # Specify prestart hook here
  #sed -i 's@export TRAVIS_WORKER_PRESTART_HOOK="/var/tmp/travis-run.d/travis-worker-prestart-hook"@export TRAVIS_WORKER_PRESTART_HOOK="/var/tmp/travis-run.d/travis-worker-prestart-hook-docker-import"@' /etc/default/travis-worker-cloud-init
}

__uptime_in_secs() {
  printf "%.0f\n" "$(awk '{ print $1}' /proc/uptime)"
}

__prestart_hook() {
  TIME=/usr/bin/time
  TIME_FORMAT="-f %E\t%C"
  TIME_ARGS="--output=/tmp/stopwatch"
  source /etc/default/travis-worker-cloud-init

  if [[ "$DOCKER_METHOD" == "pull" ]]; then
    logger "DOCKER_METHOD IS PULL"
    $TIME --append $TIME_ARGS $TIME_FORMAT /var/tmp/travis-run.d/travis-worker-prestart-hook
  elif [[ "$DOCKER_METHOD" == "import" ]]; then
    logger "DOCKER_METHOD IS IMPORT"
    sed -i 's@.*TRAVIS_WORKER_PRESTART_HOOK.*@export TRAVIS_WORKER_PRESTART_HOOK="/var/tmp/travis-run.d/travis-worker-prestart-hook-docker-import"@' /etc/default/travis-worker-cloud-init
    sed -i 's@.*TRAVIS_WORKER_PRESTART_HOOK.*@export TRAVIS_WORKER_PRESTART_HOOK="/var/tmp/travis-run.d/travis-worker-prestart-hook-docker-import"@' /var/tmp/travis-run.d/travis-worker.env
    source /etc/default/travis-worker-cloud-init
    apt install -y lzop
    $TIME --append $TIME_ARGS $TIME_FORMAT /var/tmp/travis-run.d/travis-worker-prestart-hook-docker-import
  else
    logger "DOCKER_METHOD IS UNKNOWN!!!!!!!!!"
  fi
}

__mark() {
  action="$1"
  : "${RUNDIR:=/var/tmp/travis-run.d}"

  instance_id="$(cat "${RUNDIR}/instance-id")"
  instance_type="$(curl -sSL http://169.254.169.254/latest/meta-data/instance-type)"
  instance_ipv4="$(curl -sSL http://169.254.169.254/latest/meta-data/local-ipv4)"
  docker_method="$(cat /tmp/benchmark-docker-method)"
  graphdriver="$(docker info --format '{{ json .Driver }}' | tr -d '"')"
  filesystem="$(docker info --format '{{ index .DriverStatus 3 }}')"
  total_time="$(tail -n1 /tmp/stopwatch | awk '{print $1}')"
  mem_total="$(free -hm | grep ^Mem: | awk '{print $2}')"
  boot_time="$(cat /var/lib/cloud/data/status.json | grep start | head -n1 | awk '{print $2}' | tr -d ',')"
  boot_time="$(date -d@$boot_time +"%m/%d %H:%M:%S")"

  now="$(__uptime_in_secs)"
  data='{"instance_id":'\"$instance_id\"',"instance_ipv4":'\"$instance_ipv4\"','\"$action\"':'$now',"method":'\"$docker_method\"','
  data=''$data'"boot_time":'\"$boot_time\"',"instance_type":'\"$instance_type\"',"graphdriver":'\"$graphdriver\"','
  data=''$data'"filesystem":'\"$filesystem\"',"total":'\"$total_time\"',"mem":'\"$mem_total\"'}'

  __post_to_ngrok "$data"
}

__post_to_ngrok() {
  curl -H "Content-Type: application/json" -X POST -d "$@" soulshake.ngrok.io
}

main() {
  __mark "cloud-init-0-start"
  TIME=/usr/bin/time
  TIME_FORMAT="-f %E\t%C"
  TIME_ARGS="--output=/tmp/stopwatch"

  : "${ETCDIR:=/etc}"
  : "${VARTMP:=/var/tmp}"
  : "${RUNDIR:=/var/tmp/travis-run.d}"
  __extra "${RUNDIR}"

  local instance_id
  instance_id="$(cat "${RUNDIR}/instance-id")"

  for envfile in "${ETCDIR}/default/travis-worker"*; do
    sed -i "s/___INSTANCE_ID___/${instance_id}/g" "${envfile}"
  done

  __set_aio_max_nr

  chown -R travis:travis "${RUNDIR}"

  if [[ -d "${ETCDIR}/systemd/system" ]]; then
    cp -v "${VARTMP}/travis-worker.service" \
      "${ETCDIR}/systemd/system/travis-worker.service"
    systemctl enable travis-worker || true
  fi

  if [[ -d "${ETCDIR}/init" ]]; then
    cp -v "${VARTMP}/travis-worker.conf" \
      "${ETCDIR}/init/travis-worker.conf"
  fi

  service travis-worker stop || true
  $TIME --append $TIME_ARGS $TIME_FORMAT service travis-worker start || true

  iptables -t nat -I PREROUTING -p tcp -d '169.254.169.254' \
    --dport 80 -j DNAT --to-destination '192.0.2.1'

  __wait_for_docker

  local registry_hostname
  registry_hostname="$(cat "${RUNDIR}/registry-hostname")"

  set +o pipefail
  set +o errexit
  dig +short "${registry_hostname}" | while read -r ipv4; do
    iptables -I DOCKER -s "${ipv4}" -j DROP || true
  done

  __prestart_hook
  __mark "cloud-init-1-finish"
}

__wait_for_docker() {
  local i=0

  while ! docker version; do
    if [[ $i -gt 600 ]]; then
      exit 86
    fi
    start docker &>/dev/null || true
    sleep 10
    let i+=10
  done
}

__set_aio_max_nr() {
  # NOTE: we do this mostly to ensure file IO chatty services like mysql will
  # play nicely with others, such as when multiple containers are running mysql,
  # which is the default on precise + trusty.  The value we set here is 16^5,
  # which is one power higher than the default of 16^4 :sparkles:.
  sysctl -w fs.aio-max-nr=1048576
}

__DOCKER_METHOD__

main "$@"
