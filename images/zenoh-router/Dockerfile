# syntax=docker/dockerfile:1.7

ARG ROS_DISTRO=jazzy
ARG ROS_IMAGE=ros:${ROS_DISTRO}-ros-base-noble

FROM ${ROS_IMAGE} AS base

ARG ROS_DISTRO=jazzy
ARG OCI_SOURCE=""
ARG OCI_REVISION=unknown

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV ROS_DISTRO=${ROS_DISTRO} \
    RMW_IMPLEMENTATION=rmw_zenoh_cpp \
    DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.source="${OCI_SOURCE}" \
      org.opencontainers.image.revision="${OCI_REVISION}" \
      org.opencontainers.image.title="Curt Mini Piper Zenoh Router" \
      org.opencontainers.image.licenses="MIT"

COPY images/zenoh-router/packages.txt /tmp/runtime-packages.txt
RUN apt-get update \
    && xargs -r -a /tmp/runtime-packages.txt \
      apt-get install -y --no-install-recommends \
    && apt-get install -y --no-install-recommends \
      "ros-${ROS_DISTRO}-rmw-zenoh-cpp" \
    && rm -rf /var/lib/apt/lists/* /tmp/runtime-packages.txt

FROM base AS dependencies

FROM dependencies AS builder

RUN source "/opt/ros/${ROS_DISTRO}/setup.bash" \
    && ros2 pkg prefix rmw_zenoh_cpp

FROM builder AS test

RUN source "/opt/ros/${ROS_DISTRO}/setup.bash" \
    && ros2 pkg executables rmw_zenoh_cpp \
      | grep -F "rmw_zenoh_cpp rmw_zenohd"

FROM base AS runtime

COPY common/ros_entrypoint.sh /opt/container/ros_entrypoint.sh
RUN chmod 0755 /opt/container/ros_entrypoint.sh

ENTRYPOINT ["/opt/container/ros_entrypoint.sh"]
CMD ["ros2", "run", "rmw_zenoh_cpp", "rmw_zenohd"]
