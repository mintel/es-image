
wait_for_tcp() {
  # Return 0 when tcp socket can be opened or 1 if timeout expires
  TIMEOUT=$1
  HOST=$2
  PORT=$3

  for i in `seq $TIMEOUT` ; do
    nc -z "$HOST" "$PORT" > /dev/null 2>&1
    
    result=$?
    if [ $result -eq 0 ] ; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_cluster_health_yg() {
  # Return 0 when cluster health status is either yellow or green - return 1 if timeout expires
  TIMEOUT=$1
  HOST=$2
  PORT=$3

  for i in `seq $TIMEOUT` ; do
    set -o pipefail
    status=$(curl -fqs "${HOST}:${PORT}/_cluster/health" 2>/dev/null | jq -re '.status | select(. | test("yellow|green"))')
    set +o pipefail
    
    result=$?
    if [ $result -eq 0 ] ; then
      return 0
    fi
    sleep 1
  done
  return 1
}

get_cluster_health_status() {
  # Return the cluster health status string or None if it failed
  HOST=$1
  PORT=$2

  set -o pipefail
  status=$(curl -fqs "${HOST}:${PORT}/_cluster/health" 2>/dev/null | jq -re '.status')
  set +o pipefail
  
  result=$?
  if [ $result -eq 0 ] ; then
    echo $status
    return 0
  fi
  
  echo "None"
  return 1
}



### TEST

wait_for_tcp 15 172.17.0.6 9200
echo $?
wait_for_cluster_health_yg 15 172.17.0.6 9200
echo $?
get_cluster_health_status 172.17.0.6 9200
echo $?
