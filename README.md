# cgroups-playground

An experimental project for injecting additional CPUs to container via cgroups modification.
The injection done using an OCI that is running prior to container creation.

The injected CPUs can be shared among different guranteed containers and save the reservation of complete CPUs for lightweight tasks.
