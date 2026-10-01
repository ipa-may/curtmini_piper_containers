# Compose file structure

Run commands from `curtmini_piper_containers/`. The infrastructure includes the
application definitions and adds shared configuration:

| File | Purpose |
| --- | --- |
| `compose.yaml` | Includes each application repository's `docker/compose.yaml` |
| `compose.cyclonedds.yaml` | Configures CycloneDDS and mounts its configuration |
| `compose.zenoh.yaml` | Configures Zenoh and starts the local router |
| `compose.gui.yaml` | Includes each application's `docker/compose.gui.yaml` |
| `compose.workspace.yaml` | Adds the workspace builder and shared install mounts |

The robot and simulator checkouts must exist before Compose can load the includes.
Their locations are selected by `CURTMINI_PIPER_SOURCE` and
`CURTMINI_PIPER_GZ_SIM_SOURCE`, with defaults matching the project workspace.
Paths inside included application files are resolved relative to those files.

## Application services

`curtmini_piper/docker/compose.yaml` defines hardware, RViz, MoveItPy, teleop, and
ROS CLI services. Its builds select one of four targets from `docker/Dockerfile`:
`hardware`, `moveit-rviz`, `moveitpy`, or `teleop`.

`curtmini_piper_gz_sim/docker/compose.yaml` defines `gz-sim` and its Gazebo build.
Gazebo is headless by default (`gui:=false`). It starts MoveIt and controllers;
RViz is a separate client, so the simulation uses `use_rviz:=false`.
See [Compose services](README_compose_service.md) for the service names and roles.

## Middleware and GUI

Use one middleware overlay, matching `RMW`: `compose.cyclonedds.yaml` or
`compose.zenoh.yaml`. The GUI overlay includes application settings for `DISPLAY`,
the X11 socket, and `/dev/dri`. It enables the Gazebo window and passes world,
lidar, and spawn settings. RViz defaults to hardware rendering; use
`LIBGL_ALWAYS_SOFTWARE=1` for its software-rendering fallback.

For example, launch the office world and RViz with the regular application images:

```bash
export CONTAINER_ROS_DISTRO=jazzy
export RMW=cyclonedds
xhost +si:localuser:root
SIM_WORLD=curtmini_piper_map docker compose \
  -f compose.yaml -f compose.cyclonedds.yaml -f compose.gui.yaml \
  up --build gz-sim moveit-rviz-sim
```

The X11 rule names `root` because that is the current container user. The GUI
files are overlays and must be combined with the base configuration.

## Workspace overlay

Use this optional workflow to compile mounted local repositories into a shared
install volume. Build it before starting any service that uses the volume:

```bash
docker compose -f compose.yaml -f compose.cyclonedds.yaml \
  -f compose.workspace.yaml build workspace-builder
docker compose -f compose.yaml -f compose.cyclonedds.yaml \
  -f compose.workspace.yaml run --rm workspace-builder
SIM_WORLD=curtmini_piper_map docker compose \
  -f compose.yaml -f compose.cyclonedds.yaml \
  -f compose.workspace.yaml -f compose.gui.yaml \
  up gz-sim moveit-rviz-sim
```

The simulator and `neo_gz_worlds` default to checkouts under
`src/curtmini_piper_simulation/`. Source mounts are read-only; the builder writes
compiled packages to named volumes. Rerun it after editing local source, then
restart affected services with the overlay. Gazebo and simulation tools use the
development image; hardware services retain their normal images with the shared
installation mounted over `/opt/ws/install`.

Without this overlay, application builds copy their owning repository locally
and import upstream sources from repository-owned manifests. See
[source inputs](README.md#source-inputs) and
[local workspace details](README.md#local-simulation-workspace).

## Environment selection

`.env` supplies values on each Compose invocation, and shell exports take
precedence. An exported `COMPOSE_FILE` such as
`compose.yaml:compose.cyclonedds.yaml:compose.gui.yaml` replaces repeated `-f`
arguments. Export it in each terminal, or set it in `.env`. Explicit `-f`
arguments override that selection. `.env.example` does not set `COMPOSE_FILE`.
