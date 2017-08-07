#!/bin/bash
set -euo pipefail
if [ -n "${DEBUG:-}" ] ; then
    set -x
fi

if [[ $# -eq 0 ]]
then
  all=true
fi

while (($#))
do
  case $1 in
    kibana)
      kibana=true
      ;;
    fluentd)
      fluentd=true
      ;;
    curator)
      curator=true
      ;;
    elasticsearch)
      elasticsearch=true
      ;;
    *)
      echo Unknown argument $1
      exit 1
      ;;
  esac
  shift
done

DATE=`date +%Y%m%d_%H%M%S`
target="logging-$DATE"
logs_folder="$target/logs"
es_folder="$target/es"
fluentd_folder="$target/fluentd"
kibana_folder="$target/kibana"
curator_folder="$target/curator"
project_folder="$target/project"

dump_resource_items() {
  local type=$1
  mkdir $project_folder/$type
  for resource in `oc get $type -o name`
  do
    oc get $resource -o yaml > $project_folder/$resource
  done
}

get_project_info() {
  mkdir $project_folder
  echo Getting general objects
  echo -- Nodes Description
  oc describe nodes > $project_folder/nodes
  echo -- Project Description
  oc get namespace logging -o yaml > $project_folder/logging-project
  echo -- Events
  oc get events > $project_folder/events
  # Don't get the secrets content for security reasons
  echo -- Secrets
  oc describe secrets > $project_folder/secrets

  resource_types=(deploymentconfigs daemonsets configmaps services routes serviceaccounts pvs pvcs pods)
  for resource_type in ${resource_types[@]}
  do
    echo -- Extracting $resource_type ...
    dump_resource_items $resource_type
  done
}

get_env() {
  local pod=$1
  local env_file=$2/$pod
  containers=$(oc get po $pod -o jsonpath='{.spec.containers[*].name}')
  for container in $containers
  do
    dockerfile=$(oc exec $pod -c $container -- find /root/buildinfo -name "Dockerfile-openshift3-logging*")
    if [[ ! $dockerfile ]]
    then
      echo Unable to get buildinfo for $pod - $container ... skipping
    else
      echo Dockerfile info: $dockerfile > $env_file
      oc exec $pod -c $container -- grep -o "\"build-date\"=\"[^[:blank:]]*\"" $dockerfile >> $env_file
    fi
    echo -- Environment Variables >> $env_file
    oc exec $pod -c $container -- env >> $env_file
  done
}

get_pod_logs() {
  local pod=$1
  local logs_folder=$2/logs
  echo -- POD $1 Logs
  if [ ! -d "$logs_folder" ]
  then
    mkdir $logs_folder
  fi
  local containers=$(oc get po $pod -o jsonpath='{.spec.containers[*].name}')
  for container in $containers
  do
    oc logs $pod -c $container > $logs_folder/$pod-$container.log
  done
}

check_fluentd_connectivity() {
  local pod=$1
  echo --Connectivity between $pod and elasticsearch >> $fluentd_folder/$pod
  es_host=$(oc get pod $pod  -o jsonpath='{.spec.containers[0].env[?(@.name=="ES_HOST")].value}')
  es_port=$(oc get pod $pod  -o jsonpath='{.spec.containers[0].env[?(@.name=="ES_PORT")].value}')
  echo "  with ca" >> $fluentd_folder/$pod
  oc exec $pod -- curl -ILvs --key /etc/fluent/keys/key --cert /etc/fluent/keys/cert --cacert /etc/fluent/keys/ca -XGET https://$es_host:$es_port &>> $fluentd_folder/$pod
  echo "  without ca" >> $fluentd_folder/$pod
  oc exec $pod -- curl -ILkvs --key /etc/fluent/keys/key --cert /etc/fluent/keys/cert -XGET https://$es_host:$es_port &>> $fluentd_folder/$pod
  echo --Connectivity between $pod and elasticsearch-ops >> $fluentd_folder/$pod
  es_host=$(oc get pod $pod  -o jsonpath='{.spec.containers[0].env[?(@.name=="OPS_HOST")].value}')
  es_port=$(oc get pod $pod  -o jsonpath='{.spec.containers[0].env[?(@.name=="OPS_PORT")].value}')
  echo "  with ca" >> $fluentd_folder/$pod
  oc exec $pod -- curl -ILvs --key /etc/fluent/keys/key --cert /etc/fluent/keys/cert --cacert /etc/fluent/keys/ca -XGET https://$es_host:$es_port &>> $fluentd_folder/$pod
  echo "  without ca" >> $fluentd_folder/$pod
  oc exec $pod -- curl -ILkvs --key /etc/fluent/keys/key --cert /etc/fluent/keys/cert -XGET https://$es_host:$es_port &>> $fluentd_folder/$pod
}

check_fluentd() {
  echo -- Checking Fluentd health
  fluentd_pods=$(oc get pods | grep -o logging-fluentd-[^[:blank:]]*)
  mkdir $fluentd_folder
  for pod in $fluentd_pods
  do
    echo ---- Fluentd pod: $pod
    get_env $pod $fluentd_folder
    get_pod_logs $pod $fluentd_folder
    check_fluentd_connectivity $pod
  done
}

check_curator_connectivity() {
  local pod=$1
  echo --Connectivity between $pod and elasticsearch >> $curator_folder/$pod
  es_host=$(oc get pod $pod  -o jsonpath='{.spec.containers[0].env[?(@.name=="ES_HOST")].value}')
  es_port=$(oc get pod $pod  -o jsonpath='{.spec.containers[0].env[?(@.name=="ES_PORT")].value}')
  echo "  with ca" >> $curator_folder/$pod
  oc exec $pod -- curl -ILvs --key /etc/curator/keys/key --cert /etc/curator/keys/cert --cacert /etc/curator/keys/ca -XGET https://$es_host:$es_port &>> $curator_folder/$pod
  echo "  without ca" >> $curator_folder/$pod
  oc exec $pod -- curl -ILkvs --key /etc/curator/keys/key --cert /etc/curator/keys/cert -XGET https://$es_host:$es_port &>> $curator_folder/$pod
  echo --Connectivity between $pod and elasticsearch-ops >> $curator_folder/$pod
  es_host=$(oc get pod $pod  -o jsonpath='{.spec.containers[0].env[?(@.name=="OPS_HOST")].value}')
  es_port=$(oc get pod $pod  -o jsonpath='{.spec.containers[0].env[?(@.name=="OPS_PORT")].value}')
  echo "  with ca" >> $curator_folder/$pod
  oc exec $pod -- curl -ILvs --key /etc/curator/keys/key --cert /etc/curator/keys/cert --cacert /etc/curator/keys/ca -XGET https://$es_host:$es_port &>> $curator_folder/$pod
  echo "  without ca" >> $curator_folder/$pod
  oc exec $pod -- curl -ILkvs --key /etc/curator/keys/key --cert /etc/curator/keys/cert -XGET https://$es_host:$es_port &>> $curator_folder/$pod
}

check_curator() {
  echo -- Checking Curator health
  local curator_pods=$(oc get pods | grep -o logging-curator-[^[:blank:]]*)
  mkdir $curator_folder
  for pod in $curator_pods
  do
    echo ---- Curator pod: $pod
    get_env $pod $curator_folder
    get_pod_logs $pod $curator_folder
    check_curator_connectivity $pod
  done
}

check_kibana_connectivity() {
  pod=$1
  echo ---- Connectivity between $pod and elasticsearch >> $kibana_folder/$pod
  es_host=$(oc get pod $pod  -o jsonpath='{.spec.containers[?(@.name=="kibana")].env[?(@.name=="ES_HOST")].value}')
  es_port=$(oc get pod $pod  -o jsonpath='{.spec.containers[?(@.name=="kibana")].env[?(@.name=="ES_PORT")].value}')
  echo "  with ca" >> $kibana_folder/$pod
  oc exec $pod -c kibana -- curl -ILvs --key /etc/kibana/keys/key --cert /etc/kibana/keys/cert --cacert /etc/kibana/keys/ca -XGET https://$es_host:$es_port &>> $kibana_folder/$pod
  echo "  without ca" >> $kibana_folder/$pod
  oc exec $pod -c kibana -- curl -ILkvs --key /etc/kibana/keys/key --cert /etc/kibana/keys/cert -XGET https://$es_host:$es_port &>> $kibana_folder/$pod
}

check_kibana() {
  echo -- Checking Kibana health
  kibana_pods=$(oc get pods | grep -o logging-kibana-[^[:blank:]]*)
  mkdir $kibana_folder
  for pod in $kibana_pods
  do
    echo ---- Kibana pod: $pod
    get_env $pod $kibana_folder
    get_pod_logs $pod $kibana_folder
    check_kibana_connectivity $pod
  done
}

get_elasticsearch_status() {
  local pod=$1
  local cluster_folder=$es_folder/cluster-$2
  mkdir $cluster_folder
  scurl_es='curl -sv --max-time 5 --key /etc/elasticsearch/secret/admin-key --cert /etc/elasticsearch/secret/admin-cert --cacert /etc/elasticsearch/secret/admin-ca https://localhost:9200'
  curl_es='curl --max-time 5 --key /etc/elasticsearch/secret/admin-key --cert /etc/elasticsearch/secret/admin-cert --cacert /etc/elasticsearch/secret/admin-ca https://localhost:9200'
  local cat_items=(health nodes indices aliases thread_pool)
  for cat_item in ${cat_items[@]}
  do
    oc exec $pod -- $scurl_es/_cat/$cat_item?v &> $cluster_folder/$cat_item
  done
  local health=$(oc exec $pod -- $curl_es/_cat/health?h=status)
  if [ $health != "green" ]
  then
    echo Gathering additional cluster information Cluster status is $health
    cat_items=(recovery shards pending_tasks)
    for cat_item in ${cat_items[@]}
    do
      oc exec $pod -- $scurl_es/_cat/$cat_item?v &> $cluster_folder/$cat_item
    done
    oc exec $pod -- $scurl_es/_cat/shards?h=index,shard,prirep,state,unassigned.reason,unassigned.description | grep UNASSIGNED &> $cluster_folder/unassigned_shards
  fi

}

list_es_storage() {
  local pod=$1
  local mountPath=$(oc get pod $pod -o jsonpath='{.spec.containers[0].volumeMounts[?(@.name=="elasticsearch-storage")].mountPath}')
  echo -- Persistence files -- >> $es_folder/$pod
  oc exec $pod -- ls -lR $mountPath >> $es_folder/$pod
}

check_elasticsearch() {
  echo Checking Elasticsearch health
  echo -- Checking Elasticsearch health
  local es_pods=$(oc get pods | grep -o logging-es-[^[:blank:]]*)
  mkdir $es_folder
  for pod in $es_pods
  do
    echo ---- Elasticsearch pod: $pod
    get_env $pod $es_folder
    get_pod_logs $pod $es_folder
    list_es_storage $pod
  done
  echo -- Getting Elasticsearch cluster info from logging-es pod
  local anypod=$(oc get pods --selector="component=es" --no-headers | grep Running | awk '{print$1}' | tail -1)
  get_elasticsearch_status $anypod es
  echo -- Getting Elasticsearch OPS cluster info from logging-es-ops pod
  anypod=$(oc get po --selector="component=es-ops" --no-headers | grep Running | awk '{print$1}' | tail -1)
  if [[ ! $anypod ]]
  then
    echo No es-ops pods found. Skipping...
  else
    get_elasticsearch_status $anypod es-ops
  fi
}

oc project logging
mkdir $target

if [ "$all" = true ]
then
  get_project_info
fi
if [ "$all" = true ] || [ "$fluentd" = true ]
then
  check_fluentd
fi
if [ "$all" = true ] || [ "$kibana" = true ]
then
  check_kibana
fi
if [ "$all" = true ] || [ "$curator" = true ]
then
  check_curator
fi
if [ "$all" = true ] || [ "$elasticsearch" = true ]
then
  check_elasticsearch
fi
