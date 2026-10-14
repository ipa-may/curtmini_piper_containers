# syntax=docker/dockerfile:1.7
ARG ROS_DISTRO=jazzy
ARG ROS_IMAGE=ros:${ROS_DISTRO}-ros-base-noble
FROM ${ROS_IMAGE} AS runtime

ARG ROS_DISTRO=jazzy
ARG RMW=cyclonedds
ENV ROS_DISTRO=${ROS_DISTRO} \
    RMW_IMPLEMENTATION=rmw_${RMW}_cpp \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      "ros-${ROS_DISTRO}-apriltag-ros" \
      "ros-${ROS_DISTRO}-rmw-${RMW}-cpp" \
    && rm -rf /var/lib/apt/lists/*

COPY common/ros_entrypoint.sh /opt/container/ros_entrypoint.sh
RUN chmod 0755 /opt/container/ros_entrypoint.sh

ENTRYPOINT ["/opt/container/ros_entrypoint.sh"]
CMD ["ros2", "run", "apriltag_ros", "apriltag_node"]
