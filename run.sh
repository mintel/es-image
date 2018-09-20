#!/bin/sh

set -ex

# SIGTERM-handler
term_handler() {
  if [ $PID -ne 0 ]; then
    pkill -SIGTERM "$PID"
    wait "$PID"
    sleep 10
  fi
  exit 0;
}

export NODE_NAME=${NODE_NAME:-${HOSTNAME}}

BASE=/usr/share/elasticsearch

# allow for memlock if enabled
if [ "$MEMORY_LOCK" == "true" ]; then
    ulimit -l unlimited
fi

# Set a random node name if not set.
if [ -z "${NODE_NAME}" ]; then
	NODE_NAME=${HOSTNAME}
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
if [ ! -z "${NETWORK_ADDRESS_CACHE_TTL}" ]; then
    sed -i -e "s/#networkaddress.cache.ttl=-1/networkaddress.cache.ttl=${NETWORK_ADDRESS_CACHE_TTL}/" /opt/jdk-10.0.2/conf/security/java.security
fi

if [ ! -z "${NETWORK_ADDRESS_CACHE_NEGATIVE_TTL}" ]; then
    sed -i -e ""s/networkaddress.cache.negative.ttl=10/networkaddress.cache.negative.ttl=${NETWORK_ADDRESS_CACHE_NEGATIVE_TTL}/"" /opt/jdk-10.0.2/conf/security/java.security
fi

trap 'kill ${!}; term_handler' SIGTERM

# run
if [[ $(whoami) == "root" ]]; then
    chown -R elasticsearch:elasticsearch $BASE
    chown -R elasticsearch:elasticsearch /data
    exec su-exec elasticsearch $BASE/bin/elasticsearch $ES_EXTRA_ARGS &
else
    # the container's first process is not running as 'root',
    # it does not have the rights to chown. however, we may
    # assume that it is being ran as 'elasticsearch', and that
    # the volumes already have the right permissions. this is
    # the case for kubernetes for example, when 'runAsUser: 1000'
    # and 'fsGroup:1000' are defined in the pod's security context.
    $BASE/bin/elasticsearch $ES_EXTRA_ARGS &
fi

PID="$!"

while true ; do
   tail -f /dev/null & wait ${!}
done
