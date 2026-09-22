#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "${repo_root}" <<'PY'
from pathlib import Path
import re
import sys

import yaml


repo_root = Path(sys.argv[1])
sha_pattern = re.compile(r"^[0-9a-f]{40}$")

for distro_dir in sorted((repo_root / "locks").iterdir()):
    if not distro_dir.is_dir():
        continue
    versions = {}
    lock_files = [distro_dir / "dependencies.repos"]
    if not lock_files:
        raise SystemExit(f"No repository locks in {distro_dir}")
    for lock_file in lock_files:
        data = yaml.safe_load(lock_file.read_text())
        repositories = data.get("repositories", {})
        if not repositories:
            raise SystemExit(f"No repositories in {lock_file}")
        required = {"curt_mini", "curtmini_piper", "curtmini_piper_gz_sim",
                    "agx_arm_urdf", "agx_arm_ros", "candle_ros2", "openzenros2",
                    "neo_gz_worlds"}
        if missing := required - repositories.keys():
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
                    f"Inconsistent {name} versions in {distro_dir.name}: "
                    f"{versions[name]} and {source}"
                )
            versions[name] = source

    python_lock = {}
    python_lock_file = distro_dir / "hardware-python.env"
    for line in python_lock_file.read_text().splitlines():
        if line and not line.startswith("#"):
            key, value = line.split("=", 1)
            python_lock[key] = value

    if not python_lock.get("PYAGXARM_URL", "").startswith("https://"):
        raise SystemExit(f"{python_lock_file}: pyAgxArm URL must use HTTPS")
    if not sha_pattern.fullmatch(python_lock.get("PYAGXARM_REF", "")):
        raise SystemExit(f"{python_lock_file}: pyAgxArm must be pinned to a SHA")

required_stages = ("base", "dependencies", "builder", "test", "runtime")
for dockerfile in sorted(repo_root.glob("images/*/Dockerfile")):
    text = dockerfile.read_text()
    if re.search(r"COPY --from=(curt_mini_source|curtmini_piper_source)", text):
        raise SystemExit(f"{dockerfile}: source repositories must come from locks")
    stages = ("runtime",) if dockerfile.parent.name == "workspace" else required_stages
    for stage in stages:
        if not re.search(rf"\bAS {stage}\b", text, re.IGNORECASE):
            raise SystemExit(f"{dockerfile}: missing {stage} stage")

for package_file in sorted(repo_root.glob("images/*/packages.txt")):
    for line in package_file.read_text().splitlines():
        if line.startswith("ros-"):
            raise SystemExit(
                f"{package_file}: ROS packages belong in ros-packages.txt"
            )

print("Source locks and Dockerfile stages are valid")
PY
