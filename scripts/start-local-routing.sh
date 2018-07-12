#!/bin/bash

set -ex

export NODE_NAME=${NODE_NAME:-${HOSTNAME}}


curl --retry 6 --connect-timeout 3 -s -XGET "http://${DISCOVERY_SERVICE}:9200/_cluster/settings" 
CLUSTER_SETTINGS=$(curl --connect-timeout 3 -s -XGET "http://${DISCOVERY_SERVICE}:9200/_cluster/settings")
if echo "${CLUSTER_SETTINGS}" | grep -E "${NODE_NAME}"; then
  echo "Activate node ${NODE_NAME}"
  curl --retry 3 --connect-timeout 3 -s -XPUT -H 'Content-Type: application/json' "http://${DISCOVERY_SERVICE}:9200/_cluster/settings" -d "{ \"transient\" :{ \"cluster.routing.allocation.exclude._name\" : null }}"
fi
