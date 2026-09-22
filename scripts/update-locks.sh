#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <workspace-src-directory> [ros-distro]" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_src="$(realpath "$1")"
ros_distro="${2:-${CONTAINER_ROS_DISTRO:-jazzy}}"
lock_dir="${repo_root}/locks/${ros_distro}"

if [[ ! -d "${lock_dir}" ]]; then
  echo "Unknown ROS distro lock directory: ${lock_dir}" >&2
  exit 2
fi

python3 - "${repo_root}" "${workspace_src}" "${lock_dir}" <<'PY'
from pathlib import Path
import os
import subprocess
import sys

import yaml


repo_root = Path(sys.argv[1])
workspace_src = Path(sys.argv[2])
lock_dir = Path(sys.argv[3])
lock_files = [lock_dir / "dependencies.repos"]

# Discover repositories below grouping directories such as piper_driver and
# curtmini_piper_simulation. Stop at Git roots instead of scanning their assets.
checkouts = {}
for directory, subdirs, files in os.walk(workspace_src):
    path = Path(directory)
    if ".git" in subdirs or ".git" in files:
        checkouts.setdefault(path.name, []).append(path)
        subdirs[:] = []
    else:
        subdirs[:] = [name for name in subdirs
                      if not name.startswith(".") and name not in {"build", "install", "log"}]

for lock_file in lock_files:
    data = yaml.safe_load(lock_file.read_text())
    for name, entry in data.get("repositories", {}).items():
        checkout = workspace_src / name
        if not (checkout / ".git").exists():
            matches = checkouts.get(Path(name).name, [])
            if len(matches) != 1:
                raise SystemExit(
                    f"Expected one Git checkout for {name} below {workspace_src}; "
                    f"found {len(matches)}: {matches}"
                )
            checkout = matches[0]
        entry["version"] = subprocess.check_output(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"],
            text=True,
        ).strip()
    lock_file.write_text(yaml.safe_dump(data, sort_keys=False))
    print(f"Updated {lock_file.relative_to(repo_root)}")
PY
