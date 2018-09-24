#!/bin/sh

set -ex

export POST_TERM_WAIT=${POST_TERM_WAIT:-15}

# SIGTERM-handler
term_handler() {
  if [ $PID -ne 0 ]; then
    set +e
    kill -15 "$PID" # SIGTERM
    wait "$PID"
    echo "Sleeping $POST_TERM_WAIT Seconds before exiting the term_handler"
    sleep $POST_TERM_WAIT
    set -e
  fi
  exit 0;
  #exit 143; # 128 + 15 -- SIGTERM
}


BASE=/usr/share/elasticsearch

# allow for memlock if enabled
if [ "$MEMORY_LOCK" == "true" ]; then
    ulimit -l unlimited
fi

NODE_NAME=${NODE_NAME:-${HOSTNAME}}

# Set a random node name if not set.
if [ -z "${NODE_NAME}" ]; then
	NODE_NAME=$(uuidgen)
fi
export NODE_NAME=${NODE_NAME}

# Create a temporary folder for Elastic Search ourselves.
# Ref: https://github.com/elastic/elasticsearch/pull/27659
export ES_TMPDIR=`mktemp -d -t elasticsearch.XXXXXXXX`

# Prevent "Text file busy" errors
sync

if [ ! -z "${ES_PLUGINS_INSTALL}" ]; then
   OLDIFS=$IFS
   IFS=','
   for plugin in ${ES_PLUGINS_INSTALL}; do
      if ! $BASE/bin/elasticsearch-plugin list | grep -qs ${plugin}; then
         until $BASE/bin/elasticsearch-plugin install --batch ${plugin}; do
           echo "failed to install ${plugin}, retrying in 3s"
           sleep 3
         done
      fi
   done
   IFS=$OLDIFS
fi

# Configure Shard Allocation Awareness
# XXX: If runnig kubernetes and kubernetes is runnign in the cloud -> Fetch zone from node 
if [ ! -z "${SHARD_ALLOCATION_AWARENESS_ATTR}" ]; then
    # this will map to a file like  /etc/hostname => /dockerhostname so reading that file will get the
    #  container hostname
    if [ "$NODE_DATA" == "true" ]; then
        ES_SHARD_ATTR=`cat ${SHARD_ALLOCATION_AWARENESS_ATTR}`
        NODE_NAME="${ES_SHARD_ATTR}-${NODE_NAME}"
        echo "node.attr.${SHARD_ALLOCATION_AWARENESS}: ${ES_SHARD_ATTR}" >> $BASE/config/elasticsearch.yml
    fi
    if [ "$NODE_MASTER" == "true" ]; then
        echo "cluster.routing.allocation.awareness.attributes: ${SHARD_ALLOCATION_AWARENESS}" >> $BASE/config/elasticsearch.yml
    fi
fi

# configuration overrides
# CONF directory and files need to be writable by the user running the container

## DNS Timers
if [ ! -z "${NETWORK_ADDRESS_CACHE_TTL}" ]; then
    sed -i -e "s/#networkaddress.cache.ttl=.*/networkaddress.cache.ttl=${NETWORK_ADDRESS_CACHE_TTL}/" /opt/jdk-10.0.2/conf/security/java.security
fi

if [ ! -z "${NETWORK_ADDRESS_CACHE_NEGATIVE_TTL}" ]; then
    sed -i -e ""s/networkaddress.cache.negative.ttl=.*/networkaddress.cache.negative.ttl=${NETWORK_ADDRESS_CACHE_NEGATIVE_TTL}/"" /opt/jdk-10.0.2/conf/security/java.security
fi

# Trap the TERM Signals
trap 'kill ${!}; term_handler' SIGTERM

# run Elasticsearch in the background
$BASE/bin/elasticsearch $ES_EXTRA_ARGS &
PID="$!"

while true ; do
   tail -f /dev/null & wait ${!}
done
