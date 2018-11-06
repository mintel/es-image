import time
import os
import sys
import json
from elasticsearch import Elasticsearch
from elasticsearch.exceptions import ConnectionError
from pprint import pprint

# Environment from Kubernetes

## Recovery settings - TRANSIENT
RECOVERY_MAX_BYTES=os.environ.get('MAX_BYTES', None)

## How many concurrent incoming shard recoveries are allowed to happen on a node. Incoming recoveries are the recoveries where the target shard (most likely the replica unless a shard is relocating) is allocated on the node. Defaults to 2.
## cluster.routing.allocation.node_concurrent_incoming_recoveries
NODE_CONCURRENT_INCOMING_RECOVERIES=os.environ.get("NODE_CONCURRENT_INCOMING_RECOVERIES", None)

## How many concurrent outgoing shard recoveries are allowed to happen on a node. Outgoing recoveries are the recoveries where the source shard (most likely the primary unless a shard is relocating) is allocated on the node. Defaults to 2.
## cluster.routing.allocation.node_concurrent_outgoing_recoveries
NODE_CONCURRENT_OUTGOING_RECOVERIES=os.environ.get("NODE_CONCURRENT_OUTGOING_RECOVERIES", None)

## While the recovery of replicas happens over the network, the recovery of an unassigned primary after node restart uses data from the local disk. These should be fast so more initial primary recoveries can happen in parallel on the same node. Defaults to 4.
## cluster.routing.allocation.node_initial_primaries_recoveries
NODE_INITIAL_PRIMARIES_RECOVERIES=os.environ.get("NODE_INITIAL_PRIMARIES_RECOVERIES", None)


## Performance Settings - PERSISTENT

## The cluster.routing.allocation.cluster_concurrent_rebalance property determines the number of shards allowed for concurrent rebalance (default 2). 
## This property needs to be set appropriately depending on the hardware being used, for example the number of CPUs, IO capacity, etc. 
## If this property is not set appropriately, it can impact the performance of ES indexing.
CLUSTER_CONCURRENT_REBALANCE=os.environ.get('CLUSTER_CONCURRENT_REBALANCE', None)

## Persisntent Settings file
## 
## JSON file location containing an arbitrary set of persistent settings 
PERSITENT_SETTINGS_FILE_PATH=os.environ.get('PERSITENT_SETTINGS_FILE_PATH', None)



## ENV Settings
DISCOVERY_SERVICE=os.environ.get("DISCOVERY_SERVICE", None)
NODE_NAME=os.environ.get("NODE_NAME", None)

## Allowed Modes: 
##  * None ( default ) - no Management of maintenance mode, pod will just be stopped by Kubernetes
##  * Drain ( Drain local node ) - The node will be Drained ( moving all shards ) before proceeding with stop - NOTE: This need to finish before GracePeriod expire
##  * Allocation ( Disable shard allocation ) - This will disable shards allocation as described https://www.elastic.co/guide/en/elasticsearch/reference/current/rolling-upgrades.html
MAINTENANCE_MODE=os.environ.get("MAINTENANCE_MODE", None)


def get_client(timeout=30):
  client = Elasticsearch(DISCOVERY_SERVICE, sniff_on_start=False)

  # wait for red, yellow or green status
  # Any state will mean the cluster is up
  for _ in range(timeout):
    try:
      client.cluster.health(wait_for_status='red')
      return client
    except ConnectionError:
      time.sleep(1)
  else:
    # timeout
    raise Exception('Elasticsearch connection Timed out after %s seconds' % str(timeout))


def flush_synced_all(client, trys=5):
  for _ in range(trys):
    ret=client.indices.flush_synced(index="")
    if ret['_shards']['failed'] == 0:
      # Synced flush operations might fail due to pending indexing operations - reissue 
      break
    time.sleep(5)

def set_setting(client,persistency,setting,value):

    ret=client.cluster.put_settings(
      body='''
          {
            "%s": {
              "%s": \"%s\"
            }
          }
      ''' % (persistency,setting,value))

    if 'acknowledged' not in ret or ret['acknowledged'] != True:
        raise Exception('Failed to set %s to %s : \n%s' % (setting,value,json.dumps(ret)))

def unset_setting(client,persistency,setting):

    ret=client.cluster.put_settings(
      body='''
          {
            "%s": {
              "%s": null
            }
          }
      ''' % (persistency,setting)
    )

    if 'acknowledged' not in ret or ret['acknowledged'] != True:
        raise Exception('Failed to set %s to null : \n%s' % (setting,json.dumps(ret)))


def disable_shard_allocation(client):
    set_setting(client,"transient","cluster.routing.allocation.enable","none")

def enable_shard_allocation(client):
    unset_setting(client,"transient","cluster.routing.allocation.enable")


def get_all_nodes(client):
  nodes=[]
  for key,value in client.nodes.info()['nodes'].iteritems():
    node={}
    node['id']=key
    node['name']=value['name']
    nodes.append(node)

  return nodes
    
def is_node_in_cluster(client,node):
  if node in [ x['name'] for x in get_all_nodes(client) ]:
    return True
  else:
    return False

def wait_for_node_in_cluster(client,node,timeout=90):
  for _ in range(timeout):
    if is_node_in_cluster(client,node):
      return True
    else:
      time.sleep(1)
  raise Exception('Node not in cluster after timeout: %s' % str(timeout))

def is_any_shard_relocating_or_initializing(client):
  health=client.cluster.health()
  relocating=health['relocating_shards']
  initializing=health['initializing_shards']

  if relocating != 0 or initializing != 0:
    return True
  else:
    return False

def wait_for_no_relocating_or_initializing_shards(client):
  # Return true if for 5 checks no shards are in either relocating or initializing state
  count=0
  while True:
    if is_any_shard_relocating_or_initializing(client):
      count = 0
    else:
      count += 1

    if count == 5:
      break

    time.sleep(2)
  

  
## Action Functions

def post_start_data_node(client,mode,node):
  if mode.upper() == "ALLOCATION":
    # Sequence:
    # - wait for node to join cluster
    # - set recovery settings
    # - enable shards allocation
    # - Wait for 0 Initializing or Relocating Shards ( Unassigned shards should be ok if this is cold startup of an elasticsearch cluster )
    # - remove temporary recovery settings
    pprint('Wait for node %s to join the cluster' % node)
    wait_for_node_in_cluster(client,node)
    pprint('Set recovery settings')
    if RECOVERY_MAX_BYTES: set_setting(client,"transient","indices.recovery.max_bytes_per_sec",RECOVERY_MAX_BYTES) 
    if NODE_CONCURRENT_INCOMING_RECOVERIES: set_setting(client,"transient","cluster.routing.allocation.node_concurrent_incoming_recoveries",NODE_CONCURRENT_INCOMING_RECOVERIES)
    if NODE_CONCURRENT_OUTGOING_RECOVERIES: set_setting(client,"transient","cluster.routing.allocation.node_concurrent_outgoing_recoveries",NODE_CONCURRENT_OUTGOING_RECOVERIES)
    if NODE_INITIAL_PRIMARIES_RECOVERIES: set_setting(client,"transient","cluster.routing.allocation.node_initial_primaries_recoveries",NODE_INITIAL_PRIMARIES_RECOVERIES)
    pprint('Enable Shard Allocation')
    enable_shard_allocation(client)
    pprint('Wait for RELOCATING and INITIALIZING Shards to drop to 0')
    wait_for_no_relocating_or_initializing_shards(client)
    pprint('Reset Recovery Settings')
    if RECOVERY_MAX_BYTES: unset_setting(client,"transient","indices.recovery.max_bytes_per_sec")
    if NODE_CONCURRENT_INCOMING_RECOVERIES: unset_setting(client,"transient","cluster.routing.allocation.node_concurrent_incoming_recoveries")
    if NODE_CONCURRENT_OUTGOING_RECOVERIES: unset_setting(client,"transient","cluster.routing.allocation.node_concurrent_outgoing_recoveries")
    if NODE_INITIAL_PRIMARIES_RECOVERIES: unset_setting(client,"transient","cluster.routing.allocation.node_initial_primaries_recoveries")
  elif mode.upper() == "DRAIN":
    # Sequence:
    # - wait for node to join cluster
    # - set recovery settings
    # - undrain Node
    # - Wait for 0 Initializing or Relocating Shards ( Unassigned shards should be ok if this is cold startup of an elasticsearch cluster )
    # - remove temporary recovery settings
    pprint('Wait for node %s to join the cluster' % node)
    wait_for_node_in_cluster(client,node)
    pprint('Set recovery settings')
    if RECOVERY_MAX_BYTES: set_setting(client,"transient","indices.recovery.max_bytes_per_sec",RECOVERY_MAX_BYTES) 
    if NODE_CONCURRENT_INCOMING_RECOVERIES: set_setting(client,"transient","cluster.routing.allocation.node_concurrent_incoming_recoveries",NODE_CONCURRENT_INCOMING_RECOVERIES)
    if NODE_CONCURRENT_OUTGOING_RECOVERIES: set_setting(client,"transient","cluster.routing.allocation.node_concurrent_outgoing_recoveries",NODE_CONCURRENT_OUTGOING_RECOVERIES)
    if NODE_INITIAL_PRIMARIES_RECOVERIES: set_setting(client,"transient","cluster.routing.allocation.node_initial_primaries_recoveries",NODE_INITIAL_PRIMARIES_RECOVERIES)
    pprint('UnDrain Local Node %s' % node)
    unset_setting(client,"transient","cluster.routing.allocation.exclude._name")
    pprint('Wait for RELOCATING and INITIALIZING Shards to drop to 0')
    wait_for_no_relocating_or_initializing_shards(client)
    pprint('Reset Recovery Settings')
    if RECOVERY_MAX_BYTES: unset_setting(client,"transient","indices.recovery.max_bytes_per_sec")
    if NODE_CONCURRENT_INCOMING_RECOVERIES: unset_setting(client,"transient","cluster.routing.allocation.node_concurrent_incoming_recoveries")
    if NODE_CONCURRENT_OUTGOING_RECOVERIES: unset_setting(client,"transient","cluster.routing.allocation.node_concurrent_outgoing_recoveries")
    if NODE_INITIAL_PRIMARIES_RECOVERIES: unset_setting(client,"transient","cluster.routing.allocation.node_initial_primaries_recoveries")
  else:
    raise Exception("Not support mode %s requested for pre_stop_data_node" % mode)

def pre_stop_data_node(client,mode,node):
  if mode.upper() == "ALLOCATION":
    # Sequence:
    # - Disable Shard Allocation
    # - Perform a Synced Flush 
    pprint('Disabling Shard Allocation')
    disable_shard_allocation(client)
    pprint('Perform a Synced Flush')
    flush_synced_all(client)
  elif mode.upper() == "DRAIN":
    # Sequence:
    # - set recovery settings
    # - drain Node
    # - Wait for 0 shards on this node
    pprint('Setting Recovery Max Bytes during drain operation')
    if RECOVERY_MAX_BYTES: set_setting(client,"transient","indices.recovery.max_bytes_per_sec",RECOVERY_MAX_BYTES)
    if NODE_CONCURRENT_INCOMING_RECOVERIES: set_setting(client,"transient","cluster.routing.allocation.node_concurrent_incoming_recoveries",NODE_CONCURRENT_INCOMING_RECOVERIES)
    if NODE_CONCURRENT_OUTGOING_RECOVERIES: set_setting(client,"transient","cluster.routing.allocation.node_concurrent_outgoing_recoveries",NODE_CONCURRENT_OUTGOING_RECOVERIES)
    if NODE_INITIAL_PRIMARIES_RECOVERIES: set_setting(client,"transient","cluster.routing.allocation.node_initial_primaries_recoveries",NODE_INITIAL_PRIMARIES_RECOVERIES)
    pprint('Drain Local Node %s' % node)
    set_setting(client,"transient","cluster.routing.allocation.exclude._name",node)
    pprint('Wait for RELOCATING and INITIALIZING Shards to drop to 0')
    wait_for_no_relocating_or_initializing_shards(client)
    if RECOVERY_MAX_BYTES: unset_setting(client,"transient","indices.recovery.max_bytes_per_sec")
    if NODE_CONCURRENT_INCOMING_RECOVERIES: unset_setting(client,"transient","cluster.routing.allocation.node_concurrent_incoming_recoveries")
    if NODE_CONCURRENT_OUTGOING_RECOVERIES: unset_setting(client,"transient","cluster.routing.allocation.node_concurrent_outgoing_recoveries")
    if NODE_INITIAL_PRIMARIES_RECOVERIES: unset_setting(client,"transient","cluster.routing.allocation.node_initial_primaries_recoveries")
  else:
    raise Exception("Not support mode %s requested for pre_stop_data_node" % mode)
    

def set_persitent_settings(client, srcfile):
  try:
    settings=json.load(open(srfcile))
  except:
    raise Exception("Failed to Load json settings file %s" % srcfile)

  for key,value in settings.items():
    if key == "persistent" or key == "transient":
      continue

    set_setting(client,"persistent",key,value)


####


## Main 

def main():
  if len(sys.argv) != 2:
    raise Exception('Need to specify Action for the script : ( post-start-data , pre-stop-data , post-start-master , pre-stop-master , persistent-settings )')

  action=sys.argv[1]

  client=get_client()

  if action == "post-start-data":
    if MAINTENANCE_MODE:
      post_start_data_node(client,MAINTENANCE_MODE,NODE_NAME)
    else:
      pprint("No Maintenance mode set")
      sys.exit(0)
  elif action == "pre-stop-data":
    if MAINTENANCE_MODE:
      pre_stop_data_node(client,MAINTENANCE_MODE,NODE_NAME)
    else:
      pprint("No Maintenance mode set")
      sys.exit(0)
  elif action == "post-start-master":
    raise Exception("Not Implemented Yet")
  elif action == "post-start-master":
    raise Exception("Not Implemented Yet")
  elif action == "persitent-settings":
    pprint("Current Settings:")
    pprint(client.cluster.get_settings())
    if  PERSITENT_SETTINGS_FILE_PATH: 
      set_persistent_settings(client, PERSITENT_SETTINGS_FILE_PATH)
    else:
      pprint("No persistent settings file available - skipping")
  else:
    raise Exception("No correct action specified")

  pprint("Hook Completed")
  sys.exit(0)


main()
