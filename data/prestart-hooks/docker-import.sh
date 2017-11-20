#!/bin/bash
# vim:filetype=sh
set -x

main() {
  : "${RUNDIR:=/var/tmp/travis-run.d}"
  : "${POST_SHUTDOWN_SLEEP:=300}"

  set -o xtrace

  local i=0
  while ! docker version; do
    if [[ $i -gt 600 ]]; then
      exit 86
    fi
    sleep 10
    let i+=10
  done
  echo "==== BEFORE __docker_pre_import ===="
  # FIXME: Don't know where all these 0B images are coming from
  docker images
  echo "===================================="
  docker images | grep 0B$ | awk '{print $1 ":" $2}' | xargs docker rmi

  __docker_pre_import
  wait

  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_ANDROID" travis:android
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_DEFAULT" travis:default
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_ERLANG" travis:erlang
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_ERLANG" travis:elixir
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_GO" travis:go
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_HASKELL" travis:haskell
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_JVM" travis:jvm
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_JVM" travis:clojure
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_JVM" travis:groovy
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_JVM" travis:java
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_JVM" travis:scala
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_NODE_JS" travis:node-js
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_NODE_JS" travis:node_js
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_PERL" travis:perl
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_PHP" travis:php
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_PYTHON" travis:python
  __docker_import_tag "$TRAVIS_WORKER_DOCKER_IMAGE_RUBY" travis:ruby

}

__docker_pre_import() {
  images="
  travisci/ci-garnet:packer-1508249879-29cd77f
  travisci/ci-amethyst:packer-1508250117-29cd77f
  "
  docker images
  for image in $images; do
    if ! docker inspect "$image" >/dev/null; then
      curl -sSL "http://aj-benchmark.s3.amazonaws.com/${image}.tar.lzo" | lzop -d | docker import --message "New image imported from s3" - "${image}" &
    fi
  done
  wait
}

__docker_import_tag() {
  local image="$1"
  local tag="$2"

  [[ "$image" ]] || {
    echo 'Missing image name'
    return 1
  }

  set -o pipefail
  if ! docker inspect "$image" >/dev/null; then
    curl -sSL "http://aj-benchmark.s3.amazonaws.com/${image}.tar.lzo" | lzop -d | docker import --message "New image imported from s3" - "${image}"
  fi
  docker tag "${image}" "${tag}"
}

__docker_upload_tag() {
  local image="$1"

  [[ "$image" ]] || {
    echo 'Missing image name'
    return 1
  }

  CID=$(docker run -d "${image}" true)
  docker export "$CID" -o export.tar
  docker rm "$CID"
  lzop -9 export.tar -o export.tar.lzo
  aws s3 cp "export.tar.lzo" "s3://aj-benchmark/${image}.tar"
}

main "$@"
