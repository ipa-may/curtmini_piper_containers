"""Import only dependencies not supplied by the local workspace mounts."""
from pathlib import Path
import subprocess
import yaml

local = {"agx_arm_urdf", "curt_mini", "curtmini_piper", "curtmini_piper_gz_sim",
         "neo_gz_worlds"}
manifest = yaml.safe_load(Path("/opt/locks/dependencies.repos").read_text())
repositories = {key: value for key, value in manifest["repositories"].items()
                if key not in local}
# Existing checkouts are retained to support incremental/offline builds.
missing = {key: value for key, value in repositories.items()
           if not (Path('/opt/ws/dependencies') / key).exists()}
if missing:
    subprocess.run(
        ["vcs", "import", "--recursive", "/opt/ws/dependencies"],
        input=yaml.safe_dump({"repositories": missing}), text=True, check=True,
    )
