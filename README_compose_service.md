# Compose services

The root `compose.yaml` includes the robot and simulator repositories'
`docker/compose.yaml` files. The workspace and Zenoh overlays add development
and middleware services.

| Service | Profile | Role |
| --- | --- | --- |
| `gz-sim` | `simulation` | Runs Gazebo, simulated controllers, and the MoveIt server |
| `real-bringup` | `hardware` | Runs Curt Mini and Piper hardware bringup with the MoveIt server |
| `piper-bringup` | `piper-hardware` | Runs only Piper hardware and the MoveIt server, with no base, IMU, or joystick |
| `moveit-rviz-sim` | `simulation` | RViz client for `gz-sim` |
| `moveit-rviz-hardware` | `hardware` | RViz client for `real-bringup` or `piper-bringup` |
| `moveitpy-sim` | `simulation-tools` | MoveItPy example for simulation |
| `moveitpy-hardware` | `hardware-tools` | MoveItPy example for the real robot |
| `keyboard-teleop-sim` | `simulation-tools` | Keyboard control for the simulated base |
| `keyboard-teleop-hardware` | `hardware-tools` | Keyboard control through the hardware command mux |
| `mapping-sim` | `mapping` | Builds a map using SLAM Toolbox |
| `nav2-sim` | `navigation` | Localizes on a saved map and follows goal poses |
| `nav2-rviz-sim` | `navigation-tools` | Displays maps and provides initial-pose, goal and cancel controls |
| `ros-cli` | `tools` | Interactive ROS shell |
| `workspace-builder` | `workspace` | Builds simulation, navigation and MoveIt examples, excluding hardware bringup and drivers |
| `zenoh-router` | none | Local Zenoh router added by `compose.zenoh.yaml` |

`workspace-builder` is defined in `compose.workspace.yaml` and `zenoh-router`
in `compose.zenoh.yaml`. `gz-sim` is defined in the simulator repository;
the remaining application services are defined in `curtmini_piper/docker/compose.yaml`.

## Simulation

`gz-sim` starts `simulation.launch.py` with the Gazebo-owned controller manager
and one MoveIt server. `SIM_WORLD=curtmini_piper_map` selects the office world;
the default is `curtmini_piper`. Both worlds and their `neo_gz_worlds` model
assets are installed in the Gazebo image and local workspace install.

`SIM_USE_HOKUYO` defaults to `true`, enabling `/scan` and the lidar model in
simulation RViz and MoveItPy. Set the initial base pose and arm joints in the
simulator's `config/initial_state.yaml`. These settings apply with or without
the Gazebo window.
See [mapping world and lidar](README.md#mapping-world-and-lidar) for startup,
keyboard driving, and controller recovery commands.

## Piper arm only

`piper-bringup` reuses the hardware image, disables the Curt Mini base, IMU,
and joystick, and connects to the host CAN interface (`CAN_PORT`, default
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
option. The separate `piper-hardware` profile keeps the arm-only backend out
of a full `--profile hardware up` startup. Run only one hardware backend
(`real-bringup` or `piper-bringup`) in a given ROS domain.

The launch defaults automatically enable the arm. RViz still displays the
combined Curt Mini/Piper model; only the Piper hardware is started.

## RViz services

The two RViz services normally use the same image, Dockerfile, launch file,
network, and ROS environment. Both wait for the `/move_action` action before
starting.

| Setting | `moveit-rviz-sim` | `moveit-rviz-hardware` |
| --- | --- | --- |
| Backend | `gz-sim` | `real-bringup` or `piper-bringup` |
| Profile | `simulation` | `hardware` |
| ROS time | `use_sim_time:=true` | `use_sim_time:=false` |
| Workspace overlay | Development image with shared local install | Regular image with its own install |

RViz is only a client. The corresponding backend provides `move_group`, robot
state, and controllers.

## MoveItPy services

The two MoveItPy services normally use the same image, executable, readiness
check, network, and ROS environment. Both wait for `/joint_states` and use
`MOVEIT_PLAN_ONLY` to decide whether trajectories may execute.

| Setting | `moveitpy-sim` | `moveitpy-hardware` |
| --- | --- | --- |
| Backend | `gz-sim` | `real-bringup` or `piper-bringup` |
| Profile | `simulation-tools` | `hardware-tools` |
| Controller mode | `simulation` | `hardware` |
| ROS time | `use_sim_time:=true` | `use_sim_time:=false` |
| Workspace overlay | Development image with shared local install | Regular image with its own install |

Start the appropriate backend before its RViz, MoveItPy, or keyboard client.

## Keyboard services

`keyboard-teleop-sim` publishes to `/base_controller/cmd_vel`.
`keyboard-teleop-hardware` publishes to `/cmd_vel`, which hardware bringup processes
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
