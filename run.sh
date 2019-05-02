#!/bin/bash

set -ex

export POST_TERM_WAIT=${POST_TERM_WAIT:-15}

# https://stackoverflow.com/questions/1527049/how-can-i-join-elements-of-an-array-in-bash
function join_by { local IFS="$1"; shift; echo "$*"; }

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
elif [ ! -z "${KUBERNETES_SHARD_ALLOCATION_AWARENESS}" ]; then
  # Configure Kubernetes Aware shard allocation Awareness
  # Fetches labels from Node running this pod
  # ATTRS:
  #  - failure-domain.beta.kubernetes.io/zone -> zone
  #  - kubernetes.io/hostname -> server
  KUBE_TOKEN=$(</var/run/secrets/kubernetes.io/serviceaccount/token)
  
  echo "Fetching Node Informations" >2   
  labels=$(curl --fail --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -sS -H "Authorization: Bearer $KUBE_TOKEN" \
           https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/nodes/$WORKER_NODE_NAME | jq -r '.metadata.labels')

  declare -A attrs

  attrs[server]=$(echo $labels | jq '."kubernetes.io/hostname"' -r)
  attrs[zone]=$(echo $labels | jq '."failure-domain.beta.kubernetes.io/zone"' -r)
  

  # For each defined attribute set the required config in elasticsearch.yml and delete undefined attributes
  for attr in "${!attrs[@]}"; do
    if [ "${attrs[$attr]}" != "null" ]; then
      if [ "$NODE_DATA" == "true" ]; then
        echo "node.attr.$attr: ${attrs[$attr]}" >> $BASE/config/elasticsearch.yml
      fi
    else 
      unset attrs[$attr] 
    fi
  done

  if [ ${#attrs[@]} -gt 0 ]; then
    attributes=$(join_by , "${!attrs[@]}")
    if [ "$NODE_MASTER" == "true" ]; then
      echo "cluster.routing.allocation.awareness.attributes: ${attributes}" >> $BASE/config/elasticsearch.yml
    fi
  fi

  

  echo ""
fi

# configuration overrides
# CONF directory and files need to be writable by the user running the container

## GC Log Settings
if [[ ! -z ${ES_GCLOG_FILE_COUNT} ]]; then
  sed -i -E "s/(8:-XX:NumberOfGCLogFiles=)\w+/\1${ES_GCLOG_FILE_COUNT}/" ${BASE}/config/jvm.options
  sed -i -E "s/(9-:-Xlog:gc.+filecount=)[^:,]+(.*)/\1${ES_GCLOG_FILE_COUNT}\2/" ${BASE}/config/jvm.options
fi

if [[ ! -z ${ES_GCLOG_FILE_PATH} ]]; then
  mkdir -p "$(dirname "${ES_GCLOG_FILE_PATH}")"
  touch ${ES_GCLOG_FILE_PATH}
  sed -i -E "s%(8:-Xloggc:).+%\1${ES_GCLOG_FILE_PATH}%" ${BASE}/config/jvm.options
  sed -i -E "s%(9-:-Xlog:gc.+file=)[^:,]+(.*)%\1${ES_GCLOG_FILE_PATH}\2%" ${BASE}/config/jvm.options
fi

if [[ ! -z ${ES_GCLOG_FILE_SIZE} ]]; then
  sed -i -E "s/(8:-XX:GCLogFileSize=)\w+/\1${ES_GCLOG_FILE_SIZE}/" ${BASE}/config/jvm.options
  sed -i -E "s/(9-:-Xlog:gc.+filesize=)[^:,]+(.*)/\1${ES_GCLOG_FILE_SIZE}\2/" ${BASE}/config/jvm.options
fi

## DNS Timers
if [ ! -z "${NETWORK_ADDRESS_CACHE_TTL}" ]; then
    sed -i -e "s/#networkaddress.cache.ttl=.*/networkaddress.cache.ttl=${NETWORK_ADDRESS_CACHE_TTL}/" /opt/jdk-*/conf/security/java.security
fi

if [ ! -z "${NETWORK_ADDRESS_CACHE_NEGATIVE_TTL}" ]; then
    sed -i -e ""s/networkaddress.cache.negative.ttl=.*/networkaddress.cache.negative.ttl=${NETWORK_ADDRESS_CACHE_NEGATIVE_TTL}/"" /opt/jdk-*/conf/security/java.security
fi

# Trap the TERM Signals
trap 'kill ${!}; term_handler' SIGTERM

# run Elasticsearch in the background
$BASE/bin/elasticsearch $ES_EXTRA_ARGS &
PID="$!"

if [ ! -z "${ES_GCS_CREDENTIALS_FILE}" ]; then
  until $BASE/bin/elasticsearch-keystore add-file gcs.client.default.credentials_file ${ES_GCS_CREDENTIALS_FILE}; do
    echo "failed to add keystore file ${file}, retrying in 3s"
    sleep 3
  done
fi

while true ; do
   tail -f /dev/null & wait ${!}
done
