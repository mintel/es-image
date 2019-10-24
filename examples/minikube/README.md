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
