#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

python3 - <<'CHECK'
import json
import os
import subprocess

settings = {
    "SIM_WORLD": ("world", "curtmini_piper", "curtmini_piper_map"),
    "SIM_USE_HOKUYO": ("use_hokuyo", "true", "false"),
    "SIM_SPAWN_X": ("spawn_x", "0.0", "1.25"),
    "SIM_SPAWN_Y": ("spawn_y", "-2.0", "-3.5"),
    "SIM_SPAWN_Z": ("spawn_z", "0.16", "0.25"),
    "SIM_SPAWN_YAW": ("spawn_yaw", "0.0", "1.57"),
}
for distro in ("jazzy", "kilted"):
    for rmw in ("cyclonedds", "zenoh"):
        for workspace in (False, True):
            for gui in (False, True):
                for custom in (False, True):
                    env = dict(os.environ, CONTAINER_ROS_DISTRO=distro,
                               RMW=rmw, DISPLAY=":0")
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
                    if sim["environment"]["RMW_IMPLEMENTATION"] != f"rmw_{rmw}_cpp":
                        raise SystemExit(f"Incorrect simulation middleware: {command}")
                    if workspace:
                        mounts = {v["target"]: v for v in
                                  services["workspace-builder"]["volumes"]}
                        for package in ("curtmini_piper_gz_sim", "neo_gz_worlds"):
                            mount = mounts[f"/opt/ws/src/{package}"]
                            if not mount["read_only"] or mount["bind"]["create_host_path"]:
                                raise SystemExit(f"Unsafe source mount: {mount}")
        print(f"Validated {distro}/{rmw}: headless, GUI, workspace, and launch overrides")
CHECK
