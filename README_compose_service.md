# Compose services

Most services are defined in `compose.yaml`. The workspace and Zenoh overlays
add development and middleware services.

| Service | Profile | Role |
| --- | --- | --- |
| `gz-sim` | `simulation` | Runs Gazebo, simulated controllers, and the MoveIt server |
| `real-bringup` | `hardware` | Runs Curt Mini and Piper hardware bringup with the MoveIt server |
| `moveit-rviz-sim` | `simulation` | RViz client for `gz-sim` |
| `moveit-rviz-hardware` | `hardware` | RViz client for `real-bringup` |
| `moveitpy-sim` | `simulation-tools` | MoveItPy example for simulation |
| `moveitpy-hardware` | `hardware-tools` | MoveItPy example for the real robot |
| `keyboard-sim` | `simulation-tools` | Keyboard control for the simulated base |
| `keyboard-hardware` | `hardware-tools` | Keyboard control through the hardware command mux |
| `ros-cli` | `tools` | Interactive ROS shell |
| `workspace-builder` | `workspace` | Builds mounted local sources into the shared install volume |
| `zenoh-router` | none | Local Zenoh router added by `compose.zenoh.yaml` |

`workspace-builder` is defined in `compose.workspace.yaml` and `zenoh-router`
in `compose.zenoh.yaml`. The other services are defined in `compose.yaml`.

## RViz services

The two RViz services normally use the same image, Dockerfile, launch file,
network, and ROS environment. Both wait for the `/move_action` action before
starting.

| Setting | `moveit-rviz-sim` | `moveit-rviz-hardware` |
| --- | --- | --- |
| Backend | `gz-sim` | `real-bringup` |
| Profile | `simulation` | `hardware` |
| ROS time | `use_sim_time:=true` | `use_sim_time:=false` |
| Workspace overlay | Uses the shared local install | Uses the regular image |

RViz is only a client. The corresponding backend provides `move_group`, robot
state, and controllers.

## MoveItPy services

The two MoveItPy services normally use the same image, executable, readiness
check, network, and ROS environment. Both wait for `/joint_states` and use
`MOVEIT_PLAN_ONLY` to decide whether trajectories may execute.

| Setting | `moveitpy-sim` | `moveitpy-hardware` |
| --- | --- | --- |
| Backend | `gz-sim` | `real-bringup` |
| Profile | `simulation-tools` | `hardware-tools` |
| Controller mode | `simulation` | `hardware` |
| ROS time | `use_sim_time:=true` | `use_sim_time:=false` |
| Workspace overlay | Uses the shared local install | Uses the regular image |

Start the appropriate backend before its RViz, MoveItPy, or keyboard client.

## Keyboard services

`keyboard-sim` publishes to `/base_controller/cmd_vel`.
`keyboard-hardware` publishes to `/cmd_vel`, which hardware bringup processes
through `twist_mux`.
