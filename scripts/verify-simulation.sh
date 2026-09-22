#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

# Extra arguments are Compose options, e.g. -f compose.workspace.yaml.
compose=(docker compose -f compose.yaml -f "compose.${RMW:-cyclonedds}.yaml" "$@")
# Read the resolved command so SIM_USE_HOKUYO in .env is respected too.
use_hokuyo="$("${compose[@]}" --profile simulation config --format json | python3 -c '
import json, sys
command = json.load(sys.stdin)["services"]["gz-sim"]["command"]
print(next(arg.split(":=", 1)[1] for arg in command if arg.startswith("use_hokuyo:=")))
')"
"${compose[@]}" exec -T gz-sim /opt/container/ros_entrypoint.sh \
  python3 - --use-hokuyo "${use_hokuyo}" --timeout "${SIM_CHECK_TIMEOUT:-120}" \
  < scripts/check-simulation.py
