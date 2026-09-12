#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

export ROS_DISTRO="${ROS_DISTRO:-jazzy}"
export RMW="${RMW:-cyclonedds}"

case "${RMW}" in
  cyclonedds|zenoh)
    ;;
  *)
    echo "Unsupported RMW '${RMW}'; expected cyclonedds or zenoh" >&2
    exit 2
    ;;
esac

services=(
  gz-sim
  real-bringup
  moveit-rviz-sim
  moveitpy-sim
  keyboard-teleop-sim
)

if [[ "${RMW}" == "zenoh" ]]; then
  services+=(zenoh-router)
fi

docker compose \
  -f compose.yaml \
  -f "compose.${RMW}.yaml" \
  build "${services[@]}"
