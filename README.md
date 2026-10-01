# Curt Mini Piper Containers

Compose entry point and shared tooling for Curt Mini with a Piper arm. Application
Dockerfiles and services are maintained in their owning source repositories. The repository supports ROS distro and middleware variants from
one source branch. Nav2 and RealSense are intentionally outside its scope.

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
| `CONTAINER_ROS_DISTRO` | `jazzy`, `kilted` |
| `RMW` | `cyclonedds`, `zenoh` |

Images are tagged `<distro>-<rmw>`, for example:

| Image | Responsibility |
| --- | --- |
| `curtmini-piper-gazebo:jazzy-cyclonedds` | Gazebo, simulated controllers, and MoveIt |
| `curtmini-piper-hardware:jazzy-cyclonedds` | Curt Mini and Piper hardware bringup with MoveIt |
| `curtmini-piper-moveit-rviz:jazzy-cyclonedds` | Standalone MoveIt RViz client |
| `curtmini-piper-moveitpy:jazzy-cyclonedds` | MoveItPy planning and execution examples |
| `curtmini-piper-teleop:jazzy-cyclonedds` | Keyboard teleoperation and ROS CLI |
| `curtmini-piper-zenoh-router:jazzy-zenoh` | Robot-side Zenoh router |

`curtmini_piper/docker/Dockerfile` produces four runtime targets: `hardware`,
`moveit-rviz`, `moveitpy`, and `teleop`. They share the ROS base; the first three
also share MoveIt dependencies and the common robot build. Their optional test
targets are named `<target>-test`.

`curtmini_piper_gz_sim/docker/Dockerfile` and the infrastructure's Zenoh Dockerfile
retain `base`, `dependencies`, `builder`, `test`, and `runtime` stages. The
workspace image has a single `runtime` stage with development tools.

The distro and middleware variants do not require long-lived branches. CI can
build a matrix from `main`; use release branches only if compatibility requires
real divergence.

## Source inputs

The root `compose.yaml` includes the Compose files from:

- `../rob4_fraunhofer_ws/src/curtmini_piper/docker/`
- `../rob4_fraunhofer_ws/src/curtmini_piper_simulation/curtmini_piper_gz_sim/docker/`

Each owner maintains its Dockerfile, package lists, Compose services, and GUI
settings. Image builds copy the owner's local checkout and clone upstream
repositories from its `dependencies.repos`. A manifest at
`docker/dependencies/<distro>.repos` takes precedence when present. Hardware's
Python SDK revision lives in the robot repository's
`docker/dependencies/<distro>-hardware-python.env`.

For example, a regular Gazebo image uses the local simulator code but imports
`curtmini_piper`, `curt_mini`, `agx_arm_urdf`, and `neo_gz_worlds` from GitHub.
The teleop target installs binary packages and skips the source-build stages.
`project-docs/dependencies.repos` creates the host checkout layout.

Create local configuration without replacing an existing file:

```bash
[ -f .env ] || cp .env.example .env
```

`.env` selects the distro, middleware, image names, runtime settings, and source
paths used for Compose includes and workspace mounts. Both application checkouts
must exist. For another directory layout, adjust `CURTMINI_PIPER_SOURCE` and
`CURTMINI_PIPER_GZ_SIM_SOURCE`, and set `CONTAINER_INFRA_SOURCE` to this
infrastructure repository's absolute path for the shared build scripts.

Rebuild an application image to use edits in its own checkout. Use the workspace
overlay below when you want multiple mounted repositories built together.
Source manifests can use branches, tags, or commit SHAs; the default Jazzy
manifests use project branches, while Kilted has additional pinned dependencies.
Kilted remains a compatibility baseline until its full build and runtime matrix
has passed. Base-image tags, branches, and apt packages can change.

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

robot_source=../rob4_fraunhofer_ws/src/curtmini_piper
docker buildx build --build-arg ROS_DISTRO=jazzy --build-arg RMW=cyclonedds \
  --build-context container_common=./common --target moveitpy-test \
  -f "$robot_source/docker/Dockerfile" "$robot_source"
```

The robot's other test targets are `hardware-test`, `moveit-rviz-test`, and
`teleop-test`. Adjust the paths above if your checkout layout differs.
`ROS_IMAGE` can override the derived `ros:<distro>-ros-base-noble` base image.

An unchanged import layer can be cached even when its GitHub branch advances.
To refresh the simulation's downloaded dependencies:

```bash
docker compose -f compose.yaml -f compose.cyclonedds.yaml build --no-cache gz-sim
```

Then recreate the service with the appropriate `up` command.

## Local simulation workspace

`compose.workspace.yaml` mounts the local repositories into a
`workspace-builder`. It runs `colcon build` and shares the resulting install
volume with Gazebo, RViz, and MoveItPy.

Set the checkout paths in `.env` if they differ from `.env.example`, then build
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
  piper_driver/agx_arm_urdf/
  curtmini_piper_simulation/
    curtmini_piper_gz_sim/
    neo_gz_worlds/
```

For an existing `.env`, update `CURTMINI_PIPER_GZ_SIM_SOURCE` to the nested
simulation path and add `NEO_GZ_WORLDS_SOURCE` from `.env.example`.
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
workspace image when its package lists change. The dependency helper reads the
mounted owners' manifests, imports missing dependencies, and retains existing
checkouts; a changed manifest does not update those cached checkouts.

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
| `SIM_SPAWN_X` | `0.0` | Initial x position in metres |
| `SIM_SPAWN_Y` | `-2.0` | Initial y position in metres |
| `SIM_SPAWN_Z` | `0.16` | Initial z position in metres |
| `SIM_SPAWN_YAW` | `0.0` | Initial yaw in radians |

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
  --profile hardware up real-bringup
```

The service maps Candle USB, the LPMS serial device, and the joystick. It does
not use `privileged: true`.

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

This reuses the hardware image with the base, IMU, and joystick disabled,
and requires only the host CAN interface configured above. No IMU or joystick
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
`ARM_MOUNT_XYZ`, `ARM_MOUNT_RPY`, `TCP_OFFSET_XYZ`, and `TCP_OFFSET_RPY`.

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

Compose validation covers both distros and middleware variants, with and without
the workspace and GUI overlays, including nondefault world, lidar, and spawn
settings. Image verification checks both installed worlds and their referenced
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

To explicitly pin one distro's repository-owned source manifests to local commits:

```bash
./scripts/update-locks.sh /path/to/workspace/src jazzy
```

Checkout discovery supports nested grouping directories such as
`curtmini_piper_simulation` and `piper_driver`. Flat paths are preferred;
otherwise a repository basename must match exactly one checkout. Every manifest
entry must be present locally, including hardware dependencies. Missing or
ambiguous checkouts fail before either owner's manifest is written. This command
replaces branch names with commit SHAs; skip it when you want to track branches.

Review and commit manifest changes in the owning repositories explicitly. A later GitHub Actions workflow can
use a distro, RMW, and image matrix, with headless Gazebo, MoveIt RViz launch,
MoveItPy, and teleop tests. Hardware execution still requires a self-hosted
runner connected to the robot.

## Curt Mini package split

RViz and MoveItPy build `curt_mini_description`; Gazebo also builds
`curt_mini_teleop`. Hardware bringup builds `curt_mini`. Description and
teleoperation users therefore do not depend on `ipa_ros2_control`, and the
Dockerfiles no longer edit the package manifest during a build.
