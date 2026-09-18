# Curt Mini Piper Containers

Independent ROS 2 container images and Compose services for the Curt Mini with
a Piper arm. The repository supports ROS distro and middleware variants from
one source branch. Nav2 and RealSense are intentionally outside its scope.

See [Compose file structure](README_compose_files.md) for how the base file and
optional overlays are combined, and [Compose services](README_compose_service.md)
for the available services and their roles.

## Variant model

Set the variant with environment variables:

```bash
export ROS_DISTRO=jazzy
export RMW=cyclonedds
```

Supported values are:

| Input | Values |
| --- | --- |
| `ROS_DISTRO` | `jazzy`, `kilted` |
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

Each application Dockerfile contains `base`, `dependencies`, `builder`, `test`,
and `runtime` stages. Published images use `runtime`; CI can target `test`.
The workspace image is a development environment and has a single stage.

The distro and middleware variants do not require long-lived branches. CI can
build a matrix from `main`; use release branches only if compatibility requires
real divergence.

## Source inputs

All Git source dependencies are listed once per distro in
`locks/<distro>/dependencies.repos`. Every application image and the workspace
builder reads this manifest. Images retain their individual package build
selections. Python dependency revisions remain in
`locks/<distro>/hardware-python.env` because they are installed with pip.

Git revisions may be branches, tags, or commit SHAs. Use development branches
for now and release tags after the packages reach version `0.1.0`.

Create local configuration:

```bash
cp .env.example .env
```

`.env` selects the ROS distro, middleware, image names, and runtime settings.
It does not select source repositories. Host workspace checkouts and
`project-docs/dependencies.repos` are independent of the container builds;
no sibling checkout layout is required.

To change source code used by an image, update its manifest revision and rebuild
the affected image. To test unpublished changes, use the workspace override
below.

Kilted remains a compatibility baseline until its full build and runtime matrix
has passed. Branch references, base image tags, and apt packages can change.

## Build

Build the selected application images and, for Zenoh, the router:

```bash
ROS_DISTRO=jazzy RMW=cyclonedds ./scripts/build-all.sh
ROS_DISTRO=jazzy RMW=zenoh ./scripts/build-all.sh
```

Build one image or its test stage:

```bash
docker compose -f compose.yaml -f compose.cyclonedds.yaml build gz-sim

docker buildx build \
  --build-arg ROS_DISTRO=jazzy \
  --build-arg RMW=cyclonedds \
  --build-arg LOCK_DIR=locks/jazzy \
  --target test \
  -f images/gazebo/Dockerfile .
```

`ROS_IMAGE` can override the derived `ros:<distro>-ros-base-noble` base image.

## Local simulation workspace

`compose.workspace.yaml` mounts the local repositories into a
`workspace-builder`. It runs `colcon build` and shares the resulting install
volume with Gazebo, RViz, and MoveItPy.

Set the checkout paths in `.env` if they differ from `.env.example`, then build
the development image once and compile the workspace:

```bash
docker compose -f compose.yaml -f compose.workspace.yaml build workspace-builder
docker compose -f compose.yaml -f compose.workspace.yaml run --rm workspace-builder
```

Run Gazebo, then start RViz in another terminal:

```bash
docker compose -f compose.yaml -f compose.cyclonedds.yaml \
  -f compose.workspace.yaml -f compose.gui.yaml \
  up gz-sim

docker compose -f compose.yaml -f compose.cyclonedds.yaml \
  -f compose.workspace.yaml -f compose.gui.yaml \
  run --rm moveit-rviz-sim

docker compose -f compose.yaml -f compose.cyclonedds.yaml \
  -f compose.workspace.yaml run --rm moveitpy-sim
```

After source or checkout-path changes, rerun `workspace-builder`; no image
rebuild is needed. Rebuild the workspace image only when its ROS or system
dependencies change. Use `down -v` with the workspace overlay when dependency
revisions change or stale build output must be removed.

## CycloneDDS

Always combine the generic Compose file with the middleware overlay:

```bash
export ROS_DISTRO=jazzy
export RMW=cyclonedds

docker compose \
  -f compose.yaml \
  -f compose.cyclonedds.yaml \
  --profile simulation up gz-sim
```

For Gazebo and the standalone MoveIt RViz client through X11, append
`compose.gui.yaml` and name both services:

```bash
xhost +local:docker
docker compose \
  -f compose.yaml \
  -f compose.cyclonedds.yaml \
  -f compose.gui.yaml \
  --profile simulation up gz-sim moveit-rviz-sim
```

The `gz-sim` service owns `move_group`, the simulated controllers, and Gazebo.
The `moveit-rviz-sim` service waits for `/move_action` and then starts only
RViz. This prevents a second MoveIt server from being launched.

Add `/dev/dri` through a local override when hardware-accelerated rendering is
required.

## Zenoh

The Zenoh overlay starts one robot-side router and configures every local ROS
container as a peer connected to `tcp/127.0.0.1:7447`:

```bash
export ROS_DISTRO=jazzy
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
xhost +local:docker
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
xhost +local:docker
docker compose \
  -f compose.yaml \
  -f "compose.${RMW}.yaml" \
  -f compose.gui.yaml \
  run --rm moveit-rviz-sim
```

Run RViz against an already active real robot:

```bash
xhost +local:docker
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

Validate source locks, Dockerfile stages, the Compose matrix, and built images:

```bash
./scripts/validate-locks.sh
./scripts/validate-compose.sh
ROS_DISTRO=jazzy RMW=cyclonedds ./scripts/verify-images.sh
ROS_DISTRO=jazzy RMW=zenoh ./scripts/verify-images.sh
```

Update one distro's existing lock entries from local Git checkouts:

```bash
./scripts/update-locks.sh /path/to/workspace/src jazzy
```

Review and commit lock changes explicitly. A later GitHub Actions workflow can
use a distro, RMW, and image matrix, with headless Gazebo, MoveIt RViz launch,
MoveItPy, and teleop tests. Hardware execution still requires a self-hosted
runner connected to the robot.

## Curt Mini package split

RViz and MoveItPy build `curt_mini_description`; Gazebo also builds
`curt_mini_teleop`. Hardware bringup builds `curt_mini`. Description and
teleoperation users therefore do not depend on `ipa_ros2_control`, and the
Dockerfiles no longer edit the package manifest during a build.
