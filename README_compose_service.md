# Compose services

The root `compose.yaml` includes the robot, simulator, and tools repositories'
Compose files. The workspace and Zenoh overlays add development
and middleware services.

| Service | Profile | Role |
| --- | --- | --- |
| `gz-sim` | `simulation` | Runs Gazebo, simulated controllers, and the MoveIt server |
| `base-bringup` | `hardware` | Runs Curt Mini base hardware, joystick, and IMU; the Piper service publishes the full robot model |
| `realsense-base` | `hardware-cameras` | Runs the base D435i by serial number and publishes its mount TF |
| `realsense-tool` | `hardware-cameras` | Runs the tool D435i by serial number and publishes its mount TF |
| `apriltag-base` | `apriltags` | Detects AprilTags in the base camera color image |
| `tag-pose-sim` | `apriltags` | Publishes a fresh observed tag pose in `map` |
| `nav2-goal-client` | `navigation-tools` | Runs the Python Nav2 goal client on request |
| `piper-bringup` | `piper-hardware` | Runs Piper hardware, the full robot model, and the MoveIt server |
| `moveit-rviz-sim` | `simulation` | RViz client for `gz-sim` |
| `moveit-rviz-hardware` | `hardware` | RViz client for `piper-bringup` |
| `moveitpy-sim` | `simulation-tools` | MoveItPy example for simulation |
| `moveitpy-hardware` | `hardware-tools` | MoveItPy example for the real robot |
| `moveit-action-client-sim` | `simulation-tools` | C++ client for the simulated MoveIt server |
| `moveit-action-client-hardware` | `hardware-tools` | C++ client for the real MoveIt server |
| `keyboard-teleop-sim` | `simulation-tools` | Keyboard control for the simulated base |
| `keyboard-teleop-hardware` | `hardware-tools` | Keyboard control through the hardware command mux |
| `mapping-sim` | `mapping` | Builds a map using SLAM Toolbox |
| `nav2-sim` | `navigation` | Localizes on a saved map and follows goal poses |
| `nav2-rviz-sim` | `navigation-tools` | Displays maps and provides initial-pose, goal and cancel controls |
| `ros-cli` | `tools` | Diagnostic shell with controller/TF tools, RViz, PlotJuggler, robot meshes, and persistent output |
| `workspace-builder` | `workspace` | Builds simulation, navigation and MoveIt examples, excluding hardware bringup and drivers |
| `zenoh-router` | none | Local Zenoh router added by `compose.zenoh.yaml` |

`workspace-builder` is defined in `compose.workspace.yaml` and `zenoh-router`
in `compose.zenoh.yaml`. `gz-sim` is defined in the simulator repository.
`moveitpy-*`, `moveit-action-client-*`, `tag-pose-sim`, and `nav2-goal-client` are defined in their
packages' Compose files under `curtmini_piper_tools/`; the remaining application services
are collected by `curtmini_piper/compose.yaml` from package-owned Compose files.

## Diagnostic shell

Build the updated service from your local robot checkout:

```bash
CURTMINI_PIPER_IMAGE_SOURCE="$(realpath ../rob4_fraunhofer_ws/src/curtmini_piper)" \
  docker compose build ros-cli
docker compose run --rm ros-cli
```

Use the regular middleware overlay from `.env`. Set `ROS_CLI_UID` and
`ROS_CLI_GID` there to `id -u` and `id -g`. The shell starts in `/diagnostics`,
bound to `./diagnostics` on the host; PDFs, layouts, bags and preferences persist.
For GUI tools, include `compose.gui.yaml` and authorize your user from the host
desktop with `xhost +si:localuser:$(id -un)`.

Inside the shell:

```bash
ros2 control list_controllers -c /piper/controller_manager
rviz2 -d /diagnostics/rviz/robot.rviz
ros2 run plotjuggler plotjuggler
```

See [Diagnosing the running system](../project-docs/docs/startup/remote-development/diagnostics.md)
for TF PDFs, recording, GUI setup, and saved configurations. The diagnostic
image includes the base and Piper description assets; it reads live robot
description and TF topics from the backend.

## Simulation

`gz-sim` starts `simulation.launch.py` with the Gazebo-owned controller manager
and one MoveIt server. `SIM_WORLD=curtmini_piper_map` selects the office world;
the default is `curtmini_piper`. Both worlds and their `neo_gz_worlds` model
assets are installed in the Gazebo image and local workspace install.

`SIM_USE_HOKUYO` defaults to `true`, enabling `/scan` and the lidar model in
simulation RViz and MoveItPy. Set the initial base pose and arm joints in the
simulator's `config/initial_state.yaml`. These settings apply with or without
the Gazebo window.
`SIM_USE_CAMERAS` also defaults to `true`. It enables both simulated RGBD and
IMU sensors plus their mount and optical TFs in `gz-sim`. The existing
`moveit-rviz-sim` view shows the robot camera bodies and both color and depth
images. Camera streams use `/base_camera` and `/tool_camera` topic prefixes.
The regular Gazebo image builds the camera implementation from upstream `main`.
See [mapping world and lidar](README.md#mapping-world-and-lidar) for startup,
keyboard driving, and controller recovery commands.

Start the camera example from `curtmini_piper_containers/`:

```bash
docker compose -f compose.yaml -f compose.cyclonedds.yaml \
  -f compose.gui.yaml up --build gz-sim moveit-rviz-sim
```

The two included Gazebo worlds already load the rendering and IMU systems
required by the cameras.

## Physical RealSense cameras

The `curtmini_piper_sensors` package lives inside the robot repository. Its
`config/camera_mounts.yaml` contains **provisional** mount offsets. Replace
them with measured robot-to-camera poses before using hardware TFs. Set the
two camera serials in `.env`, then start the robot and camera services:

```bash
BASE_CAMERA_SERIAL=123456789 TOOL_CAMERA_SERIAL=987654321 \
  docker compose -f compose.yaml -f compose.cyclonedds.yaml \
  -f compose.gui.yaml up base-bringup piper-bringup realsense-base realsense-tool moveit-rviz-hardware
```

Substitute the actual serial numbers. Each RealSense node publishes its own
internal optical frames. Its service publishes only `chassis` to
`base_camera_link` or `piper_tcp_link` to `tool_camera_link`. These camera
services are independent of `base-bringup`, but the robot backend is needed
for RViz to place them in the robot TF tree.

## AprilTag exercise

Set `SIM_USE_APRILTAGS=true` to spawn the panels listed in the simulator's
`config/apriltags.yaml`. That file is a local runtime mount. The optional
`apriltag-base` service uses `apriltag_ros` with the base camera color image and
calibration. Its `APRILTAG_SIZE` setting defaults to 0.20 m, matching the
supplied panels. It publishes `/base_camera/tag_detections` and observed tag TFs;
Gazebo does not publish the panels' true world poses into ROS.

With the regular Compose files selected, start the exercise from this repository:

```bash
SIM_WORLD=curtmini_piper_map SIM_USE_APRILTAGS=true \
  docker compose up --build gz-sim apriltag-base moveit-rviz-sim
```

The detector image is separate from the Gazebo image.
With mapping or AMCL running, `tag-pose-sim` composes the observed tag TF into
`map` and publishes `/tag_pose_in_map`. It does not use the Gazebo layout as
ground truth or choose a base navigation goal.

## Piper arm only

`piper-bringup` uses an arm-only image and connects to the host CAN interface (`CAN_PORT`, default
`can0`). It requires no USB, IMU, or joystick device mappings. Configure CAN
on the host first, as described in the [real robot instructions](README.md#real-robot).

For Piper hardware, MoveIt, and RViz with CycloneDDS:

```bash
export RMW=cyclonedds
xhost +si:localuser:root
docker compose \
  -f compose.yaml \
  -f compose.cyclonedds.yaml \
  -f compose.gui.yaml \
  up piper-bringup moveit-rviz-hardware
```

For Zenoh, set `RMW=zenoh` and use `compose.zenoh.yaml` instead.
Explicit service names activate the required services without a `--profile`
option. The separate `piper-hardware` profile keeps the arm service out
of a full `--profile hardware up` startup. Start `base-bringup` together with
`piper-bringup` for the complete robot.

The launch defaults automatically enable the arm. RViz still displays the
combined Curt Mini/Piper model; only the Piper hardware is started.

For the complete robot, start `base-bringup` alongside `piper-bringup`. The
Piper service publishes the combined model, so the base service skips its
base-only model by default. For base-only operation, set
`PUBLISH_BASE_DESCRIPTION=True` before starting `base-bringup`.

## RViz services

The two RViz services normally use the same image, Dockerfile, launch file,
network, and ROS environment. Both wait for the `/move_action` action before
starting.

| Setting | `moveit-rviz-sim` | `moveit-rviz-hardware` |
| --- | --- | --- |
| Backend | `gz-sim` | `piper-bringup` |
| Profile | `simulation` | `hardware` |
| ROS time | `use_sim_time:=true` | `use_sim_time:=false` |
| Workspace overlay | Development image with shared local install | Regular image with its own install |

RViz is only a client. The corresponding backend provides `move_group`, robot
state, and controllers.

## MoveItPy services

The two MoveItPy services normally use the same image, executable, readiness
check, network, and ROS environment. Both wait for `/joint_states` and use
`MOVEIT_PLAN_ONLY` to decide whether trajectories may execute.
Their package and image build now belong to `curtmini_piper_tools`; the service
names and `moveit_goal` command remain the same.

| Setting | `moveitpy-sim` | `moveitpy-hardware` |
| --- | --- | --- |
| Backend | `gz-sim` | `piper-bringup` |
| Profile | `simulation-tools` | `hardware-tools` |
| Controller mode | `simulation` | `hardware` |
| ROS time | `use_sim_time:=true` | `use_sim_time:=false` |
| Workspace overlay | Development image with shared local install | Regular image with its own install |

Start the appropriate backend before its RViz, MoveItPy, or keyboard client.

## Keyboard services

`keyboard-teleop-sim` publishes to `/base_controller/cmd_vel`.
`keyboard-teleop-hardware` publishes to `/cmd_vel`, which `base-bringup` processes
through `twist_mux`.


## Gz-Sim

Copy `.env.example` to `.env`. 

```sh
SIM_WORLD=curtmini_piper_map docker compose up gz-sim moveit-rviz-sim 
```
## Navigation

Start `mapping-sim` while driving with keyboard teleoperation, save the map,
then stop both mapping and teleoperation before starting `nav2-sim`.
Use `nav2-rviz-sim` for both workflows. Maps persist in
`curtmini_piper/curtmini_piper_navigation/maps/` on the host.
See the [navigation guide](../rob4_fraunhofer_ws/src/curtmini_piper/curtmini_piper_navigation/README.md) for commands.
