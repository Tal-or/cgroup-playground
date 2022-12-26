#!/usr/bin/env bash

JQ="/usr/bin/jq"
CGROUPS_GU_POD_PATH="/sys/fs/cgroup/cpuset/kubepods.slice"

# The state of the container MUST be passed to hooks over stdin
# so that they may do work appropriate to the current state of the container.
# https://github.com/opencontainers/runtime-spec/blob/main/runtime.md#state
state=$(${JQ} -r '.' /dev/stdin 2>&1)
shared_cnt=$(${JQ} -r '.annotations["cpu-shared-container.crio.io"]' <<< "${state}")
bundle=$(${JQ} -r '.bundle' <<< "${state}")
pod_cgroups=$(${JQ} -r '.linux.cgroupsPath' < ${bundle}/config.json)

# make sure it's a guaranteed pod
if [[ ${pod_cgroups} =~ .*burstable.* ]] || [[ ${pod_cgroups} =~ .*besteffort.* ]]; then
    logger "pod $(${JQ} -r .hostname < "${bundle}"/config.json) is not guaranteed"
    exit 0
fi

# find the state file of the shared container by its name
for cnt in /run/runc/*; do
  name=$(${JQ} -r '.config.labels[]|select(startswith("io.kubernetes.container.name"))' < "${cnt}"/state.json | awk -F '=' '{print $2}')
  if [[ "$name" == "$shared_cnt" ]]; then
    shared_cpuset=$(${JQ} -r .config.cgroups.cpuset_cpus < "${cnt}"/state.json)
    break
  fi
done

if [[ -z "$shared_cpuset" ]]; then
  logger "cpuset of shared container $shared_cnt is empty"
  exit 0
fi

# parse cpuset into an array of cpu numbers
# usually we would only have a single cpu reserved for the shared container,
# but let's cover multiple cpus just in case
IFS=', ' read -r -a shared_cpulist <<< "${shared_cpuset}"

# get the container (the one that triggered the hook) cpuset
cpuset=$(${JQ} -r '.linux.resources.cpu.cpus' < "${bundle}"/config.json)

if [[ -z "$cpuset" ]]; then
  logger "cpuset for current container is empty"
  exit 0
fi

# append cpus of the shared container
for cpu in "${shared_cpulist[@]}"; do
  cpuset+=",${cpu}"
done

IFS=':' read -ra cgroups_path <<< "${pod_cgroups}"
echo "${cpuset}" > "${CGROUPS_GU_POD_PATH}"/"${cgroups_path[0]}"/"${cgroups_path[1]}"-"${cgroups_path[2]}".scope/cpuset.cpus
logger "updated cpuset in cgroups: $(cat "${CGROUPS_GU_POD_PATH}"/"${cgroups_path[0]}"/"${cgroups_path[1]}"-"${cgroups_path[2]}".scope/cpuset.cpus)"

env_path=$(${JQ} -r '.mounts[] |  select(.destination == "/run/.containerenv") | .source' < "${bundle}/config.json")
# inject the shared CPUs via environment variable
echo "SHARED_CPUS=${shared_cpuset}" >> "${env_path}"
