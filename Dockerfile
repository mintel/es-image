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

FROM docker.elastic.co/elasticsearch/elasticsearch-oss:6.3.2

LABEL vendor="Mintel"
LABEL version="6.3.2"
LABEL maintainer "fciocchetti@mintel.com"


# Export HTTP & Transport
EXPOSE 9200 9300

ENV ES_VERSION 6.3.2

ENV PATH /usr/share/elasticsearch/bin:$PATH

WORKDIR /usr/share/elasticsearch

# Copy configuration
COPY config /usr/share/elasticsearch/config

# Copy run script
COPY run.sh /

# Copy scripts 
COPY scripts /

# Set environment variables defaults
ENV ES_JAVA_OPTS "-Xms512m -Xmx512m"
ENV CLUSTER_NAME elasticsearch-default
ENV NODE_MASTER true
ENV NODE_DATA true
ENV NODE_INGEST true
ENV HTTP_ENABLE true
ENV NETWORK_HOST _site_
ENV HTTP_CORS_ENABLE true
ENV HTTP_CORS_ALLOW_ORIGIN *
ENV MINIMUM_NUMBER_OF_MASTERS 1
ENV MAX_LOCAL_STORAGE_NODES 1
ENV SHARD_ALLOCATION_AWARENESS ""
ENV SHARD_ALLOCATION_AWARENESS_ATTR ""
# Kubernetes requires swap is turned off, so memory lock is redundant
ENV MEMORY_LOCK false
ENV REPO_LOCATIONS ""
ENV DISCOVERY_SERVICE elasticsearch-discovery
ENV NETWORK_ADDRESS_CACHE_TTL 3
ENV NETWORK_ADDRESS_CACHE_NEGATIVE_TTL 10
ENV DISCOVERY_SERVICE elasticsearch-discovery

# Volume for Elasticsearch data
VOLUME ["/data"]

RUN chown elasticsearch:elasticsearch -R /usr/share/elasticsearch /data && \
    chown elasticsearch:elasticsearch -R /opt/jdk-10.0.2/conf
USER elasticsearch

CMD ["/run.sh"]
