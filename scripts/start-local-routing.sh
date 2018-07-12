#!/bin/bash

set -ex

export NODE_NAME=${NODE_NAME:-${HOSTNAME}}


count=1
while [ $count -le 5 ]; do
  (( count++ ))
  CLUSTER_SETTINGS=$(curl --connect-timeout 3 -s -XGET "http://${DISCOVERY_SERVICE}:9200/_cluster/settings")
  if echo "${CLUSTER_SETTINGS}" | grep -E "${NODE_NAME}"; then
    echo "Activate node ${NODE_NAME}"
    curl --connect-timeout 3 -s -XPUT -H 'Content-Type: application/json' "http://${DISCOVERY_SERVICE}:9200/_cluster/settings" -d "{ \"transient\" :{ \"cluster.routing.allocation.exclude._name\" : null }}"
    if [ $? -eq 0 ]; then
      break
    fi
  fi
  sleep 10
done
