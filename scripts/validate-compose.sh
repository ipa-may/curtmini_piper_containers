#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

python3 - <<'CHECK'
import json
import os
from pathlib import Path
import subprocess

settings = {
    "SIM_WORLD": ("world", "curtmini_piper", "curtmini_piper_map"),
    "SIM_USE_HOKUYO": ("use_hokuyo", "true", "false"),
    "SIM_USE_CAMERAS": ("use_cameras", "true", "false"),
    "SIM_USE_APRILTAGS": ("use_apriltags", "false", "true"),
}
for distro in ("jazzy",):
    for rmw in ("cyclonedds", "zenoh"):
        for workspace in (False, True):
            for gui in (False, True):
                for custom in (False, True):
                    env = dict(os.environ, CONTAINER_ROS_DISTRO=distro,
                               RMW=rmw, DISPLAY=":0")
                    env.pop("CURTMINI_PIPER_TOOLS_SSH_AUTH", None)
                    for key, (_, _, value) in settings.items():
                        env.pop(key, None)
                        if custom:
                            env[key] = value
                    command = ["docker", "compose", "--env-file", "/dev/null",
                               "-f", "compose.yaml", "-f", f"compose.{rmw}.yaml"]
                    if workspace:
                        command += ["-f", "compose.workspace.yaml"]
                    if gui:
                        command += ["-f", "compose.gui.yaml"]
                    result = subprocess.check_output(
                        command + ["--profile", "*", "config", "--format", "json"],
                        env=env, text=True)
                    services = json.loads(result)["services"]
                    sim = services["gz-sim"]
                    expected = [f"gui:={str(gui).lower()}", "use_rviz:=false"]
                    expected += [f"{arg}:={override if custom else default}"
                                 for arg, default, override in settings.values()]
                    for argument in expected:
                        if argument not in sim["command"]:
                            raise SystemExit(f"Missing {argument}: {command}")
                    for name, camera in (("realsense-base", "base_camera"),
                                         ("realsense-tool", "tool_camera")):
                        service = services[name]
                        if f"camera:={camera}" not in service["command"]:
                            raise SystemExit(f"Wrong camera selection: {name}")
                        if service["build"]["target"] != "sensors":
                            raise SystemExit(f"Wrong sensor image: {name}")
                        if service["build"]["context"] != (
                                "https://github.com/ipa-may/curtmini_piper.git#main"):
                            raise SystemExit(f"Sensor image does not use upstream: {name}")
                        if not any(v["target"] == "/dev/bus/usb"
                                   for v in service["volumes"]):
                            raise SystemExit(f"Missing USB bus: {name}")
                    if sim["environment"]["RMW_IMPLEMENTATION"] != f"rmw_{rmw}_cpp":
                        raise SystemExit(f"Incorrect simulation middleware: {command}")
                    base = services["base-bringup"]
                    arm = services["piper-bringup"]
                    if (base["build"]["target"] != "base-hardware"
                            or "publish_robot_description:=False" not in base["command"]):
                        raise SystemExit("Base bringup must use its own image and defer the robot model")
                    if (arm["build"]["target"] != "hardware"
                            or "start_base:=false" in arm["command"]):
                        raise SystemExit("Piper bringup must use the arm-only image")
                    detector = services["apriltag-base"]
                    if detector["environment"]["RMW_IMPLEMENTATION"] != f"rmw_{rmw}_cpp":
                        raise SystemExit("AprilTag detector middleware differs from simulation")
                    for argument in ("image_rect:=/base_camera/color/image_raw",
                                     "camera_info:=/base_camera/color/camera_info",
                                     "detections:=/base_camera/tag_detections",
                                     "qos_profile:=default"):
                        if argument not in detector["command"]:
                            raise SystemExit(f"AprilTag detector missing {argument}")
                    if not any(v["target"].startswith("/etc/curtmini-piper/")
                               for v in detector.get("volumes", [])):
                        raise SystemExit("AprilTag detector lacks middleware config")
                    tag_pose = services["tag-pose-sim"]
                    if "use_sim_time:=true" not in tag_pose["command"]:
                        raise SystemExit("Tag pose tool must use simulation time")
                    if tag_pose["environment"]["RMW_IMPLEMENTATION"] != f"rmw_{rmw}_cpp":
                        raise SystemExit("Tag pose middleware differs from simulation")
                    if not any(v["target"].startswith("/etc/curtmini-piper/")
                                   for v in tag_pose.get("volumes", [])):
                        raise SystemExit("Tag pose tool lacks middleware config")
                    for name, sim_time in (("moveit-action-client-sim", "true"),
                                           ("moveit-action-client-hardware", "false")):
                        client = services[name]
                        if ("/move_action" not in client["command"]
                                or f"use_sim_time:={sim_time}" not in client["command"]
                                or client["environment"]["RMW_IMPLEMENTATION"] != f"rmw_{rmw}_cpp"):
                            raise SystemExit(f"Incorrect MoveIt action client setup: {name}")
                        if not any(v["target"].startswith("/etc/curtmini-piper/")
                                       for v in client.get("volumes", [])):
                            raise SystemExit(f"MoveIt action client lacks middleware config: {name}")
                    if not workspace:
                        robot_source = "https://github.com/ipa-may/curtmini_piper.git#main"
                        sim_source = "https://github.com/ipa-may/curtmini_piper_gz_sim.git#main"
                        tools_source = ("git@github.com:2026-2027-ROB4-Fraunhofer/"
                                        "curtmini_piper_tools.git#main")
                        if sim["build"]["context"] != sim_source:
                            raise SystemExit("Regular Gazebo build does not use upstream")
                        if sim["build"]["additional_contexts"]["robot_source"] != robot_source:
                            raise SystemExit("Gazebo robot source does not use upstream")
                        for name in ("base-bringup", "piper-bringup",
                                     "moveit-rviz-sim", "moveit-rviz-hardware",
                                     "keyboard-teleop-sim", "keyboard-teleop-hardware",
                                     "mapping-sim", "nav2-sim", "nav2-rviz-sim",
                                     "ros-cli"):
                            if services[name]["build"]["context"] != robot_source:
                                raise SystemExit(f"Regular build does not use upstream: {name}")
                        for name in ("moveitpy-sim", "moveitpy-hardware"):
                            build = services[name]["build"]
                            if (build["context"] != tools_source
                                    or build["target"] != "runtime"
                                    or build["dockerfile"] !=
                                    "curtmini_piper_moveitpy_example/docker/Dockerfile"):
                                raise SystemExit(f"MoveItPy build does not use tools upstream: {name}")
                            if build["ssh"] != ["default"]:
                                raise SystemExit(f"MoveItPy build lacks SSH auth: {name}")
                            image_prefix = env.get("IMAGE_PREFIX", "curtmini-piper")
                            expected_base = (
                                f"docker-image://{image_prefix}-moveit-rviz:{distro}-{rmw}"
                            )
                            if build["additional_contexts"]["moveit_base"] != expected_base:
                                raise SystemExit(f"MoveItPy base image differs: {name}")
                        for name in ("moveit-action-client-sim",
                                     "moveit-action-client-hardware"):
                            build = services[name]["build"]
                            if (build["context"] != tools_source
                                    or build["target"] != "runtime"
                                    or build["dockerfile"] !=
                                    "curtmini_piper_moveit_action_client_example/docker/Dockerfile"):
                                raise SystemExit(f"MoveIt action client build differs: {name}")
                            if build["additional_contexts"]["moveit_base"] != expected_base:
                                raise SystemExit(f"MoveIt action client base image differs: {name}")
                        for name, package in (
                                ("tag-pose-sim", "curtmini_piper_tag_tools"),
                                ("nav2-goal-client", "curtmini_piper_nav_examples")):
                            build = services[name]["build"]
                            if (build["context"] != tools_source
                                    or build["target"] != "runtime"
                                    or build["dockerfile"] != f"{package}/docker/Dockerfile"):
                                raise SystemExit(f"Navigation tool does not use tools upstream: {name}")
                            if build["ssh"] != ["default"]:
                                raise SystemExit(f"Navigation tool build lacks SSH auth: {name}")
                            if build["additional_contexts"]["container_common"] != str(
                                    Path("common").resolve()):
                                raise SystemExit(f"Navigation tool helper path differs: {name}")
                        if services["tag-pose-sim"]["image"] == services["nav2-goal-client"]["image"]:
                            raise SystemExit("Tag pose and Nav2 client must have separate images")
                        sim_mounts = {v["target"] for v in sim["volumes"]}
                        if "/opt/ws/install/share/curtmini_piper_gz_sim/config" in sim_mounts:
                            raise SystemExit("Gazebo overlays all upstream config")
                        if ("/opt/ws/install/share/curtmini_piper_gz_sim/config/initial_state.yaml"
                                not in sim_mounts):
                            raise SystemExit("Gazebo initial pose override is missing")
                        if ("/opt/ws/install/share/curtmini_piper_gz_sim/config/apriltags.yaml"
                                not in sim_mounts):
                            raise SystemExit("Gazebo AprilTag layout override is missing")
                    lidar = "false" if custom else "true"
                    if f"use_hokuyo:={lidar}" not in services["moveit-rviz-sim"]["command"]:
                        raise SystemExit("RViz lidar setting differs from simulation")
                    for name in ("mapping-sim", "nav2-sim", "nav2-rviz-sim"):
                        service = services[name]
                        if service["environment"]["RMW_IMPLEMENTATION"] != f"rmw_{rmw}_cpp":
                            raise SystemExit(f"Incorrect navigation middleware: {name}")
                        if not any(v["target"].startswith("/etc/curtmini-piper/")
                                   for v in service.get("volumes", [])):
                            raise SystemExit(f"Navigation missing middleware configuration: {name}")
                    mapping = next(v for v in services["mapping-sim"]["volumes"]
                                   if v["target"] == "/maps")
                    navigation = next(v for v in services["nav2-sim"]["volumes"]
                                      if v["target"] == "/maps")
                    if mapping["source"] != navigation["source"] or mapping.get("read_only", False):
                        raise SystemExit("Mapping must save to the shared host map directory")
                    if not navigation.get("read_only"):
                        raise SystemExit("Navigation map mount must be read-only")
                    if "map:=/maps/map.yaml" not in services["nav2-sim"]["command"]:
                        raise SystemExit("Unexpected default navigation map")
                    if gui and "DISPLAY" not in services["nav2-rviz-sim"]["environment"]:
                        raise SystemExit("Navigation RViz missing GUI configuration")
                    if workspace:
                        for name in ("base-bringup", "piper-bringup",
                                     "realsense-base", "realsense-tool",
                                     "moveit-rviz-hardware", "moveitpy-hardware",
                                     "moveit-action-client-hardware"):
                            service = services[name]
                            if "REQUIRE_WORKSPACE_INSTALL" in service["environment"]:
                                raise SystemExit(f"Hardware requires workspace: {name}")
                            if any(v["target"] == "/opt/ws/install"
                                   for v in service.get("volumes", [])):
                                raise SystemExit(f"Hardware mounts workspace: {name}")
                        for name in ("gz-sim", "moveit-rviz-sim", "moveitpy-sim",
                                     "moveit-action-client-sim",
                                     "mapping-sim", "nav2-sim", "nav2-rviz-sim",
                                     "tag-pose-sim", "nav2-goal-client"):
                            service = services[name]
                            if service["environment"].get("REQUIRE_WORKSPACE_INSTALL") != "1":
                                raise SystemExit(f"Simulation missing workspace: {name}")
                            if not any(v["target"] == "/opt/ws/install" and v["read_only"]
                                       for v in service.get("volumes", [])):
                                raise SystemExit(f"Simulation missing install mount: {name}")
                        mounts = {v["target"]: v for v in
                                  services["workspace-builder"]["volumes"]}
                        for package in ("curtmini_piper_gz_sim", "neo_gz_worlds",
                                        "curtmini_piper_tools"):
                            mount = mounts[f"/opt/ws/src/{package}"]
                            if not mount["read_only"] or mount["bind"]["create_host_path"]:
                                raise SystemExit(f"Unsafe source mount: {mount}")
        print(f"Validated {distro}/{rmw}: headless, GUI, workspace, and launch overrides")
CHECK
