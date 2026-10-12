# Shared container helpers

This folder contains small scripts used by Docker containers and the maintenance
scripts in [`../scripts/`](../scripts/). They prepare ROS, build the workspace,
and coordinate startup.

**You normally run Docker Compose commands, not these scripts directly.** Compose
and the Docker images call the appropriate helpers for you.

## A few useful terms

- **Host:** your computer, where you open a terminal and run `docker compose`.
- **Container:** the environment where the project's ROS programs run.
- **Entrypoint:** the first program Docker runs when a container starts.
- **Source a setup file:** run `source setup.bash` to make ROS commands and
  packages available in the current shell.
- **Docker volume:** persistent storage managed by Docker. It remains when a
  temporary container is removed.

## What each file does

| File | Where it runs | Purpose |
| --- | --- | --- |
| [ros_entrypoint.sh](ros_entrypoint.sh) | Inside runtime containers | Prepares the ROS environment, then starts the requested program. |
| [wait_for_ros.sh](wait_for_ros.sh) | Inside RViz and MoveItPy containers | Waits for a ROS topic, service, or action to appear before starting a client. |
| [workspace-build.sh](workspace-build.sh) | Inside `workspace-builder` | Builds simulation, navigation and MoveIt example packages. |
| [workspace-sources.py](workspace-sources.py) | Inside `workspace-builder` | Imports missing simulation source dependencies. This one is Python. |
| [compose-settings.sh](compose-settings.sh) | On your host | Reads Compose settings for the build and verification scripts. |

## Preparing ROS: `ros_entrypoint.sh`

Most of the project's containers start with this script. It:

1. Sources `/opt/ros/jazzy/setup.bash` to make ROS available.
2. Sources `/opt/ws/install/setup.bash` if the workspace installation exists.
3. Starts the container's requested command, such as `ros2 launch ...`.

For services using the workspace overlay, the installation must exist. If it is
missing, the script stops with:

```text
Workspace install missing. Run the workspace-builder service first.
```

The final `exec "$@"` in the script means “replace this shell with the command
and arguments passed to me.” This lets Docker send stop signals directly to
that program.

## Waiting for ROS: `wait_for_ros.sh`

Starting two containers together does not guarantee that their ROS programs
become ready at the same time. This script delays a client until a required ROS
name appears.

The current services use it as follows:

| Client | Waits for | Timeout |
| --- | --- | --- |
| RViz | The `/move_action` action | 120 seconds |
| MoveItPy | The `/joint_states` topic | 120 seconds |

For example, this command inside a ROS-ready container waits for MoveIt and
then launches RViz:

```bash
/opt/container/wait_for_ros.sh action /move_action 120 -- \
  ros2 launch curtmini_piper_moveit_config moveit_rviz.launch.py use_sim_time:=true
```

The script checks the output of `ros2 topic list`, `ros2 service list`, or
`ros2 action list`. If the name does not appear before the timeout, it exits
with an error instead of starting the client.

**This checks discovery, not full readiness.** A topic can appear before useful
messages arrive. For a more complete simulation check, use
[`verify-simulation.sh`](../scripts/verify-simulation.sh).

## Building packages: `workspace-build.sh`

This is the entrypoint of the `workspace-builder` service. It:

1. Sources ROS itself, without sourcing an older workspace installation.
2. Calls `workspace-sources.py` to prepare source dependencies.
3. Runs `colcon build` for `curtmini_piper_gz_sim`,
   `curtmini_piper_motion_examples` and `curtmini_piper_navigation`, and their dependencies.

The build includes robot descriptions, simulation controllers, and MoveIt
configuration. It does not build hardware bringup or hardware drivers.

Local source repositories are mounted read-only under `/opt/ws/src`. Build
results go into Docker volumes:

| Container directory | Contents |
| --- | --- |
| `/opt/ws/build` | Intermediate build files |
| `/opt/ws/install` | Installed packages that ROS can use |
| `/opt/ws/log` | Build logs |

That is why running the builder does **not** create `build/` or `install/` in
your host workspace. Gazebo, navigation, simulation RViz, and simulation MoveItPy share the
installed packages through the install volume.

## Preparing sources: `workspace-sources.py`

This helper reads the simulator's dependency manifest, which lists source
repositories needed by the project. It skips dependencies supplied by the local
source mounts. For other dependencies, it uses `vcs import --recursive` to clone
missing repositories into `/opt/ws/dependencies`, another Docker volume.

With the current manifest and workspace mounts, all listed simulation
dependencies are supplied locally, so it normally downloads nothing.

Existing cached checkouts are retained. Changing a manifest revision does not
automatically update an existing checkout. Hardware dependencies left in the
cache by an older builder are not selected by the current simulation build.

## Reading configuration: `compose-settings.sh`

This helper runs on your host. Scripts such as
[`build-all.sh`](../scripts/build-all.sh),
[`verify-images.sh`](../scripts/verify-images.sh), and
[`verify-simulation.sh`](../scripts/verify-simulation.sh) source it and call its
`load_compose_settings` function.

It asks Compose to resolve configuration, including `.env` and exported shell
variables. Shell overrides take precedence over `.env`. It then exports the
settings those scripts need, such as `RMW`, the image prefix, and source paths.
It checks that the selected distribution is Jazzy and that the middleware is
`cyclonedds` or `zenoh`.

This keeps helper scripts consistent with Compose without executing `.env` as
shell code. `.env.example` is only a template; Compose reads `.env`.

## Commands you normally use

Run these from `curtmini_piper_containers/`. For the local Jazzy simulation with
CycloneDDS and GUI support, select the configuration in your terminal:

```bash
export CONTAINER_ROS_DISTRO=jazzy
export RMW=cyclonedds
export ROS_DOMAIN_ID=42
export COMPOSE_FILE=compose.yaml:compose.cyclonedds.yaml:compose.workspace.yaml:compose.gui.yaml
```

Build the development image, then build the ROS packages:

```bash
docker compose build workspace-builder
docker compose run --rm workspace-builder
```

These are different steps: `build` creates the container image and copies the
helpers into it; `run` starts that image and compiles your ROS packages.
`--rm` removes the temporary builder container afterward, but keeps its volumes.

Start the simulation and RViz after configuring desktop access as described in
the [main README](../README.md#cyclonedds):

```bash
SIM_WORLD=curtmini_piper_map docker compose up gz-sim moveit-rviz-sim
```

The startup flow is:

```text
workspace-builder -> workspace-build.sh -> workspace-sources.py -> colcon build
gz-sim            -> ros_entrypoint.sh -> simulation launch
moveit-rviz-sim   -> ros_entrypoint.sh -> wait_for_ros.sh -> RViz launch
```

Keep the workspace overlay selected when launching programs that should use the
packages you just built. See the [Compose file guide](../README_compose_files.md)
for details about overlays and explicit `-f` options.

## After editing a helper

The container helpers are copied into images under `/opt/container/` during
image builds. Editing the host copy does not update an existing image.

- For the workspace workflow, rebuild the `workspace-builder` image. Simulation
  services also use that image. Rerun the builder if the build scripts changed,
  and recreate affected runtime containers.
- For regular application images, rebuild the affected services and recreate
  their containers.
- `compose-settings.sh` runs directly on the host, so its changes apply on the
  next helper-script invocation; no image rebuild is needed.

For example, after a workspace helper change:

```bash
docker compose stop gz-sim moveit-rviz-sim
docker compose build workspace-builder
docker compose run --rm workspace-builder
SIM_WORLD=curtmini_piper_map docker compose up --force-recreate gz-sim moveit-rviz-sim
```
