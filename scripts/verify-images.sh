#!/usr/bin/env bash

set -euo pipefail

image_prefix="${IMAGE_PREFIX:-curtmini-piper}"
ros_distro="${ROS_DISTRO:-jazzy}"
rmw="${RMW:-cyclonedds}"
image_tag="${ros_distro}-${rmw}"
expected_rmw="rmw_${rmw}_cpp"

docker image inspect "${image_prefix}-gazebo:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-hardware:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-moveit-rviz:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-moveitpy:${image_tag}" >/dev/null
docker image inspect "${image_prefix}-teleop:${image_tag}" >/dev/null

if [[ "${rmw}" == "zenoh" ]]; then
  docker image inspect \
    "${image_prefix}-zenoh-router:${ros_distro}-zenoh" >/dev/null
  docker run --rm "${image_prefix}-zenoh-router:${ros_distro}-zenoh" \
    ros2 pkg prefix rmw_zenoh_cpp
fi

docker run --rm "${image_prefix}-gazebo:${image_tag}" \
  ros2 pkg prefix curtmini_piper_gz_sim
docker run --rm "${image_prefix}-hardware:${image_tag}" \
  ros2 pkg prefix curtmini_piper_bringup
docker run --rm "${image_prefix}-hardware:${image_tag}" \
  python3 -c "import pyAgxArm"
docker run --rm "${image_prefix}-hardware:${image_tag}" \
  bash -c "test -f /opt/ws/install/lib/libipa_ros2_control.so"
docker run --rm "${image_prefix}-hardware:${image_tag}" \
  ros2 pkg prefix agx_arm_ctrl
# Import the driver and its dependencies without starting a node or accessing CAN.
docker run --rm "${image_prefix}-hardware:${image_tag}" \
  python3 -c "import agx_arm_ctrl.agx_arm_ctrl_single_node"
docker run --rm "${image_prefix}-moveit-rviz:${image_tag}" \
  ros2 pkg prefix curtmini_piper_moveit_config
docker run --rm "${image_prefix}-moveitpy:${image_tag}" \
  ros2 pkg prefix curtmini_piper_motion_examples
docker run --rm "${image_prefix}-teleop:${image_tag}" \
  ros2 pkg prefix teleop_twist_keyboard

for image in gazebo hardware moveit-rviz moveitpy teleop; do
  docker run --rm "${image_prefix}-${image}:${image_tag}" \
    bash -c "test ! -d /opt/ws/src"
  docker run --rm "${image_prefix}-${image}:${image_tag}" \
    bash -c "test \"\${RMW_IMPLEMENTATION}\" = '${expected_rmw}'"
done

echo "All ${ros_distro}/${rmw} runtime images passed verification"
