#!/usr/bin/env python3
"""
Flutter Client Distribution Pipeline.
Orchestrates the packaging process for Linux and Android platforms.
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

import argparse
import os
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS_DIR = os.path.join(REPO_ROOT, "scripts")
UPDATE_SCRIPT = os.path.join(SCRIPTS_DIR, "update_and_embed.py")
APP_DIR = os.path.join(REPO_ROOT, "vps-app")


def run_command(cmd: list[str], cwd: str | None = None) -> None:
    """Run a shell command with real-time output streaming."""
    print(f"🚀 Running: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, cwd=cwd, check=True)
    except subprocess.CalledProcessError as e:
        print(f"❌ Error: Command failed with exit code {e.returncode}")
        sys.exit(e.returncode)


def main() -> None:
    """Build distribution packages for the Flutter client."""
    parser = argparse.ArgumentParser(description="PublicNode App Distribution Tool")
    parser.add_argument("platform", choices=["apk", "linux"], help="Target platform")
    args = parser.parse_args()

    # 1. Always sync assets first
    print("🧹 Phase 1: Synchronizing PublicNode Assets...")
    run_command(["make", "sync"], cwd=REPO_ROOT)

    # 2. Build for target platform
    print(f"🏗️ Phase 2: Building for {args.platform.upper()}...")

    if args.platform == "apk":
        run_command(
            ["uv", "run", "vps-release", "--apk-only", "--dry-run", "--skip-audit"]
        )
    elif args.platform == "linux":
        run_command(
            ["uv", "run", "vps-release", "--linux-only", "--dry-run", "--skip-audit"]
        )

    print(f"✨ Build Complete for {args.platform.upper()}!")


if __name__ == "__main__":
    main()
