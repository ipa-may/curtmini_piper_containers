#!/usr/bin/env bash
set -eo pipefail
# Build against ROS itself, not the previous contents of the install volume.
source "/opt/ros/${ROS_DISTRO}/setup.bash"
python3 /opt/container/workspace-sources.py
cd /opt/ws
colcon --log-base /opt/ws/log build \
  --base-paths /opt/ws/src /opt/ws/dependencies \
  --build-base /opt/ws/build --install-base /opt/ws/install \
  --merge-install \
  --packages-up-to \
    curtmini_piper_bringup \
    curtmini_piper_gz_sim \
    curtmini_piper_motion_examples \
  --cmake-args -DCMAKE_BUILD_TYPE=Release "$@"
