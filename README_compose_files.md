# Compose file structure

Run commands from `curtmini_piper_containers/`. The infrastructure includes the
application definitions and adds shared configuration:

| File | Purpose |
| --- | --- |
| `compose.yaml` | Includes the application repositories' Compose files |
| `compose.cyclonedds.yaml` | Configures CycloneDDS and mounts its configuration |
| `compose.zenoh.yaml` | Configures Zenoh and starts the local router |
| `compose.gui.yaml` | Includes each application's GUI aggregator or overlay |
| `compose.workspace.yaml` | Adds the workspace builder and shared install mounts |

The robot, simulator, and tools checkouts must exist before Compose can load
their includes. Their locations are selected by `CURTMINI_PIPER_SOURCE`,
`CURTMINI_PIPER_GZ_SIM_SOURCE`, and `CURTMINI_PIPER_TOOLS_SOURCE`, with defaults
matching the project workspace.
Paths inside included application files are resolved relative to those files.

## Application services

`curtmini_piper/compose.yaml` includes package-owned `docker/compose.yaml`
files for hardware, RealSense, RViz, teleop, navigation, and ROS CLI services.
Its six runtime targets are
`hardware` (arm), `base-hardware`, `moveit-rviz`, `teleop`, `navigation`, and
`sensors`.

Shared ROS, description, and MoveIt configuration images are declared by
`piper-ros-base`, `piper-description`, and `piper-moveit-config`. They have
zero replicas. Compose builds them automatically when a selected image
needs them, without starting helper containers. Package GUI overrides are
collected by `curtmini_piper/compose.gui.yaml`. The infrastructure continues to
apply middleware configuration to the same public service names.

Compose 2.24.4 or newer is required for the workspace overlay's `!override`
build contexts. This prevents normal robot image dependencies from leaking
into the independent workspace build.

`curtmini_piper_tools/compose.yaml` includes one Compose file from each tools
package. The MoveItPy example defines `moveitpy-sim` and `moveitpy-hardware`,
and the C++ MoveIt client defines `moveit-action-client-sim` and
`moveit-action-client-hardware`. The navigation example defines
`nav2-goal-client`, and the tag package defines `tag-pose-sim`. Each package
owns its Dockerfile and ROS package list. Both MoveIt clients build on the
robot's MoveIt RViz image; the other two use a ROS base image. Build the MoveIt RViz image first; `scripts/build-all.sh`
handles that order.

`curtmini_piper_gz_sim/docker/compose.yaml` defines `gz-sim` and its Gazebo build.
Regular application builds use their owning repositories' upstream `main`
branches. Gazebo still reads the local `geometry.yaml` and
`initial_state.yaml` mount settings at runtime. Local simulator code is built
by the workspace workflow below.
Compose still loads service definitions from the local checkouts, so edits to
their package `docker/compose.yaml` files can change commands, mounts, and build settings
for regular services. Physical camera mounts and navigation maps are local
runtime inputs too.
Gazebo is headless by default (`gui:=false`). It starts MoveIt and controllers;
RViz is a separate client, so the simulation uses `use_rviz:=false`.
See [Compose services](README_compose_service.md) for the service names and roles.

## Middleware and GUI

Use one middleware overlay, matching `RMW`: `compose.cyclonedds.yaml` or
`compose.zenoh.yaml`. The GUI overlay includes application settings for `DISPLAY`,
the X11 socket, and `/dev/dri`. It enables the Gazebo window and passes world,
and lidar settings. Initial pose comes from the simulator's `config/initial_state.yaml`. RViz defaults to hardware rendering; use
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

Use this optional workflow to compile simulation, navigation, and tools
packages from mounted local repositories into a shared install volume. Hardware bringup
and drivers are excluded. Build it before starting any service that uses the volume:

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
development image; hardware services use the installation in their own images
and do not mount the shared workspace installation.

Without this overlay, application builds default to their owning repository's
upstream `main` and import dependencies from repository-owned manifests.
`CURTMINI_PIPER_IMAGE_SOURCE=/absolute/path/to/curtmini_piper` selects a local
robot image build, including hardware, independently of the workspace overlay. See
[source inputs](README.md#source-inputs) and
[local workspace details](README.md#local-simulation-workspace).

## Environment selection

`.env` supplies values on each Compose invocation, and shell exports take
precedence. An exported `COMPOSE_FILE` such as
`compose.yaml:compose.cyclonedds.yaml:compose.gui.yaml` replaces repeated `-f`
arguments. Export it in each terminal, or set it in `.env`. Explicit `-f`
arguments override that selection. `.env.example` selects regular application
images with CycloneDDS and GUI support. Add `compose.workspace.yaml` only when
building local source changes with `workspace-builder`.
Changing `RMW` also requires selecting its matching middleware overlay.

Build and verification helper scripts resolve settings through Compose, honoring
`.env` and shell overrides. `build-all.sh` builds the regular application images;
`verify-simulation.sh` accepts extra `-f` options for the workspace overlay.

Navigation services belong to `curtmini_piper_navigation/docker/compose.yaml`,
included by the robot root Compose file.
They use the same middleware, workspace and GUI files as the other simulation
services; no additional overlay is needed.
