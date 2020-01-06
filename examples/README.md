## Description

Simple statefulsets to start a 3 Master Node + 3 Data Node cluster 

Resource allocation for the master and data nodes is the minimum amount that got me a cluster running with no OOMKilling happening.
You might want to review those settings, especially if you are lucky enough to have **more RAM** than me

## Instructions

Start minikube, point your docker client at the daemon inside minikube and run a make build in the root of this project:

```bash
minikube start --cpus=2 --memory=4096 --kubernetes-version=v1.13.7
eval $(minikube docker-env)
```
or
```bash
k3d create -v /dev/mapper:/dev/mapper --publish 8080:80 --publish 8443:443 --workers 1

k3d i mintel/es-image:XXXXXX
k3d i mintel/fluentd-es-image:XXXXXX

sudo sysctl -w vm.max_map_count=262144

export KUBECONFIG="$(k3d get-kubeconfig --name='k3s-default')"

kubectl apply -f elasticstack/namespace.yml
kubectl apply -f elasticstack/rbac.yml
kubectl apply -f elasticstack/config.yml
kubectl apply -f elasticstack/3-master-statefulset.yml
kubectl rollout status statefulset/elasticsearch-master-log -n monitoring
kubectl apply -f elasticstack/3-node-statefulset.yml
kubectl rollout status statefulset/elasticsearch-data-log -n monitoring

kubectl port-forward -n monitoring elasticsearch-master-log-0 9200
curl 'localhost:9200/_cluster/health?pretty'
curl 'localhost:9200/_cat/nodes?v'

kubectl apply -f elasticstack/kibana.yml
kubectl port-forward -n monitoring service/kibana-log 5601

kubectl apply -f fluentd/
kubectl apply -f grafana/

```

Minikube doesn't inherit your host's vm.max_map_count setting so you need to make sure this is set to the correct value within the minikube VM or the pod won't start:

```bash
minikube ssh
sudo sysctl -w vm.max_map_count=262144
logout
```

Next ensure you're on the right context and apply each of the manifests as follows:

```bash
kubectl config set-context minikube
kubectl apply -f namespace.yml
kubectl apply -f config.yml
kubectl apply -f rbac.yml
kubectl apply -f 3-master-statefulset.yml
kubectl rollout status statefulset/elasticsearch-master -n monitoring
kubectl apply -f 3-node-statefulset.yml
kubectl rollout status statefulset/elasticsearch-node -n monitoring
```