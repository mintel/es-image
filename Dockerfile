# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


FROM docker.elastic.co/elasticsearch/elasticsearch-oss:7.4.1

LABEL vendor="Mintel"
LABEL version="7.4.1"
LABEL maintainer="fciocchetti@mintel.com"
LABEL vcs-url="https://github.com/mintel/es-image"

# Run elasticsearch as unprivileged
RUN chown elasticsearch:elasticsearch -R /usr/share/elasticsearch && \
    mkdir -p /data && \
    chown elasticsearch:elasticsearch -R /data && \
    chown elasticsearch:elasticsearch -R /usr/share/elasticsearch/jdk/conf

# Install Any extra package here
ENV JQ_VERSION=1.5 \
    JQ_SHA256=c6b3a7d7d3e7b70c6f51b706a3b90bd01833846c54d32ca32f0027f00226ff6d
# Last pip version that has not deprecated python 2.7
ENV NEW_PIP_VERSION=18.1
ENV ELASTICSEARCH_PY_VERSION=7.0.5

# jq
RUN set -xe \
    && curl -L https://github.com/stedolan/jq/releases/download/jq-${JQ_VERSION}/jq-linux64 -o /tmp/jq \
    && cd /tmp \
    && echo "$JQ_SHA256  jq" | sha256sum -c \
    && mv jq /usr/local/bin \
    && chmod +x /usr/local/bin/jq

# Install pip
RUN set -e \
    && yum install -y epel-release \
    && yum install -y python-pip \
    && yum remove -y epel-release \
    && yum clean all

# Pip package installs/upgrades
RUN set -e \
    && pip install --upgrade \
       pip==${NEW_PIP_VERSION} \
       elasticsearch==${ELASTICSEARCH_PY_VERSION}

# Export HTTP & Transport
EXPOSE 9200 9300

ENV CLUSTER_NAME=elasticsearch-default \
    CLUSTER_MASTER_SERVICE_NAME="localhost" \
    DISCOVERY_SERVICE=elasticsearch-discovery \
    ES_GCLOG_FILE_COUNT=4 \
    ES_GCLOG_FILE_PATH=/data/log/gc.log \
    ES_GCLOG_FILE_SIZE=64m \
    ES_JAVA_OPTS="-Xms512m -Xmx512m" \
    ES_VERSION=7.4.1 \
    HTTP_CORS_ALLOW_ORIGIN="*" \
    HTTP_CORS_ENABLE=true \
    MASTER_NODES=localhost \
    MEMORY_LOCK=false \
    NETWORK_ADDRESS_CACHE_NEGATIVE_TTL=10 \
    NETWORK_ADDRESS_CACHE_TTL=3 \
    NETWORK_HOST=_site_ \
    NODE_DATA=true \
    NODE_INGEST=true \
    NODE_MASTER=true \
    PATH=/usr/share/elasticsearch/bin:$PATH \
    REPO_LOCATIONS="" \
    SHARD_ALLOCATION_AWARENESS="" \
    SHARD_ALLOCATION_AWARENESS_ATTR=""

WORKDIR /usr/share/elasticsearch

# Copy run script
COPY run.sh /

# Copy scripts 
COPY scripts /

# Copy configuration
COPY config/* /usr/share/elasticsearch/config/

USER elasticsearch

CMD ["/run.sh"]
