"""
Code Quality & Security Audit Pipeline.
Performs linting, type checking, and security analysis.
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
import shutil
import subprocess
import sys
import tempfile
import time

# Absolute Bytecode & Cache Redirection
sys.dont_write_bytecode = True
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
os.environ["PYTHONPYCACHEPREFIX"] = os.path.join(tempfile.gettempdir(), ".pycache")
os.environ["PYTEST_CACHE_DIR"] = os.path.join(tempfile.gettempdir(), ".pytest_cache")


# ANSI Color Codes for Rich Terminal Output
class Colors:
    """ANSI Color Codes for Rich Terminal Output."""

    HEADER = "\033[95m"
    OKBLUE = "\033[94m"
    OKCYAN = "\033[96m"
    OKGREEN = "\033[92m"
    WARNING = "\033[93m"
    FAIL = "\033[91m"
    ENDC = "\033[0m"
    BOLD = "\033[1m"


def verify_dependencies() -> None:
    """Ensure all required CLI tools are available in the system PATH."""
    required_tools = ["ruff", "uv", "dart", "flutter"]
    missing = []
    for tool in required_tools:
        if shutil.which(tool) is None:
            missing.append(tool)

    if missing:
        print(
            f"\n{Colors.FAIL}❌ AUDIT ABORTED: Missing required dependencies: {', '.join(missing)}{Colors.ENDC}"
        )
        print(
            f"{Colors.WARNING}Please ensure they are installed and available in your PATH.{Colors.ENDC}"
        )
        sys.exit(1)


failures: list[tuple[str, int | str]] = []


def run_step(
    name: str, cmd: list[str], cwd: str | None = None, halt_on_fail: bool = True
) -> bool:
    """Execute a shell command with timing and error handling."""
    print(f"\n{Colors.OKBLUE}{Colors.BOLD}{name}{Colors.ENDC}")
    start_time = time.time()

    try:
        # We pipe output directly to the terminal, but catch errors
        subprocess.run(cmd, cwd=cwd, check=True)
        elapsed = time.time() - start_time
        print(f"{Colors.OKGREEN}✓ Completed in {elapsed:.2f}s{Colors.ENDC}")
        return True
    except subprocess.CalledProcessError as e:
        elapsed = time.time() - start_time
        print(
            f"{Colors.FAIL}❌ Failed after {elapsed:.2f}s with exit code {e.returncode}{Colors.ENDC}"
        )
        print(f"{Colors.WARNING}Command: {' '.join(cmd)}{Colors.ENDC}")
        failures.append((name, e.returncode))
        if halt_on_fail:
            sys.exit(e.returncode)
        return False
    except Exception as e:
        print(f"{Colors.FAIL}❌ Unexpected failure: {e}{Colors.ENDC}")
        failures.append((name, "UNEXPECTED"))
        if halt_on_fail:
            sys.exit(1)
        return False


def main() -> None:
    """Industrial-grade linting, formatting, and analysis sequence."""
    total_start = time.time()

    print(
        f"{Colors.HEADER}{Colors.BOLD}🚀 PUBLICNODE SECURE AUDIT: Commencing Automated Diagnostics...{Colors.ENDC}"
    )

    # 0. Validate Environment
    verify_dependencies()

    # 0.5 Ensure Flutter dependencies are resolved (especially after a deep cleanup)
    run_step(
        "📦 STEP 0.5: Flutter Dependency Synchronization (pub get)",
        ["flutter", "pub", "get"],
        cwd="vps-app",
        halt_on_fail=True,
    )

    # 1. Python Formatting
    run_step(
        "🎨 STEP 1: Python Engine Formatting (ruff format)",
        ["ruff", "format", "."],
        halt_on_fail=False,
    )

    # 2. Python Fixing
    run_step(
        "🔧 STEP 2: Python Engine Safe Fixing (ruff check --fix)",
        ["ruff", "check", "--fix", "."],
        halt_on_fail=False,
    )

    # 3. Python Type Audit
    run_step(
        "🔍 STEP 3: Python Engine Type Verification (mypy)",
        ["uv", "run", "--extra", "dev", "mypy", "."],
        halt_on_fail=False,
    )

    # 4. Dart Format
    run_step(
        "✨ STEP 4: Dart Client Auto-Formatting (dart format)",
        ["dart", "format", "."],
        cwd="vps-app",
        halt_on_fail=False,
    )

    # 5. Dart Fix
    run_step(
        "🛠️  STEP 5: Dart Client Safe Fixing (dart fix --apply)",
        ["dart", "fix", "--apply"],
        cwd="vps-app",
        halt_on_fail=False,
    )

    # 6. Flutter Analyze
    run_step(
        "🔬 STEP 6: Flutter Client Deep Analysis (flutter analyze)",
        ["flutter", "analyze"],
        cwd="vps-app",
        halt_on_fail=False,
    )

    # 7. Flutter Engine Sanity & Tests
    if os.path.exists("tests/sanity_test.dart"):
        run_step(
            "🧪 STEP 7: Flutter Engine Deep Sanity Check (flutter test)",
            ["flutter", "test", "../tests/sanity_test.dart"],
            cwd="vps-app",
            halt_on_fail=False,
        )
    elif os.path.exists("vps-app/test"):
        run_step(
            "🛡️ STEP 7: Flutter Client Unit Testing (flutter test)",
            ["flutter", "test"],
            cwd="vps-app",
            halt_on_fail=False,
        )

    # 8. Python Engine Sanity & Tests
    if os.path.exists("tests/sanity_test.py"):
        run_step(
            "🧪 STEP 8: Python Engine Deep Sanity Check (pytest)",
            ["uv", "run", "pytest", "tests/sanity_test.py", "-v"],
            halt_on_fail=False,
        )
    elif os.path.exists("tests"):
        run_step(
            "🛡️ STEP 8: Python Engine Unit Testing (pytest)",
            ["uv", "run", "pytest", "tests", "-v"],
            halt_on_fail=False,
        )

    total_elapsed = time.time() - total_start

    if not failures:
        print(
            f"\n{Colors.OKGREEN}{Colors.BOLD}✅ FULL AUDIT COMPLETE: System is 100% Battle-Ready. (Total time: {total_elapsed:.2f}s){Colors.ENDC}\n"
        )
    else:
        print(
            f"\n{Colors.FAIL}{Colors.BOLD}❌ AUDIT FAILED: {len(failures)} stage(s) reported issues. (Total time: {total_elapsed:.2f}s){Colors.ENDC}"
        )
        for name, code in failures:
            print(f"  - {name} (Exit Code: {code})")
        print()
        sys.exit(1)


if __name__ == "__main__":
    main()
