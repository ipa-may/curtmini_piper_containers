#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

for ros_distro in jazzy kilted; do
  for rmw in cyclonedds zenoh; do
    CONTAINER_ROS_DISTRO="${ros_distro}" RMW="${rmw}" \
      docker compose \
        -f compose.yaml \
        -f "compose.${rmw}.yaml" \
        --profile "*" config --quiet
    CONTAINER_ROS_DISTRO="${ros_distro}" RMW="${rmw}" \
      docker compose \
        -f compose.yaml \
        -f "compose.${rmw}.yaml" \
        -f compose.workspace.yaml \
        --profile "*" config --quiet
    echo "Validated ${ros_distro}/${rmw}, including local workspace"
  done
done
