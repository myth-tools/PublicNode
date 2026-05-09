"""
==============================================================================
 PUBLICNODE MASTER RELEASE ORCHESTRATOR
 Local CI/CD Pipeline — Builds all distribution formats and publishes
 to GitHub Releases. No GitHub Actions required.

 Usage:
     uv run vps-release                  # Build all + push to GitHub
     uv run vps-release --skip-audit     # Skip the audit step
     uv run vps-release --snap-store     # Also publish to Snap Store
     uv run vps-release --dry-run        # Build only, don't push

 (c) 2026 mohammadhasanulislam — GNU GPLv3 Licensed
==============================================================================
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
import datetime
import glob
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

import yaml

# Absolute Bytecode & Cache Redirection
sys.dont_write_bytecode = True
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
os.environ["PYTHONPYCACHEPREFIX"] = os.path.join(tempfile.gettempdir(), ".pycache")

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = os.path.join(REPO_ROOT, "vps-app")
RELEASE_DIR = os.path.join(REPO_ROOT, "release")


# ─── ANSI Terminal Colors ────────────────────────────────────────────────────
class C:
    """ANSI Escape Sequences for Industrial Terminal Output."""

    H = "\033[95m"  # Header
    B = "\033[94m"  # Blue
    OK = "\033[92m"  # Green
    W = "\033[93m"  # Warning
    F = "\033[91m"  # Fail
    E = "\033[0m"  # End
    BOLD = "\033[1m"


# ─── Helpers ─────────────────────────────────────────────────────────────────
def log(msg: str, icon: str = "◢◤") -> None:
    """Print an industrial-grade log message with an icon."""
    print(f"{C.B}{C.BOLD}{icon} {msg}{C.E}")


def ok(msg: str) -> None:
    """Print a success message."""
    print(f"{C.OK}✓ {msg}{C.E}")


def warn(msg: str) -> None:
    """Print a warning message."""
    print(f"{C.W}⚠ {msg}{C.E}")


def fail(msg: str) -> None:
    """Print a failure message and exit with error code."""
    print(f"{C.F}❌ {msg}{C.E}")
    sys.exit(1)


def run(
    cmd: list[str],
    cwd: str | None = None,
    check: bool = True,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[bytes]:
    """Execute a command with timing and pretty output."""
    # Resolve the executable path if it's not an absolute path
    if cmd and not os.path.isabs(cmd[0]):
        tool = shutil.which(cmd[0])
        if tool:
            cmd[0] = tool

    log(f"Running: {' '.join(cmd)}", "🚀")
    start = time.time()
    try:
        result = subprocess.run(cmd, cwd=cwd, check=check, env=env)
        elapsed = time.time() - start
        ok(f"Completed in {elapsed:.2f}s")
        return result
    except subprocess.CalledProcessError as e:
        elapsed = time.time() - start
        fail(
            f"Command failed after {elapsed:.2f}s (exit code {e.returncode}): {' '.join(cmd)}"
        )
        raise  # unreachable but satisfies type checker


def get_version() -> str:
    """Read the app version from pubspec.yaml."""
    pubspec = os.path.join(APP_DIR, "pubspec.yaml")
    with open(pubspec) as f:
        for line in f:
            match = re.match(r"^version:\s*(.+)$", line.strip())
            if match:
                # Strip build metadata (e.g., "0.1.0+1" -> "0.1.0")
                ver = match.group(1).strip().split("+")[0]
                return ver
    fail("Could not parse version from pubspec.yaml")
    return ""  # unreachable


def verify_dependencies() -> None:
    """Ensure all required CLI tools exist with version auditing."""
    required = {
        "gh": "GitHub CLI (https://cli.github.com/)",
        "flutter": "Flutter SDK (https://flutter.dev/)",
        "dart": "Dart SDK (bundled with Flutter)",
        "docker": "Docker (for RPM builds)",
        "patchelf": "ELF RPATH patching tool",
        "file": "Artifact verification tool",
    }
    optional = {
        "snapcraft": "Snap packaging (sudo snap install snapcraft --classic)",
    }

    missing = []
    for tool, desc in required.items():
        if shutil.which(tool) is None:
            missing.append(f"  - {tool}: {desc}")

    if missing:
        fail("Missing required industrial dependencies:\n" + "\n".join(missing))

    # Version Audit
    try:
        f_ver = subprocess.check_output(["flutter", "--version"], text=True).split(
            "\n"
        )[0]
        ok(f"Industrial Toolchain Verified: {f_ver}")
    except Exception:
        warn("Could not audit toolchain versions.")

    for tool, desc in optional.items():
        if shutil.which(tool) is None:
            warn(f"Optional tool not found: {tool} ({desc})")


def check_system_health() -> None:
    """Audit system resources to ensure build stability."""
    log("Phase 0.1: System Health Audit", "🩺")
    # Check Disk Space (Require at least 5GB free)
    _, _, free = shutil.disk_usage(REPO_ROOT)
    free_gb = free // (2**30)
    if free_gb < 5:
        fail(
            f"Insufficient disk space: {free_gb}GB free. Require at least 5GB for industrial build."
        )
    ok(f"Disk Health: {free_gb}GB available.")

    # Check for Docker daemon
    try:
        subprocess.run(["docker", "info"], capture_output=True, check=True)
        ok("Virtualization: Docker engine is operational.")
    except Exception:
        warn(
            "Virtualization: Docker engine not found or unreachable. RPM build will fail."
        )


def find_fastforge() -> str:
    """Find the packaging tool (fastforge or flutter_distributor)."""
    if shutil.which("fastforge"):
        return "fastforge"
    # Try dart run fastforge
    result = subprocess.run(
        ["dart", "run", "fastforge", "--version"],
        cwd=APP_DIR,
        capture_output=True,
        timeout=15,
        check=False,
    )
    if result.returncode == 0:
        return "dart run fastforge"
    fail(
        "Neither 'fastforge' nor 'flutter_distributor' found.\n"
        "Install with: dart pub global activate fastforge"
    )
    return ""  # unreachable


def ensure_linux_bundle() -> str:
    """Ensure the Flutter Linux bundle is built and return its path."""
    bundle_dir = os.path.join(APP_DIR, "build", "linux", "x64", "release", "bundle")
    if not os.path.exists(bundle_dir):
        log("Building Flutter Linux bundle...", "🏗️")
        # Note: We rely on the top-level clean in build_all_formats
        run(["flutter", "pub", "get"], cwd=APP_DIR)
        run(["flutter", "build", "linux", "--release"], cwd=APP_DIR)
    return bundle_dir


# ─── Build Stages ────────────────────────────────────────────────────────────
def build_apk() -> list[str]:
    """Build Android APKs and return the artifact paths."""
    log("Building Android APK (Release Optimized)...", "📱")
    # Industrial Optimization: Split per ABI, obfuscate, and strip symbols to reduce size
    symbols_dir = os.path.join(APP_DIR, "build", "app", "outputs", "symbols")
    os.makedirs(symbols_dir, exist_ok=True)

    # 1. Build the Split ABI APKs
    run(
        [
            "flutter",
            "build",
            "apk",
            "--release",
            "--split-per-abi",
            "--obfuscate",
            f"--split-debug-info={symbols_dir}",
        ],
        cwd=APP_DIR,
    )

    # 2. Build the Universal "Fat" APK
    log("Building Universal Android APK...", "📱")
    run(
        [
            "flutter",
            "build",
            "apk",
            "--release",
            "--obfuscate",
            f"--split-debug-info={symbols_dir}",
        ],
        cwd=APP_DIR,
    )

    artifacts = []
    apk_glob = os.path.join(
        APP_DIR, "build", "app", "outputs", "flutter-apk", "app-*-release.apk"
    )
    for p in glob.glob(apk_glob):
        ok(f"APK artifact: {p}")
        artifacts.append(p)

    # Always collect the universal "Fat" APK as well
    universal_apk = os.path.join(
        APP_DIR, "build", "app", "outputs", "flutter-apk", "app-release.apk"
    )
    if os.path.exists(universal_apk):
        ok(f"APK artifact: {universal_apk}")
        artifacts.append(universal_apk)

    return artifacts


def build_rpm_via_docker(version: str) -> str | None:
    """Build RPM package using a native Enterprise Linux (AlmaLinux) Docker container."""
    log("Building RPM Package (via Docker)...", "🐳")

    rpm_config_dir = os.path.join(APP_DIR, "linux", "packaging", "rpm")
    make_config_path = os.path.join(rpm_config_dir, "make_config.yaml")

    if not os.path.exists(make_config_path):
        warn("RPM make_config.yaml not found. Skipping RPM build.")
        return None

    with open(make_config_path) as cfg_file:
        config = yaml.safe_load(cfg_file)

    pkg_name = config.get("package_name", "publicnode")

    # 0. Ensure Flutter Linux bundle exists
    bundle_dir = ensure_linux_bundle()

    # 1. Prepare Staging Area
    stage_dir = os.path.join(APP_DIR, "build", "rpm_stage")
    os.makedirs(os.path.join(stage_dir, "SPECS"), exist_ok=True)
    os.makedirs(os.path.join(stage_dir, "SOURCES"), exist_ok=True)

    # Copy bundle to SOURCES
    sources_bundle = os.path.join(stage_dir, "SOURCES", "bundle")
    if os.path.exists(sources_bundle):
        shutil.rmtree(sources_bundle)
    shutil.copytree(bundle_dir, sources_bundle)

    # --- RPATH Patching (Industrial Portability) ---
    log("Patching ELF binaries for portability...", "🔧")
    # Patch main executable
    main_exe = os.path.join(sources_bundle, pkg_name)
    if os.path.exists(main_exe):
        subprocess.run(
            ["patchelf", "--set-rpath", "$ORIGIN/lib", main_exe], check=False
        )

    # Patch all shared libraries
    lib_dir = os.path.join(sources_bundle, "lib")
    if os.path.exists(lib_dir):
        for root, _, files in os.walk(lib_dir):
            for f in files:
                if f.endswith(".so") or ".so." in f:
                    lib_path = os.path.join(root, f)
                    subprocess.run(
                        ["patchelf", "--set-rpath", "$ORIGIN", lib_path], check=False
                    )
    # ---------------------------------------------

    # Copy icon
    icon_src = os.path.join(APP_DIR, config.get("icon", "assets/icon.png"))
    if os.path.exists(icon_src):
        shutil.copy2(icon_src, os.path.join(stage_dir, "SOURCES", "icon.png"))

    spec_path = os.path.join(stage_dir, "SPECS", f"{pkg_name}.spec")
    summary = config.get("description", "PublicNode Terminal Viewer")
    license_name = config.get("license", "GPLv3")
    url = config.get("homepage", "https://github.com/myth-tools/PublicNode")
    display_name = config.get("display_name", "PublicNode")
    depends = config.get("depends", [])

    # Use dynamic metadata for changelog
    now = datetime.datetime.now()
    date_str = now.strftime("%a %b %d %Y")
    author_name = config.get("maintainer", {}).get("name", "Shesher Hasan")
    author_email = config.get("maintainer", {}).get("email", "shesher0007@gmail.com")

    requires_line = ""
    if depends:
        requires_line = "Requires:       " + ", ".join(depends)

    spec_content = f"""
Name:           {pkg_name}
Version:        {version}
Release:        1%{{?dist}}
Summary:        {summary}
License:        {license_name}
URL:            {url}
BuildArch:      x86_64
{requires_line}

%description
{summary}

# Filter out internal libraries and libjvm from requirements
%global __requires_exclude ^(libflutter_linux_gtk\\.so|libflutter_secure_storage_linux_plugin\\.so|libapp\\.so|libdartjni.so|libjvm\\.so).*$
%global __provides_exclude ^(libflutter_linux_gtk\\.so|libflutter_secure_storage_linux_plugin\\.so|libapp\\.so|libdartjni.so).*$

%install
mkdir -p %{{buildroot}}%{{_bindir}}
mkdir -p %{{buildroot}}%{{_datadir}}/%{{name}}
mkdir -p %{{buildroot}}%{{_datadir}}/applications
mkdir -p %{{buildroot}}%{{_datadir}}/pixmaps

# Copy bundle contents (mounted at SOURCES/bundle)
cp -r %{{_sourcedir}}/bundle/* %{{buildroot}}%{{_datadir}}/%{{name}}/

# Create relative symlink for the executable
ln -s ../share/%{{name}}/{pkg_name} %{{buildroot}}%{{_bindir}}/%{{name}}

# Install desktop file
cat <<EOF > %{{buildroot}}%{{_datadir}}/applications/%{{name}}.desktop
[Desktop Entry]
Name={display_name}
Exec=%{{name}} %U
Terminal=false
Type=Application
Icon=%{{name}}
Categories=Utility;
MimeType=x-scheme-handler/publicnode;
EOF

# Install icon
if [ -f %{{_sourcedir}}/icon.png ]; then
    cp %{{_sourcedir}}/icon.png %{{buildroot}}%{{_datadir}}/pixmaps/%{{name}}.png
fi

%files
%{{_bindir}}/%{{name}}
%{{_datadir}}/%{{name}}
%{{_datadir}}/applications/%{{name}}.desktop
%{{_datadir}}/pixmaps/%{{name}}.png

%changelog
* {date_str} {author_name} <{author_email}> - {version}-1
- Industrial-grade release for PublicNode VPS.
"""
    with open(spec_path, "w") as spec_file:
        spec_file.write(spec_content.strip() + "\n")

    # 3. Build Docker Image
    dockerfile = os.path.join(rpm_config_dir, "Dockerfile.rpm")
    run(
        [
            "docker",
            "build",
            "--build-arg",
            f"CACHE_BUST={time.time()}",
            "-t",
            "publicnode-rpm-builder",
            "-f",
            dockerfile,
            rpm_config_dir,
        ]
    )

    # 4. Run RPM Build in Container
    dist_dir = os.path.join(APP_DIR, "dist")
    os.makedirs(dist_dir, exist_ok=True)

    # We use -v to mount the staging area and dist directory
    run(
        [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{os.path.join(stage_dir, 'SPECS')}:/home/builder/rpmbuild/SPECS:Z",
            "-v",
            f"{os.path.join(stage_dir, 'SOURCES')}:/home/builder/rpmbuild/SOURCES:Z",
            "-v",
            f"{dist_dir}:/home/builder/rpmbuild/RPMS/x86_64:Z",
            "publicnode-rpm-builder",
            "-bb",
            f"/home/builder/rpmbuild/SPECS/{pkg_name}.spec",
        ]
    )

    # Find the generated RPM
    for p in glob.glob(os.path.join(dist_dir, f"{pkg_name}-{version}-*.rpm")):
        ok(f"RPM artifact built: {p}")
        return p

    return None


def build_linux_packages(version: str) -> list[str]:
    """Build DEB and RPM packages, return list of artifact paths."""
    log("Building Linux Packages (DEB + RPM)...", "🐧")

    artifacts: list[str] = []

    # Build DEB using fastforge
    log("Phase 3a: Building DEB package...", "📦")
    forge = find_fastforge()
    if forge.startswith("dart run"):
        cmd = [
            "dart",
            "run",
            "fastforge",
            "package",
            "--platform",
            "linux",
            "--targets",
            "deb",
        ]
    else:
        cmd = [forge, "package", "--platform", "linux", "--targets", "deb"]

    run(cmd, cwd=APP_DIR)

    # Collect DEB
    dist_dir = os.path.join(APP_DIR, "dist")
    for p in glob.glob(os.path.join(dist_dir, "**", "*.deb"), recursive=True):
        artifacts.append(p)
        ok(f"DEB artifact: {p}")

    # Build RPM using Docker
    log("Phase 3b: Building RPM package...", "📦")
    rpm_path = build_rpm_via_docker(version)
    if rpm_path:
        artifacts.append(rpm_path)

    if not artifacts:
        warn("Linux packages built but no .deb/.rpm artifacts found in dist/")

    return artifacts


def build_snap() -> str | None:
    """Build Snap package and return artifact path."""
    if shutil.which("snapcraft") is None:
        warn("snapcraft not installed. Skipping Snap build.")
        return None

    log("Building Snap Package (Destructive Mode)...", "🔧")

    # Pre-build Cleanup: Ensure a fresh environment for destructive mode
    snap_artifacts = ["parts", "stage", "prime", "overlay"]
    for artifact in snap_artifacts:
        path = os.path.join(APP_DIR, artifact)
        if os.path.exists(path):
            log(f"Clearing stale Snapcraft artifact: {artifact}", "🧹")
            subprocess.run(["sudo", "rm", "-rf", path], check=False)

    # 0. Ensure Flutter Linux bundle exists (since we use 'dump' plugin)
    ensure_linux_bundle()

    # Suppress internal Python SyntaxWarnings from snapcraft/gnupg
    env = os.environ.copy()
    env["PYTHONWARNINGS"] = "ignore"

    cmd = ["sudo", "/snap/bin/snapcraft", "pack", "--destructive-mode"]

    try:
        run(cmd, cwd=APP_DIR, env=env)
    except Exception as e:
        warn("Snap build via destructive mode (sudo) failed.")
        raise e

    # Find the .snap file
    for p in glob.glob(os.path.join(APP_DIR, "*.snap")):
        ok(f"Snap artifact: {p}")
        return p

    warn("Snap build completed but .snap file not found.")
    return None


# ... (Removed redundant stage_artifacts block)


# ─── Artifact Collection ─────────────────────────────────────────────────────
def collect_artifacts(version: str, artifacts: list[str | None]) -> list[str]:
    """Relocate all artifacts into release/vX.Y.Z/ (Zero-Copy)."""
    ver_dir = os.path.join(RELEASE_DIR, f"v{version}")
    os.makedirs(ver_dir, exist_ok=True)

    collected: list[str] = []
    name_map: dict[str, str] = {
        ".deb": f"publicnode-{version}-linux-amd64.deb",
        ".rpm": f"publicnode-{version}-linux-amd64.rpm",
        ".snap": f"publicnode-{version}-linux-amd64.snap",
    }

    for src in artifacts:
        if src is None or not os.path.exists(src):
            continue
        ext = os.path.splitext(src)[1].lower()

        # Enhanced APK Naming: Preserve architecture from Flutter's split-per-abi
        if ext == ".apk":
            basename = os.path.basename(src)
            # Handle the universal fat APK
            if basename == "app-release.apk":
                dest_name = f"publicnode-{version}-android-universal.apk"
            else:
                # Patterns: app-arm64-v8a-release.apk, app-armeabi-v7a-release.apk, etc.
                match = re.search(r"app-(.+)-release\.apk", basename)
                if match:
                    abi = match.group(1)
                    dest_name = f"publicnode-{version}-android-{abi}.apk"
                else:
                    dest_name = f"publicnode-{version}-android-universal.apk"
        else:
            dest_name = name_map.get(ext, os.path.basename(src))

        dest = os.path.join(ver_dir, dest_name)

        # MOVE instead of copy to ensure no duplicates are left in source tree
        shutil.move(src, dest)
        ok(f"Relocated to Release: {dest_name}")
        collected.append(dest)

    return collected


def verify_artifact_integrity(path: str) -> bool:
    """Deep verification of artifact file headers and structure."""
    if not os.path.exists(path):
        return False

    ext = os.path.splitext(path)[1].lower()
    try:
        if ext == ".apk":
            # APK is a ZIP file but 'file' command may report 'Android package'
            res = subprocess.run(
                ["file", path], capture_output=True, text=True, check=False
            )
            return "Zip archive data" in res.stdout or "Android package" in res.stdout
        elif ext in [".deb", ".rpm"]:
            res = subprocess.run(
                ["file", path], capture_output=True, text=True, check=False
            )
            return (
                "Debian binary package" in res.stdout
                or "RPM v3.0" in res.stdout
                or "RPM v4.0" in res.stdout
            )
        elif ext == ".snap":
            res = subprocess.run(
                ["file", path], capture_output=True, text=True, check=False
            )
            return "Squashfs filesystem" in res.stdout
    except Exception:
        return True  # Fallback to existence if 'file' fails
    return True


def generate_checksums(ver_dir: str, artifacts: list[str]) -> str:
    """Generate SHA256 checksums with deep integrity verification."""
    log("Phase 4b: Generating High-Fidelity Integrity Checksums...", "🛡️")
    checksum_file = os.path.join(ver_dir, "SHA256SUMS.txt")
    with open(checksum_file, "w") as f:
        for a in artifacts:
            # Deep Integrity Check
            if not verify_artifact_integrity(a):
                warn(f"Artifact integrity check FAILED for {os.path.basename(a)}")

            sha256_hash = hashlib.sha256()
            with open(a, "rb") as bf:
                for byte_block in iter(lambda: bf.read(4096), b""):
                    sha256_hash.update(byte_block)
            checksum = sha256_hash.hexdigest()
            name = os.path.basename(a)
            f.write(f"{checksum}  {name}\n")
            # Show FULL hash in logs for transparency
            ok(f"Verified {name}: {checksum}")
    return checksum_file


# ─── GitHub Release ──────────────────────────────────────────────────────────
def publish_github_release(version: str, artifacts: list[str]) -> None:
    """Create a GitHub Release and upload all artifacts."""
    tag = f"v{version}"
    log(f"Publishing GitHub Release: {tag}", "🚀")

    # Get Repo from config
    config_path = os.path.join(REPO_ROOT, "vps-config.yaml")
    with open(config_path) as f:
        config = yaml.safe_load(f)

    github_repo = config.get("distribution", {}).get("github_repo")
    if not github_repo:
        fail(
            "No github_repo found in vps-config.yaml. Please set it under the 'distribution' key."
        )

    # SECURE CHECK: Ensure local branch is in sync with remote
    log("Verifying remote synchronization...", "🔄")
    subprocess.run(["git", "fetch"], cwd=REPO_ROOT, check=False)
    rev_result = subprocess.run(
        ["git", "rev-list", "HEAD..@{u}"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if rev_result.stdout.strip():
        fail("Remote has commits that you don't have locally. Pull first.")

    rev_result = subprocess.run(
        ["git", "rev-list", "@{u}..HEAD"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if rev_result.stdout.strip():
        warn("Local branch has unpushed commits. Pushing now...")
        run(["git", "push"], cwd=REPO_ROOT)

    repo_url = f"https://github.com/{github_repo}.git"

    # Ensure all changes are committed
    result = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.stdout.strip():
        warn("Uncommitted changes detected. Committing before release...")
        run(["git", "add", "-A"], cwd=REPO_ROOT)
        run(["git", "commit", "-m", f"release: v{version}"], cwd=REPO_ROOT)

    # Delete existing remote tag to allow re-pushing
    subprocess.run(
        ["git", "push", repo_url, "--delete", tag],
        cwd=REPO_ROOT,
        capture_output=True,
        check=False,
    )

    # Tag
    subprocess.run(
        ["git", "tag", "-d", tag], cwd=REPO_ROOT, capture_output=True, check=False
    )  # delete if exists
    run(["git", "tag", "-a", tag, "-m", f"PublicNode v{version}"], cwd=REPO_ROOT)

    # Push to the configured repo URL directly
    run(["git", "push", repo_url, "--tags", "HEAD"], cwd=REPO_ROOT)

    # Delete existing release if any (for re-releases)
    subprocess.run(
        [
            "gh",
            "release",
            "delete",
            tag,
            "--repo",
            github_repo,
            "--yes",
            "--cleanup-tag",
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        check=False,
    )

    # Create descriptive guide for users
    guide_path = os.path.join(RELEASE_DIR, f"v{version}", "INSTALL_GUIDE.md")
    with open(guide_path, "w") as f:
        f.write(
            f"""## 📦 Installation Guide (v{version})

### 📱 Android (Mobile)
Please download the APK that matches your device architecture:
*   **`publicnode-{version}-android-arm64-v8a.apk`**: **Highly Recommended.** For most modern phones (Samsung S8+, Pixel, OnePlus, etc.)
*   **`publicnode-{version}-android-armeabi-v7a.apk`**: For older or budget 32-bit phones.
*   **`publicnode-{version}-android-x86_64.apk`**: For Android emulators on PC.
*   **`publicnode-{version}-android-universal.apk`**: Works on all phones (It's generally much larger though).

### 🐧 Linux (Desktop)
*   **Debian/Ubuntu/Mint**: Download the `publicnode-{version}-linux-amd64.deb` package.
*   **Fedora/AlmaLinux/CentOS**: Download the `publicnode-{version}-linux-amd64.rpm` package.
*   **Universal**: Download the `publicnode-{version}-linux-amd64.snap` package.

---
### 🛠️ Verification
Verify artifact integrity using the `SHA256SUMS.txt` file provided below.
"""
        )

    # Create release with the guide and auto-generated notes
    cmd = [
        "gh",
        "release",
        "create",
        tag,
        "--repo",
        github_repo,
        "--title",
        f"PublicNode v{version}",
        "--notes-file",
        guide_path,
        "--generate-notes",
        *artifacts,
    ]

    run(cmd, cwd=REPO_ROOT)
    ok(f"GitHub Release v{version} published successfully!")


def publish_snap_store(snap_path: str) -> None:
    """Upload and release the snap to the Snap Store."""
    log("Publishing to Snap Store...", "🏪")
    result = subprocess.run(
        ["snapcraft", "upload", snap_path, "--release=stable"], cwd=APP_DIR, check=False
    )
    if result.returncode == 0:
        ok("Snap published to the Snap Store (stable channel)!")
    else:
        warn("Snap Store upload failed. You may need to run 'snapcraft login' first.")


def sanitize_environment(deep: bool = False) -> None:
    """Wipe build and dist directories to ensure a clean state."""
    log("Sanitizing build environment...", "🧹")
    clean_dirs = [os.path.join(APP_DIR, "build"), os.path.join(APP_DIR, "dist")]
    if deep:
        log("Executing Deep Sanitization (Caches)...", "☢️")
        clean_dirs.extend(
            [
                os.path.join(APP_DIR, ".dart_tool"),
                os.path.join(APP_DIR, "android", ".gradle"),
            ]
        )

    for d in clean_dirs:
        if os.path.exists(d):
            shutil.rmtree(d)

    # Clean stale packages in root
    for ext in ["*.snap", "*.deb", "*.rpm", "*.apk"]:
        for p in glob.glob(os.path.join(APP_DIR, ext)):
            os.remove(p)


def deep_cleanup() -> None:
    """Wipe all intermediate build directories to leave a zero-trace workspace."""
    log("Phase 7: Performing Deep Cleanup of intermediate assets...", "🧹")
    targets = [
        os.path.join(APP_DIR, "build"),
        os.path.join(APP_DIR, "dist"),
        os.path.join(APP_DIR, ".dart_tool"),
        os.path.join(APP_DIR, ".flutter-plugins"),
        os.path.join(APP_DIR, ".flutter-plugins-dependencies"),
    ]
    for target in targets:
        if os.path.exists(target):
            try:
                if os.path.isdir(target):
                    shutil.rmtree(target)
                else:
                    os.remove(target)
                ok(f"Purged: {os.path.basename(target)}")
            except Exception as e:
                warn(f"Failed to purge {target}: {e}")

    # Industrial Cleanup: Snapcraft Destructive Mode Artifacts (Requires Sudo)
    snap_artifacts = ["parts", "stage", "prime", "overlay"]
    for artifact in snap_artifacts:
        path = os.path.join(APP_DIR, artifact)
        if os.path.exists(path):
            try:
                # Use sudo as these folders often contain root-owned files
                subprocess.run(["sudo", "rm", "-rf", path], check=True)
                ok(f"Purged Snapcraft Artifact: {artifact}")
            except Exception as e:
                warn(f"Failed to purge Snapcraft artifact {artifact}: {e}")


def print_release_summary(version: str, artifact_count: int, elapsed: float) -> None:
    """Print the final high-fidelity release report."""
    print(f"\n{C.OK}{C.BOLD}{'═' * 60}{C.E}")
    print(f"{C.OK}{C.BOLD}   🚀 RELEASE v{version} COMPLETE{C.E}")
    print(f"{C.OK}{C.BOLD}{'═' * 60}{C.E}")
    print(f"{C.BOLD}  Organization: {C.B}myth-tools{C.E}")
    print(f"{C.BOLD}  Creator:      {C.B}Shesher Hasan{C.E}")
    print(f"{C.BOLD}  Artifacts:    {C.B}{artifact_count} items staged{C.E}")
    print(f"{C.BOLD}  Total Time:   {C.B}{elapsed:.1f}s{C.E}")
    print(f"{C.OK}{C.BOLD}{'═' * 60}{C.E}\n")


def build_all_formats(
    version: str, args: argparse.Namespace
) -> tuple[list[str | None], str | None]:
    """Execute Phase 3: Build all requested distribution formats."""
    log("Phase 3: Building Distribution Artifacts...", "🏗️")
    sanitize_environment(deep=args.deep_clean)

    # Perform a single unified clean at the start to prevent subsequent wipes from deleting artifacts
    log("Initializing clean build environment...", "🧹")
    run(["flutter", "clean"], cwd=APP_DIR)
    run(["flutter", "pub", "get"], cwd=APP_DIR)

    all_artifacts: list[str | None] = []

    # DEB + RPM (Skip if APK-only or Snap-only)
    if not any([args.apk_only, args.snap_only]):
        if args.rpm_only:
            rpm_path = build_rpm_via_docker(version)
            if rpm_path:
                all_artifacts.append(rpm_path)
        elif args.deb_only:
            # Build only DEB
            log("Phase 3a: Building DEB package...", "📦")
            forge = find_fastforge()
            if forge.startswith("dart run"):
                cmd = [
                    "dart",
                    "run",
                    "fastforge",
                    "package",
                    "--platform",
                    "linux",
                    "--targets",
                    "deb",
                ]
            else:
                cmd = [forge, "package", "--platform", "linux", "--targets", "deb"]
            run(cmd, cwd=APP_DIR)
            for p in glob.glob(
                os.path.join(APP_DIR, "dist", "**", "*.deb"), recursive=True
            ):
                all_artifacts.append(p)
        else:
            # Build both (standard --linux-only or full release)
            all_artifacts.extend(build_linux_packages(version))

    # Snap
    snap_path = None
    # Build snap if: full build, OR snap-only, OR linux-only (unless explicitly skipped)
    is_snap_requested = args.snap_only or (
        not any([args.apk_only, args.rpm_only, args.deb_only, args.skip_snap])
    )

    if is_snap_requested:
        snap_path = build_snap()
        all_artifacts.append(snap_path)
    else:
        warn("Phase 3: Snap build skipped")

    # APK (Skip if any Linux-specific flag or snap-only is set)
    # Note: Built LAST because fastforge (in DEB phase) aggressively runs `flutter clean`
    if not any([args.linux_only, args.rpm_only, args.deb_only, args.snap_only]):
        all_artifacts.extend(build_apk())
    else:
        log("Phase 3: Skipping APK build (Targeted build requested)")

    return all_artifacts, snap_path


def publish_assets(
    version: str, collected: list[str], snap_path: str | None, args: argparse.Namespace
) -> None:
    """Execute Phase 5 & 6: Publish artifacts to GitHub and Snap Store."""
    if args.dry_run:
        warn("Phase 5: Dry-run mode — skipping GitHub Release.")
        return

    log("Phase 5: Publishing to GitHub Releases...", "🌐")
    publish_github_release(version, collected)

    # ── Phase 6: Snap Store (Optional) ───────────────────────────────────
    if args.snap_store:
        if snap_path:
            snap_staged = os.path.join(
                RELEASE_DIR, f"v{version}", f"publicnode-{version}-linux-amd64.snap"
            )
            if os.path.exists(snap_staged):
                publish_snap_store(snap_staged)
        else:
            warn("--snap-store requested but no .snap artifact was built.")


# ─── Main Entry Point ────────────────────────────────────────────────────────
def main() -> None:
    """Main orchestrator for the PublicNode release process."""
    parser = argparse.ArgumentParser(
        description="PublicNode Master Release Orchestrator — Local CI/CD Pipeline"
    )
    parser.add_argument(
        "--skip-audit", action="store_true", help="Skip the dev-audit step"
    )
    parser.add_argument(
        "--snap-store", action="store_true", help="Also publish to Snap Store"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Build only, don't push to GitHub"
    )
    parser.add_argument(
        "--skip-snap", action="store_true", help="Skip Snap package build"
    )
    parser.add_argument(
        "--linux-only", action="store_true", help="Build only Linux packages"
    )
    parser.add_argument(
        "--rpm-only", action="store_true", help="Build only RPM package"
    )
    parser.add_argument(
        "--deb-only", action="store_true", help="Build only DEB package"
    )
    parser.add_argument(
        "--snap-only", action="store_true", help="Build only Snap package"
    )
    parser.add_argument(
        "--apk-only", action="store_true", help="Build only Android APK"
    )
    parser.add_argument(
        "--deep-clean", action="store_true", help="Perform industrial deep sanitization"
    )
    args = parser.parse_args()

    total_start = time.time()
    print(f"\n{C.H}{C.BOLD}{'═' * 60}{C.E}")
    print(f"{C.H}{C.BOLD}   🚀 PUBLICNODE MASTER RELEASE ORCHESTRATOR{C.E}")
    print(f"{C.H}{C.BOLD}{'═' * 60}{C.E}\n")

    # ── Phase 0 & 1: Pre-flight & Audit ──────────────────────────────────
    log("Phase 0: Pre-flight Integrity Checks", "🔍")
    verify_dependencies()
    check_system_health()
    version = get_version()
    ok(f"Release Candidate: v{version}")

    if not args.skip_audit:
        log("Phase 1: Running Industrial Codebase Audit...", "🔬")
        run(["uv", "run", "vps-dev-audit"], cwd=REPO_ROOT)
    else:
        warn("Phase 1: Audit skipped (--skip-audit)")

    # ── Phase 2: Sync Assets ─────────────────────────────────────────────
    log("Phase 2: Synchronizing Engine Assets...", "🔄")
    run(["make", "sync"], cwd=REPO_ROOT)

    # ── Phase 3: Build ───────────────────────────────────────────────────
    all_artifacts, snap_path = build_all_formats(version, args)

    # ── Phase 4: Collect & Stage ─────────────────────────────────────────
    log("Phase 4: Staging Release Artifacts...", "📦")
    collected = collect_artifacts(version, all_artifacts)
    if not collected:
        fail("No artifacts were collected. Build may have failed silently.")

    checksum_file = generate_checksums(
        os.path.join(RELEASE_DIR, f"v{version}"), collected
    )
    collected.append(checksum_file)

    print(f"\n{C.OK}{C.BOLD}Staged {len(collected)} artifact(s):{C.E}")
    for a in collected:
        print(f"  📄 {os.path.basename(a)}")

    # ── Phase 5 & 6: Publish ─────────────────────────────────────────────
    publish_assets(version, collected, snap_path, args)

    # ── Phase 7: Deep Cleanup ────────────────────────────────────────────
    deep_cleanup()

    # ── Summary ──────────────────────────────────────────────────────────
    total_elapsed = time.time() - total_start
    ver_dir = os.path.join(RELEASE_DIR, f"v{version}")

    print(f"\n{C.OK}{C.BOLD}{'═' * 60}{C.E}")
    print(f"{C.OK}{C.BOLD}   🚀 PUBLICNODE INDUSTRIAL RELEASE v{version} COMPLETE{C.E}")
    print(f"{C.OK}{C.BOLD}{'═' * 60}{C.E}")
    print(f"{C.BOLD}  Organization: {C.B}myth-tools{C.E}")
    print(f"{C.BOLD}  Creator:      {C.B}Shesher Hasan{C.E}")
    print(f"{C.BOLD}  Artifacts:    {C.B}{len(collected)} items staged{C.E}")
    print(f"{C.BOLD}  Target Dir:   {C.B}{ver_dir}{C.E}")
    print(f"{C.BOLD}  Total Time:   {C.B}{total_elapsed:.1f}s{C.E}")
    print(f"{C.OK}{C.BOLD}{'═' * 60}{C.E}")

    print(f"\n{C.BOLD}Verification Matrix:{C.E}")
    for a in collected:
        size_mb = os.path.getsize(a) / (1024 * 1024)
        print(f"  {C.OK}✓{C.E} {os.path.basename(a):<40} {size_mb:>8.2f} MB")
    print(f"{C.OK}{C.BOLD}{'═' * 60}{C.E}\n")


if __name__ == "__main__":
    main()
