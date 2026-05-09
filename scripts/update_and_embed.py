"""
Asset Synchronization & Embedding Tool.

FULL PIPELINE (executed on every sync):
  1. Regenerate vps_setup.ipynb from master_build_vps.py + vps-config.yaml
     (picks up ALL structural changes: apt packages, boot logic, etc.)
  2. Update Base64-encoded vps-os/*.py payloads inside the notebook
  3. Embed the final notebook into notebook_template.dart for the Flutter app

This guarantees that EVERY build path (make sync, uv run vps-dist,
uv run vps-release, uv run vps-dev-audit, fastforge, etc.) produces
a notebook that is fully in sync with both the config and the engine sources.
"""

# PublicNode VPS
# Copyright (C) 2026 mohammadhasanulislam
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

import base64
import datetime
import json
import os
import re
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OS_DIR = os.path.join(REPO_ROOT, "vps-os")
APP_DIR = os.path.join(REPO_ROOT, "vps-app")
NOTEBOOK_PATH = os.path.join(REPO_ROOT, "publicnode-vps-engine", "vps_setup.ipynb")
EMBED_SCRIPT = os.path.join(REPO_ROOT, "scripts", "embed_notebook.py")
MASTER_BUILD_SCRIPT = os.path.join(REPO_ROOT, "scripts", "master_build_vps.py")
DEFAULT_CONFIG = os.path.join(REPO_ROOT, "vps-config.yaml")


def _rebuild_notebook_from_config() -> None:
    """Step 1: Regenerate vps_setup.ipynb from master_build_vps.py.

    This ensures every structural change in vps-config.yaml and
    master_build_vps.py (apt packages, boot orchestration, fail-safes,
    etc.) is materialized into the notebook before we update the
    Base64 payloads.
    """
    config_path = os.environ.get("CONFIG", DEFAULT_CONFIG)
    if not os.path.exists(config_path):
        config_path = DEFAULT_CONFIG

    print(
        f"📐 Step 1/3: Rebuilding notebook from config ({os.path.basename(config_path)})..."
    )

    result = subprocess.run(
        [sys.executable, MASTER_BUILD_SCRIPT, "--config", config_path],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    if result.returncode != 0:
        print(f"❌ Notebook rebuild FAILED:\n{result.stderr}")
        raise RuntimeError("master_build_vps.py failed. Cannot continue sync.")

    # Show key output lines for transparency
    for line in result.stdout.strip().splitlines():
        if line.startswith("[BUILD]"):
            print(f"   {line}")


def _update_b64_payloads() -> list[str]:
    """Step 2: Update the Base64-encoded vps-os/*.py payloads inside the notebook.

    Reads every .py file from vps-os/, encodes it, and patches the
    corresponding B64 constant inside vps_setup.ipynb.
    """
    print("🔄 Step 2/3: Encoding vps-os/ engine files into notebook...")

    # Discover ALL Python files in vps-os/ (future-proof)
    all_py_files = sorted(f for f in os.listdir(OS_DIR) if f.endswith(".py"))

    # Mapping of file names to their B64 constants in the notebook
    # This is the canonical registry — add new files here
    file_map = {
        "vps_os_engine.py": "OS_ENGINE_B64",
    }

    # Safety: warn if there are .py files in vps-os/ not in the map
    unmapped = [f for f in all_py_files if f not in file_map and f != "__init__.py"]
    if unmapped:
        print(f"   ⚠️  Unmapped vps-os/ files (not embedded): {unmapped}")

    with open(NOTEBOOK_PATH) as nb_file:
        nb = json.load(nb_file)

    updated_files = []

    for file_name, b64_key in file_map.items():
        file_path = os.path.join(OS_DIR, file_name)
        if not os.path.exists(file_path):
            print(f"   ⚠️  {file_name} not found in {OS_DIR}. Skipping.")
            continue

        with open(file_path, "rb") as engine_file:
            raw_bytes = engine_file.read()

        b64_val = base64.b64encode(raw_bytes).decode()

        # Verify round-trip integrity
        decoded = base64.b64decode(b64_val)
        if decoded != raw_bytes:
            raise RuntimeError(
                f"CRITICAL: Base64 round-trip failed for {file_name}. "
                "Data corruption detected."
            )

        found = False
        for cell in nb["cells"]:
            if cell["cell_type"] == "code":
                source = "".join(cell["source"])
                if b64_key in source:
                    pattern = rf"{b64_key} = ['\"][^'\"]+['\"]"
                    replacement = f"{b64_key} = '{b64_val}'"

                    if re.search(pattern, source):
                        new_source = re.sub(pattern, replacement, source)
                        cell["source"] = [
                            line + "\n" for line in new_source.split("\n") if line
                        ]
                        found = True
                        updated_files.append(file_name)
                        break

        if not found:
            print(f"   ❌ Could not find {b64_key} cell in notebook.")

    # Save the updated notebook
    with open(NOTEBOOK_PATH, "w") as out_file:
        json.dump(nb, out_file, indent=2)

    # Report
    for fname in updated_files:
        fpath = os.path.join(OS_DIR, fname)
        size_kb = os.path.getsize(fpath) / 1024
        print(f"   ✓ {fname} ({size_kb:.1f} KB) → {file_map[fname]}")

    return updated_files


def _embed_into_dart() -> None:
    """Step 3: Embed the final notebook into notebook_template.dart."""
    print("📦 Step 3/3: Embedding notebook into Flutter app...")
    subprocess.run([sys.executable, EMBED_SCRIPT], check=True)


def _write_sync_log() -> None:
    """Write a machine-readable sync status log for debugging."""
    log_path = os.path.join(APP_DIR, "assets", "sync_status.log")
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "w") as log_file:
        friendly_time = datetime.datetime.now().strftime("%A, %B %d, %Y at %I:%M:%S %p")
        log_file.write(f"PUBLICNODE ENGINE LAST SYNCED: {friendly_time}\n")


def main() -> None:
    """Full sync pipeline: rebuild → encode → embed."""
    print("🚀 Synchronizing PublicNode Engine with Master Notebook...")
    print()

    # Step 1: Regenerate notebook from config + master_build_vps.py
    _rebuild_notebook_from_config()
    print()

    # Step 2: Update B64 payloads for every vps-os/*.py file
    updated_files = _update_b64_payloads()
    print()

    # Step 3: Embed into Flutter app (notebook_template.dart)
    _embed_into_dart()

    # Write sync log
    _write_sync_log()

    print()
    print(f"✅ Full sync complete: {', '.join(updated_files)}")
    print("✨ PublicNode App Assets Refreshed.")


if __name__ == "__main__":
    main()
