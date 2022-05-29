#!/usr/bin/env bash

shared_cnt=$(jq -r '.annotations.cpu-shared-container.crio.io' /dev/stdin 2>&1)
bundle=$(jq -r '.bundle' /dev/stdin 2>&1)
cnt_id=$(jq -r '.id' < ${bundle}/config.json)
pod_cgroup=$(jq '.linux.cgroupsPath' < ${bundle}/config.json)

# make sure it's a guaranteed pod
if [[ ${pod_cgroup} =~ ".*burstable.*" ]] || [[ ${pod_cgroup} =~ ".*besteffort.*" ]]; then
    echo "pod $(jq -r .hostname < "${bundle}"/config.json) is not guaranteed"
    exit 0
fi

for cnt in /run/runc/*; do
  # find the container name
  name=$(jq -r '.config.labels[]|select(startswith("io.kubernetes.container.name"))' < $cnt/state.json | awk -F '=' '${print $2}')

  if [[ "$name" == "$shared_cnt" ]]; then
    cpuset=$(jq -r .config.cgroups.cpuset_cpus < $cnt/state.json)
    break
  fi
done

if [[ -z $cpuset ]]; then
  echo "cpuset for container $shared_cnt is empty"
  exit 0
fi

# parse cpuset into an array of cpu numbers
# usually we would have only a single cpu,
# but let's cover multiple cpus just in case
IFS=', ' read -r -a cpulist <<< "$cpuset"














