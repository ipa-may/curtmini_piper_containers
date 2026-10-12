#!/usr/bin/env bash
# Source from host scripts after setting repo_root. Let Compose parse .env;
# never source it as shell code or print unrelated environment variables.
load_compose_settings() {
  local settings key value
  settings="$(cd "${repo_root}" && python3 - <<'PY'
import subprocess

result = subprocess.check_output(
    ["docker", "compose", "-f", "compose.yaml", "config", "--environment"],
    text=True,
)
values = dict(line.split("=", 1) for line in result.splitlines() if "=" in line)
defaults = {
    "CONTAINER_ROS_DISTRO": "jazzy",
    "RMW": "cyclonedds",
    "IMAGE_PREFIX": "curtmini-piper",
    "CURTMINI_PIPER_SOURCE": "../rob4_fraunhofer_ws/src/curtmini_piper",
    "CURTMINI_PIPER_GZ_SIM_SOURCE": "../rob4_fraunhofer_ws/src/curtmini_piper_simulation/curtmini_piper_gz_sim",
    "SIM_CHECK_TIMEOUT": "120",
}
for key, default in defaults.items():
    print(f"{key}={values.get(key) or default}")
PY
)" || return
  while IFS='=' read -r key value; do
    export "${key}=${value}"
  done <<< "${settings}"
  if [[ "${CONTAINER_ROS_DISTRO}" != jazzy ]]; then
    echo "Only ROS 2 Jazzy is supported." >&2
    return 2
  fi
  case "${RMW}" in
    cyclonedds|zenoh) ;;
    *) echo "Unsupported RMW '${RMW}'; expected cyclonedds or zenoh" >&2; return 2 ;;
  esac
}
