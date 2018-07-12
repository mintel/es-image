#!/bin/bash

set -ex

export NODE_NAME=${NODE_NAME:-${HOSTNAME}}

echo "Disabling Local Routing for this Node - Will move all shards to other nodes"
curl -s -XPUT -H 'Content-Type: application/json' 'localhost:9200/_cluster/settings' -d "{ \"transient\" :{ \"cluster.routing.allocation.exclude._name\" : \"${NODE_NAME}\" }}"

while true ; do
  echo -e "Wait for node ${NODE_NAME} to become empty"
  SHARDS_ALLOCATION=$(curl -s -XGET 'http://localhost:9200/_cat/shards')
  if ! echo "${SHARDS_ALLOCATION}" | grep -E "${NODE_NAME}"; then
    break
  fi
  sleep 2
done
