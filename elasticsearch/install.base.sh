#!/bin/bash

set -ex
set -o nounset

tar -xf /tmp/elasticsearch-${ES_VER}.tar.gz -C $ES_HOME --strip-components=1
rm /tmp/elasticsearch-${ES_VER}.tar.gz

# list of plugins to be installed
if [ -z "${ES_CLOUD_K8S_URL:-}" ] ; then
    ES_CLOUD_K8S_URL=http://central.maven.org/maven2/io/fabric8/elasticsearch-cloud-kubernetes/${ES_CLOUD_K8S_VER}/elasticsearch-cloud-kubernetes-${ES_CLOUD_K8S_VER}.zip
fi
es_plugins=($ES_CLOUD_K8S_URL)

echo "ES plugins: ${es_plugins[@]}"
for es_plugin in ${es_plugins[@]}
do
  ${ES_HOME}/bin/elasticsearch-plugin install $es_plugin
done

mkdir /elasticsearch
mkdir -p $ES_PATH_CONF
chmod -R og+w $ES_PATH_CONF ${ES_HOME} ${HOME} /elasticsearch
chmod -R o+rx /etc/elasticsearch
