# Compose file structure

See [Compose services](README_compose_service.md) for the available services
and the differences between their simulation and hardware variants.

The Compose configuration is split into a base file and optional overlays:

| File | Purpose |
| --- | --- |
| `compose.yaml` | Defines the services and their default headless behavior |
| `compose.cyclonedds.yaml` | Configures CycloneDDS and mounts its configuration |
| `compose.zenoh.yaml` | Configures Zenoh and starts the local router |
| `compose.gui.yaml` | Adds X11 access and enables graphical applications |
| `compose.workspace.yaml` | Builds mounted local sources and uses their shared install |

The overlay files contain partial service definitions and are intended to be
used with `compose.yaml`. Compose merges files from left to right, so later
files extend or override earlier settings.

For example, this combines the base services, CycloneDDS, the local development
workspace, and GUI support:

```bash
docker compose \
  -f compose.yaml \
  -f compose.cyclonedds.yaml \
  -f compose.workspace.yaml \
  -f compose.gui.yaml \
  up gz-sim
```

## Base services

`compose.yaml` owns service names, images, build definitions, commands,
profiles, networking, and common ROS environment variables. Gazebo is headless
by default (`gui:=false`), which also supports CI. RViz runs as a separate
service, so Gazebo uses `use_rviz:=false`.

## Middleware overlays

Use exactly one middleware overlay. `compose.cyclonedds.yaml` mounts the
CycloneDDS configuration. `compose.zenoh.yaml` mounts the Zenoh session
configuration, adds the router, and makes ROS services wait for it.

## GUI overlay

`compose.gui.yaml` passes `DISPLAY`, mounts the X11 socket, enables the Gazebo
GUI, and configures software rendering for RViz. Leave it out for headless use.
Its Gazebo command also forwards `SIM_WORLD`, `SIM_USE_HOKUYO`, and the
`SIM_SPAWN_*` settings, retaining the selections made for headless operation.

## Workspace overlay

`compose.workspace.yaml` adds `workspace-builder`, which mounts the local source
repositories and runs `colcon build`. Its install volume is shared with the
Gazebo, simulation RViz, and simulation MoveItPy services. Changing source or
checkout paths requires another workspace build, not an image rebuild.
The simulator and `neo_gz_worlds` are mounted from
`src/curtmini_piper_simulation/` by default. Their installed world files and
models are included in the shared install volume.

Leave this overlay out when building or running images directly from the Git
revisions in `locks/<distro>/dependencies.repos`.
