#!/usr/bin/env bash

POD=$POD
SHAREDCNT="${1}"

CGROUP_PATH="/sys/fs/cgroup"
CPU_SUBSYSTEM="cpuset"
CGROUP_K8S="kubepods.slice"
CGROUP_K8S_PATH="$CGROUP_PATH/$CPU_SUBSYSTEM/$CGROUP_K8S"

PODS_PREFIX="kubepods-pod"
PODS_SUFFIX=".slice"

CNT_ID=""
POD_ID=""

function get_cnt_id() {
    local prefix="cri-o://"
    local id

    id=$(oc get pod "$POD" -o json | jq '.status.containerStatuses[] | select(.name == "$SHAREDCNT") | .containerID')

    # remove trailing and leading double quotes
    id=$(echo $id | tr -d '"')

    # remove prefix
    id=${id#"$prefix"}

    CNT_ID=$id
}

function get_pod_id() {
  local id

  id=$(oc get pod "$POD" -o json | jq .metadata.uid)

  # remove trailing and leading double quotes
  id=$(echo $id | tr -d '"')

  POD_ID=$id
}

get_cnt_id
if [ -z $CNT_ID ]; then
  echo "failed to get container id"
  exit 1
fi

get_pod_id
if [ -z $POD_ID ]; then
  echo "failed to get container id"
  exit 2
fi







