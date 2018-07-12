#!/bin/bash

set -ex

export NODE_NAME=${NODE_NAME:-${HOSTNAME}}

CLUSTER_SETTINGS=$(curl -s -XGET "http://${DISCOVERY_SERVICE}:9200/_cluster/settings")
if echo "${CLUSTER_SETTINGS}" | grep -E "${NODE_NAME}"; then
  echo "Activate node ${NODE_NAME}"
  curl -s -XPUT -H 'Content-Type: application/json' "http://${DISCOVERY_SERVICE}:9200/_cluster/settings" -d "{ \"transient\" :{ \"cluster.routing.allocation.exclude._name\" : null }}"
fi
