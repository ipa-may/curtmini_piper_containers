#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/common/compose-settings.sh"
load_compose_settings

python3 - "${repo_root}" <<'PY'
from pathlib import Path
import os
import re
import sys

import yaml


repo_root = Path(sys.argv[1])
sha_pattern = re.compile(r"^[0-9a-f]{40}$")

owners = {
    "curtmini_piper": (repo_root / os.environ.get(
        "CURTMINI_PIPER_SOURCE", "../rob4_fraunhofer_ws/src/curtmini_piper")).resolve(),
    "curtmini_piper_gz_sim": (repo_root / os.environ.get(
        "CURTMINI_PIPER_GZ_SIM_SOURCE",
        "../rob4_fraunhofer_ws/src/curtmini_piper_simulation/curtmini_piper_gz_sim")).resolve(),
}
tools_root = (repo_root / os.environ.get(
    "CURTMINI_PIPER_TOOLS_SOURCE",
    "../rob4_fraunhofer_ws/src/curtmini_piper_tools")).resolve()
required = {
    "curtmini_piper": {"curt_mini", "agx_arm_urdf", "agx_arm_ros", "candle_ros2", "openzenros2"},
    "curtmini_piper_gz_sim": {"curt_mini", "curtmini_piper", "agx_arm_urdf", "neo_gz_worlds"},
}
for distro in ("jazzy",):
    versions = {}
    for owner, root in owners.items():
        lock_file = root / "docker/dependencies" / f"{distro}.repos"
        if not lock_file.is_file():
            lock_file = root / "dependencies.repos"
        data = yaml.safe_load(lock_file.read_text())
        if owner == "curtmini_piper":
            robot_sources = data["repositories"]
        repositories = {Path(key).name: value for key, value in data.get("repositories", {}).items()}
        if not repositories:
            raise SystemExit(f"No repositories in {lock_file}")
        if owner in repositories:
            raise SystemExit(f"{lock_file}: the owning repository must come from the local build context")
        if missing := required[owner] - repositories.keys():
            raise SystemExit(f"{lock_file}: missing source repositories {sorted(missing)}")
        for name, entry in repositories.items():
            url = entry.get("url", "")
            version = entry.get("version", "")
            if not url.startswith("https://"):
                raise SystemExit(f"{lock_file}: {name} does not use HTTPS")
            if not isinstance(version, str) or not version.strip():
                raise SystemExit(f"{lock_file}: {name} needs a Git revision")
            source = (url, version)
            if name in versions and versions[name] != source:
                raise SystemExit(
                    f"Inconsistent {name} versions for {distro}: "
                    f"{versions[name]} and {source}"
                )
            versions[name] = source

    split_sources = {}
    for part in ("arm", "base"):
        split_file = owners["curtmini_piper"] / "docker/dependencies" / f"{part}.repos"
        for name, entry in yaml.safe_load(split_file.read_text())["repositories"].items():
            if name in split_sources and split_sources[name] != entry:
                raise SystemExit(f"Inconsistent source in split manifests: {name}")
            split_sources[name] = entry
    if split_sources != robot_sources:
        raise SystemExit("Arm and base Docker source manifests differ from dependencies.repos")

    python_lock = {}
    python_lock_file = (owners["curtmini_piper"] / "curtmini_piper_bringup/docker/dependencies"
                        / f"{distro}-hardware-python.env")
    for line in python_lock_file.read_text().splitlines():
        if line and not line.startswith("#"):
            key, value = line.split("=", 1)
            python_lock[key] = value

    if not python_lock.get("PYAGXARM_URL", "").startswith("https://"):
        raise SystemExit(f"{python_lock_file}: pyAgxArm URL must use HTTPS")
    if not sha_pattern.fullmatch(python_lock.get("PYAGXARM_REF", "")):
        raise SystemExit(f"{python_lock_file}: pyAgxArm must be pinned to a SHA")

required_stages = ("base", "dependencies", "builder", "test", "runtime")
dockerfiles = list(repo_root.glob("images/*/Dockerfile"))
for root in owners.values():
    dockerfiles.extend((root / "docker").rglob("Dockerfile"))
    dockerfiles.extend(root.glob("*/docker/Dockerfile"))
dockerfiles.extend(tools_root.glob("*/docker/Dockerfile"))
robot_stages = {
    "docker/common/Dockerfile": ("runtime",),
    "curtmini_piper_description/docker/Dockerfile": ("dependencies", "builder", "test", "runtime"),
    "curtmini_piper_moveit_config/docker/Dockerfile": (
        "dependencies", "builder", "moveit-rviz-test", "config", "moveit-rviz"),
    "curtmini_piper_bringup/docker/Dockerfile": (
        "hardware-builder", "base-hardware-builder", "hardware", "base-hardware",
        "teleop", "hardware-test", "teleop-test"),
    "curtmini_piper_navigation/docker/Dockerfile": (
        "navigation-base", "navigation-builder", "navigation"),
    "curtmini_piper_sensors/docker/Dockerfile": ("sensors-deps", "sensors-builder", "sensors"),
}
for dockerfile in sorted(dockerfiles):
    text = dockerfile.read_text()
    stages = ("runtime",) if dockerfile.parent.name in ("workspace", "apriltag") else required_stages
    if dockerfile.is_relative_to(owners["curtmini_piper"]):
        relative = dockerfile.relative_to(owners["curtmini_piper"]).as_posix()
        if relative not in robot_stages:
            raise SystemExit(f"Unexpected robot Dockerfile: {relative}")
        stages = robot_stages[relative]
    if dockerfile in tools_root.glob("*/docker/Dockerfile"):
        stages = ("dependencies", "builder", "runtime")
    for stage in stages:
        if not re.search(rf"\bAS {stage}\s*$", text, re.IGNORECASE | re.MULTILINE):
            raise SystemExit(f"{dockerfile}: missing {stage} stage")

package_files = list(repo_root.glob("images/*/packages.txt"))
for root in owners.values():
    package_files.extend((root / "docker").rglob("packages.txt"))
    for directory in root.glob("*/docker"):
        package_files.extend(directory.rglob("packages.txt"))
package_files.extend(tools_root.glob("*/docker/packages.txt"))
for package_file in sorted(package_files):
    for line in package_file.read_text().splitlines():
        if line.startswith("ros-"):
            raise SystemExit(
                f"{package_file}: ROS packages belong in ros-packages.txt"
            )

print("Repository-owned dependencies and Dockerfile stages are valid")
PY
