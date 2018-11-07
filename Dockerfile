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

FROM docker.elastic.co/elasticsearch/elasticsearch-oss:6.4.1

LABEL vendor="Mintel"
LABEL version="6.4.1"
LABEL maintainer "fciocchetti@mintel.com"
LABEL vcs-url "https://github.com/mintel/es-image"


# Copy configuration
COPY config /usr/share/elasticsearch/config

# Run elasticsearch as unprivileged
RUN chown elasticsearch:elasticsearch -R /usr/share/elasticsearch && \
    mkdir -p /data && \
    chown elasticsearch:elasticsearch -R /data && \
    chown elasticsearch:elasticsearch -R /opt/jdk-10.0.2/conf

# Install Any extra package here
ENV JQ_VERSION=1.5 \
    JQ_SHA256=c6b3a7d7d3e7b70c6f51b706a3b90bd01833846c54d32ca32f0027f00226ff6d
ENV ELASTICSEARCH_PY_VERSION=6.3.1 \
    ELASTICSEARCH_PY_SHA256=aada5cfdc4a543c47098eb3aca6663848ef5d04b4324935ced441debc11ec98b

# jq
RUN set -xe \
    && curl -L https://github.com/stedolan/jq/releases/download/jq-${JQ_VERSION}/jq-linux64 -o /tmp/jq \
    && cd /tmp \
    && echo "$JQ_SHA256  jq" | sha256sum -c \
    && mv jq /usr/local/bin \
    && chmod +x /usr/local/bin/jq

# Install python setuptools and elasticsearch-py
RUN set -e \
    && yum install -y python-setuptools \
    && yum clean all

WORKDIR /tmp
RUN set -e \
    && curl -L https://files.pythonhosted.org/packages/9d/ce/c4664e8380e379a9402ecfbaf158e56396da90d520daba21cfa840e0eb71/elasticsearch-${ELASTICSEARCH_PY_VERSION}.tar.gz -o /tmp/elasticsearch.tar.gz \
    && echo "$ELASTICSEARCH_PY_SHA256  elasticsearch.tar.gz" | sha256sum -c \
    && tar xzf elasticsearch.tar.gz \
    && cd elasticsearch-$ELASTICSEARCH_PY_VERSION \
    && python setup.py install \
    && rm -rf /tmp/elasticsearch*

# Export HTTP & Transport
EXPOSE 9200 9300

ENV ES_VERSION=6.4.1 \
    PATH=/usr/share/elasticsearch/bin:$PATH \
    ES_JAVA_OPTS="-Xms512m -Xmx512m" \
    CLUSTER_NAME=elasticsearch-default \
    NODE_MASTER=true \
    NODE_DATA=true \
    NODE_INGEST=true \
    HTTP_ENABLE=true \
    NETWORK_HOST=_site_ \
    HTTP_CORS_ENABLE=true \
    HTTP_CORS_ALLOW_ORIGIN="*" \
    MINIMUM_NUMBER_OF_MASTERS=1 \
    MAX_LOCAL_STORAGE_NODES=1 \
    SHARD_ALLOCATION_AWARENESS="" \
    SHARD_ALLOCATION_AWARENESS_ATTR="" \
    MEMORY_LOCK=false \
    REPO_LOCATIONS="" \
    DISCOVERY_SERVICE=elasticsearch-discovery \
    NETWORK_ADDRESS_CACHE_TTL=3 \
    NETWORK_ADDRESS_CACHE_NEGATIVE_TTL=10 \
    DISCOVERY_SERVICE=elasticsearch-discovery

WORKDIR /usr/share/elasticsearch

# Copy run script
COPY run.sh /

# Copy scripts 
COPY scripts /

USER elasticsearch

CMD ["/run.sh"]
