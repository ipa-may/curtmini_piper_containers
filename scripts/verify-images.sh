#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/common/compose-settings.sh"
load_compose_settings

image_prefix="${IMAGE_PREFIX:-curtmini-piper}"
ros_distro="${CONTAINER_ROS_DISTRO:-jazzy}"
rmw="${RMW:-cyclonedds}"
image_tag="${ros_distro}-${rmw}"
expected_rmw="rmw_${rmw}_cpp"

docker image inspect "${image_prefix}-gazebo:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-hardware:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-base-hardware:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-sensors:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-apriltag:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-moveit-rviz:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-moveitpy:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-moveit-action-client:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-nav2-goal-client:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-tag-pose:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-teleop:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-ros-cli:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-description:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-moveit-config:${image_tag}" >/dev/null

if [[ "${rmw}" == "zenoh" ]]; then
  docker image inspect \
    "${image_prefix}-zenoh-router:${ros_distro}-zenoh" >/dev/null
  docker run --rm "${image_prefix}-zenoh-router:${ros_distro}-zenoh" \
    ros2 pkg prefix rmw_zenoh_cpp
fi

docker run --rm "${image_prefix}-gazebo:${image_tag}" \
  ros2 pkg prefix curtmini_piper_gz_sim
docker run --rm -i "${image_prefix}-gazebo:${image_tag}" python3 - <<'PY'
from pathlib import Path
import xml.etree.ElementTree as ET
from ament_index_python.packages import get_package_share_directory

sim_share = Path(get_package_share_directory("curtmini_piper_gz_sim"))
models = Path(get_package_share_directory("neo_gz_worlds")) / "models"
for name in ("curtmini_piper", "curtmini_piper_map"):
    world = sim_share / "worlds" / f"{name}.sdf"
    for uri in ET.parse(world).iter("uri"):
        if uri.text and uri.text.startswith("model://"):
            model = models / uri.text.removeprefix("model://")
            if not (model / "model.config").is_file():
                raise SystemExit(f"Missing world model: {model}")
print("Both packaged worlds and their model assets are installed")
PY
docker run --rm "${image_prefix}-hardware:${image_tag}" \
  ros2 pkg prefix curtmini_piper_bringup
docker run --rm "${image_prefix}-base-hardware:${image_tag}" \
  ros2 pkg prefix curt_mini_bringup
docker run --rm "${image_prefix}-sensors:${image_tag}" \
  ros2 pkg prefix curtmini_piper_sensors
docker run --rm "${image_prefix}-sensors:${image_tag}" \
  ros2 pkg prefix realsense2_camera
docker run --rm "${image_prefix}-apriltag:${image_tag}" \
  ros2 pkg prefix apriltag_ros
docker run --rm "${image_prefix}-hardware:${image_tag}" \
  python3 -c "import pyAgxArm"
docker run --rm "${image_prefix}-base-hardware:${image_tag}" \
  bash -c "test -f /opt/ws/install/lib/libipa_ros2_control.so"
docker run --rm "${image_prefix}-hardware:${image_tag}" \
  ros2 pkg prefix agx_arm_ctrl
# Import the driver and its dependencies without starting a node or accessing CAN.
docker run --rm "${image_prefix}-hardware:${image_tag}" \
  python3 -c "import agx_arm_ctrl.agx_arm_ctrl_single_node"
docker run --rm "${image_prefix}-moveit-rviz:${image_tag}" \
  ros2 pkg prefix curtmini_piper_moveit_config
docker run --rm "${image_prefix}-description:${image_tag}" \
  ros2 pkg prefix curtmini_piper_description
docker run --rm "${image_prefix}-moveit-config:${image_tag}" \
  ros2 pkg prefix curtmini_piper_moveit_config
docker run --rm "${image_prefix}-moveitpy:${image_tag}" \
  ros2 pkg prefix curtmini_piper_moveitpy_example
docker run --rm "${image_prefix}-moveit-action-client:${image_tag}" \
  ros2 pkg executables curtmini_piper_moveit_action_client_example
docker run --rm "${image_prefix}-tag-pose:${image_tag}" \
  ros2 pkg prefix curtmini_piper_tag_tools
docker run --rm "${image_prefix}-nav2-goal-client:${image_tag}" \
  ros2 pkg prefix curtmini_piper_nav_examples
docker run --rm "${image_prefix}-teleop:${image_tag}" \
  ros2 pkg prefix teleop_twist_keyboard

docker run --rm "${image_prefix}-navigation:${image_tag}" \
  ros2 pkg prefix curtmini_piper_navigation
docker run --rm "${image_prefix}-navigation:${image_tag}" \
  ros2 pkg prefix slam_toolbox
docker run --rm "${image_prefix}-navigation:${image_tag}" \
  ros2 launch curtmini_piper_navigation navigation.launch.py --show-args

docker run --rm "${image_prefix}-ros-cli:${image_tag}" bash -c '
  for package in ros2controlcli tf2_tools rviz2 plotjuggler_ros rqt_graph rqt_console ros2bag agx_arm_urdf curt_mini_description curtmini_piper_description; do
    ros2 pkg prefix "$package" || exit 1
  done
  ros2 control --help >/dev/null && dot -V
'

for image in gazebo hardware base-hardware sensors apriltag description moveit-config moveit-rviz moveitpy moveit-action-client nav2-goal-client tag-pose teleop ros-cli navigation; do
  docker run --rm "${image_prefix}-${image}:${image_tag}" \
    bash -c "test ! -d /opt/ws/src"
  docker run --rm "${image_prefix}-${image}:${image_tag}" \
    bash -c "test \"\${RMW_IMPLEMENTATION}\" = '${expected_rmw}'"
done

echo "All ${ros_distro}/${rmw} runtime images passed verification"
