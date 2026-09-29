#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <workspace-src-directory> [ros-distro]" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_src="$(realpath "$1")"
ros_distro="${2:-${CONTAINER_ROS_DISTRO:-jazzy}}"
if [[ "${ros_distro}" != jazzy && "${ros_distro}" != kilted ]]; then
  echo "Unsupported ROS distro: ${ros_distro}" >&2
  exit 2
fi

python3 - "${workspace_src}" "${ros_distro}" <<'PY'
from pathlib import Path
import os
import subprocess
import sys

import yaml


workspace_src = Path(sys.argv[1])
ros_distro = sys.argv[2]

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

def find_checkout(name):
    checkout = workspace_src / name
    if (checkout / ".git").exists():
        return checkout
    matches = checkouts.get(Path(name).name, [])
    if len(matches) != 1:
        raise SystemExit(
            f"Expected one Git checkout for {name} below {workspace_src}; "
            f"found {len(matches)}: {matches}"
        )
    return matches[0]


pending = {}
for owner in ("curtmini_piper", "curtmini_piper_gz_sim"):
    root = find_checkout(owner)
    lock_file = root / "docker/dependencies" / f"{ros_distro}.repos"
    if not lock_file.is_file():
        lock_file = root / "dependencies.repos"
    data = yaml.safe_load(lock_file.read_text())
    for name, entry in data.get("repositories", {}).items():
        checkout = find_checkout(name)
        entry["version"] = subprocess.check_output(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"],
            text=True,
        ).strip()
    pending[lock_file] = yaml.safe_dump(data, sort_keys=False)

# Resolve every checkout before changing either owner's manifest.
for lock_file, contents in pending.items():
    lock_file.write_text(contents)
    print(f"Updated {lock_file}")
PY
