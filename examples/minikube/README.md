## Description

Simple staetfulsets to start a 3 Master Node + 3 Data Node cluster 

Resource allocation for the master and data nodes is the minimum amount that got me a cluster running with no OOMKilling happening.
You might want to review those settings, especially if you are lucky enough to have **more RAM** than me

## Instructions

* kubectl apply -f namespace.yml
* kubectl apply -f 3-master-statefuleset.yml
* kubectl rollout status statefulset/elasticsearch-master -n monitoring
* kubectl apply -f 3-node-statefuleset.yml
* kubectl rollout status statefulset/elasticsearch-node -n monitoring

