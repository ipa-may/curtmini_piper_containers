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
      org.opencontainers.image.title="Curt Mini Piper MoveItPy" \
      org.opencontainers.image.licenses="MIT"

COPY images/moveitpy/packages.txt /tmp/runtime-packages.txt
COPY images/moveitpy/ros-packages.txt /tmp/ros-packages.txt
RUN apt-get update \
    && xargs -r -a /tmp/runtime-packages.txt \
      apt-get install -y --no-install-recommends \
    && sed "s|^|ros-${ROS_DISTRO}-|" /tmp/ros-packages.txt \
      > /tmp/ros-apt-packages.txt \
    && xargs -r -a /tmp/ros-apt-packages.txt \
      apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* /tmp/*-packages.txt

FROM base AS dependencies

ARG LOCK_DIR=locks/jazzy

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      cmake \
      git \
      python3-colcon-common-extensions \
      python3-rosdep \
      python3-vcstool \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/ws

COPY ${LOCK_DIR}/moveitpy.repos /tmp/dependencies.lock.repos
RUN mkdir -p /opt/ws/src \
    && vcs import --recursive /opt/ws/src < /tmp/dependencies.lock.repos

COPY --from=curt_mini_source / /opt/ws/src/curt_mini
COPY --from=curtmini_piper_source / /opt/ws/src/curtmini_piper

# MoveItPy consumes the robot description, not the real-hardware base driver.
RUN sed -i '\|<depend>ipa_ros2_control</depend>|d' \
      /opt/ws/src/curt_mini/curt_mini/package.xml

RUN apt-get update \
    && rosdep update --rosdistro "${ROS_DISTRO}" \
    && rosdep install \
      --from-paths \
        /opt/ws/src/agx_arm_urdf \
        /opt/ws/src/curt_mini/curt_mini \
        /opt/ws/src/curtmini_piper/curtmini_piper_description \
        /opt/ws/src/curtmini_piper/curtmini_piper_moveit_config \
        /opt/ws/src/curtmini_piper/curtmini_piper_motion_examples \
      --ignore-src \
      --rosdistro "${ROS_DISTRO}" \
      --skip-keys \
        "ament_python candle_ros2 gz_ros2_control ipa_ros2_control warehouse_ros_mongo" \
      -r -y \
    && rm -rf /var/lib/apt/lists/*

FROM dependencies AS builder

RUN source "/opt/ros/${ROS_DISTRO}/setup.bash" \
    && colcon build \
      --merge-install \
      --cmake-args -DCMAKE_BUILD_TYPE=Release \
      --packages-select \
        agx_arm_urdf \
        curt_mini \
        curtmini_piper_description \
        curtmini_piper_moveit_config \
        curtmini_piper_motion_examples

FROM builder AS test

RUN source "/opt/ws/install/setup.bash" \
    && colcon test \
      --merge-install \
      --packages-select curtmini_piper_motion_examples \
    && colcon test-result --verbose

FROM base AS runtime

ARG RMW=cyclonedds

ENV RMW_IMPLEMENTATION=rmw_${RMW}_cpp

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      "ros-${ROS_DISTRO}-rmw-${RMW}-cpp" \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/ws/install/ /opt/ws/install/
COPY common/ros_entrypoint.sh /opt/container/ros_entrypoint.sh
COPY common/wait_for_ros.sh /opt/container/wait_for_ros.sh
RUN chmod 0755 \
      /opt/container/ros_entrypoint.sh \
      /opt/container/wait_for_ros.sh

ENTRYPOINT ["/opt/container/ros_entrypoint.sh"]
CMD ["ros2", "run", "curtmini_piper_motion_examples", "moveit_goal"]
