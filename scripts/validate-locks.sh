#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
required = {
    "curtmini_piper": {"curt_mini", "agx_arm_urdf", "agx_arm_ros", "candle_ros2", "openzenros2"},
    "curtmini_piper_gz_sim": {"curt_mini", "curtmini_piper", "agx_arm_urdf", "neo_gz_worlds"},
}
for distro in ("jazzy", "kilted"):
    versions = {}
    for owner, root in owners.items():
        lock_file = root / "docker/dependencies" / f"{distro}.repos"
        if not lock_file.is_file():
            lock_file = root / "dependencies.repos"
        data = yaml.safe_load(lock_file.read_text())
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

    python_lock = {}
    python_lock_file = owners["curtmini_piper"] / "docker/dependencies" / f"{distro}-hardware-python.env"
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
for dockerfile in sorted(dockerfiles):
    text = dockerfile.read_text()
    stages = ("runtime",) if dockerfile.parent.name == "workspace" else required_stages
    if dockerfile == owners["curtmini_piper"] / "docker/Dockerfile":
        stages = ("ros-base", "moveit-base", "robot-builder", "moveitpy-builder",
                  "hardware-builder", "teleop", "moveit-rviz", "moveitpy", "hardware",
                  "teleop-test", "moveit-rviz-test", "moveitpy-test", "hardware-test")
    for stage in stages:
        if not re.search(rf"\bAS {stage}\s*$", text, re.IGNORECASE | re.MULTILINE):
            raise SystemExit(f"{dockerfile}: missing {stage} stage")

package_files = list(repo_root.glob("images/*/packages.txt"))
for root in owners.values():
    package_files.extend((root / "docker").rglob("packages.txt"))
for package_file in sorted(package_files):
    for line in package_file.read_text().splitlines():
        if line.startswith("ros-"):
            raise SystemExit(
                f"{package_file}: ROS packages belong in ros-packages.txt"
            )

print("Repository-owned dependencies and Dockerfile stages are valid")
PY
