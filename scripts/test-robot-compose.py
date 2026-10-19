"""Check robot package composition and build dependencies without starting services."""
import json
import os
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
ROBOT = (ROOT / "../rob4_fraunhofer_ws/src/curtmini_piper").resolve()
HELPERS = {"piper-ros-base", "piper-description", "piper-moveit-config"}
PACKAGES = {
    "base-bringup": "bringup",
    "piper-bringup": "bringup",
    "keyboard-teleop-sim": "bringup",
    "keyboard-teleop-hardware": "bringup",
    "ros-cli": "bringup",
    "moveit-rviz-sim": "moveit_config",
    "moveit-rviz-hardware": "moveit_config",
    "mapping-sim": "navigation",
    "nav2-sim": "navigation",
    "nav2-rviz-sim": "navigation",
    "realsense-base": "sensors",
    "realsense-tool": "sensors",
}


def compose(arguments, *, root=ROOT, files=("compose.yaml",), overrides=None):
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(("COMPOSE_", "CURTMINI_PIPER_", "CONTAINER_")):
            env.pop(key)
    env.update(RMW="cyclonedds", DISPLAY=":0", IMAGE_PREFIX="curtmini-piper")
    env.update(overrides or {})
    command = ["docker", "compose", "--env-file", "/dev/null"]
    for file in files:
        command += ["-f", file]
    return subprocess.check_output(command + arguments, cwd=root, env=env, text=True)


def model(**kwargs):
    return json.loads(compose(["--profile", "*", "config", "--format", "json"], **kwargs))


class RobotComposeTest(unittest.TestCase):
    def test_root_includes_package_services(self):
        services = model(root=ROBOT)["services"]
        self.assertEqual(set(services), set(PACKAGES) | HELPERS)
        for name, package in PACKAGES.items():
            with self.subTest(service=name):
                service = services[name]
                dockerfile = f"curtmini_piper_{package}/docker/Dockerfile"
                self.assertEqual(service["build"]["dockerfile"], dockerfile)
                self.assertTrue((ROBOT / dockerfile).is_file())
                self.assertEqual(service["network_mode"], "host")
                for volume in service.get("volumes", []):
                    if volume["type"] == "bind" and str(ROBOT) in volume["source"]:
                        self.assertTrue(Path(volume["source"]).exists(), volume["source"])
        mapping = next(v for v in services["mapping-sim"]["volumes"] if v["target"] == "/maps")
        navigation = next(v for v in services["nav2-sim"]["volumes"] if v["target"] == "/maps")
        self.assertEqual(mapping["source"], str(ROBOT / "curtmini_piper_navigation/maps"))
        self.assertEqual(mapping["source"], navigation["source"])
        self.assertFalse(mapping.get("read_only", False))
        self.assertTrue(navigation["read_only"])

    def test_middleware_gui_and_workspace_overlays(self):
        for rmw in ("cyclonedds", "zenoh"):
            for workspace in (False, True):
                for gui in (False, True):
                    with self.subTest(rmw=rmw, workspace=workspace, gui=gui):
                        files = ["compose.yaml", f"compose.{rmw}.yaml"]
                        if workspace:
                            files.append("compose.workspace.yaml")
                        if gui:
                            files.append("compose.gui.yaml")
                        services = model(files=files, overrides={"RMW": rmw})["services"]
                        for name in PACKAGES:
                            service = services[name]
                            self.assertEqual(service["environment"]["RMW_IMPLEMENTATION"],
                                             f"rmw_{rmw}_cpp")
                            self.assertTrue(any(v["target"].startswith("/etc/curtmini-piper/")
                                                for v in service.get("volumes", [])), name)
                        for name in ("moveit-rviz-sim", "moveit-rviz-hardware", "nav2-rviz-sim", "ros-cli"):
                            self.assertEqual("DISPLAY" in services[name]["environment"], gui)
                        cli = services["ros-cli"]
                        self.assertEqual(cli["build"]["target"], "ros-cli")
                        self.assertEqual(cli["working_dir"], "/diagnostics")
                        output = next(v for v in cli["volumes"] if v["target"] == "/diagnostics")
                        self.assertFalse(output.get("read_only", False))
                        self.assertFalse(output["bind"]["create_host_path"])
                        for name in ("base-bringup", "piper-bringup", "realsense-base", "realsense-tool"):
                            self.assertNotIn("REQUIRE_WORKSPACE_INSTALL", services[name]["environment"])
                        if workspace:
                            for name in ("moveit-rviz-sim", "mapping-sim", "nav2-sim", "nav2-rviz-sim"):
                                contexts = services[name]["build"]["additional_contexts"]
                                self.assertEqual(set(contexts), {"simulation_source", "robot_source", "tools_source"})
                                self.assertEqual(services[name]["environment"]["REQUIRE_WORKSPACE_INSTALL"], "1")

    def test_local_source_changes_builds_only(self):
        upstream = model()["services"]
        local = model(overrides={"CURTMINI_PIPER_IMAGE_SOURCE": str(ROBOT)})["services"]
        for name in set(PACKAGES) | HELPERS:
            with self.subTest(service=name):
                self.assertEqual(local[name]["build"]["context"], str(ROBOT))
                self.assertEqual(upstream[name]["build"]["context"],
                                 "https://github.com/ipa-may/curtmini_piper.git#main")
                self.assertEqual({k: v for k, v in upstream[name].items() if k != "build"},
                                 {k: v for k, v in local[name].items() if k != "build"})

    def test_package_test_targets_keep_runtime_tags(self):
        runtime = model(root=ROBOT)["services"]
        tests = model(root=ROBOT, files=("compose.yaml", "compose.test.yaml"))["services"]
        for name, original in runtime.items():
            self.assertEqual(tests[name], original, name)
        runtime_images = {service["image"] for service in runtime.values()}
        for name, target in (("piper-description-test", "test"),
                             ("piper-moveit-test", "moveit-rviz-test"),
                             ("piper-hardware-test", "hardware-test"),
                             ("piper-teleop-test", "teleop-test")):
            service = tests[name]
            self.assertEqual(service["build"]["target"], target)
            self.assertEqual(service["profiles"], ["image-test"])
            self.assertNotIn(service["image"], runtime_images)

    def test_build_dependencies_and_zero_replica_helpers(self):
        cli_targets = json.loads(compose(["build", "--print", "ros-cli"]))["target"]
        self.assertEqual(set(cli_targets), {"piper-ros-base", "piper-description", "ros-cli"})
        self.assertEqual(cli_targets["ros-cli"]["contexts"]["robot_description"], "target:piper-description")
        targets = json.loads(compose(["build", "--print", "piper-bringup"]))["target"]
        self.assertEqual(set(targets), HELPERS | {"piper-bringup"})
        self.assertEqual(targets["piper-bringup"]["contexts"]["moveit_config"], "target:piper-moveit-config")
        self.assertEqual(targets["piper-moveit-config"]["contexts"]["robot_description"], "target:piper-description")
        self.assertEqual(targets["piper-description"]["contexts"]["ros_base"], "target:piper-ros-base")
        common = targets["piper-ros-base"]["contexts"]["container_common"]
        self.assertEqual(common, str(ROOT / "common"))
        for profile in ("piper-hardware", "hardware", "simulation", "navigation", "hardware-cameras"):
            services = json.loads(compose(["--profile", profile, "config", "--format", "json"]))["services"]
            for name in HELPERS:
                self.assertEqual(services[name]["scale"], 0, (profile, name))
            for name in set(PACKAGES).intersection(services):
                self.assertFalse(HELPERS.intersection(services[name].get("depends_on", {})), name)


if __name__ == "__main__":
    unittest.main()
