#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <topic|service|action> <name> [timeout_seconds] [-- command ...]" >&2
  exit 2
fi

resource_type="$1"
resource_name="$2"
timeout_seconds="${3:-60}"

if [[ $# -ge 3 ]]; then
  shift 3
else
  shift 2
fi

if [[ "${1:-}" == "--" ]]; then
  shift
fi

case "${resource_type}" in
  topic)
    list_command=(ros2 topic list)
    ;;
  service)
    list_command=(ros2 service list)
    ;;
  action)
    list_command=(ros2 action list)
    ;;
  *)
    echo "Unsupported ROS resource type: ${resource_type}" >&2
    exit 2
    ;;
esac

deadline=$((SECONDS + timeout_seconds))
until "${list_command[@]}" | grep -Fxq "${resource_name}"; do
  if ((SECONDS >= deadline)); then
    echo "Timed out waiting for ${resource_type} ${resource_name}" >&2
    exit 1
  fi
  sleep 1
done

if [[ $# -gt 0 ]]; then
  exec "$@"
fi
