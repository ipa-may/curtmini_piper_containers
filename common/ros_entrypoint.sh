#!/usr/bin/env bash

set -e

source "/opt/ros/${ROS_DISTRO}/setup.bash"

if [[ "${REQUIRE_WORKSPACE_INSTALL:-0}" == "1" && ! -f /opt/ws/install/setup.bash ]]; then
  echo "Workspace install missing. Run the workspace-builder service first." >&2
  exit 1
fi

if [[ -f /opt/ws/install/setup.bash ]]; then
  source /opt/ws/install/setup.bash
fi

exec "$@"
