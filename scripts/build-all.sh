#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

source "${repo_root}/common/compose-settings.sh"
load_compose_settings

services=(
  gz-sim
  base-bringup
  piper-bringup
  realsense-base
  apriltag-base
  moveit-rviz-sim
  nav2-goal-client
  tag-pose-sim
  keyboard-teleop-sim
  nav2-sim
)

if [[ "${RMW}" == "zenoh" ]]; then
  services+=(zenoh-router)
fi

docker compose \
  -f compose.yaml \
  -f "compose.${RMW}.yaml" \
  build "${services[@]}"

# MoveItPy uses the locally built MoveIt RViz image as its base.
docker compose \
  -f compose.yaml \
  -f "compose.${RMW}.yaml" \
  build moveitpy-sim moveit-action-client-sim
