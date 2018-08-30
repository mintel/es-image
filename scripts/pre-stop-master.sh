#!/bin/bash
export ELASTIC_STOP_SLEEP=${ELASTIC_STOP_SLEEP:-5}
echo "Sleeping for ${ELASTIC_STOP_SLEEP} seconds before sending SIGTERM..."
sleep ${ELASTIC_STOP_SLEEP} && pkill -SIGTERM java
echo "Done."
