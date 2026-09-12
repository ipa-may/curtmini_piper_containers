# syntax=docker/dockerfile:1.7

ARG ROS_DISTRO=jazzy
ARG ROS_IMAGE=ros:${ROS_DISTRO}-ros-base-noble

FROM ${ROS_IMAGE} AS base

ARG ROS_DISTRO=jazzy
ARG OCI_SOURCE=""
ARG OCI_REVISION=unknown

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV ROS_DISTRO=${ROS_DISTRO} \
    PYTHONPATH=/opt/ws/python \
    DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.source="${OCI_SOURCE}" \
      org.opencontainers.image.revision="${OCI_REVISION}" \
      org.opencontainers.image.title="Curt Mini Piper Hardware" \
      org.opencontainers.image.licenses="MIT"

COPY images/hardware/packages.txt /tmp/runtime-packages.txt
COPY images/hardware/ros-packages.txt /tmp/ros-packages.txt
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
      libbluetooth-dev \
      libusb-1.0-0-dev \
      python3-colcon-common-extensions \
      python3-pip \
      python3-rosdep \
      python3-vcstool \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/ws

COPY ${LOCK_DIR}/dependencies.repos /tmp/dependencies.lock.repos
RUN mkdir -p /opt/ws/src \
    && vcs import --recursive /opt/ws/src < /tmp/dependencies.lock.repos

COPY ${LOCK_DIR}/hardware-python.env /tmp/python.lock.env
RUN source /tmp/python.lock.env \
    && python3 -m pip install \
      --break-system-packages \
      --no-deps \
      --target /opt/ws/python \
      "git+${PYAGXARM_URL}@${PYAGXARM_REF}"

RUN apt-get update \
    && rosdep update --rosdistro "${ROS_DISTRO}" \
    && rosdep install \
      --from-paths \
        /opt/ws/src/agx_arm_ros/src \
        /opt/ws/src/agx_arm_urdf \
        /opt/ws/src/candle_ros2 \
        /opt/ws/src/openzenros2 \
        /opt/ws/src/curt_mini/ipa_ros2_control \
        /opt/ws/src/curt_mini/curt_mini \
        /opt/ws/src/curt_mini/curt_mini_description \
        /opt/ws/src/curt_mini/curt_mini_teleop \
        /opt/ws/src/curtmini_piper/curtmini_piper_description \
        /opt/ws/src/curtmini_piper/curtmini_piper_moveit_config \
        /opt/ws/src/curtmini_piper/curtmini_piper_bringup \
      --ignore-src \
      --rosdistro "${ROS_DISTRO}" \
      --skip-keys "gz_ros2_control warehouse_ros_mongo" \
      -r -y \
    && rm -rf /var/lib/apt/lists/*

FROM dependencies AS builder

RUN source "/opt/ros/${ROS_DISTRO}/setup.bash" \
    && colcon build \
      --merge-install \
      --cmake-args -DCMAKE_BUILD_TYPE=Release \
      --packages-up-to curtmini_piper_bringup

FROM builder AS test

RUN source "/opt/ws/install/setup.bash" \
    && colcon test \
      --merge-install \
      --packages-select \
        curtmini_piper_description \
        curtmini_piper_moveit_config \
        curtmini_piper_bringup \
    && colcon test-result --verbose

FROM base AS runtime

ARG RMW=cyclonedds

ENV RMW_IMPLEMENTATION=rmw_${RMW}_cpp

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      "ros-${ROS_DISTRO}-rmw-${RMW}-cpp" \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/ws/install/ /opt/ws/install/
COPY --from=builder /opt/ws/python/ /opt/ws/python/
COPY common/ros_entrypoint.sh /opt/container/ros_entrypoint.sh
COPY common/wait_for_ros.sh /opt/container/wait_for_ros.sh
RUN chmod 0755 \
      /opt/container/ros_entrypoint.sh \
      /opt/container/wait_for_ros.sh

ENTRYPOINT ["/opt/container/ros_entrypoint.sh"]
CMD ["ros2", "launch", "curtmini_piper_bringup", "bringup.launch.py", "use_rviz:=false"]
