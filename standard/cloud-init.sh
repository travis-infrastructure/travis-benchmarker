#!/usr/bin/env bash
# vim:filetype=sh
# set -o errexit
set -o pipefail
shopt -s nullglob
#set -x

__extra() {
  run_d="$1"
  # Remove 'set -o errexit' from /var/tmp/travis-run.d/travis-worker-prestart-hook
  sed -i 's/set -o errexit//g' "${run_d}/travis-worker-prestart-hook"
}

__uptime_in_secs() {
  printf "%.0f\n" "$(awk '{ print $1}' /proc/uptime)"
}

__mark() {
  now=$(__uptime_in_secs)
  msg="$1"
  echo "$now    $msg" >> /tmp/stopwatch
}

__prestart_hook() {
  TIME=/usr/bin/time
  TIME_FORMAT="-f %E\t%C"
  TIME_ARGS="--output=/tmp/stopwatch"
  source /etc/default/travis-worker-cloud-init
  $TIME --append $TIME_ARGS $TIME_FORMAT /var/tmp/travis-run.d/travis-worker-prestart-hook
}

__finish() {
  cat /tmp/stopwatch | wall
  __post_to_ngrok '{"finished": '"$(tail -n1 /tmp/stopwatch)"', 'instance_id': '$(cat /var/tmp/travis-run.d/instance_id)'}'
}

__post_to_ngrok() {
  curl -X POST -d "$@" soulshake.ngrok.io
}

main() {
  TIME=/usr/bin/time
  TIME_FORMAT="-f %E\t%C"
  TIME_ARGS="--output=/tmp/stopwatch"
  __post_to_ngrok "{'start': '$(date)', 'instance_id': '$(cat /var/tmp/travis-run.d/instance_id)'}"

  __mark "Starting cloud-init."
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

  __mark "Setting up init."
  if [[ -d "${ETCDIR}/systemd/system" ]]; then
    cp -v "${VARTMP}/travis-worker.service" \
      "${ETCDIR}/systemd/system/travis-worker.service"
    systemctl enable travis-worker || true
  fi

  if [[ -d "${ETCDIR}/init" ]]; then
    cp -v "${VARTMP}/travis-worker.conf" \
      "${ETCDIR}/init/travis-worker.conf"
  fi

  __mark "Stopping travis-worker."
  service travis-worker stop || true
  __mark "Starting travis-worker."
  $TIME --append $TIME_ARGS $TIME_FORMAT service travis-worker start || true

  iptables -t nat -I PREROUTING -p tcp -d '169.254.169.254' \
    --dport 80 -j DNAT --to-destination '192.0.2.1'

  __mark "Waiting for docker"
  __wait_for_docker
  __mark "Docker now ready"

  local registry_hostname
  registry_hostname="$(cat "${RUNDIR}/registry-hostname")"

  set +o pipefail
  set +o errexit
  dig +short "${registry_hostname}" | while read -r ipv4; do
    iptables -I DOCKER -s "${ipv4}" -j DROP || true
  done
  __mark "Done with cloud-init"

  __mark "Starting prestart hook"
  __prestart_hook
  __mark "Finished"
  __finish
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

main "$@"
