#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

for ros_distro in jazzy kilted; do
  for rmw in cyclonedds zenoh; do
    ROS_DISTRO="${ros_distro}" RMW="${rmw}" \
      docker compose \
        -f compose.yaml \
        -f "compose.${rmw}.yaml" \
        config --quiet
    echo "Validated ${ros_distro}/${rmw}"
  done
done
