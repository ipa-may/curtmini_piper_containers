"""Exercise Compose dotenv resolution without starting containers."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[1] / "common/compose-settings.sh"


class ComposeSettingsTest(unittest.TestCase):
    def resolve(self, dotenv, overrides=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "compose.yaml").write_text(
                "name: settings-test\nservices:\n  cli:\n    image: scratch\n"
            )
            (root / ".env").write_text(dotenv)
            env = {key: value for key, value in os.environ.items()
                   if key not in {"RMW", "CONTAINER_ROS_DISTRO", "IMAGE_PREFIX",
                                  "CURTMINI_PIPER_SOURCE", "COMPOSE_FILE",
                                  "COMPOSE_ENV_FILES", "COMPOSE_DISABLE_ENV_FILE"}}
            env.update(overrides or {})
            return subprocess.run(
                ["bash", "-eu", "-c",
                 'repo_root="$1"; source "$2"; load_compose_settings; '
                 'printf "%s\\n" "$RMW" "$IMAGE_PREFIX" "$CURTMINI_PIPER_SOURCE"',
                 "settings-test", directory, str(HELPER)],
                env=env, text=True, capture_output=True,
            )

    def test_dotenv_and_quoted_paths(self):
        result = self.resolve(
            "RMW=zenoh\nIMAGE_PREFIX=custom\n"
            "CURTMINI_PIPER_SOURCE='../sources with spaces/robot'\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(),
                         ["zenoh", "custom", "../sources with spaces/robot"])

    def test_shell_overrides_dotenv(self):
        result = self.resolve("RMW=zenoh\n", {"RMW": "cyclonedds"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], "cyclonedds")

    def test_unsupported_distribution_is_rejected(self):
        result = self.resolve("CONTAINER_ROS_DISTRO=unsupported\n")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Only ROS 2 Jazzy", result.stderr)


if __name__ == "__main__":
    unittest.main()
