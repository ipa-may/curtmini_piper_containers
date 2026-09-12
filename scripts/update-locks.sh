#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <workspace-src-directory> [ros-distro]" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_src="$(realpath "$1")"
ros_distro="${2:-${ROS_DISTRO:-jazzy}}"
lock_dir="${repo_root}/locks/${ros_distro}"

if [[ ! -d "${lock_dir}" ]]; then
  echo "Unknown ROS distro lock directory: ${lock_dir}" >&2
  exit 2
fi

python3 - "${repo_root}" "${workspace_src}" "${lock_dir}" <<'PY'
from pathlib import Path
import subprocess
import sys

import yaml


repo_root = Path(sys.argv[1])
workspace_src = Path(sys.argv[2])
lock_dir = Path(sys.argv[3])
lock_files = [lock_dir / "dependencies.repos"]

for lock_file in lock_files:
    data = yaml.safe_load(lock_file.read_text())
    for name, entry in data.get("repositories", {}).items():
        checkout = workspace_src / name
        if not (checkout / ".git").exists():
            raise SystemExit(f"Missing Git checkout for {name}: {checkout}")
        entry["version"] = subprocess.check_output(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"],
            text=True,
        ).strip()
    lock_file.write_text(yaml.safe_dump(data, sort_keys=False))
    print(f"Updated {lock_file.relative_to(repo_root)}")
PY
