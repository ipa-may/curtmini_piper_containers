"""Check a running simulation without moving the robot or changing controllers."""
import argparse
import time

from controller_manager_msgs.srv import ListControllers
from moveit_msgs.action import MoveGroup
import rclpy
from rclpy.action import ActionClient
from rclpy.qos import qos_profile_sensor_data
from rosgraph_msgs.msg import Clock
from sensor_msgs.msg import JointState, LaserScan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--use-hokuyo", choices=("true", "false"), default="true")
    args = parser.parse_args()
    rclpy.init()
    node = rclpy.create_node("container_simulation_check")
    clocks = []
    joints = set()
    scan = {"ready": args.use_hokuyo == "false", "status": "no scan received"}

    def on_clock(msg):
        stamp = msg.clock.sec * 1_000_000_000 + msg.clock.nanosec
        if not clocks:
            clocks.append(stamp)
        elif stamp > clocks[0]:
            clocks[:] = [clocks[0], stamp]

    def on_joints(msg):
        joints.clear()
        joints.update(msg.name)

    def on_scan(msg):
        scan["status"] = f"frame={msg.header.frame_id!r}, ranges={len(msg.ranges)}"
        scan["ready"] = msg.header.frame_id == "hokuyo_link" and len(msg.ranges) == 1081

    node.create_subscription(Clock, "/clock", on_clock, qos_profile_sensor_data)
    node.create_subscription(JointState, "/joint_states", on_joints, qos_profile_sensor_data)
    if args.use_hokuyo == "true":
        node.create_subscription(LaserScan, "/scan", on_scan, qos_profile_sensor_data)
    controllers = node.create_client(ListControllers, "/controller_manager/list_controllers")
    move_group = ActionClient(node, MoveGroup, "/move_action")
    expected_controllers = {"joint_state_broadcaster", "base_controller", "arm_controller"}
    expected_joints = {"front_left_motor", "back_left_motor",
                       "front_right_motor", "back_right_motor",
                       *(f"piper_joint{i}" for i in range(1, 7))}
    active = set()
    future = None
    request_started = 0.0
    deadline = time.monotonic() + args.timeout
    try:
        while time.monotonic() < deadline:
            rclpy.spin_once(node, timeout_sec=0.1)
            if future is not None and future.done():
                active = {c.name for c in future.result().controller if c.state == "active"}
                future = None
            if future is not None and time.monotonic() - request_started > 2.0:
                controllers.remove_pending_request(future)
                future.cancel()
                future = None
            if future is None and controllers.service_is_ready():
                future = controllers.call_async(ListControllers.Request())
                request_started = time.monotonic()
            if (len(clocks) == 2 and expected_joints <= joints and scan["ready"]
                    and expected_controllers <= active and move_group.server_is_ready()):
                print("Simulation ready: clock advances, joints present, controllers active, "
                      "MoveIt available" + (", Hokuyo scan valid" if args.use_hokuyo == "true" else ""))
                return
        raise SystemExit(
            f"Simulation not ready within {args.timeout:g}s:\n"
            f"  clock advances: {len(clocks) == 2}\n"
            f"  missing joints: {sorted(expected_joints - joints)}\n"
            f"  inactive/missing controllers: {sorted(expected_controllers - active)}\n"
            f"  MoveIt available: {move_group.server_is_ready()}\n"
            f"  Hokuyo: {scan['status'] if args.use_hokuyo == 'true' else 'disabled'}")
    finally:
        move_group.destroy()
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
