# Curt Mini Piper Containers

Independent ROS 2 container images and Compose services for the Curt Mini with
a Piper arm. The repository supports ROS distro and middleware variants from
one source branch. Nav2 and RealSense are intentionally outside its scope.

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

Every Dockerfile is independently buildable and contains `base`,
`dependencies`, `builder`, `test`, and `runtime` stages. Published images use
`runtime`; CI can target `test`.

The four variants do not require long-lived branches. Future CI should build a
matrix from `main`; use distro release branches only if source compatibility
eventually requires real divergence.

## Source inputs

Docker BuildKit injects the two actively developed repositories as named
contexts. Defaults assume sibling checkouts:

```text
src/
|-- curt_mini/
|-- curtmini_piper/
`-- curtmini_piper_containers/
```

Create local configuration:

```bash
cp .env.example .env
```

Local directories, Git URLs, tags, and commit SHAs are accepted:

```bash
CURTMINI_PIPER_SOURCE=../curtmini_piper \
CURT_MINI_SOURCE=../curt_mini \
docker compose -f compose.yaml -f compose.cyclonedds.yaml build gz-sim
```

For a public release, set both variables to public Git contexts:

```bash
CURTMINI_PIPER_SOURCE=https://github.com/ORG/curtmini_piper.git#v1.0.0
CURT_MINI_SOURCE=https://github.com/ORG/curt_mini.git#COMMIT_SHA
```

Other repositories and `pyAgxArm` are pinned under `locks/<distro>/`.
The Kilted locks currently mirror the Jazzy upstream revisions and are a
compatibility baseline until the complete Kilted build and runtime matrix has
passed.

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
  --build-context curtmini_piper_source=../curtmini_piper \
  --build-context curt_mini_source=../curt_mini \
  -f images/gazebo/Dockerfile .
```

`ROS_IMAGE` can override the derived `ros:<distro>-ros-base-noble` base image.

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
docker compose -f compose.yaml -f "compose.${RMW}.yaml" run --rm keyboard-sim
docker compose -f compose.yaml -f "compose.${RMW}.yaml" run --rm keyboard-hardware
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
