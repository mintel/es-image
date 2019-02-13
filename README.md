# Mintel Kubernetes ( Mostly ) Elasticsearch Image

This repository contains the Mintel docker image that we use , mostly , within Kubernetes

## Build Details

The Image builds on-top of the [Official Elasticsearch](https://github.com/elastic/elasticsearch-docker) image and customize the following :

* It only run as unpriviliged user *elasticsearch* (uid:1000 / gid: 1000)
* The indexes are stored in /data
  **if attaching a volume onto /data/ make sure the elasticsearch user can R/W to it**
* JQ is added to the image
* elasticsearch-py python client library is added to the image
* run.sh *entrypoint* is customized to support a series of options / functionalities - see [below](#run.sh-customizations)
* some management scripts are added to enable rolling restarts on Kubernetes - see [below](#lifecycle-scripts)
  Those scripts are meant to be used as [lifecycle hooks](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/) in kubernetes

## run.sh customizations


* On Graceful stop of the java process force sleep a few seconds to allow for other nodes to try to connect to the now stopped-pod and get a connection refuse.
  **This is extremely important when stopping the active master** - you can read more [here](https://discuss.elastic.co/t/timed-out-waiting-for-all-nodes-to-process-published-state-and-cluster-unavailability/138590)
	Time to sleep can be customized by exporting *POST_TERM_WAIT* environment variable (Default to 15s)
* Install plugins at boot by specifying a comma separated list in *ES_PLUGINS_INSTALL* environment variable
* Support defining a custom *SHARD_ALLOCATION_AWARENESS* - TODO: To be improved soon with support with Kubernetes cloud zones
* Customization of *Network DNS Caching TTL* 
  By default this java configuration from upstream will cache positive names forever and negative for a while ( TODO: how long? ) 
	set *NETWORK_ADDRESS_CACHE_TTL* environment variable to define positive caching in seconds ( default to 3s )
	set *NETWORK_ADDRESS_CACHE_NEGATIVE_TTL* environment variable to define negative caching in seconds ( default to 10s )

## lifecycle scripts

a Python script to manage various aspects of the Elasticsearch lifecycle is provided in */manage-es.py* 

A simple set of sh script to be used in *kubernetes* as [lifecycle hooks](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/)  is provided in 

pre-stop hook
```
/stop-data-node.sh

python /manage-es.py pre-stop-data
```

post-start hook
```
/start-data-node.sh

python /manage-es.py persitent-settings
python /manage-es.py post-start-data
```

See the [minikube](#run-in-minikube-example) example for a working example of the definition of those hooks

the following action are supported by the python script
**NOTE: In some cases running this scripts as lifecycle hook can lead to a cluster that can't startup**
* For example all data action expect to be able to contact the cluster masters before proceeding. Is MASTER and DATA functions are on the same node this will never work

*  pre-stop-data - Hook for Pre-Stop of a data node
```
    if mode.upper() == "ALLOCATION":
        # Sequence:
        # - Disable Shard Allocation
        # - Perform a Synced Flush
    elif mode.upper() == "DRAIN":
        # Sequence:
        # - set recovery settings
        # - drain Node
        # - Wait for 0 shards in relocating or initializing status

```
*  post-start-data - Hook for Post-Start of a data node
```
    if mode.upper() == "ALLOCATION":                        
        # Sequence:                                                                                           
        # - wait for node to join cluster                                                                                                                                                    
        # - set recovery settings                           
        # - enable shards allocation                                                                          
        # - Wait for 0 Initializing or Relocating Shards ( Unassigned shards should be ok if this is cold startup of an elasticsearch cluster )                           
        # - remove temporary recovery settings  
    elif mode.upper() == "DRAIN":
        # Sequence:
        # - wait for node to join cluster
        # - set recovery settings
        # - undrain Node
        # - Wait for 0 Initializing or Relocating Shards ( Unassigned shards should be ok if this is cold startup of an elasticsearch cluster )                        
        # - remove temporary recovery settings
```
*  pre-stop-master - Hook for Pre-Stop of a master node
```
Not implemented yet 
```
*  post-start-master - Hook for Post-Start of a master node
```
Not implemented yet 
```
*  peristent-settings - Set some elasticsearch persistent settings from a provided file
```
If path to a json persitent settings file is provided

push persistent settings to the cluster
```

## ENVironment Variables

### Startup Environment variables

* [CLUSTER\_NAME](https://www.elastic.co/guide/en/elasticsearch/reference/current/important-settings.html#cluster.name)
* [NODE\_NAME](https://www.elastic.co/guide/en/elasticsearch/reference/current/important-settings.html#node.name)
* [NODE\_MASTER](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html#master-node)
* [NODE\_DATA](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html#data-node)
* [NETWORK\_HOST](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-network.html#network-interface-values)
* [HTTP\_ENABLE](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-http.html#_settings_2)
* [HTTP\_CORS\_ENABLE](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-http.html#_settings_2)
* [HTTP\_CORS\_ALLOW\_ORIGIN](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-http.html#_settings_2)
* [NUMBER\_OF\_MASTERS](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-discovery-zen.html#master-election)
* [MAX\_LOCAL\_STORAGE\_NODES](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html#max-local-storage-nodes)
* ES\_GCLOG\_FILE\_COUNT - Number of GC log files to keep in the rotation.
* ES\_GCLOG\_FILE\_PATH - Location of main GC file (e.g. data/gc.log).
* ES\_GCLOG\_FILE\_SIZE - Max size of each rolled GC log (e.g. 64m).
* [ES\_JAVA\_OPTS](https://www.elastic.co/guide/en/elasticsearch/reference/current/heap-size.html)
* [ES\_PLUGINS\_INSTALL](https://www.elastic.co/guide/en/elasticsearch/plugins/current/installation.html) - comma separated list of Elasticsearch plugins to be installed. Example: `ES_PLUGINS_INSTALL="repository-gcs,x-pack"`
* [SHARD\_ALLOCATION\_AWARENESS](https://www.elastic.co/guide/en/elasticsearch/reference/current/allocation-awareness.html#CO287-1)
* [SHARD\_ALLOCATION\_AWARENESS\_ATTR](https://www.elastic.co/guide/en/elasticsearch/reference/current/allocation-awareness.html#CO287-1)
* KUBERNETES\_SHARD\_ALLOCATION\_AWARENESS - Enable SHARD Allocation awareness for a Kubernetes Cluster using labels
  * server = WORKER NODE NAME
	* zone = Kubernetes failure domain zone ( Only for cloud )
* [MEMORY\_LOCK](https://www.elastic.co/guide/en/elasticsearch/reference/current/important-settings.html#bootstrap.memory_lock) - memory locking control - enable to prevent swap (default = `true`) .
* [REPO\_LOCATIONS](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-snapshots.html#_shared_file_system_repository) - list of registered repository locations. For example `"/backup"` (default = `[]`). The value of REPO\_LOCATIONS is automatically wrapped within an `[]` and therefore should not be included in the variable declaration. To specify multiple repository locations simply specify a comma separated string for example `"/backup", "/backup2"`.
* [PROCESSORS](https://github.com/elastic/elasticsearch-definitive-guide/pull/679/files) - allow elasticsearch to optimize for the actual number of available cpus (must be an integer - default = 1)

### Elasticsearch settings environment variables

#### Transient settings set during Maintenance 
* WAIT\_FOR\_NODE\_IN\_CLUSTER - default: 180 - Seconds to wait for NODE to rejoin cluster 
* WAIT\_FOR\_NO\_SHARDS\_RELOCATING - default: 1800 - Seconds to wait for cluster to have no Relocating nor Initializing shards 
* NODE\_CONCURRENT\_INCOMING\_RECOVERIES - default: ES Version defaut - set cluster.routing.allocation.node\_concurrent\_incoming\_recoveries
* NODE\_CONCURRENT\_OUTGOING\_RECOVERIES - default: ES Version defaut - set cluster.routing.allocation.node\_concurrent\_outgoing\_recoveries
* NODE\_INITIAL\_PRIMARIES\_RECOVERIES - default: ES Version defaut - set cluster.routing.allocation.node\_initial\_primaries\_recoveries
* CLUSTER\_CONCURRENT\_REBALANCE - default: ES Version defaut - set cluster.routing.allocation.cluster\_concurrent\_rebalance

#### Persistent Settings set by every node at startup 
* PERSITENT\_SETTINGS\_FILE\_PATH - path to a JSON file of persistent settings 

#### Other Startup Settings
* DISCOVERY\_SERVICE - Elasticsearch discovery URL
* MAINTENANCE\_MODE 
  * None ( default ) - no Management of maintenance mode, pod will just be stopped by Kubernetes
  * Drain ( Drain local node ) - The node will be Drained ( moving all shards ) before proceeding with stop - NOTE: This need to finish before GracePeriod expire
  * Allocation ( Disable shard allocation ) - This will disable shards allocation as described https://www.elastic.co/guide/en/elasticsearch/reference/current/rolling-upgrades.html

## run in minikube example

see example [here](https://github.com/mintel/es-image/tree/master/examples/minikube)
