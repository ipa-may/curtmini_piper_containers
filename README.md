# Curt Mini Piper Containers

Compose entry point and shared tooling for Curt Mini with a Piper arm. Application
Dockerfiles and services are maintained in their owning source repositories. The repository targets ROS 2 Jazzy with CycloneDDS or Zenoh. Nav2 mapping and goal navigation are available in simulation, along with two D435i-like cameras. Two optional RealSense services run physical cameras.

See [Compose file structure](README_compose_files.md) for how the base file and
optional overlays are combined, and [Compose services](README_compose_service.md)
for the available services and their roles. Run commands below from
`curtmini_piper_containers/`.

## Variant model

Set the variant with environment variables:

```bash
export CONTAINER_ROS_DISTRO=jazzy
export RMW=cyclonedds
```

`CONTAINER_ROS_DISTRO` defaults to `jazzy` and is independent of the host's
`ROS_DISTRO`, so sourcing ROS 2 Humble on the host does not change the container
variant. If you have an existing `.env`, rename its `ROS_DISTRO` setting to
`CONTAINER_ROS_DISTRO`. Dockerfiles still use `ROS_DISTRO` internally; Compose
passes the selected container distro as that build argument.

Supported values are:

| Input | Values |
| --- | --- |
| `CONTAINER_ROS_DISTRO` | `jazzy` |
| `RMW` | `cyclonedds`, `zenoh` |

Images are tagged `jazzy-<rmw>`, for example:

| Image | Responsibility |
| --- | --- |
| `curtmini-piper-gazebo:jazzy-cyclonedds` | Gazebo, simulated controllers, and MoveIt |
| `curtmini-piper-hardware:jazzy-cyclonedds` | Piper arm hardware and MoveIt |
| `curtmini-piper-base-hardware:jazzy-cyclonedds` | Curt Mini base hardware, joystick, and IMU |
| `curtmini-piper-sensors:jazzy-cyclonedds` | Two separately selectable physical D435i cameras |
| `curtmini-piper-apriltag:jazzy-cyclonedds` | Optional base camera AprilTag detector |
| `curtmini-piper-moveit-rviz:jazzy-cyclonedds` | Standalone MoveIt RViz client |
| `curtmini-piper-moveitpy:jazzy-cyclonedds` | MoveItPy planning and execution examples |
| `curtmini-piper-moveit-action-client:jazzy-cyclonedds` | C++ client for the running MoveIt server |
| `curtmini-piper-nav2-goal-client:jazzy-cyclonedds` | Python client for Nav2 goal requests |
| `curtmini-piper-tag-pose:jazzy-cyclonedds` | Observed AprilTag poses in `map` |
| `curtmini-piper-navigation:jazzy-cyclonedds` | SLAM Toolbox, Nav2 and navigation RViz |
| `curtmini-piper-teleop:jazzy-cyclonedds` | Keyboard teleoperation and ROS CLI |
| `curtmini-piper-zenoh-router:jazzy-zenoh` | Robot-side Zenoh router |

`curtmini_piper/docker/Dockerfile` produces six runtime targets: `hardware`
(arm), `base-hardware`, `moveit-rviz`, `teleop`, `navigation`, and `sensors`. The arm and RViz
targets share the robot build. Each package in `curtmini_piper_tools` owns its
Dockerfile and Compose file. The MoveItPy image uses the robot's MoveIt RViz
image as its base, as does the C++ MoveIt action client. The Nav2 client and tag
pose images use the ROS base image.

`curtmini_piper_gz_sim/docker/Dockerfile` and the infrastructure's Zenoh Dockerfile
retain `base`, `dependencies`, `builder`, `test`, and `runtime` stages. The
workspace image has a single `runtime` stage with development tools.

The middleware variants share one source branch and use ROS 2 Jazzy.

## Source inputs

The root `compose.yaml` includes the Compose files from:

- `../rob4_fraunhofer_ws/src/curtmini_piper/docker/`
- `../rob4_fraunhofer_ws/src/curtmini_piper_tools/compose.yaml`
- `../rob4_fraunhofer_ws/src/curtmini_piper_simulation/curtmini_piper_gz_sim/docker/`

Each owner maintains its Dockerfile, package lists, and Compose services.
Regular image builds fetch the owning repository from upstream `main`.
The MoveItPy and C++ MoveIt client images build on the robot's published
MoveIt RViz image. The Nav2 client and tag pose images use a ROS base image.
The workspace overlay builds
unpublished local tools source.
The tools repository is private: regular tools builds use SSH authentication.
An SSH agent with access to it works by default. If that machine selects a
specific key through an SSH host alias, set
`CURTMINI_PIPER_TOOLS_SSH_AUTH=default=/absolute/path/to/private_key` in
`.env` so BuildKit uses the same key for its canonical GitHub URL.
Hardware's Python SDK revision lives
in the robot repository's `docker/dependencies/jazzy-hardware-python.env`.

For example, a regular Gazebo image fetches the simulator and robot code from
upstream `main`. It imports `curt_mini`, `agx_arm_urdf`, and `neo_gz_worlds`
from GitHub. The local robot `geometry.yaml` and simulator
`initial_state.yaml` remain runtime mount settings.
The teleop target installs binary packages and skips the source-build stages.
`project-docs/dependencies.repos` creates the host checkout layout.

Create local configuration without replacing an existing file:

```bash
[ -f .env ] || cp .env.example .env
```

`.env` selects the distro, middleware, image names, runtime settings, and source
paths used for Compose includes and workspace mounts. All three application
checkouts must exist. For another directory layout, adjust
`CURTMINI_PIPER_SOURCE`, `CURTMINI_PIPER_TOOLS_SOURCE`, and
`CURTMINI_PIPER_GZ_SIM_SOURCE`, and set `CONTAINER_INFRA_SOURCE` to this
infrastructure repository's absolute path for the shared build scripts.

Use the workspace overlay below to build edits in local checkouts. Rebuild a
regular image after its upstream code changes; a cached Git import may require
`docker compose build --no-cache` to fetch a new upstream `main` commit.
Source manifests use a mixture of branches, tags, and commit SHAs. Base-image
tags, branches, and apt packages can change.

## Optional configuration

The example selects regular application images with GUI support. Add
`compose.workspace.yaml` only when building unpublished local source changes;
see [local simulation workspace](#local-simulation-workspace). Explicit `-f`
options select a different workflow regardless of `COMPOSE_FILE` in `.env`.

Compose already supplies defaults for the following optional overrides:

| Settings | Purpose |
| --- | --- |
| `CAN_PORT`, `LPMS_DEVICE`, `JOYSTICK_DEVICE` | Hardware interfaces |
| `PUBLISH_BASE_DESCRIPTION` | Set `True` only when running `base-bringup` without `piper-bringup`; defaults to `False` for the full robot |
| `CONTROL_ENABLED`, `FAST_MODE` | Piper command acceptance and streaming; both default to `true` |
| `MOVEIT_PLAN_ONLY` | Plan without execution; defaults to `true` |
| `LIBGL_ALWAYS_SOFTWARE` | RViz rendering fallback; defaults to `0` |
| `IMAGE_PREFIX`, `ROS_IMAGE` | Image naming and custom Jazzy base image |
| `OCI_SOURCE`, `OCI_REVISION` | Image metadata |
| `ZENOH_ROUTER_CHECK_ATTEMPTS`, `SIM_CHECK_TIMEOUT` | Readiness timeouts |
| `CURT_MINI_SOURCE`, `CURTMINI_PIPER_SOURCE`, `AGX_ARM_URDF_SOURCE` | Alternate source checkout paths |
| `CURTMINI_PIPER_GZ_SIM_SOURCE`, `NEO_GZ_WORLDS_SOURCE` | Alternate simulation checkout paths |
| `CURTMINI_PIPER_TOOLS_SSH_AUTH` | SSH agent or key for the private upstream tools build |
| `CONTAINER_INFRA_SOURCE`, `CURTMINI_PIPER_DESCRIPTION_CONFIG_DIR` | Shared build-script path and simulator geometry-config path |

Inherit `DISPLAY` from the desktop session. Build and verification scripts read
settings through Compose, respecting `.env` and shell overrides. `ROS_IMAGE`
must contain Jazzy; other ROS distributions are not supported.

## Build

Build the selected application images and, for Zenoh, the router:

```bash
CONTAINER_ROS_DISTRO=jazzy RMW=cyclonedds ./scripts/build-all.sh
CONTAINER_ROS_DISTRO=jazzy RMW=zenoh ./scripts/build-all.sh
```

Build one application image through Compose:

```bash
docker compose -f compose.yaml -f compose.cyclonedds.yaml build gz-sim
```

To build a test target directly, supply the same shared script context as Compose:

```bash
sim_source=../rob4_fraunhofer_ws/src/curtmini_piper_simulation/curtmini_piper_gz_sim
docker buildx build --build-arg ROS_DISTRO=jazzy --build-arg RMW=cyclonedds \
  --build-context container_common=./common --target test \
  -f "$sim_source/docker/Dockerfile" "$sim_source"

docker compose -f compose.yaml -f compose.cyclonedds.yaml build moveit-rviz-sim
docker compose -f compose.yaml -f compose.cyclonedds.yaml build moveitpy-sim
```

The robot's test targets include `hardware-test`, `moveit-rviz-test`, and
`teleop-test`. Adjust the paths above if your checkout layout differs.
`ROS_IMAGE` can override the `ros:jazzy-ros-base-noble` base image.

An unchanged import layer can be cached even when its GitHub branch advances.
To refresh the simulation's downloaded dependencies:

```bash
docker compose -f compose.yaml -f compose.cyclonedds.yaml build --no-cache gz-sim
```

Then recreate the service with the appropriate `up` command.

## Local simulation workspace

`compose.workspace.yaml` mounts the local repositories into a
`workspace-builder`. It builds `curtmini_piper_gz_sim`,
`curtmini_piper_moveitpy_example`, `curtmini_piper_tag_tools`,
`curtmini_piper_nav_examples`, `curtmini_piper_navigation`, and their dependencies,
sharing the resulting install volume with Gazebo, simulation RViz, and tools. Hardware
bringup and drivers are excluded; hardware services use their own images.

Set optional checkout-path overrides in `.env` for a nonstandard layout, then build
the development image once and compile the workspace:

```bash
docker compose -f compose.yaml -f compose.cyclonedds.yaml \
  -f compose.workspace.yaml build workspace-builder
docker compose -f compose.yaml -f compose.cyclonedds.yaml \
  -f compose.workspace.yaml run --rm workspace-builder
```

The default source layout matches `project-docs/dependencies.repos`:

```text
rob4_fraunhofer_ws/src/
  curt_mini/
  curtmini_piper/
  curtmini_piper_tools/
  piper_driver/agx_arm_urdf/
  curtmini_piper_simulation/
    curtmini_piper_gz_sim/
    neo_gz_worlds/
```

The default paths already match this layout. For a different layout, override
`CURTMINI_PIPER_GZ_SIM_SOURCE` and `NEO_GZ_WORLDS_SOURCE` in `.env`.
`AGX_ARM_URDF_SOURCE` configures the arm description checkout. All these mounts
are read-only. The builder installs both the simulator and the Neobotix models
into the shared install volume; runtime containers use that installed copy.

Run Gazebo, then start RViz in another terminal with matching distro, middleware,
and ROS domain settings:

```bash
xhost +si:localuser:root
docker compose -f compose.yaml -f compose.cyclonedds.yaml \
  -f compose.workspace.yaml -f compose.gui.yaml \
  up gz-sim

docker compose -f compose.yaml -f compose.cyclonedds.yaml \
  -f compose.workspace.yaml -f compose.gui.yaml \
  run --rm moveit-rviz-sim

docker compose -f compose.yaml -f compose.cyclonedds.yaml \
  -f compose.workspace.yaml run --rm moveitpy-sim
```

After source or checkout-path changes, stop affected services, rerun
`workspace-builder`, and restart them with the workspace overlay. Rebuild the
workspace image when its package lists or workspace helper scripts change. The
dependency helper reads only the simulator's manifest, imports missing simulation
dependencies, and retains existing checkouts; a changed manifest does not update
those cached checkouts. Hardware dependencies cached by an older builder may
remain in the dependency volume, but are not selected for compilation.

Using `--profile '*' down -v` with the workspace overlay removes the project
containers and workspace volumes, including cached dependencies and build output.
It leaves the host source checkouts intact. Rebuild the workspace before launching
again after such a reset.

## CycloneDDS

Always combine the generic Compose file with the middleware overlay:

```bash
export CONTAINER_ROS_DISTRO=jazzy
export RMW=cyclonedds

docker compose \
  -f compose.yaml \
  -f compose.cyclonedds.yaml \
  --profile simulation up gz-sim
```

For Gazebo and the standalone MoveIt RViz client through X11, append
`compose.gui.yaml` and name both services:

```bash
xhost +si:localuser:root
docker compose \
  -f compose.yaml \
  -f compose.cyclonedds.yaml \
  -f compose.gui.yaml \
  --profile simulation up gz-sim moveit-rviz-sim
```

The `gz-sim` service owns `move_group`, the simulated controllers, and Gazebo.
The `moveit-rviz-sim` service waits for `/move_action` and then starts only
RViz. This prevents a second MoveIt server from being launched.

The current containers run as root; the X11 rule above allows their GUI clients
to use the desktop display. The GUI definitions already pass `/dev/dri` for GPU
access. RViz defaults to `LIBGL_ALWAYS_SOFTWARE=0`; set it to `1` only when you
need software rendering.

## Mapping world and lidar

`SIM_WORLD` selects `curtmini_piper` (default) or `curtmini_piper_map` (office
environment). Both the regular image and local workspace install these worlds.
The simulator requires `neo_gz_worlds` at startup even for the default world.

The simulation manifests select `neo_gz_worlds: gz-harmonic`, which provides the
office assets. If an older image reports missing furniture or window models,
check the selected manifest and rebuild without cache. For the workspace workflow,
check the local `neo_gz_worlds` branch and rerun `workspace-builder`.

Start the mapping world with Gazebo and the standalone MoveIt RViz client:

```bash
SIM_WORLD=curtmini_piper_map docker compose \
  -f compose.yaml -f compose.cyclonedds.yaml -f compose.gui.yaml \
  up gz-sim moveit-rviz-sim
```

For local sources, insert `-f compose.workspace.yaml` before the GUI overlay
after building the workspace. Omit the GUI overlay and name only `gz-sim` for
headless operation. Use `compose.zenoh.yaml` and `RMW=zenoh` for Zenoh.

| Setting | Default | Purpose |
| --- | --- | --- |
| `SIM_WORLD` | `curtmini_piper` | Packaged world name |
| `SIM_USE_HOKUYO` | `true` | Enable simulated Hokuyo and `/scan` |
| `SIM_USE_CAMERAS` | `true` | Enable the two simulated RGBD cameras and IMUs |

Set the starting base pose and arm joints in the simulator's
`config/initial_state.yaml`. Set arm, TCP, lidar, and camera mounts in
`curtmini_piper_description/config/geometry.yaml`. These local settings are
bind-mounted; restart the affected services after editing them. Bridge and
controller YAML files come from upstream in regular images. Use the workspace
overlay to test local changes to those files or to robot and simulator code.

These settings apply to both GUI and headless launches. An external world path
must exist inside the container; mount its file and assets with a local override.
The default Hokuyo scan has frame `hokuyo_link` and 1081 ranges. Gazebo's GPU
lidar requires a working renderer even when the GUI is disabled. The RViz-only
`LIBGL_ALWAYS_SOFTWARE` setting is not applied to Gazebo.

The launch starts the controller spawners automatically. In another terminal,
verify readiness and then start keyboard control:

```bash
./scripts/verify-simulation.sh
docker compose -f compose.yaml -f compose.cyclonedds.yaml \
  run --rm keyboard-teleop-sim
```

For the workspace workflow, pass `-f compose.workspace.yaml` to the verification
script. It checks the running `gz-sim` service using the selected middleware.
Keep the teleop terminal focused: `i`/`,` drive, `j`/`l` turn, and `k` stops.

If the robot spawned but a base controller stayed inactive, inspect the launch
logs and use the upstream README's recovery commands:

```bash
docker compose -f compose.yaml -f compose.cyclonedds.yaml run --rm ros-cli \
  ros2 control set_controller_state joint_state_broadcaster active
docker compose -f compose.yaml -f compose.cyclonedds.yaml run --rm ros-cli \
  ros2 control set_controller_state base_controller active
docker compose -f compose.yaml -f compose.cyclonedds.yaml run --rm ros-cli \
  ros2 control list_controllers
```

## Zenoh

The Zenoh overlay starts one robot-side router and configures every local ROS
container as a peer connected to `tcp/127.0.0.1:7447`:

```bash
export CONTAINER_ROS_DISTRO=jazzy
export RMW=zenoh

docker compose \
  -f compose.yaml \
  -f compose.zenoh.yaml \
  --profile simulation up gz-sim
```

Add `compose.gui.yaml` and `moveit-rviz-sim` to the command to run the
standalone RViz client over Zenoh.

`config/zenoh/router.json5` is the router policy.
`config/zenoh/local-session.json5` is used by containers on the robot host.
Multicast discovery and Zenoh shared memory are disabled initially, making the
topology deterministic and avoiding cross-container shared-memory assumptions.

On a remote computer, use `remote-client-session.json5` and point it at the
robot host:

```bash
docker run --rm --network host \
  -e RMW_IMPLEMENTATION=rmw_zenoh_cpp \
  -e ZENOH_SESSION_CONFIG_URI=/etc/curtmini-piper/zenoh/session.json5 \
  -e 'ZENOH_CONFIG_OVERRIDE=connect/endpoints=["tcp/ROBOT_IP:7447"]' \
  -v "$PWD/config/zenoh/remote-client-session.json5:/etc/curtmini-piper/zenoh/session.json5:ro" \
  curtmini-piper-teleop:jazzy-zenoh \
  ros2 topic list
```

Expose TCP port `7447` only on the intended robot network. Authentication,
TLS/QUIC, ACLs, priorities, and downsampling belong in the router policy when
the network requirements are defined.

## Real robot

Configure `can0` on the host before starting the container. The container uses
host networking but does not administer host CAN:

```bash
sudo ip link set can0 up type can bitrate 1000000
```

Set `LPMS_DEVICE` and `JOYSTICK_DEVICE` in `.env`, then run with the chosen
middleware overlay:

```bash
docker compose \
  -f compose.yaml \
  -f "compose.${RMW}.yaml" \
  up base-bringup piper-bringup
```

`base-bringup` maps Candle USB, the LPMS serial device, and the joystick;
`piper-bringup` uses the CAN interface. The Piper service publishes the full
robot description, and the base service skips its base-only description.
Neither service uses `privileged: true`.

For only the Piper arm hardware, MoveIt, and RViz, use `piper-bringup`:

```bash
export RMW=cyclonedds
xhost +si:localuser:root
docker compose \
  -f compose.yaml \
  -f compose.cyclonedds.yaml \
  -f compose.gui.yaml \
  up piper-bringup moveit-rviz-hardware
```

This uses an arm-only hardware image and requires only the host CAN interface
configured above. No IMU or joystick
devices are mapped. The arm is automatically enabled by the launch defaults.
For Zenoh, set `RMW=zenoh` and replace the middleware overlay with
`compose.zenoh.yaml`. See [Piper arm only](README_compose_service.md#piper-arm-only)
for profile and visualization details.

## Tools

Run RViz against an already active simulation:

```bash
xhost +si:localuser:root
docker compose \
  -f compose.yaml \
  -f "compose.${RMW}.yaml" \
  -f compose.gui.yaml \
  run --rm moveit-rviz-sim
```

Run RViz against an already active real robot:

```bash
xhost +si:localuser:root
docker compose \
  -f compose.yaml \
  -f "compose.${RMW}.yaml" \
  -f compose.gui.yaml \
  run --rm moveit-rviz-hardware
```

Both services use the same image. The simulation service enables ROS time;
the hardware service uses wall time. Mount and TCP offsets are read from
`curtmini_piper_description/config/geometry.yaml`. Simulation RViz and MoveItPy
also follow `SIM_USE_HOKUYO`, matching the simulator's lidar model.

Start simulation or hardware bringup first. MoveItPy plans without execution by
default:

```bash
docker compose -f compose.yaml -f "compose.${RMW}.yaml" run --rm moveitpy-sim
docker compose -f compose.yaml -f "compose.${RMW}.yaml" run --rm moveitpy-hardware
```

Set `MOVEIT_PLAN_ONLY=false` to execute the example trajectory.

Run keyboard control against the active robot:

```bash
docker compose -f compose.yaml -f "compose.${RMW}.yaml" run --rm keyboard-teleop-sim
docker compose -f compose.yaml -f "compose.${RMW}.yaml" run --rm keyboard-teleop-hardware
```

Simulation publishes stamped commands to `/base_controller/cmd_vel`. Hardware
publishes stamped commands to `/cmd_vel`, which is processed by `twist_mux`.

Do not run simulation and physical bringup in the same ROS domain at the same
time. Change `ROS_DOMAIN_ID` when both must run on one host.

## Validation

Validate repository-owned source manifests, Dockerfile stages, the Compose matrix,
and built images:

```bash
./scripts/validate-locks.sh
./scripts/validate-compose.sh
CONTAINER_ROS_DISTRO=jazzy RMW=cyclonedds ./scripts/verify-images.sh
CONTAINER_ROS_DISTRO=jazzy RMW=zenoh ./scripts/verify-images.sh
```

Compose validation covers both Jazzy middleware variants, with and without
the workspace and GUI overlays, including nondefault world and lidar settings. Image verification checks both installed worlds and their referenced
Neobotix models.

With `gz-sim` running, check advancing `/clock`, combined `/joint_states`, all
three active controllers, the `/move_action` server, and valid `/scan` data:

```bash
RMW=cyclonedds ./scripts/verify-simulation.sh
# With the local workspace overlay:
RMW=cyclonedds ./scripts/verify-simulation.sh -f compose.workspace.yaml
```

Repeat with `SIM_WORLD=curtmini_piper_map` when starting Gazebo. The check uses
the resolved `SIM_USE_HOKUYO` setting and skips lidar only when explicitly
disabled. `SIM_CHECK_TIMEOUT` defaults to 120 seconds. No motion commands or
controller state changes are issued by the check.

A later GitHub Actions workflow can
use a Jazzy RMW and image matrix, with headless Gazebo, MoveIt RViz launch,
MoveItPy, and teleop tests. Hardware execution still requires a self-hosted
runner connected to the robot.

## Curt Mini package split

RViz and MoveItPy build `curt_mini_description`; Gazebo also builds
`curt_mini_teleop`. Hardware bringup builds `curt_mini_bringup`. Description and
teleoperation users therefore do not depend on `ipa_ros2_control`, and the
Dockerfiles no longer edit the package manifest during a build.

## Navigation in simulation

Use `mapping-sim` to build a map, `nav2-sim` to navigate on a saved map, and
`nav2-rviz-sim` to set the initial pose and goal. These services are included in
the existing Compose files. Follow the [student navigation guide](../rob4_fraunhofer_ws/src/curtmini_piper/curtmini_piper_navigation/README.md).

`NAV2_MAP` optionally selects a YAML filename inside the navigation package’s
`maps/` directory; it defaults to `map.yaml`. No new `.env` entries are required.
