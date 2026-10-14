# syntax=docker/dockerfile:1.7
ARG ROS_DISTRO=jazzy
ARG ROS_IMAGE=ros:${ROS_DISTRO}-ros-base-noble
FROM ${ROS_IMAGE} AS runtime
ARG ROS_DISTRO=jazzy
ARG RMW=cyclonedds
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV ROS_DISTRO=${ROS_DISTRO} DEBIAN_FRONTEND=noninteractive
ENV RMW_IMPLEMENTATION=rmw_${RMW}_cpp
COPY --from=simulation_source docker/ros-packages.txt /tmp/gazebo.txt
COPY --from=robot_source curtmini_piper_moveit_config/docker/ros-packages.txt /tmp/moveit-base.txt
COPY --from=robot_source curtmini_piper_moveit_config/docker/rviz-ros-packages.txt /tmp/rviz.txt
COPY --from=tools_source curtmini_piper_moveitpy_example/docker/ros-packages.txt /tmp/moveitpy.txt
COPY --from=tools_source curtmini_piper_moveit_action_client_example/docker/ros-packages.txt /tmp/moveit-action-client.txt
COPY --from=tools_source curtmini_piper_nav_examples/docker/ros-packages.txt /tmp/nav-client.txt
COPY --from=tools_source curtmini_piper_tag_tools/docker/ros-packages.txt /tmp/tag-pose.txt
COPY --from=robot_source curtmini_piper_navigation/docker/ros-packages.txt /tmp/navigation.txt
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential cmake git ca-certificates python3-yaml \
      libusb-1.0-0-dev \
      python3-colcon-common-extensions python3-rosdep python3-vcstool \
      "ros-${ROS_DISTRO}-rmw-${RMW}-cpp" \
    && cat /tmp/gazebo.txt /tmp/moveit-base.txt /tmp/rviz.txt /tmp/moveitpy.txt /tmp/moveit-action-client.txt /tmp/navigation.txt /tmp/nav-client.txt /tmp/tag-pose.txt \
      | sort -u | sed "s|^|ros-${ROS_DISTRO}-|" \
      | xargs apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* /tmp/*.txt
COPY common/ros_entrypoint.sh common/wait_for_ros.sh common/workspace-build.sh common/workspace-sources.py /opt/container/
RUN chmod +x /opt/container/*.sh
WORKDIR /opt/ws
ENTRYPOINT ["/opt/container/ros_entrypoint.sh"]
CMD ["bash"]
