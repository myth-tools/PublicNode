#!/usr/bin/env python3
"""
Notebook Embedding Utility.
Processes the master notebook template and injects dynamic configuration.
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

import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOTEBOOK_PATH = os.path.join(REPO_ROOT, "publicnode-vps-engine", "vps_setup.ipynb")
OUTPUT_PATH = os.path.join(REPO_ROOT, "vps-app", "lib", "app", "notebook_template.dart")


def main() -> None:
    """Read the master build config and generate the Kaggle notebook."""
    if not os.path.exists(NOTEBOOK_PATH):
        print(f"Error: Notebook not found at {NOTEBOOK_PATH}")
        return

    with open(NOTEBOOK_PATH) as f:
        content = f.read()

    import base64

    b64_content = base64.b64encode(content.encode()).decode()

    dart_code = f"""// PublicNode VPS
// Copyright (C) 2026 mohammadhasanulislam
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// AUTO-GENERATED - DO NOT EDIT
import 'dart:convert';

final String vpsNotebookTemplate = utf8.decode(
  base64.decode(
    '{b64_content}',
  ),
);
"""

    with open(OUTPUT_PATH, "w") as f:
        f.write(dart_code)

    # Auto-format the generated file immediately to match standard style
    import subprocess

    try:
        subprocess.run(
            ["dart", "format", OUTPUT_PATH], capture_output=True, check=False
        )
    except Exception:
        pass  # Fallback if dart is not in path

    print(f"✅ Embedded notebook written to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
