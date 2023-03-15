package main

import "github.com/containerd/cgroups"

func main() {
	var cgroupV2 bool
	if cgroups.Mode() == cgroups.Unified {
		cgroupV2 = true
	}
}
