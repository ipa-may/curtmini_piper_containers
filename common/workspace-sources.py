"""Import only dependencies not supplied by the local workspace mounts."""
from pathlib import Path
import os
import subprocess
import yaml

local = {"agx_arm_urdf", "curt_mini", "curtmini_piper", "curtmini_piper_gz_sim",
         "neo_gz_worlds"}
repositories = {}
for owner in ("curtmini_piper", "curtmini_piper_gz_sim"):
    root = Path("/opt/ws/src") / owner
    manifest_file = root / "docker/dependencies" / f"{os.environ['ROS_DISTRO']}.repos"
    if not manifest_file.is_file():
        manifest_file = root / "dependencies.repos"
    manifest = yaml.safe_load(manifest_file.read_text())
    for key, value in manifest["repositories"].items():
        # Preserve the existing flat dependency cache and skip mounted sources.
        name = Path(key).name
        if name in local:
            continue
        if name in repositories and repositories[name] != value:
            raise SystemExit(f"Conflicting dependency {name} in {manifest_file}")
        repositories[name] = value
# Existing checkouts are retained to support incremental/offline builds.
missing = {key: value for key, value in repositories.items()
           if not (Path('/opt/ws/dependencies') / key).exists()}
if missing:
    subprocess.run(
        ["vcs", "import", "--recursive", "/opt/ws/dependencies"],
        input=yaml.safe_dump({"repositories": missing}), text=True, check=True,
    )
