#!/bin/bash

count="$1"
[ -z "$count" ] && echo "Provide a count for each matrix combination (2 * 3 * 4 * COUNT)" && exit 1

instance_types=(
  "c3.2xlarge"
  "c3.8xlarge"
  "r4.8xlarge"
  "c5.9xlarge"
)

docker_methods=(
  "pull-hub"
  "pull-mirror"
  "import"
)

graph_drivers=(
  "overlay2"
  "devicemapper"
)

instance_types=( $(shuf -e "${instance_types[@]}") )
docker_methods=( $(shuf -e "${docker_methods[@]}") )
graph_drivers=( $(shuf -e "${graph_drivers[@]}") )

for instance_type in ${instance_types[@]}; do
  for docker_method in ${docker_methods[@]}; do
    for graph_driver in ${graph_drivers[@]}; do
      cmd="./benchmark.sh $count $instance_type $docker_method $graph_driver"
      echo "$cmd" | bash
      # sleep 400
    done
  done
done
