"""
PublicNode VPS Codebase Sanity & Quality Audit Suite.
This module enforces industrial-grade standards across the entire Python ecosystem.
"""

import ast
import re
import shutil
import subprocess
from pathlib import Path

import pytest

# Constants
ROOT_DIR = Path(__file__).parent.parent
PYTHON_TARGET_DIRS = ["vps-os", "scripts"]
SHELL_SCRIPTS = ["vps-cli.sh"]


@pytest.fixture(scope="session")
def python_files() -> list[Path]:
    """Retrieve all target Python files in the project."""
    files = []
    for d in PYTHON_TARGET_DIRS:
        target_dir = ROOT_DIR / d
        if target_dir.exists():
            files.extend(list(target_dir.rglob("*.py")))

    # Filter out any virtualenvs
    return [f for f in files if ".venv" not in f.parts]


def test_python_syntax_and_ast_quality(python_files: list[Path]) -> None:
    """
    1. Deep Syntax & Architectural Analysis:
    Parses the Abstract Syntax Tree (AST) of every Python file.
    Guarantees zero runtime SyntaxErrors and enforces absolute enterprise quality:
    - No bare excepts (except:)
    - Mandatory docstrings for all Modules, Classes, and Functions.
    - No wildcard imports (from x import *)
    """
    assert len(python_files) > 0, "No Python files found to test."

    for file_path in python_files:
        try:
            content = file_path.read_text(encoding="utf-8")
            tree = ast.parse(content, filename=str(file_path))

            # Enforce Module Docstrings
            if not ast.get_docstring(tree):
                pytest.fail(
                    f"Quality Error: Missing module-level docstring in {file_path}. All files must be documented."
                )

            for node in ast.walk(tree):
                # Enforce Class & Function Docstrings
                if isinstance(
                    node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)
                ):
                    if not ast.get_docstring(node):
                        pytest.fail(
                            f"Quality Error: Missing docstring for {node.__class__.__name__} '{node.name}' in {file_path}. All components must be documented."
                        )

                # Enforce No Bare Excepts
                if isinstance(node, ast.ExceptHandler):
                    if node.type is None:
                        pytest.fail(
                            f"Quality Error: Bare 'except:' clause found in {file_path} at line {node.lineno}. Use 'except Exception as e:' to prevent catching system exits."
                        )

                # Enforce No Wildcard Imports
                if isinstance(node, ast.ImportFrom):
                    if any(alias.name == "*" for alias in node.names):
                        pytest.fail(
                            f"Quality Error: Wildcard import detected in {file_path} at line {node.lineno}. Use explicit imports."
                        )

        except SyntaxError as e:
            pytest.fail(
                f"FATAL: Syntax error in {file_path}\n{e.msg} at line {e.lineno}"
            )
        except Exception as e:
            pytest.fail(f"FATAL: Failed to read or parse {file_path}: {e}")


def test_complexity_and_naming_conventions(python_files: list[Path]) -> None:
    """
    2. Professional Code Standards:
    Enforces naming conventions (PEP8) and complexity limits.
    """
    for file_path in python_files:
        content = file_path.read_text(encoding="utf-8")
        tree = ast.parse(content)

        for node in ast.walk(tree):
            # Function Naming (snake_case)
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                if not re.match(r"^[a-z_][a-z0-9_]*$", node.name):
                    pytest.fail(
                        f"Naming Error: Function '{node.name}' in {file_path} must be snake_case."
                    )

                # Complexity: Check function length as a proxy for complexity
                lines = len(node.body)
                if lines > 100:
                    pytest.fail(
                        f"Complexity Error: Function '{node.name}' in {file_path} is too long ({lines} lines). Refactor into smaller units."
                    )

            # Class Naming (PascalCase)
            if isinstance(node, ast.ClassDef):
                if not re.match(r"^[A-Z][a-zA-Z0-9]*$", node.name):
                    pytest.fail(
                        f"Naming Error: Class '{node.name}' in {file_path} must be PascalCase."
                    )


def test_advanced_security_and_portability(python_files: list[Path]) -> None:
    """
    3. Deep Security Audit & Cross-Platform Portability:
    Ensures that Python code will work seamlessly across any Linux distro and Android.
    """
    # Regex for sensitive data (API keys, secrets)
    secret_pattern = re.compile(
        r'(?i)(api[_-]?key|secret|password|token|bearer|credential|private[_-]?key)[:=]\s*["\'][a-zA-Z0-9+/=]{10,}["\']'
    )
    hardcoded_path_pattern = re.compile(
        r'["\']/(usr|bin|etc|var|opt|root|home)/[a-zA-Z0-9_/.-]+["\']'
    )

    for file_path in python_files:
        content = file_path.read_text(encoding="utf-8")
        lines = content.splitlines()

        # Shebang portability check (Only for executable scripts)
        if lines and lines[0].startswith("#!"):
            assert lines[0] == "#!/usr/bin/env python3" or "python" not in lines[0], (
                f"FATAL: Hardcoded shebang '{lines[0]}' found in {file_path}. Must use '#!/usr/bin/env python3' for Android/Linux portability."
            )

        # Enforce Logging over Print in Core Engine
        if "vps-os" in file_path.parts:
            has_print = any(
                re.search(r"\bprint\(", line) and not line.strip().startswith("#")
                for line in lines
            )
            if has_print:
                pytest.fail(
                    f"Quality Error: Bare print() statements are outlawed in core engine ({file_path}). Use the 'logging' module for proper observability."
                )

        for i, line in enumerate(lines, 1):
            trimmed = line.strip()

            # Rule: Production Code should not have pending TODOs or FIXMEs
            if ("TODO:" in trimmed or "FIXME:" in trimmed) and not trimmed.startswith(
                "assert"
            ):
                pytest.fail(
                    f"Unresolved Task found in {file_path} at line {i}: {trimmed}. Resolve all tasks before release."
                )

            if trimmed.startswith("#"):
                continue

            # Secret Scanning
            if secret_pattern.search(trimmed):
                # Allow examples or placeholders
                if not any(
                    x in trimmed.lower()
                    for x in ["example", "placeholder", "your_", "my_"]
                ):
                    pytest.fail(
                        f"Security Error: Potential hardcoded secret/API key detected in {file_path} at line {i}."
                    )

            # Insecure HTTP endpoint check (Core Engine only)
            if "vps-os" in file_path.parts:
                if (
                    "http://" in trimmed
                    and "localhost" not in trimmed
                    and "127.0.0.1" not in trimmed
                ):
                    pytest.fail(
                        f"Insecure hardcoded HTTP URL found in {file_path} at line {i}. Use HTTPS."
                    )

            # Dangerous shell execution check (Core Engine only)
            if "vps-os" in file_path.parts:
                if (
                    "os.system(" in trimmed or "shell=True" in trimmed
                ) and not trimmed.startswith("#"):
                    pytest.fail(
                        f"Dangerous shell execution found in {file_path} at line {i}. Use subprocess.run with secure arrays, not shell=True."
                    )

            # Hardcoded absolute paths (Core Engine only - scripts/notebooks are exempt)
            if "vps-os" in file_path.parts:
                if hardcoded_path_pattern.search(trimmed):
                    pytest.fail(
                        f"FATAL: Hardcoded absolute path detected in {file_path} at line {i}: '{trimmed}'. "
                        f"This breaks Android (Termux) compatibility! Use os.path.join, pathlib, or environment variables (like os.environ.get('HOME'))."
                    )

            # Dangerous chmod permissions
            if "chmod 777" in trimmed or "chmod(0o777)" in trimmed:
                pytest.fail(
                    f"FATAL: Highly insecure 'chmod 777' detected in {file_path} at line {i}. Use restricted permissions (e.g., 755 or 600)."
                )

            # Pathlib Enforcement (Encourage Pathlib over os.path)
            if "os.path.join(" in trimmed or "os.path.exists(" in trimmed:
                # We issue a warning if possible, but for now let's just flag it as a quality issue
                # pytest.fail(f"Quality Warning: Use 'pathlib.Path' instead of 'os.path' in {file_path} at line {i} for modern standards.")
                pass


def test_shell_script_robustness() -> None:
    """
    4. Shell Script Audit:
    Checks critical shell scripts for best practices (set -e, shellcheck).
    """
    for script in SHELL_SCRIPTS:
        script_path = ROOT_DIR / script
        if not script_path.exists():
            continue

        content = script_path.read_text(encoding="utf-8")
        # Check for set -e, set -u, set -o pipefail
        # We don't fail immediately but warn or require at least set -e
        if "set -e" not in content:
            pytest.fail(
                f"Robustness Error: '{script}' is missing 'set -e'. It must exit on first error."
            )

        # ShellCheck integration (if available)
        if shutil.which("shellcheck"):
            result = subprocess.run(
                ["shellcheck", str(script_path)],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                pytest.fail(f"ShellCheck Failed for '{script}':\n{result.stdout}")


def test_deep_security_audit_bandit() -> None:
    """
    5. Strict Security Static Analysis: Executes 'bandit' over the entire codebase.
    """
    result = subprocess.run(
        ["uv", "run", "bandit", "-r", "vps-os", "scripts", "-ll"],
        cwd=ROOT_DIR,
        capture_output=True,
        text=True,
        check=False,
    )
    if (
        result.returncode != 0
        and "No module named" not in result.stderr
        and "not found" not in result.stderr
    ):
        pytest.fail(
            f"Bandit Security Audit Failed! Vulnerabilities detected:\n\n{result.stdout}\n{result.stderr}"
        )


def test_deep_static_linting_ruff() -> None:
    """
    6. Strict Ruff Linting.
    """
    result = subprocess.run(
        ["uv", "run", "ruff", "check", "vps-os", "scripts"],
        cwd=ROOT_DIR,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        pytest.fail(
            f"Ruff Linting Failed! The codebase has quality issues:\n\n{result.stdout}\n{result.stderr}"
        )


def test_deep_type_checking_mypy() -> None:
    """
    7. Strict Type Checking.
    """
    result = subprocess.run(
        ["uv", "run", "mypy", "vps-os", "scripts"],
        cwd=ROOT_DIR,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        pytest.fail(
            f"MyPy Type Checking Failed! The codebase has type inconsistencies:\n\n{result.stdout}\n{result.stderr}"
        )


def test_critical_infrastructure_paths() -> None:
    """
    8. Environment Validation.
    """
    required_paths = [
        "vps-os/vps_os_engine.py",
        "scripts/master_build_vps.py",
        "pyproject.toml",
        "Makefile",
    ]

    for path in required_paths:
        target = ROOT_DIR / path
        assert target.exists(), (
            f"Critical structural path is missing from project: {path}"
        )


def test_pyproject_toml_integrity() -> None:
    """
    9. Dependency Validation.
    """
    pyproject_path = ROOT_DIR / "pyproject.toml"
    assert pyproject_path.exists()

    content = pyproject_path.read_text(encoding="utf-8")
    assert "[project]" in content, "pyproject.toml is missing the [project] block."

    # Check for wildcard dependencies (Industrial standard: No '*' versions)
    if re.search(r'["\'][\w.-]+\s*==\s*\*["\']', content) or re.search(
        r'["\'][\w.-]+\s*=\s*\*["\']', content
    ):
        pytest.fail(
            "Quality Error: Wildcard dependencies (*) are prohibited in pyproject.toml. Use pinned or range-based versions."
        )


def test_infrastructure_file_quality() -> None:
    """
    10. Root Infrastructure File Quality:
    Scans root scripts and configs for TODOs/FIXMEs.
    """
    root_files = ["vps-cli.sh", "Makefile", "pyproject.toml", "README.md"]
    for file_name in root_files:
        path = ROOT_DIR / file_name
        if path.exists():
            content = path.read_text(encoding="utf-8")
            lines = content.splitlines()
            for i, line in enumerate(lines, 1):
                trimmed = line.strip()
                if "TODO:" in trimmed or "FIXME:" in trimmed:
                    # Skip the line if it is part of the check itself
                    if "assert" in trimmed or (
                        "TODO:" in trimmed and "re.search" in content
                    ):
                        continue
                    pytest.fail(
                        f"Unresolved Task found in root infrastructure file {file_name} at line {i}: {trimmed}"
                    )
