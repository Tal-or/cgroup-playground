#!/usr/bin/env bash

JQ="/usr/bin/jq"

# The state of the container MUST be passed to hooks over stdin
# so that they may do work appropriate to the current state of the container.
# https://github.com/opencontainers/runtime-spec/blob/main/runtime.md#state
state=$(${JQ} -r '.' /dev/stdin 2>&1)

shared_cnt=$(${JQ} -r '.annotations["cpu-shared-container.crio.io"]' <<< "${state}")
bundle=$(${JQ} -r '.bundle' <<< "${state}")
pod_cgroup=$(${JQ} '.linux.cgroupsPath' < ${bundle}/config.json)

# make sure it's a guaranteed pod
if [[ ${pod_cgroup} =~ .*burstable.* ]] || [[ ${pod_cgroup} =~ .*besteffort.* ]]; then
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
  logger "cpuset for container $shared_cnt is empty"
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

logger "updated cpuset ${cpuset}"

tmpf=$(mktemp)

# update the bundle file and redirect to temp file
${JQ} --arg cpuset "${cpuset}"  '.linux.resources.cpu.cpus = $cpuset'  < "${bundle}"/config.json > "${tmpf}"

logger -S 500KiB "tmpf: $(cat ${tmpf})"
# override the original config with the changes
mv -fv "${tmpf}" "${bundle}"/config.json


logger -S 500KiB "bundle/config.json after: $(cat ${bundle}/config.json)"

logger "new cpuset_cpus for container $(${JQ} '.linux.resources.cpu.cpus' < "${bundle}"/config.json)"

