# syntax=docker/dockerfile:1.7

ARG ROS_DISTRO=jazzy
ARG ROS_IMAGE=ros:${ROS_DISTRO}-ros-base-noble

FROM ${ROS_IMAGE} AS base

ARG ROS_DISTRO=jazzy
ARG OCI_SOURCE=""
ARG OCI_REVISION=unknown

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV ROS_DISTRO=${ROS_DISTRO} \
    DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.source="${OCI_SOURCE}" \
      org.opencontainers.image.revision="${OCI_REVISION}" \
      org.opencontainers.image.title="Curt Mini Piper Teleop" \
      org.opencontainers.image.licenses="MIT"

COPY images/teleop/packages.txt /tmp/runtime-packages.txt
COPY images/teleop/ros-packages.txt /tmp/ros-packages.txt
RUN apt-get update \
    && xargs -r -a /tmp/runtime-packages.txt \
      apt-get install -y --no-install-recommends \
    && sed "s|^|ros-${ROS_DISTRO}-|" /tmp/ros-packages.txt \
      > /tmp/ros-apt-packages.txt \
    && xargs -r -a /tmp/ros-apt-packages.txt \
      apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* /tmp/*-packages.txt

FROM base AS dependencies

FROM dependencies AS builder

RUN source "/opt/ros/${ROS_DISTRO}/setup.bash" \
    && ros2 pkg prefix teleop_twist_keyboard

FROM builder AS test

RUN source "/opt/ros/${ROS_DISTRO}/setup.bash" \
    && ros2 pkg executables teleop_twist_keyboard \
      | grep -F "teleop_twist_keyboard teleop_twist_keyboard"

FROM base AS runtime

ARG RMW=cyclonedds

ENV RMW_IMPLEMENTATION=rmw_${RMW}_cpp

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      "ros-${ROS_DISTRO}-rmw-${RMW}-cpp" \
    && rm -rf /var/lib/apt/lists/*

COPY common/ros_entrypoint.sh /opt/container/ros_entrypoint.sh
RUN chmod 0755 /opt/container/ros_entrypoint.sh

ENTRYPOINT ["/opt/container/ros_entrypoint.sh"]
CMD ["ros2", "run", "teleop_twist_keyboard", "teleop_twist_keyboard", "--ros-args", "-p", "stamped:=true", "-p", "frame_id:=base_link"]
