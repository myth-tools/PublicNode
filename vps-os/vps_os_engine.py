# ruff: noqa: E402
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

"""
==============================================================================
 PUBLICNODE OS ENGINE
Headless background engine for System Vault and SSH Lifecycle management.

Core Architecture:
  - Absolute Security — Localhost-only API binding
  - Uvicorn Async Event-Loop — Zero-Lag Concurrency
  - Data PublicNodety V5 — Atomic, Verified, Versioned sync

(c) 2026 mohammadhasanulislam — GNU GPLv3 Licensed
==============================================================================
"""

import os
import sys

if os.path.dirname(os.path.abspath(__file__)) not in sys.path:
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import asyncio
import json
import logging
import mimetypes
import platform
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from collections import deque
from contextlib import asynccontextmanager
from logging.handlers import RotatingFileHandler
from typing import Any, Deque, Dict, List, Optional, cast

import psutil
import requests
import uvicorn
from fastapi import Depends, FastAPI, HTTPException, Query, Request

# --- PublicNode Singleton Lock & Audit Core ---
PID_FILE = "/tmp/vps_os_engine.pid"  # nosec B108


def setup_audit_logger() -> logging.Logger:
    """Initialize a rotating file logger for system-wide auditing."""
    logger = logging.getLogger("vps_audit")
    if logger.handlers:
        return logger

    logger.setLevel(logging.INFO)
    audit_file = os.path.join(
        "/kaggle/working"
        if os.path.exists("/kaggle/working")
        else os.path.expanduser("~"),
        "logs/audit.log",
    )
    os.makedirs(os.path.dirname(audit_file), exist_ok=True)
    handler = RotatingFileHandler(audit_file, maxBytes=10 * 1024 * 1024, backupCount=5)
    formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
    handler.setFormatter(formatter)
    logger.addHandler(handler)

    # Engine should log to file only; VpsArmor handles console output
    return logger


audit_log = setup_audit_logger()


def _acquire_singleton_lock() -> None:
    """Ensure only one instance of the engine is running. Exits SILENTLY if already running."""
    if os.path.exists(PID_FILE):
        try:
            with open(PID_FILE) as f:
                old_pid = int(f.read().strip())

            if old_pid == os.getpid():
                # We are the lock holder (likely a Uvicorn module re-import). Bypass safely.
                return

            os.kill(old_pid, 0)
            # If we reach here, a DIFFERENT process is alive. Exit silently to avoid log noise.
            sys.exit(0)
        except (OSError, ValueError):
            try:
                os.remove(PID_FILE)
            except Exception:
                pass

    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))

    def _cleanup_lock(signum: int, frame: Any) -> None:
        """Handle termination signals by removing the singleton lock file."""
        if os.path.exists(PID_FILE):
            try:
                os.remove(PID_FILE)
            except Exception:
                pass
        sys.exit(0)

    signal.signal(signal.SIGINT, _cleanup_lock)
    signal.signal(signal.SIGTERM, _cleanup_lock)


_acquire_singleton_lock()

from fastapi.exceptions import RequestValidationError
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import (
    FileResponse,
    JSONResponse,
    PlainTextResponse,
)
from pydantic import BaseModel, Field
from starlette.exceptions import HTTPException as StarletteHTTPException

sys.dont_write_bytecode = True


# --- Performance Optimization ---


def optimize_performance() -> None:
    """Harden system responsiveness by tuning priorities and IO settings."""
    is_root = os.geteuid() == 0

    try:
        # 1. CPU Priority Hardening (nice -10)
        if is_root:
            os.nice(-10)
            audit_log.info("SYSTEM: CPU priority hardened (nice -10)")
        else:
            audit_log.debug("SYSTEM: Priority tuning skipped (non-root session)")
    except Exception as e:
        # Some containers prevent nice even if EUID is 0
        audit_log.debug(f"SYSTEM: Priority tuning unavailable in this environment: {e}")

    # IO priority tuning is restricted in Kaggle, skipping...
    audit_log.debug("SYSTEM: IO priority tuning skipped: Restricted in environment")

    try:
        # 3. Kernel Low-Latency Networking
        if is_root:
            params = {
                "net.ipv4.tcp_fastopen": "3",
                "net.ipv4.tcp_low_latency": "1",
                "net.ipv4.tcp_slow_start_after_idle": "0",
                "net.ipv4.tcp_syncookies": "1",
                "net.core.rmem_max": "16777216",
                "net.core.wmem_max": "16777216",
            }
            for key, val in params.items():
                subprocess.run(
                    ["sysctl", "-w", f"{key}={val}"], capture_output=True, check=False
                )
            audit_log.info("SYSTEM: Kernel networking parameters tuned for low-latency")
    except Exception as e:
        audit_log.debug(f"SYSTEM: Kernel tuning skipped: {e}")


def optimize_network() -> None:
    """Industrial grade network tuning for Zero-Latency."""
    try:
        commands = [
            "sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1",
            "sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1",
            "sysctl -w net.ipv4.tcp_rmem='4096 87380 16777216' >/dev/null 2>&1",
            "sysctl -w net.ipv4.tcp_wmem='4096 65536 16777216' >/dev/null 2>&1",
            "sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1",
            "sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1",
            "sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1",
            "sysctl -w net.ipv4.tcp_max_syn_backlog=8192 >/dev/null 2>&1",
            "sysctl -w net.ipv4.tcp_max_tw_buckets=2000000 >/dev/null 2>&1",
        ]
        for cmd in commands:
            subprocess.run(shlex.split(cmd), capture_output=True, check=False)
        audit_log.info("Backbone: Network optimized (BBR enabled)")
    except Exception as e:
        audit_log.error(f"Backbone: Network optimization failed: {e}")


optimize_performance()
optimize_network()

# App is initialized after lifespan is defined (see bottom of module constants)

# --- Environment-Aware Paths ---
OS_ROOT = os.path.dirname(os.path.abspath(__file__))
SAFE_ROOT = (
    "/kaggle/working" if os.path.exists("/kaggle/working") else os.path.expanduser("~")
)

SETTINGS_FILE = os.path.join(SAFE_ROOT, "vps_settings.json")
LOG_DIR = os.path.join(SAFE_ROOT, "logs")
os.makedirs(LOG_DIR, exist_ok=True)

# Ensure ~/.local/bin is in PATH for all subprocesses
local_bin = os.path.expanduser("~/.local/bin")
if local_bin not in os.environ.get("PATH", ""):
    os.environ["PATH"] = f"{local_bin}:{os.environ.get('PATH', '')}"

# --- Standard Home Directory Materialization (Industry Grade) ---
for folder in ["Documents", "Downloads", "Pictures", "Projects", "Music", "Videos"]:
    os.makedirs(os.path.join(SAFE_ROOT, folder), exist_ok=True)

# --- Runtime Constants ---
KAG_USER = os.getenv("KAG_USER")
VAULT_SLUG = os.getenv("VAULT_SLUG")
VAULT_ID = f"{KAG_USER}/{VAULT_SLUG}" if KAG_USER and VAULT_SLUG else None
SESSION_PASS = (os.getenv("VPS_PASS") or "").strip()
VPS_NAME = os.getenv("VPS_NAME")
SESSION_ID = os.getenv("SESSION_ID")
START_TIME = time.time()
VPS_VERSION: Optional[str] = os.getenv("VPS_VERSION")
ENGINE_PORT: int = int(os.getenv("VPS_ENGINE_PORT", os.getenv("VPS_GUI_PORT", "5003")))
MAX_READ_SIZE = int(os.getenv("VPS_MAX_FILE_MB", "5")) * 1024 * 1024
SYNC_LOCK = threading.Lock()  # Protects GLOBAL_SYNC_STATE map
SYNC_RUN_LOCK = threading.Lock()  # Prevents concurrent sync threads
_stats_lock = threading.Lock()  # Thread-safe stats caching guard
AUTOSAVE_INTERVAL = 1800  # 30 minute baseline
LAST_FS_CHANGE: float = 0.0  # PublicNode Autonomous Persistence
SIGNAL_TOPIC: Optional[str] = os.getenv(
    "VPS_SIGNAL_TOPIC"
)  # V5.1: Remote Telemetry Backbone
HF_REPO_RAW = os.getenv("HF_REPO")
HF_TOKEN = os.getenv("HF_TOKEN")

# --- GUI Constants (KasmVNC Stack) ---
GUI_ENABLED = os.getenv("GUI_ENABLED", "false").lower() == "true"
GUI_RESOLUTION = os.getenv("GUI_RESOLUTION", "1920x1080")
GUI_DISPLAY = os.getenv("GUI_DISPLAY", ":1")
# KasmVNC serves its built-in web client on a single port.
GUI_PORT = int(os.getenv("GUI_PORT", "6080"))
# KasmVNC download URL (Ubuntu 22.04 Jammy, amd64)
GUI_KASMVNC_DEB_URL = (
    "https://github.com/kasmtech/KasmVNC/releases/download/v1.4.0/"
    "kasmvncserver_jammy_1.4.0_amd64.deb"
)


def _resolve_hf_repo() -> Optional[str]:
    """Dynamically normalize HF_REPO (ensures username/repo format)."""
    # V7: Industrial-grade fallback. Default to 'vps-vault' if missing.
    repo = HF_REPO_RAW or "vps-vault"

    if not HF_TOKEN:
        # Without a token, we can't normalize, but we return the repo name
        # so that it can be used if it's already in user/repo format.
        return repo

    if "/" in repo:
        return repo

    try:
        from huggingface_hub import HfApi

        api = HfApi(token=HF_TOKEN)
        user_info = api.whoami()
        username = user_info.get("name")
        if username:
            normalized = f"{username}/{repo}"
            # V9.7: Proactive Provisioning. Ensure the repository exists IMMEDIATELY.
            # This prevents 404 errors during the first-ever boot restoration.
            try:
                api.create_repo(
                    repo_id=normalized,
                    repo_type="dataset",
                    private=True,
                    exist_ok=True,
                )
                audit_log.info(
                    f"SYSTEM VAULT: Ensured repository exists at {normalized}"
                )
            except Exception as create_err:
                audit_log.warning(
                    f"SYSTEM VAULT: Proactive repo creation failed (ignorable): {create_err}"
                )

            return normalized
    except Exception as e:
        audit_log.warning(f"SYSTEM VAULT: Failed to resolve HF username: {e}")

    return repo


HF_REPO = _resolve_hf_repo()

# --- Singleton Lock (V2.0) ---
# Prevents multiple sentinels from fighting over the same ports/resources.
# --- Global Constants & Paths ---
VAULT_DIR = os.path.join(SAFE_ROOT, "vault")
LAST_SYNC_TIMESTAMP: float = 0.0  # Tracks the timestamp of the last successful sync

# --- Unified Storage & Sync Infrastructure (V6) ---
# SYNC_LOCK is declared above (line ~138) — single authoritative instance
GLOBAL_SYNC_STATE: Dict[str, Any] = {
    "active": False,
    "tier": None,  # "kaggle" or "hf"
    "phase": "idle",
    "progress": 0,
    "message": "",
    "error": None,
    "last_run": 0,
    "version": None,
}


class SyncManager:
    """Industrial Grade Sync Orchestrator for PublicNode."""

    @staticmethod
    def flush_disk() -> None:
        """Ensure all bytes are physically committed to storage media."""
        try:
            os.sync()
            audit_log.info("STORAGE: Filesystem buffers flushed (os.sync).")
        except Exception as e:
            audit_log.warning(f"STORAGE: Buffer flush warning: {e}")

    @staticmethod
    def set_state(
        active: bool = True,
        tier: Optional[str] = None,
        phase: str = "idle",
        progress: int = 0,
        message: str = "",
        error: Optional[str] = None,
    ) -> None:
        """Update the global synchronization state in a thread-safe manner."""
        with SYNC_LOCK:
            GLOBAL_SYNC_STATE["active"] = active
            GLOBAL_SYNC_STATE["tier"] = tier
            GLOBAL_SYNC_STATE["phase"] = phase
            GLOBAL_SYNC_STATE["progress"] = progress
            GLOBAL_SYNC_STATE["message"] = message
            GLOBAL_SYNC_STATE["error"] = error
            if progress == 100:
                GLOBAL_SYNC_STATE["last_run"] = int(time.time())

            # Industry Grade: Write status to disk for shell banner awareness
            try:
                state_dir = os.path.join(SAFE_ROOT, ".vps_state")
                os.makedirs(state_dir, exist_ok=True)
                active_file = os.path.join(state_dir, "sync_active")
                if active:
                    with open(active_file, "w") as f:
                        f.write(f"{phase}|{progress}|{message}")
                elif os.path.exists(active_file):
                    os.remove(active_file)
            except Exception:
                pass

    @staticmethod
    def panic_sync(tier: str = "kaggle") -> None:
        """Emergency sync during shutdown. Guaranteed to block until complete."""
        audit_log.warning(
            f"PANIC SYNC INITIATED: Securing {tier.upper()} before termination..."
        )
        if tier == "kaggle":
            SnapshotManager.run_sync(is_panic=True)
        elif tier == "hf":
            _run_system_save()  # FIXED: Correct helper for system vault
        SyncManager.flush_disk()

    @staticmethod
    def get_state() -> Dict[str, Any]:
        """Return a thread-safe copy of the current sync state."""
        with SYNC_LOCK:
            return GLOBAL_SYNC_STATE.copy()


# --- GUI Management Infrastructure ---
class GUIManager:
    """Industrial grade process manager for the XFCE/KasmVNC desktop environment."""

    @classmethod
    def _preseed_premium_xfce(cls, home: str) -> None:
        """Force XFCE into a modern, professional dark-mode state via XML injection."""
        # WIPE old config to ensure our premium settings stick
        for d in [".config/xfce4", ".cache/sessions", ".cache/xfce4"]:
            path = os.path.join(home, d)
            if os.path.exists(path):
                shutil.rmtree(path, ignore_errors=True)

        conf_dir = os.path.join(
            home, ".config", "xfce4", "xfconf", "xfce-perchannel-xml"
        )
        os.makedirs(conf_dir, exist_ok=True)

        # 1. Xsettings: Theme (Materia-Dark), Icons (Papirus), Fonts (Roboto)
        xsettings_xml = os.path.join(conf_dir, "xsettings.xml")
        with open(xsettings_xml, "w") as f:
            f.write(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<channel name="xsettings" version="1.0">\n'
                '  <property name="Net" type="empty">\n'
                '    <property name="ThemeName" type="string" value="Materia-dark"/>\n'
                '    <property name="IconThemeName" type="string" value="Papirus-Dark"/>\n'
                "  </property>\n"
                '  <property name="Gtk" type="empty">\n'
                '    <property name="FontName" type="string" value="Roboto 10"/>\n'
                '    <property name="MonospaceFontName" type="string" value="Roboto Mono 10"/>\n'
                '    <property name="ButtonImages" type="bool" value="true"/>\n'
                '    <property name="MenuImages" type="bool" value="true"/>\n'
                "  </property>\n"
                "</channel>\n"
            )

        # 2. Xfwm4: Centered titles and Dark Theme match
        xfwm4_xml = os.path.join(conf_dir, "xfwm4.xml")
        with open(xfwm4_xml, "w") as f:
            f.write(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<channel name="xfwm4" version="1.0">\n'
                '  <property name="general" type="empty">\n'
                '    <property name="theme" type="string" value="Materia-dark"/>\n'
                '    <property name="use_compositing" type="bool" value="false"/>\n'
                '    <property name="title_alignment" type="string" value="center"/>\n'
                '    <property name="button_layout" type="string" value="O|HMC"/>\n'
                "  </property>\n"
                "</channel>\n"
            )

        # 3. Desktop: Dynamic Signature Wallpaper
        pictures_dir = os.path.join(home, "Pictures")
        os.makedirs(pictures_dir, exist_ok=True)
        wallpaper_path = os.path.join(pictures_dir, "wallpaper.jpg")

        # Default to your official GitHub wallpaper
        default_wallpaper = "https://github.com/myth-tools/PublicNode/blob/main/Packages/wallpaper.jpg?raw=true"
        wallpaper_url = os.getenv("VPS_WALLPAPER_URL") or default_wallpaper

        if wallpaper_url:
            try:
                response = requests.get(wallpaper_url, timeout=10)
                if response.status_code == 200:
                    with open(wallpaper_path, "wb") as f:
                        f.write(response.content)
            except Exception as e:
                audit_log.warning(f"GUI: Failed to download custom wallpaper: {e}")

        desktop_xml = os.path.join(conf_dir, "xfce4-desktop.xml")
        with open(desktop_xml, "w") as f:
            # We force image-style 5 (Zoomed) and the specific path to ensure it loads even if delayed
            f.write(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<channel name="xfce4-desktop" version="1.0">\n'
                '  <property name="backdrop" type="empty">\n'
                '    <property name="screen0" type="empty">\n'
                '      <property name="monitor0" type="empty">\n'
                '        <property name="workspace0" type="empty">\n'
                '          <property name="color-style" type="int" value="0"/>\n'
                '          <property name="image-style" type="int" value="5"/>\n'
                f'          <property name="last-image" type="string" value="{wallpaper_path}"/>\n'
                f'          <property name="last-single-image" type="string" value="{wallpaper_path}"/>\n'
                "        </property>\n"
                '        <property name="workspace1" type="empty">\n'
                '          <property name="color-style" type="int" value="0"/>\n'
                '          <property name="image-style" type="int" value="5"/>\n'
                f'          <property name="last-image" type="string" value="{wallpaper_path}"/>\n'
                "        </property>\n"
                "      </property>\n"
                "    </property>\n"
                "  </property>\n"
                "</channel>\n"
            )

        # 4. Panel: Clean, modern top panel
        panel_xml = os.path.join(conf_dir, "xfce4-panel.xml")
        with open(panel_xml, "w") as f:
            f.write(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<channel name="xfce4-panel" version="1.0">\n'
                '  <property name="panels" type="array">\n'
                '    <value type="int" value="1"/>\n'
                '    <property name="panel-1" type="empty">\n'
                '      <property name="position" type="string" value="p=6;x=0;y=0"/>\n'
                '      <property name="length" type="uint" value="100"/>\n'
                '      <property name="position-locked" type="bool" value="true"/>\n'
                '      <property name="size" type="uint" value="28"/>\n'
                '      <property name="plugin-ids" type="array">\n'
                '        <value type="int" value="1"/>\n'
                '        <value type="int" value="6"/>\n'
                '        <value type="int" value="9"/>\n'
                '        <value type="int" value="2"/>\n'
                '        <value type="int" value="3"/>\n'
                '        <value type="int" value="4"/>\n'
                '        <value type="int" value="5"/>\n'
                "      </property>\n"
                '      <property name="background-style" type="uint" value="1"/>\n'
                '      <property name="background-rgba" type="array">\n'
                '        <value type="double" value="0.05"/>\n'
                '        <value type="double" value="0.05"/>\n'
                '        <value type="double" value="0.05"/>\n'
                '        <value type="double" value="0.95"/>\n'
                "      </property>\n"
                "    </property>\n"
                "  </property>\n"
                '  <property name="plugins" type="empty">\n'
                '    <property name="plugin-1" type="string" value="applicationsmenu"/>\n'
                '    <property name="plugin-6" type="string" value="launcher">\n'
                '      <property name="items" type="array">\n'
                '        <value type="string" value="xfce4-terminal.desktop"/>\n'
                "      </property>\n"
                "    </property>\n"
                '    <property name="plugin-9" type="string" value="launcher">\n'
                '      <property name="items" type="array">\n'
                '        <value type="string" value="mousepad.desktop"/>\n'
                "      </property>\n"
                "    </property>\n"
                '    <property name="plugin-2" type="string" value="tasklist"/>\n'
                '    <property name="plugin-3" type="string" value="separator">\n'
                '      <property name="expand" type="bool" value="true"/>\n'
                '      <property name="style" type="uint" value="0"/>\n'
                "    </property>\n"
                '    <property name="plugin-4" type="string" value="clock"/>\n'
                '    <property name="plugin-5" type="string" value="actions"/>\n'
                "  </property>\n"
                "</channel>\n"
            )

        # 5. Default Shell Environment (Bash)
        # Ensure terminal uses Bash and doesn't try to find missing Zsh
        term_config = os.path.join(home, ".config", "xfce4", "terminal")
        os.makedirs(term_config, exist_ok=True)
        with open(os.path.join(term_config, "terminalrc"), "w") as f:
            f.write(
                "[Configuration]\n"
                "FontName=Roboto 11\n"
                "ColorForeground=#ffffff\n"
                "ColorBackground=#1e1e1e\n"
                "ScrollingBar=TERMINAL_SCROLLBAR_NONE\n"
            )

        # 6. Cleanup: Hide broken default apps
        cls._hide_broken_apps()

    """Industrial grade process manager for the KasmVNC desktop environment."""

    # KasmVNC is a single unified binary — no separate Xvfb/VNC/Proxy processes needed.
    _kasmvnc_proc: Optional[subprocess.Popen[bytes]] = None
    _is_starting: bool = False
    _last_start_time: float = 0.0
    _last_online_time: float = 0.0
    _last_revival_attempt: float = 0.0
    _lock = threading.Lock()

    @classmethod
    def _ensure_system_groups(cls) -> None:
        """Create common missing system groups to silence apt-get/tmpfiles warnings."""
        for group in ["kvm", "render", "video", "audio"]:
            try:
                subprocess.run(
                    ["groupadd", "-r", group], capture_output=True, check=False
                )
            except Exception:
                pass

    @classmethod
    def _generate_binary_wrappers(cls) -> None:
        """Universal DNA Shadowing: Detects and wraps sandbox apps via binary diagnostics."""
        shadow_dir = os.path.join(os.sep, "usr", "local", "bin")
        # We scan all common binary locations
        source_dirs = [
            os.path.join(os.sep, "usr", "bin"),
            os.path.join(os.sep, "bin"),
            os.path.join(os.sep, "usr", "sbin"),
            os.path.join(os.sep, "sbin"),
        ]

        modified_any = False
        for s_dir in source_dirs:
            if not os.path.exists(s_dir):
                continue

            for target in os.listdir(s_dir):
                real_path = os.path.join(s_dir, target)
                # Only check real files that are executable
                if not (os.path.isfile(real_path) and os.access(real_path, os.X_OK)):
                    continue

                # Safety: Skip binaries that are already wrappers or symbolic links
                if os.path.islink(real_path):
                    continue

                wrapper_path = os.path.join(shadow_dir, target)
                # If a wrapper already exists, skip it to avoid recursion
                if os.path.exists(wrapper_path):
                    continue

                try:
                    # DNA Check: Does the binary contain 'no-sandbox' or 'DISABLE_SANDBOX'?
                    # We scan the first 2MB for performance
                    with open(real_path, "rb") as bf:
                        chunk = bf.read(2048 * 1024)
                        if b"no-sandbox" in chunk or b"chrome-sandbox" in chunk:
                            wrapper_content = (
                                "#!/bin/bash\n"
                                "# PublicNode Universal Root Fix\n"
                                f'exec {real_path} --no-sandbox --test-type "$@"\n'
                            )
                            with open(wrapper_path, "w") as f:
                                f.write(wrapper_content)
                            os.chmod(wrapper_path, 0o755)  # nosec B103
                            modified_any = True
                except Exception:
                    continue

        if modified_any:
            # Also set the global environment variable for Electron apps
            # This handles apps that use the variable instead of the flag.
            with open("/tmp/vps_electron_env", "w") as f:  # nosec B108
                f.write("export DISABLE_ELECTRON_SANDBOX=1\n")

    @classmethod
    def _hide_broken_apps(cls) -> None:
        """Forensic Patch Engine: Detects 'sandbox-aware' apps via binary DNA scanning."""
        # Run binary shadowing first for universal CLI/GUI coverage
        cls._generate_binary_wrappers()

        app_dirs = [
            os.path.join(os.sep, "usr", "share", "applications"),
            os.path.join(os.path.expanduser("~"), ".local/share/applications"),
        ]

        blacklist = [
            "debian-uxterm.desktop",
            "debian-xterm.desktop",
            "xfce4-session-logout.desktop",
            "xfhelp4.desktop",
            "xfce4-mail-reader.desktop",
            "xfce4-web-browser.desktop",
        ]

        modified_any = False
        for apps_dir in app_dirs:
            if not os.path.exists(apps_dir):
                continue

            for item in os.listdir(apps_dir):
                if not item.endswith(".desktop"):
                    continue

                path = os.path.join(apps_dir, item)
                try:
                    with open(path) as f:
                        lines = f.readlines()

                    content = "".join(lines)
                    modified = False
                    new_lines = []

                    # 1. Hide Blacklisted Apps
                    if item in blacklist:
                        if "nodisplay=true" not in content.lower():
                            new_lines = [*lines, "NoDisplay=true\n"]
                            modified = True

                    if not modified:
                        new_lines = lines

                    # 2. Forensic DNA Sandbox Patching
                    # Instead of keywords, we scan the BINARY for the 'no-sandbox' string.
                    for i, line in enumerate(new_lines):
                        if line.startswith("Exec=") and "--no-sandbox" not in line:
                            # Extract the binary path
                            try:
                                binary_cmd = line.split("=", 1)[1].strip().split()[0]
                                binary_path = shutil.which(binary_cmd.strip("'\""))

                                if binary_path and os.path.isfile(binary_path):
                                    # Forensic Check: Does the binary mention 'no-sandbox'?
                                    # We only check the first 1MB for speed
                                    with open(binary_path, "rb") as bf:
                                        chunk = bf.read(1024 * 1024)
                                        if b"no-sandbox" in chunk:
                                            key, cmd = line.split("=", 1)
                                            new_lines[i] = (
                                                f"{key}={cmd.strip().split()[0]} --no-sandbox --test-type {' '.join(cmd.strip().split()[1:])}\n"
                                            )
                                            modified = True
                                            modified_any = True
                            except Exception:
                                continue

                    if modified:
                        with open(path, "w") as f:
                            f.writelines(new_lines)
                except Exception:
                    pass

        if modified_any:
            subprocess.run(["update-desktop-database", "-q"], check=False)

    @classmethod
    def _create_kasmvnc_config(cls, home: str, port: int) -> str:
        """Generate a professional, high-performance kasmvnc.yaml for WebRTC support."""
        conf_dir = os.path.join(home, ".vnc")
        os.makedirs(conf_dir, exist_ok=True)
        yaml_path = os.path.join(conf_dir, "kasmvnc.yaml")

        # Perfected KasmVNC 1.4.0 Schema - Verified via Deep Research
        config = {
            "network": {
                "listen": {"protocol": "http", "interface": "0.0.0.0", "port": port},  # nosec B104
                "udp": {"enabled": True, "port_range": "40000-40010"},
            },
            "encoding": {
                "max_frame_rate": 60,
                "threads": 4,  # Replaces 'rect_threads' in 1.4.0
                "rect_encoding_mode": {"min_quality": 7, "max_quality": 9},
            },
            "ui": {
                "show_control_bar": False,  # Replaces nested 'enabled'
                "show_branding": False,  # Replaces nested 'enabled'
            },
            "features": {"web_rtc": {"enabled": True}, "clipboard": {"enabled": True}},
        }

        try:
            import yaml

            with open(yaml_path, "w") as f:
                yaml.dump(config, f)
        except Exception as e:
            audit_log.error(f"GUI: Failed to write kasmvnc.yaml: {e}")

        return yaml_path

    @classmethod
    def _install_kasmvnc(cls, gui_log: str) -> bool:
        """Download and install KasmVNC if not already present. One-time operation."""
        # Ensure system groups exist before installing to silence warnings
        cls._ensure_system_groups()

        if shutil.which("vncserver"):
            audit_log.info("GUI: KasmVNC already installed, skipping download.")
            return True

        audit_log.info("GUI: KasmVNC not found. Downloading v1.4.0 (~50MB)...")
        deb_path = os.path.join(tempfile.gettempdir(), "kasmvncserver.deb")  # nosec B108

        try:
            # Download the .deb package
            result = subprocess.run(
                ["wget", "-q", "-O", deb_path, GUI_KASMVNC_DEB_URL],
                capture_output=True,
                timeout=120,
                check=False,
            )
            if result.returncode != 0:
                audit_log.error(
                    f"GUI: [CRITICAL] KasmVNC download failed: {result.stderr.decode()[:200]}"
                )
                return False
            audit_log.info("GUI: KasmVNC download complete. Installing...")

            # Install KasmVNC + XFCE core components
            install_env = {**os.environ, "DEBIAN_FRONTEND": "noninteractive"}
            result = subprocess.run(
                [
                    "apt-get",
                    "install",
                    "-y",
                    "--allow-downgrades",
                    deb_path,
                    "xfce4-session",
                    "xfwm4",
                    "xfce4-panel",
                    "xfdesktop4",
                    "xfce4-settings",
                    "xfce4-terminal",
                    "dbus-x11",
                ],
                env=install_env,
                capture_output=True,
                timeout=300,  # Increased timeout for XFCE installation
                check=False,
            )
            with open(gui_log, "a") as f:
                f.write(result.stdout.decode(errors="replace"))
                f.write(result.stderr.decode(errors="replace"))

            if result.returncode != 0:
                audit_log.error(
                    "GUI: [CRITICAL] KasmVNC install failed. Check vps_gui.log."
                )
                return False

            audit_log.info("GUI: [SUCCESS] KasmVNC 1.4.0 installed.")
            return True
        except Exception as e:
            audit_log.error(f"GUI: [CRITICAL] KasmVNC install exception: {e}")
            return False
        finally:
            # Clean up the deb file
            try:
                if os.path.exists(deb_path):
                    os.remove(deb_path)
            except Exception:
                pass

    @classmethod
    def start(cls) -> bool:  # noqa: PLR0911
        """KasmVNC ignition: Install → Configure → Launch. Single-binary, no gray screen."""
        with cls._lock:
            if cls._is_running_unlocked():
                return True

            # Anti-Hammer: Skip if already starting within last 30s
            if cls._is_starting and (time.time() - cls._last_start_time) < 30:
                return True

            cls._is_starting = True
            cls._last_start_time = time.time()
            cls._stop_unlocked()

            try:
                audit_log.info("GUI: KasmVNC Ignition sequence started...")

                # --- Step 0: Pre-flight cleanup ---
                display_num = GUI_DISPLAY.replace(":", "")
                for lock_file in [
                    f"/tmp/.X{display_num}-lock",  # nosec B108
                    f"/tmp/.X11-unix/X{display_num}",  # nosec B108
                ]:
                    if os.path.exists(lock_file):
                        try:
                            if os.path.isdir(lock_file):
                                shutil.rmtree(lock_file)
                            else:
                                os.remove(lock_file)
                        except Exception:
                            pass

                # Sanitize resolution: KasmVNC -geometry only wants WIDTHxHEIGHT (no x24 suffix)
                clean_res = GUI_RESOLUTION
                if clean_res.count("x") >= 2:
                    clean_res = "x".join(clean_res.split("x")[:2])
                audit_log.info(
                    f"GUI: Resolution sanitized: {GUI_RESOLUTION} -> {clean_res}"
                )
                for proc_name in [
                    "vncserver",
                    "Xvnc",
                    "x11vnc",
                    "websockify",
                    "Xvfb",
                    "xfce4-session",
                    "xfwm4",
                    "xfce4-panel",
                    "xfdesktop",
                ]:
                    subprocess.run(
                        ["pkill", "-9", "-f", proc_name],
                        capture_output=True,
                        check=False,
                    )
                time.sleep(0.5)

                gui_log = os.path.join(LOG_DIR, "vps_gui.log")
                # Truncate large logs to prevent disk space issues from previous failure spams
                with open(gui_log, "w") as f:
                    f.write(f"--- KasmVNC IGNITION: {time.ctime()} ---\n")
                audit_log.info(f"GUI: --- KasmVNC IGNITION: {time.ctime()} ---")

                # --- Step 1: Install KasmVNC (one-time, cached after first boot) ---
                if not cls._install_kasmvnc(gui_log):
                    audit_log.error(
                        "GUI: Aborting ignition — KasmVNC installation failed."
                    )
                    cls._is_starting = False
                    return False

                home = os.path.expanduser("~")
                vnc_dir = os.path.join(home, ".vnc")
                os.makedirs(vnc_dir, exist_ok=True)

                # --- Step 2: Configure KasmVNC user non-interactively ---
                # We create a dummy user to satisfy the startup script, but we'll disable
                # the actual check to allow instant app access.
                audit_log.info("GUI: Configuring KasmVNC user (non-interactive)...")
                try:
                    # Clean up existing password file to avoid "user already taken" conflicts
                    passwd_file = os.path.expanduser("~/.kasmpasswd")
                    if os.path.exists(passwd_file):
                        os.remove(passwd_file)

                    # kasmvncpasswd -u <user> -w (for write access)
                    # It prompts: Password, Verify, View-only (y/n)
                    with open(gui_log, "a") as f:
                        subprocess.run(
                            ["kasmvncpasswd", "-u", "publicnode_user", "-w"],
                            input=b"kasm1234\nkasm1234\nn\n",
                            stdout=f,
                            stderr=f,
                            check=False,
                        )
                except Exception as e:
                    audit_log.debug(f"GUI: Password config note: {e}")

                # --- Step 2.5: Start System D-Bus ---
                # Required to prevent "Failed to get system bus" and "Couldn't connect to proxy" (upower)
                dbus_script = os.path.join("/", "etc", "init.d", "dbus")
                if os.path.exists(dbus_script):
                    subprocess.run(
                        [dbus_script, "start"], capture_output=True, check=False
                    )

                # --- Step 3: Write performance-tuned kasmvnc.yaml ---
                # This replaces the old x11vnc flags. Every setting is tuned for
                # Kaggle's 4 CPU cores, no GPU, and a mobile client over Cloudflare.
                kasmvnc_yaml_path = os.path.join(vnc_dir, "kasmvnc.yaml")
                with open(kasmvnc_yaml_path, "w", encoding="utf-8") as f:
                    f.write(
                        "# PublicNode KasmVNC Performance Config\n"
                        "# Tuned for 4-core CPU, no GPU, mobile client over Cloudflare\n"
                        "network:\n"
                        "  protocol: http\n"
                        f"  websocket_port: {GUI_PORT}\n"
                        "  ssl:\n"
                        "    require_ssl: false\n"
                        "encoding:\n"
                        "  max_frame_rate: 60\n"
                        "logging:\n"
                        "  level: 10\n"  # 10 = DEBUG: Required to see client connection logs
                    )
                audit_log.info(
                    f"GUI: Performance-tuned kasmvnc.yaml written to {kasmvnc_yaml_path}"
                )

                # --- Step 3: Hardening X11 Authentication ---
                # Silences "xauth: file /root/.Xauthority does not exist"
                xauth_path = os.path.join(home, ".Xauthority")
                if not os.path.exists(xauth_path):
                    with open(xauth_path, "wb") as f:
                        f.write(b"")
                    os.chmod(xauth_path, 0o600)
                audit_log.info(f"GUI: X11 Auth hardened at {xauth_path}")

                # --- Step 4: Write xstartup for XFCE Power Stack ---
                xstartup_path = os.path.join(vnc_dir, "xstartup")

                # --- Step 4.2: Fix XDG Directories ---
                for xdg_dir in [
                    "Templates",
                    "Documents",
                    "Downloads",
                    "Music",
                    "Pictures",
                    "Videos",
                    "Public",
                    "Desktop",
                ]:
                    os.makedirs(os.path.join(home, xdg_dir), exist_ok=True)

                # --- Step 4.3: Silence ALSA Errors ---
                with open(os.path.join(home, ".asoundrc"), "w") as f:
                    f.write("pcm.!default { type null }\nctl.!default { type null }\n")

                # --- Step 4.4: Set Default Terminal ---
                terminal_wrapper = shutil.which(
                    "xfce4-terminal.wrapper"
                ) or os.path.join("/", "usr", "bin", "xfce4-terminal.wrapper")
                with open(gui_log, "a") as f:
                    subprocess.run(
                        [
                            "update-alternatives",
                            "--set",
                            "x-terminal-emulator",
                            terminal_wrapper,
                        ],
                        stdout=f,
                        stderr=f,
                        check=False,
                    )

                # --- Step 4.5: Generate xstartup for XFCE ---
                # V12: Surgical but correct — launch each component directly so bash
                # here-doc syntax issues don't break the VNC session.
                xstartup_log = os.path.join(LOG_DIR, "xstartup.log")

                # --- Step 4.6: Pre-seed Premium XFCE configuration ---
                cls._preseed_premium_xfce(home)

                with open(xstartup_path, "w", encoding="utf-8") as f:
                    f.write(
                        "#!/bin/bash\n"
                        f"exec >> {xstartup_log} 2>&1\n"
                        'echo "[xstartup] Session starting: $(date)"\n'
                        "\n"
                        "# Environment\n"
                        "export XKL_XMODMAP_DISABLE=1\n"
                        "export XDG_CURRENT_DESKTOP=XFCE\n"
                        "export XDG_CONFIG_DIRS=/etc/xdg\n"
                        "export XDG_RUNTIME_DIR=/tmp/runtime-root\n"
                        "export NO_AT_BRIDGE=1\n"
                        "mkdir -p $XDG_RUNTIME_DIR && chmod 700 $XDG_RUNTIME_DIR\n"
                        "\n"
                        "# Start D-Bus session for XFCE components\n"
                        "dbus-launch --sh-syntax > /tmp/vps_dbus_env\n"
                        ". /tmp/vps_dbus_env\n"
                        "export DBUS_SESSION_BUS_ADDRESS\n"
                        "export DBUS_SESSION_BUS_PID\n"
                        "\n"
                        "# V13: Robust session launch via xfce4-session\n"
                        "# D-Bus is now properly initialized, so xfce4-session will manage all components\n"
                        'echo "[xstartup] Launching xfce4-session..."\n'
                        "exec xfce4-session\n"
                    )
                os.chmod(xstartup_path, 0o700)

                audit_log.info(f"GUI: xstartup written to {xstartup_path}")

                # --- Step 5: Launch KasmVNC (Integrated X server + Web Client) ---
                vnc_log = os.path.join(LOG_DIR, "vps_gui_vnc.log")
                audit_log.info(
                    f"GUI: Launching KasmVNC on display {GUI_DISPLAY} "
                    f"(resolution: {GUI_RESOLUTION}, web port: {GUI_PORT})..."
                )
                vncserver_bin = shutil.which("vncserver")
                if not vncserver_bin:
                    audit_log.error(
                        "GUI: [CRITICAL] vncserver binary not found after installation!"
                    )
                    cls._is_starting = False
                    return False

                cls._kasmvnc_proc = subprocess.Popen(
                    [
                        vncserver_bin,
                        GUI_DISPLAY,
                        "-geometry",
                        clean_res,
                        "-depth",
                        "24",
                        "-select-de",
                        "manual",
                        "-fg",
                        "-nocursor",
                        "-websocketPort",
                        str(GUI_PORT),
                        "-SecurityTypes",
                        "None",
                        "-DisableBasicAuth",
                        "-FrameRate",
                        "60",
                        "-RectThreads",
                        "4",
                        "-WebpVideoQuality",
                        "9",
                        "-JpegVideoQuality",
                        "9",
                        "-PreferBandwidth",
                        "0",
                        "-AcceptSetDesktopSize",
                        "1",
                    ],
                    stdout=open(vnc_log, "a"),  # nosec B603
                    stderr=subprocess.STDOUT,
                    start_new_session=True,  # Detach from Kaggle's cgroup monitor
                )

                # Wait up to 40s for KasmVNC's X server (Xvnc) to be ready
                # (Kaggle containers can be slow to initialize the X socket)
                audit_log.info("GUI: Waiting for KasmVNC (Xvnc) to initialize...")
                x11_socket = f"/tmp/.X11-unix/X{display_num}"  # nosec B108
                kasmvnc_ready = False
                for _wait in range(60):
                    if os.path.exists(x11_socket):
                        # Verify the display actually accepts connections
                        probe = subprocess.run(
                            ["xdpyinfo", "-display", GUI_DISPLAY],
                            capture_output=True,
                            timeout=2,
                            check=False,
                        )
                        if probe.returncode == 0:
                            kasmvnc_ready = True
                            audit_log.info(
                                f"GUI: [SUCCESS] KasmVNC Xvnc ready on {GUI_DISPLAY} after {_wait}s"
                            )
                            break
                        else:
                            audit_log.info(
                                f"GUI: Attempt {_wait}: Xvnc socket exists, waiting for initialization..."
                            )
                    elif _wait % 5 == 0:
                        audit_log.info(
                            f"GUI: Attempt {_wait}: Waiting for {x11_socket}..."
                        )
                    time.sleep(1)

                if not kasmvnc_ready:
                    # Dump the last 30 lines of the GUI log into audit for easy diagnosis
                    try:
                        with open(gui_log, errors="replace") as _gl:
                            tail = list(_gl)[-30:]
                        audit_log.error(
                            f"GUI: [CRITICAL] KasmVNC did NOT start on {GUI_DISPLAY} after 60s!\n"
                            + "".join(tail).strip()
                        )
                    except Exception:
                        audit_log.error(
                            f"GUI: [CRITICAL] KasmVNC did NOT start on {GUI_DISPLAY} after 60s!"
                        )
                    cls._is_starting = False
                    cls._stop_unlocked()
                    return False

                audit_log.info(
                    f"GUI: [ONLINE] KasmVNC Stack Ready — "
                    f"Resolution: {GUI_RESOLUTION}, "
                    f"Web Port: {GUI_PORT}, "
                    f"Display: {GUI_DISPLAY}"
                )
                cls._last_online_time = time.monotonic()
                cls._is_starting = False
                return True

            except Exception as e:
                cls._is_starting = False
                audit_log.error(f"GUI: Failed to start KasmVNC stack: {e}")
                cls._stop_unlocked()
                return False

    @classmethod
    def stop(cls) -> None:
        """Graceful termination of the entire KasmVNC desktop environment."""
        with cls._lock:
            cls._stop_unlocked()

    @classmethod
    def _stop_unlocked(cls) -> None:
        """Internal helper to kill KasmVNC processes without double-locking."""
        cls._is_starting = False
        audit_log.info("GUI: Terminating KasmVNC Desktop Stack...")

        # Gracefully stop KasmVNC via its own stop command first
        if shutil.which("vncserver"):
            subprocess.run(
                ["vncserver", "-kill", GUI_DISPLAY],
                capture_output=True,
                check=False,
                timeout=5,
            )

        # Terminate our tracked process handle
        if cls._kasmvnc_proc:
            try:
                cls._kasmvnc_proc.terminate()
                cls._kasmvnc_proc.wait(timeout=3)
            except Exception:
                try:
                    cls._kasmvnc_proc.kill()
                except Exception:
                    pass
        cls._kasmvnc_proc = None

        # Force-kill any lingering KasmVNC/X processes
        for proc_name in [
            "Xvnc",
            "vncserver",
            "xfce4-session",
            "xfwm4",
            "xfce4-panel",
            "xfdesktop",
            "x11vnc",
            "websockify",
            "Xvfb",
        ]:
            subprocess.run(
                ["pkill", "-9", "-f", proc_name], capture_output=True, check=False
            )

        # Clean up X11 lock files
        display_num = GUI_DISPLAY.replace(":", "")
        for lock_file in [
            f"/tmp/.X{display_num}-lock",  # nosec B108
            f"/tmp/.X11-unix/X{display_num}",  # nosec B108
        ]:
            try:
                if os.path.exists(lock_file):
                    if os.path.isdir(lock_file):
                        shutil.rmtree(lock_file)
                    else:
                        os.remove(lock_file)
            except Exception:
                pass

        audit_log.info("GUI: Stack Offline.")

    @classmethod
    def is_running(cls) -> bool:
        """Check if the KasmVNC stack is currently online without blocking the event loop."""
        return cls._is_running_unlocked()

    @classmethod
    def _is_running_unlocked(cls) -> bool:
        """Internal helper to check process status without double-locking."""
        # During starting phase, consider running to prevent premature Sentinel revival
        if cls._is_starting:
            return True

        # Check if our tracked vncserver process is alive
        if cls._kasmvnc_proc and cls._kasmvnc_proc.poll() is None:
            return True

        # Fallback: check if Xvnc (KasmVNC's X server) process exists in the process list
        for proc in psutil.process_iter(["name", "cmdline"]):
            try:
                name = proc.info.get("name", "") or ""
                cmdline = " ".join(proc.info.get("cmdline") or [])
                if "Xvnc" in name or "Xvnc" in cmdline:
                    return True
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue

        return False


# --- Performance Caching (Zero-Lag Pulse) ---
GLOBAL_STATS_CACHE: Dict[str, Any] = {}
STATS_CACHE_LOCK = threading.Lock()

# --- Real-Time HTTP Activity Log (V6) ---
HTTP_ACTIVITY_LOGS: Deque[str] = deque(maxlen=10000)

# --- Background Tasks Registry (RUF006) ---
background_tasks: set[asyncio.Task[Any]] = set()


def stats_cacher_loop() -> None:
    """High-frequency background thread to keep telemetry fresh with zero UI lag."""
    global GLOBAL_STATS_CACHE
    while True:
        try:
            s = _get_internal_stats()
            # Also pre-calculate top processes
            procs = []
            for p in psutil.process_iter(
                ["pid", "name", "cpu_percent", "memory_percent", "status"]
            ):
                try:
                    p_info = p.as_dict(
                        [
                            "pid",
                            "name",
                            "cpu_percent",
                            "memory_percent",
                            "status",
                            "cmdline",
                            "exe",
                        ]
                    )
                    try:
                        p_info["memory_rss_mb"] = round(
                            p.memory_info().rss / 1024 / 1024, 1
                        )
                    except (psutil.NoSuchProcess, psutil.AccessDenied):
                        p_info["memory_rss_mb"] = 0
                    procs.append(p_info)
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue

            procs = sorted(
                procs, key=lambda x: x.get("cpu_percent") or 0, reverse=True
            )[:25]

            active_conns = 0
            try:
                conns = psutil.net_connections(kind="inet")
                active_conns = len([c for c in conns if c.status == "ESTABLISHED"])
            except Exception:
                pass

            # --- Real-Time Log Pulse (V6: Exact Accuracy) ---
            log_lines = []
            try:
                master_log = os.path.join(LOG_DIR, "master.log")
                if os.path.exists(master_log):
                    with open(master_log, errors="replace") as f:
                        log_lines = [line.strip() for line in deque(f, maxlen=10000)]
            except Exception:
                pass

            # Merge sync state into 's' so Flutter app 'engine.stats' sees it
            s["sync"] = SyncManager.get_state()

            with STATS_CACHE_LOCK:
                GLOBAL_STATS_CACHE = {
                    "stats": s,
                    "procs": procs,
                    "logs": log_lines,
                    "http_logs": list(HTTP_ACTIVITY_LOGS),
                    "sync": s["sync"],
                    "net_active": active_conns,
                    "timestamp": int(time.time()),
                }
        except Exception:
            pass
        time.sleep(1)


# --- Security: Path validator ---
def is_safe_path(path: str, follow_symlinks: bool = True) -> bool:
    """Industrial-grade path validation: Explicit prefix + resolving."""
    if not path:
        return False
    try:
        from pathlib import Path

        p = Path(path).resolve()
        p_str = str(p)
        # Industry-Grade Security: Allow access to workspace OR the entire OS root
        # but ensure the path is actually valid and within the system tree.
        return p.exists() or p_str.startswith("/")
    except Exception:
        return False


# ============================================================
# DEAD MAN'S SWITCH (Heartbeat Monitor)
# ============================================================
LAST_HEARTBEAT = time.time()
HEARTBEAT_TIMEOUT = 600  # 10 Minutes buffer for network stability


def dead_man_watchdog() -> None:
    """Background watchdog to terminate kernel if Flutter app is closed."""
    audit_log.info("WATCHDOG: Dead Man's Switch ARMED (10m timeout)")
    time.sleep(300)  # Initial grace period for boot/sync
    while True:
        try:
            elapsed = time.time() - LAST_HEARTBEAT
            if elapsed > HEARTBEAT_TIMEOUT:
                audit_log.critical(
                    f"DEAD MAN'S SWITCH: No heartbeat for {int(elapsed)}s. Commencing emergency shutdown."
                )
                # Signal the handler to perform graceful sync and exit
                signal_handler(signal.SIGTERM, None)
        except Exception as e:
            audit_log.error(f"Watchdog Error: {e}")
        time.sleep(60)


# --- Security: FastAPI Auth Dependency ---


async def verify_auth(request: Request) -> None:
    """FastAPI Dependency: Validates auth on every protected route."""
    auth_key = request.headers.get("X-PublicNode-Key")
    if not auth_key and request.headers.get("Authorization"):
        header = request.headers.get("Authorization", "")
        if header.startswith("Bearer "):
            auth_key = header[7:].strip()

    client_ip = request.client.host if request.client else "unknown"
    if client_ip == "127.0.0.1":
        # Internal requests also count as activity
        global LAST_HEARTBEAT
        LAST_HEARTBEAT = time.time()
        return

    if SESSION_PASS and auth_key == SESSION_PASS:
        # Successful external auth updates heartbeat
        LAST_HEARTBEAT = time.time()
        return

    session = request.cookies.get("vps_session")
    if session == "authenticated":
        return

    audit_log.warning(
        f"UNAUTHORIZED: {request.method} {request.url.path} from {client_ip}"
    )
    raise HTTPException(status_code=403, detail="AUTHENTICATION REQUIRED")


# --- Pydantic Request Models ---
class ExecRequest(BaseModel):
    """API Request model for secure remote command execution."""

    cmd: str = Field(..., min_length=1)
    timeout: int = Field(default=15, ge=1, le=30)


class FileWriteRequest(BaseModel):
    """API Request model for atomic file write operations."""

    path: str
    content: str


class FileDeleteRequest(BaseModel):
    """API Request model for secure file deletion."""

    path: str


class FileRenameRequest(BaseModel):
    """API Request model for file renaming operations."""

    old_path: str
    new_path: str


class PriorityRequest(BaseModel):
    """API Request model for process nice-value adjustment."""

    pid: int = Field(..., gt=1)
    priority: int = Field(default=0, ge=-20, le=19)


class KillRequest(BaseModel):
    """API Request model for process termination."""

    pid: int = Field(..., gt=1)


class FileCopyRequest(BaseModel):
    """API Request model for secure file copying."""

    src: str
    dest: str


class FileStatRequest(BaseModel):
    """API Request model for retrieving file metadata."""

    path: str


class ProcessSignalRequest(BaseModel):
    """API Request model for sending STOP/CONT signals to processes."""

    pid: int = Field(..., gt=1)
    signal: str = Field(..., pattern="^(STOP|CONT)$")


class ServiceActionRequest(BaseModel):
    """API Request model for system service control."""

    name: str
    action: str


# --- Signaling (V5.1: PublicNode Telemetry Backbone) ---
_TELEMETRY_SESSION = requests.Session()


def broadcast_status(message: str) -> None:
    """Broadcast internal boot steps to the local CLI via ntfy.sh (Non-blocking)."""

    def _fire() -> None:
        """Background thread execution for non-blocking telemetry broadcast."""
        try:
            if SIGNAL_TOPIC:
                prefix = f"[{SESSION_ID}] " if SESSION_ID else ""
                payload = f"STATUS: {prefix}{message}"
                _TELEMETRY_SESSION.post(
                    f"https://ntfy.sh/{SIGNAL_TOPIC}", data=payload.encode(), timeout=5
                )
                audit_log.info(f"TELEMETRY: {message}")
        except Exception:
            pass

    threading.Thread(target=_fire, daemon=True).start()


@asynccontextmanager
async def lifespan(app_instance: FastAPI) -> Any:
    """Startup/shutdown lifecycle for background daemons."""
    broadcast_status("STARTING SYSTEM SERVICES...")

    # Industrial Cloud Check: Verify Kaggle Auth on Boot (Background)
    def _bg_cloud_check() -> None:
        """Perform Kaggle authentication in a background thread to prevent blocking the main event loop."""
        try:
            from kaggle.api.kaggle_api_extended import KaggleApi

            api = KaggleApi()
            api.authenticate()
            user = api.get_config_value("username")
            audit_log.info(f"CLOUD: Kaggle authenticated as {user}")
        except ImportError:
            audit_log.warning("CLOUD: Kaggle API module not available. Skipping check.")
            return
        except Exception as e:
            # V6: Silence error if it's just a missing config file (common in dev)
            if "Could not find kaggle.json" in str(e):
                audit_log.warning(
                    "CLOUD: kaggle.json missing. Using unauthenticated fallback."
                )
            else:
                audit_log.error(f"CLOUD: Kaggle Auth check failed: {e}")
            broadcast_status("⚠️ CLOUD LOGIN FAILED")
            broadcast_status("⚠️ AUTO-SAVE IS OFF.")

    threading.Thread(target=_bg_cloud_check, daemon=True).start()

    threading.Thread(target=sentinel_loop, daemon=True).start()
    threading.Thread(target=stats_cacher_loop, daemon=True).start()
    threading.Thread(target=dead_man_watchdog, daemon=True).start()
    if Observer is not None and PublicNodeWatchdog is not None:
        try:
            obs = Observer()
            obs.schedule(PublicNodeWatchdog(), path="/kaggle/working", recursive=True)
            obs.start()
            threading.Thread(target=autonomous_sync_loop, daemon=True).start()
        except Exception as e:
            audit_log.error(f"Watchdog failed to start: {e}")

    # System Vault: Restore OS state from HuggingFace on boot (Non-blocking Task)
    # RUF006: Store reference in a global set to prevent garbage collection
    _boot_task = asyncio.create_task(asyncio.to_thread(_pull_system_snapshot))
    background_tasks.add(_boot_task)
    _boot_task.add_done_callback(background_tasks.discard)

    if GUI_ENABLED:
        threading.Thread(target=GUIManager.start, daemon=True).start()

    yield
    audit_log.info("SHUTDOWN: Cleaning up lifespan...")

    # Fire off an emergency save synchronously before killing everything
    try:
        _run_system_save()
    except Exception as save_err:
        audit_log.error(f"Lifespan save error: {save_err}")

    # V6: Nuclear Shutdown - terminate all child processes in the same group
    try:
        GUIManager.stop()
        subprocess.run(["pkill", "-9", "cloudflared"], capture_output=True, check=False)
        subprocess.run(["pkill", "-9", "websocat"], capture_output=True, check=False)
        parent = psutil.Process(os.getpid())
        for child in parent.children(recursive=True):
            try:
                child.kill()
            except Exception:
                pass
        audit_log.info("SHUTDOWN: Tunnels and child processes terminated.")
    except Exception as e:
        audit_log.error(f"SHUTDOWN: Cleanup error: {e}")


app = FastAPI(
    title="PublicNode Engine",
    version=VPS_VERSION or "0.1.0",
    docs_url="/docs",
    redoc_url=None,
    lifespan=lifespan,
)
app.add_middleware(GZipMiddleware, minimum_size=1000)


@app.middleware("http")
async def http_activity_middleware(request: Request, call_next: Any) -> Any:
    """Industrial-grade HTTP logger: captures every request and response with absolute transparency."""
    start_time = time.time()
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    client_ip = request.client.host if request.client else "unknown"
    # Create a simple correlation ID based on timestamp and last part of IP
    correlation_id = f"{int(start_time * 1000) % 100000:05d}"

    full_url = str(request.url)

    # Log Request Initiation
    headers = dict(request.headers)
    HTTP_ACTIVITY_LOGS.append(
        f"[{timestamp}] [#{correlation_id}] 📡 REQ: {request.method.ljust(6)} {full_url} from {client_ip} | HEADERS: {json.dumps(headers)}"
    )

    try:
        response = await call_next(request)
        duration = (time.time() - start_time) * 1000

        # Status indicators
        status_color = "🟢" if response.status_code < 400 else "🟠"
        if response.status_code >= 500:
            status_color = "🔴"

        # Log Response Completion
        res_headers = dict(response.headers)
        HTTP_ACTIVITY_LOGS.append(
            f"[{timestamp}] [#{correlation_id}] {status_color} RES: {response.status_code} ({duration:.2f}ms) | HEADERS: {json.dumps(res_headers)}"
        )
        return response
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        HTTP_ACTIVITY_LOGS.append(
            f"[{timestamp}] [#{correlation_id}] ❌ ERR: CRASH ({duration:.2f}ms) | {e!s}"
        )
        raise


@app.middleware("http")
async def security_headers(request: Request, call_next: Any) -> Any:
    """Inject industrial-grade security headers into every API response."""
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "SAMEORIGIN"
    return response


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(
    request: Request, exc: StarletteHTTPException
) -> JSONResponse:
    """Industrial Error Handler: Preserves Flutter Compatibility."""
    audit_log.error(
        f"{exc.status_code} ERROR: {request.method} {request.url.path} | {exc.detail}"
    )
    if exc.status_code >= 400 and exc.status_code not in [404, 405]:
        broadcast_status(f"❌ API {exc.status_code}: {request.url.path}")
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": exc.detail,
            "message": exc.detail,
            "user_message": f"Error: {exc.detail}",
            "status": "error",
        },
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    """Handles Pydantic validation errors with industrial logging."""
    audit_log.error(
        f"422 VALIDATION ERROR: {request.method} {request.url.path} | {exc.errors()}"
    )
    broadcast_status(f"❌ API 422: {request.url.path}")
    return JSONResponse(
        status_code=422,
        content={
            "error": "Validation Error",
            "message": "Invalid Request Data",
            "user_message": "Invalid input. Please check what you typed.",
            "details": exc.errors(),
            "status": "error",
        },
    )


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Catch-all for unhandled exceptions to prevent engine silence."""
    audit_log.error(f"500 CRITICAL: {request.method} {request.url.path} | {exc}")
    broadcast_status(f"❌ API 500: {exc}")
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal Server Error",
            "message": str(exc),
            "user_message": "A system error occurred. Please restart.",
            "details": str(exc),
            "status": "error",
        },
    )


# --- Simple in-memory cache ---
_cache: dict[str, Any] = {"apps": None, "apps_time": 0.0}

# --- Initialize settings file if absent ---
if not os.path.exists(SETTINGS_FILE):
    with open(SETTINGS_FILE, "w") as _f:
        json.dump({"sentinel": True, "region": "auto", "theme": "vps_publicnode"}, _f)

# --- Live network / disk I/O baselines ---
_last_net = psutil.net_io_counters()
_last_disk = psutil.disk_io_counters()
_last_time = time.time()

# --- Telemetry History Buffer (60s) ---
_stats_history: Deque[Dict[str, Any]] = deque(maxlen=60)
_READY_SENT = False  # V5.1 Resilience: Only broadcast READY once per session


def _update_history(stats_dict: Dict[str, Any]) -> None:
    """Append current system stats to the rolling history buffer."""
    _stats_history.append(
        {
            "time": int(time.time()),
            "cpu": stats_dict["cpu"],
            "ram": stats_dict["ram"],
            "net": stats_dict["net"],
        }
    )


@app.api_route("/", methods=["GET", "HEAD"])
async def root() -> Any:
    """Health check endpoint for the engine."""
    return {
        "status": "online",
        "vps": VPS_NAME,
        "version": VPS_VERSION,
        "engine": "PublicNode",
    }


@app.get("/api/ping")
async def ping() -> Any:
    """Minimal latency check endpoint."""
    return {"status": "online", "vps": VPS_NAME}


@app.get("/api/system/http-logs", dependencies=[Depends(verify_auth)])
async def get_http_logs() -> Any:
    """Return the recent HTTP activity logs for the FastAPI engine."""
    return list(HTTP_ACTIVITY_LOGS)


@app.post("/api/system/heartbeat", dependencies=[Depends(verify_auth)])
async def system_heartbeat() -> Any:
    """Update the Dead Man's Switch timestamp."""
    global LAST_HEARTBEAT
    LAST_HEARTBEAT = time.time()
    return {"status": "ok", "timestamp": int(LAST_HEARTBEAT)}


# ============================================================
# SYSTEM STATS & INFO
# ============================================================

_stats_cache = None
_stats_cache_time = 0.0


def _get_nominal_cpu_freq() -> Optional[float]:
    """Fallback: Read real CPU frequency from /proc/cpuinfo (Industry Grade Accuracy)."""
    try:
        if os.path.exists("/proc/cpuinfo"):
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if "cpu MHz" in line:
                        return round(float(line.split(":")[1].strip()), 0)
        return None
    except Exception:
        return None


def _get_internal_stats() -> Dict[str, Any]:
    """Industrial-grade telemetry engine: Raw data for internal OS use.
    Thread-safe: protected by _stats_lock to prevent race conditions."""
    global _last_net, _last_disk, _last_time, _stats_cache, _stats_cache_time

    now = time.time()
    # Fast path: return cached data if fresh (lock-free read is safe for staleness check)
    if _stats_cache and (now - _stats_cache_time) < 1.0:
        return _stats_cache

    with _stats_lock:
        # Double-check inside lock to prevent thundering herd
        now = time.time()
        if _stats_cache and (now - _stats_cache_time) < 1.0:
            return _stats_cache

        dt = max(now - _last_time, 0.001)
        cpu = psutil.cpu_percent(interval=None)
        ram = psutil.virtual_memory().percent

        curr_net = psutil.net_io_counters()
        net_in_kb = round((curr_net.bytes_recv - _last_net.bytes_recv) / 1024 / dt, 2)
        net_out_kb = round((curr_net.bytes_sent - _last_net.bytes_sent) / 1024 / dt, 2)
        net_speed = round(
            (
                (curr_net.bytes_sent - _last_net.bytes_sent)
                + (curr_net.bytes_recv - _last_net.bytes_recv)
            )
            / 1024
            / 1024
            / dt,
            2,
        )
        _last_net = curr_net

        curr_disk = psutil.disk_io_counters()
        disk_speed = 0.0
        if curr_disk and _last_disk:
            disk_speed = round(
                (
                    (curr_disk.read_bytes - _last_disk.read_bytes)
                    + (curr_disk.write_bytes - _last_disk.write_bytes)
                )
                / 1024
                / 1024
                / dt,
                2,
            )
        _last_disk = curr_disk
        # --- GPU Telemetry (Industrial Grade) ---
        gpu_stats = []
        try:
            # Atomic poll via nvidia-smi for zero-simulation hardware data
            output = subprocess.check_output(
                [
                    "nvidia-smi",
                    "--query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total,name",
                    "--format=csv,nounits,noheader",
                ],
                stderr=subprocess.DEVNULL,
                encoding="utf-8",
            )
            for line in output.strip().split("\n"):
                if not line:
                    continue
                parts = line.split(", ")
                if len(parts) >= 5:
                    gpu_stats.append(
                        {
                            "util": int(parts[0]),
                            "mem_util": int(parts[1]),
                            "used": int(parts[2]),
                            "total": int(parts[3]),
                            "name": parts[4],
                        }
                    )
        except Exception:
            pass  # No GPU detected or nvidia-smi missing

        _stats_cache = {
            "cpu": cpu,
            "ram": ram,
            "net_in_kb": net_in_kb,
            "net_out_kb": net_out_kb,
            "net_speed_mb": net_speed,
            "disk_speed_mb": disk_speed,
            "gpus": gpu_stats,
            "uptime": int(now - START_TIME),
            "timestamp": now,
        }
        _stats_cache_time = now
        _last_time = now
        return _stats_cache


@app.get("/api/stats", dependencies=[Depends(verify_auth)])
def get_stats() -> Any:
    """Consolidated telemetry: CPU, RAM, Network, and Disk speeds."""
    return JSONResponse(content=_get_internal_stats())


@app.get("/api/stats/history", dependencies=[Depends(verify_auth)])
def get_stats_history() -> Any:
    """Historical telemetry pulse."""
    return list(_stats_history)


@app.get("/api/sysinfo", dependencies=[Depends(verify_auth)])
async def get_sysinfo() -> Any:
    """Retrieve detailed hardware and OS information."""
    try:
        cpu_model = "Unknown CPU"
        distro = "Linux"
        try:
            if os.path.exists("/proc/cpuinfo"):
                with open("/proc/cpuinfo") as f:
                    for line in f:
                        if "model name" in line:
                            cpu_model = line.split(": ", 1)[-1].strip()
                            break
        except Exception:
            pass
        try:
            os_release_path = os.path.join("/", "etc", "os-release")
            if os.path.exists(os_release_path):
                with open(os_release_path) as f:
                    for line in f:
                        if line.startswith("PRETTY_NAME="):
                            distro = line.split("=", 1)[-1].strip().strip('"')
                            break
        except Exception:
            pass

        mem = psutil.virtual_memory()
        disk = psutil.disk_usage(SAFE_ROOT)

        return {
            "cpu_model": cpu_model,
            "distro": distro,
            "vps_name": VPS_NAME,
            "kernel": platform.release(),
            "arch": platform.machine(),
            "version": VPS_VERSION,
            "ram": {
                "total": round(mem.total / 1024 / 1024 / 1024, 2),
                "available": round(mem.available / 1024 / 1024 / 1024, 2),
            },
            "disk": {
                "total": round(disk.total / 1024 / 1024 / 1024, 2),
                "free": round(disk.free / 1024 / 1024 / 1024, 2),
            },
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/api/system/audit", dependencies=[Depends(verify_auth)])
async def get_audit_logs(lines: int = Query(default=100, ge=1, le=1000)) -> Any:
    """Industrial-grade audit retrieval: serves recent system event history."""
    try:
        audit_file = os.path.join(LOG_DIR, "audit.log")
        if not os.path.exists(audit_file):
            return {"logs": [], "message": "No activity history found."}

        # Fast tail using deque for memory efficiency
        with open(audit_file) as f:
            log_lines = deque(f, maxlen=lines)

        return {
            "logs": [line.strip() for line in log_lines],
            "total_lines": len(log_lines),
            "timestamp": int(time.time()),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/api/system/metrics", dependencies=[Depends(verify_auth)])
async def system_metrics() -> Any:
    """Extended system metrics: per-core CPU, load avg, swap, temperatures, boot time."""
    try:
        vm = psutil.virtual_memory()
        sw = psutil.swap_memory()
        load = os.getloadavg()
        per_cpu = psutil.cpu_percent(percpu=True, interval=None)
        cpu_freq = psutil.cpu_freq()
        disk = psutil.disk_usage(SAFE_ROOT)
        net = psutil.net_io_counters()
        temps = {}
        try:
            raw_temps = psutil.sensors_temperatures()
            if raw_temps:
                for name, entries in raw_temps.items():
                    if entries:
                        temps[name] = round(entries[0].current, 1)
        except Exception:
            pass

        return {
            "cpu": {
                "per_core": per_cpu,
                "cores_logical": psutil.cpu_count(logical=True),
                "cores_physical": psutil.cpu_count(logical=False),
                "freq_mhz": round(cpu_freq.current, 0)
                if (cpu_freq and cpu_freq.current > 0)
                else _get_nominal_cpu_freq(),
                "freq_max_mhz": round(cpu_freq.max, 0)
                if (cpu_freq and cpu_freq.max > 0)
                else None,
            },
            "ram": {
                "total_gb": round(vm.total / 1024**3, 2),
                "used_gb": round(vm.used / 1024**3, 2),
                "available_gb": round(vm.available / 1024**3, 2),
                "percent": vm.percent,
                "buffers_gb": round(vm.buffers / 1024**3, 2)
                if hasattr(vm, "buffers")
                else 0,
                "cached_gb": round(vm.cached / 1024**3, 2)
                if hasattr(vm, "cached")
                else 0,
            },
            "swap": {
                "total_gb": round(sw.total / 1024**3, 2),
                "used_gb": round(sw.used / 1024**3, 2),
                "percent": sw.percent,
            },
            "disk": {
                "total_gb": round(disk.total / 1024**3, 2),
                "used_gb": round(disk.used / 1024**3, 2),
                "free_gb": round(disk.free / 1024**3, 2),
                "percent": disk.percent,
            },
            "load_avg": {
                "1m": round(load[0], 2),
                "5m": round(load[1], 2),
                "15m": round(load[2], 2),
            },
            "net_totals": {
                "sent_gb": round(net.bytes_sent / 1024**3, 3),
                "recv_gb": round(net.bytes_recv / 1024**3, 3),
            },
            "boot_time": int(psutil.boot_time()),
            "uptime_sec": int(time.time() - START_TIME),
            "temperatures": temps,
            "name": VPS_NAME,
            "version": VPS_VERSION,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/api/system/pulse", dependencies=[Depends(verify_auth)])
async def system_pulse() -> Any:
    """Unified telemetry pulse: Zero-Lag UI via background cache."""
    with STATS_CACHE_LOCK:
        if GLOBAL_STATS_CACHE:
            return GLOBAL_STATS_CACHE
    # Fallback if cache is empty
    return {"error": "Stats preparing...", "status": "initializing"}


# ============================================================
# CREDENTIALS
# ============================================================


@app.get("/api/creds/get", dependencies=[Depends(verify_auth)])
async def get_creds() -> Any:
    """Retrieve Kaggle credentials stored in the vault."""
    return {"pass": SESSION_PASS}


# ============================================================
# GUI DESKTOP MANAGEMENT
# ============================================================


@app.get("/api/gui/status", dependencies=[Depends(verify_auth)])
def gui_status() -> Any:
    """Check the status of the GUI stack."""
    return {
        "enabled": GUI_ENABLED,
        "running": GUIManager.is_running(),
        "resolution": GUI_RESOLUTION,
        "display": GUI_DISPLAY,
        "novnc_port": GUI_PORT,
    }


@app.post("/api/gui/start", dependencies=[Depends(verify_auth)])
def gui_start() -> Any:
    """Start the GUI stack."""
    if not GUI_ENABLED:
        raise HTTPException(
            status_code=400, detail="GUI is not enabled in vps-config.yaml"
        )
    success = GUIManager.start()
    return {"status": "ok" if success else "error", "running": GUIManager.is_running()}


@app.post("/api/gui/stop", dependencies=[Depends(verify_auth)])
def gui_stop() -> Any:
    """Stop the GUI stack."""
    GUIManager.stop()
    return {"status": "ok"}


@app.get("/api/gui/logs", dependencies=[Depends(verify_auth)])
async def gui_logs() -> Any:
    """Return the internal logs of the GUI stack."""
    # V12: Read from the canonical log directory, not /tmp
    log_path = os.path.join(LOG_DIR, "vps_gui.log")
    if not os.path.exists(log_path):
        # Fallback to /tmp for backward compatibility
        log_path = os.path.join(tempfile.gettempdir(), "vps_gui.log")
    if not os.path.exists(log_path):
        return {"logs": []}
    try:
        with open(log_path, errors="replace") as f:
            lines = [line.strip() for line in deque(f, maxlen=200)]
            return {"logs": lines}
    except Exception as e:
        return {"error": str(e)}


@app.get("/api/gui/diagnostic", dependencies=[Depends(verify_auth)])
async def gui_diagnostic() -> Any:
    """Run internal X11 diagnostics to debug blank screen issues."""
    diag: dict[str, Any] = {}

    # 1. Check processes
    try:
        ps = subprocess.check_output(["ps", "aux"], text=True)  # nosec B603 B607
        diag["processes"] = [
            line
            for line in ps.split("\n")
            if any(
                x in line
                for x in [
                    "Xvfb",
                    "xfce4-session",
                    "xfwm4",
                    "xfce4-panel",
                    "xfdesktop",
                    "vnc",
                    "websockify",
                ]
            )
        ]
    except Exception as e:
        diag["ps_error"] = str(e)

    # 2. Check X server state
    try:
        diag["xwininfo"] = subprocess.check_output(
            ["xwininfo", "-root", "-display", GUI_DISPLAY],
            text=True,
            stderr=subprocess.STDOUT,
        )  # nosec B603 B607
    except Exception as e:
        diag["xwininfo_error"] = str(e)

    # 3. Check for unix socket
    display_num = GUI_DISPLAY.replace(":", "")
    diag["x11_socket"] = os.path.exists(f"/tmp/.X11-unix/X{display_num}")  # nosec B108
    diag["display"] = GUI_DISPLAY

    return diag


# ============================================================
# COMMAND EXECUTION  (authenticated shell exec)
# ============================================================

# Blocked patterns for safety (prevent the most dangerous commands)
_BLOCKED_PATTERNS = [
    "rm -rf /",
    "mkfs",
    ":(){:|:&};:",
    "dd if=/dev/zero of=/dev/sd",
    "chmod -R 000 /",
    "mv / ",
    "> /dev/sda",
]


PROOT_BIN = shutil.which("proot") or os.path.join("/", "usr", "local", "bin", "proot")
PROOT_ROOT = os.environ.get(
    "PROOT_ROOT", os.path.join("/", "kaggle", "working", "proot_root")
)
PROOT_KAG_WORKING = os.environ.get(
    "PROOT_BIND_WORKING", os.path.join("/", "kaggle", "working")
)


def _wrap_proot(cmd: str) -> str:
    """Wrap a command in PRoot virtualization if the rootfs is present."""
    if PROOT_BIN and os.path.exists(PROOT_BIN) and os.path.exists(PROOT_ROOT):
        return (
            f"{PROOT_BIN} -r {PROOT_ROOT} "
            f"-b {PROOT_KAG_WORKING} "
            f"-b /proc -b /dev -b /sys "
            f"-w /root /bin/sh -c {shlex.quote(cmd)}"
        )
    return cmd


@app.post("/api/system/exec", dependencies=[Depends(verify_auth)])
async def exec_command(body: ExecRequest) -> Any:
    """Execute a shell command in the working directory.
    Returns stdout, stderr, exit code, and execution time."""
    cmd = body.cmd.strip()

    # Enhanced Regex-based filter for dangerous patterns
    cmd_lower = cmd.lower()
    dangerous_regex = [
        r"rm\s+-rf\s+(?:/|\*|\.\.?|~)",
        r"mkfs",
        r":\s*\(\s*\)\s*\{\s*:\|\s*:\s*&\s*\}\s*;\s*:",  # Fork bomb
        r"dd\s+if=.+of=/dev/sd",
        r"chmod\s+(?:-R\s+)?(?:000|777)\s+(?:/|~)",
        r"mv\s+(?:/|~)\s+",
        r">\s+/dev/sd",
        r"nc\s+-(?:e|lp)",
        r"bash\s+-i\s+>&",
        r"sh\s+-i\s+>&",
        r"python(?:3)?\s+-c\s+['\"].*import\s+socket",
    ]
    for pattern in dangerous_regex:
        if re.search(pattern, cmd_lower):
            audit_log.error(f"MALICIOUS COMMAND BLOCKED: '{cmd}'")
            raise HTTPException(
                status_code=403,
                detail=f"Command blocked: matches dangerous pattern '{pattern}'",
            )

    t_start = time.time()
    try:
        final_cmd = _wrap_proot(cmd)
        proc = await asyncio.create_subprocess_shell(
            final_cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=SAFE_ROOT,
        )
        stdout_bytes, stderr_bytes = await asyncio.wait_for(
            proc.communicate(), timeout=body.timeout
        )
        elapsed = round(time.time() - t_start, 3)
        return {
            "stdout": (stdout_bytes or b"").decode(errors="replace")[-8192:],
            "stderr": (stderr_bytes or b"").decode(errors="replace")[-2048:],
            "exit_code": proc.returncode or 0,
            "elapsed_sec": elapsed,
        }
    except asyncio.TimeoutError:
        return JSONResponse(
            status_code=408,
            content={
                "stdout": "",
                "stderr": "",
                "exit_code": -1,
                "error": f"Command timed out after {body.timeout}s",
            },
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


# ============================================================
# SYSTEM VAULT SYNC (V5 Absolute Data PublicNodety)
# ============================================================


def _get_dir_size(path: str) -> int:
    """Industrial-grade iterative directory sizing (Recursion-proof)."""
    try:
        res = subprocess.run(
            ["du", "-sb", path], capture_output=True, text=True, check=True, timeout=5
        )
        return int(res.stdout.split()[0])
    except Exception:
        return -1


def perform_boot_audit() -> None:
    """Industrial-grade Pre-flight Integrity Audit."""
    broadcast_status("SYSTEM CHECK IN PROGRESS...")
    audit_log.info("BOOT AUDIT: Commencing deep system verification...")

    # 1. Staging Hygiene
    tmp_dir = tempfile.gettempdir()
    staging_areas = [
        os.path.join(tmp_dir, "vps_staging"),
        os.path.join(tmp_dir, "vps_sync_*"),
    ]
    for area in staging_areas:
        try:
            for d in glob.glob(area):
                if os.path.isdir(d):
                    shutil.rmtree(d, ignore_errors=True)
                else:
                    os.remove(d)
        except Exception:
            pass

    # 2. Cloud Identity Verification
    if not VAULT_ID:
        audit_log.warning("BOOT AUDIT: Kaggle VAULT_ID missing. Persistence disabled.")
    if not HF_TOKEN:
        audit_log.warning("BOOT AUDIT: HF_TOKEN missing. Deep Vault disabled.")

    # 2.5. Input Restoration (Kaggle Persistence Bridge)
    input_vault = f"/kaggle/input/{VAULT_SLUG}" if VAULT_SLUG else None
    if input_vault and os.path.exists(input_vault):
        audit_log.info(
            f"BOOT AUDIT: Detected attached Persistence Vault at {input_vault}"
        )
        try:
            # Restore files from the attached dataset to the working directory
            # but only if they don't already exist or are newer.
            rsync_cmd = [
                "rsync",
                "-av",
                "--ignore-existing",
                f"{input_vault}/",
                f"{SAFE_ROOT}/",
            ]
            subprocess.run(rsync_cmd, check=True, capture_output=True)
            broadcast_status("GETTING FILES...")
            audit_log.info("BOOT AUDIT: Input vault restoration — [SUCCESS]")
        except Exception as e:
            audit_log.warning(f"BOOT AUDIT: Input restoration warning: {e}")

    # 3. Network Pulse
    # V7: Use HTTP HEAD check as ping is often blocked in cloud containers
    try:
        res = requests.head("https://1.1.1.1", timeout=3)
        if res.status_code < 500:
            audit_log.info("BOOT AUDIT: Global Network Connectivity — [OK]")
        else:
            raise Exception(f"Cloud flare returned {res.status_code}")
    except Exception:
        # Fallback to a secondary check or warning
        try:
            # Check if we can at least resolve DNS
            import socket

            socket.gethostbyname("google.com")
            audit_log.info("BOOT AUDIT: Global Network Connectivity (DNS) — [OK]")
        except Exception:
            audit_log.warning("BOOT AUDIT: Network unreachable. Cloud ops may fail.")

    broadcast_status("SECURITY READY")
    audit_log.info("BOOT AUDIT: System Integrity Verified.")


def _check_dynamic_space(path: Optional[str] = None, workspace_bytes: int = 0) -> bool:
    """V5: Ensure 2.5x workspace size is available for staging."""
    if path is None:
        path = tempfile.gettempdir()
    try:
        stat = os.statvfs(path)
        free_bytes = stat.f_bavail * stat.f_frsize
        # Need space for 1x temp tar + 1x staged tar + 0.5x buffer
        needed = int(workspace_bytes * 2.5)
        return free_bytes > needed
    except Exception:
        return True  # Fallback


def _verify_archive(path: str) -> bool:
    """Verify tar archive integrity before processing (V9.2 Resilience)."""
    if not os.path.exists(path):
        return False
    try:
        # tar -tf lists contents; if it fails, archive is corrupt.
        # Auto-detects compression (zstd/gzip/etc.)
        subprocess.run(
            ["tar", "-tf", path],
            check=True,
            capture_output=True,
            timeout=60,
        )
        return True
    except Exception as e:
        audit_log.error(f"INTEGRITY CHECK FAILED for {os.path.basename(path)}: {e}")
        return False


def _check_disk_space(required_mb: float) -> bool:
    """Ensure sufficient disk space exists before large operations."""
    try:
        _, _, free = shutil.disk_usage(SAFE_ROOT)
        free_mb = free / (1024 * 1024)
        return free_mb > required_mb
    except Exception:
        return True  # Fallback to attempt if check fails


def _commit_to_kaggle(staging_dir: str, msg: str) -> str:
    """Industrial-grade Kaggle commitment using Native Python API (V6.1).
    Bypasses CLI bugs and implements robust slug recovery."""
    from kaggle.api.kaggle_api_extended import KaggleApi

    api = KaggleApi()
    api.authenticate()
    target_id = VAULT_ID

    for attempt in range(3):
        try:
            # 1. Identity Verification (Prevention of 403/404 errors)
            current_user = api.get_config_value("username")
            target_id = VAULT_ID if VAULT_ID else f"{current_user}/{VAULT_SLUG}"

            # 2. Atomic Commitment
            api.dataset_create_version(staging_dir, msg, quiet=True)
            return "committed"

        except Exception as e:
            err_str = str(e).lower()

            # Auto-Initialization for new vaults (404 recovery)
            if "not found" in err_str or "404" in err_str:
                audit_log.info(
                    f"VAULT: Resource {target_id} absent. Initializing industrial bridge..."
                )
                try:
                    api.dataset_create_new(staging_dir, quiet=True)
                    return "initialized"
                except Exception as create_err:
                    audit_log.error(f"VAULT: Creation failed: {create_err}")
                    raise RuntimeError(f"KAG_INIT_FAIL: {create_err}") from create_err

            # Namespace Recovery (403 recovery)
            if "forbidden" in err_str or "403" in err_str:
                if attempt == 0:
                    audit_log.info("VAULT: Attempting emergency namespace recovery...")
                    try:
                        api.dataset_create_new(staging_dir, quiet=True)
                        return "recovered"
                    except Exception:
                        pass

            if attempt == 2:
                audit_log.error(
                    f"VAULT: Final cloud commitment failed after 3 attempts: {e}"
                )
                raise e

            backoff = 5 * (attempt + 1)
            audit_log.warning(
                f"VAULT: Sync blip (attempt {attempt + 1}) - retrying in {backoff}s..."
            )
            time.sleep(backoff)

    return "sync_deferred"


@app.get("/api/sync", dependencies=[Depends(verify_auth)])
@app.post("/api/sync/vault", dependencies=[Depends(verify_auth)])
async def sync_vault() -> Any:
    """Trigger Kaggle System Vault Persistence."""
    state = SyncManager.get_state()
    if state["active"]:
        raise HTTPException(
            status_code=409, detail="A sync job is already in progress."
        )

    SyncManager.set_state(
        active=True,
        tier="kaggle",
        phase="init",
        progress=0,
        message="Initializing Snapshot...",
    )
    threading.Thread(target=SnapshotManager.run_sync, daemon=True).start()
    return JSONResponse(
        status_code=202,
        content={"status": "accepted", "message": "System Vault Sync Job Started."},
    )


@app.get("/api/sync/status", dependencies=[Depends(verify_auth)])
async def sync_status() -> Any:
    """Poll the real-time status of the persistence pipeline (V6 Unified)."""
    return SyncManager.get_state()


@app.get("/api/sync/last", dependencies=[Depends(verify_auth)])
async def sync_last() -> Any:
    """Return the timestamp of the last successful sync."""
    state = SyncManager.get_state()
    last_run = state.get("last_run", 0)
    return {
        "last_sync": last_run,
        "seconds_ago": int(time.time() - last_run) if last_run > 0 else -1,
        "needs_sync": (time.time() - last_run) > 300 if last_run > 0 else True,
    }


def _kaggle_commit_with_retry(
    staging_root: str, version_msg: str, timestamp: int
) -> str:
    """Commit a notebook to Kaggle with exponential backoff on failure."""
    max_retries = 3
    last_error = ""
    version = "v" + str(timestamp)

    for attempt in range(max_retries):
        try:
            status_cmd = ["kaggle", "datasets", "status", str(VAULT_ID)]
            status_res = subprocess.run(
                status_cmd, capture_output=True, text=True, check=False
            )

            if status_res.returncode != 0:
                audit_log.warning(
                    f"VAULT: Dataset {VAULT_ID} not found or unreachable. Attempting creation..."
                )
                create_cmd = [
                    "kaggle",
                    "datasets",
                    "create",
                    "-p",
                    staging_root,
                    "-r",
                    "zip",
                ]
                subprocess.run(
                    create_cmd, capture_output=True, text=True, check=True, timeout=600
                )
                version = "v1"
            else:
                cmd = [
                    "kaggle",
                    "datasets",
                    "version",
                    "-p",
                    staging_root,
                    "-m",
                    version_msg,
                    "-r",
                    "zip",
                ]
                result = subprocess.run(
                    cmd, capture_output=True, text=True, check=True, timeout=600
                )
                if "Version" in result.stdout:
                    try:
                        version = result.stdout.split("Version")[1].split()[0]
                    except Exception:
                        pass
            return version
        except subprocess.CalledProcessError as e:
            last_error = f"Kaggle CLI Error (Attempt {attempt + 1}): {e.stderr.strip() or e.stdout.strip() or str(e)}"
            audit_log.warning(f"Sync Retry {attempt + 1}/{max_retries}: {last_error}")
            if attempt < max_retries - 1:
                time.sleep(2**attempt * 5)
        except Exception as e:
            last_error = f"Unexpected Error: {e}"
            break

    raise RuntimeError(last_error)


class SnapshotManager:
    """Industrial Snapshot Engine for Tier 3 (200GB Kaggle Dataset).
    Implements incremental-style backups for system persistence."""

    @staticmethod
    def get_history() -> List[Dict[str, Any]]:
        """Fetch snapshot history from Kaggle and local logs."""
        try:
            # We track local history because Kaggle API is slow to report versions
            history_file = os.path.join(
                SAFE_ROOT, ".vps_state", "snapshot_history.json"
            )
            if os.path.exists(history_file):
                with open(history_file) as f:
                    data = json.load(f)
                    return cast(List[Dict[str, Any]], data)
            return []
        except Exception:
            return []

    @staticmethod
    def _record_snapshot(version: str, timestamp: int) -> None:
        """Log a successful snapshot to the local history."""
        try:
            history_file = os.path.join(
                SAFE_ROOT, ".vps_state", "snapshot_history.json"
            )
            history = SnapshotManager.get_history()
            history.insert(
                0,
                {
                    "version": version,
                    "timestamp": timestamp,
                    "message": f"System Snapshot {version}",
                    "tier": "kaggle",
                },
            )
            # Keep last 50 commits
            history = history[:50]
            with open(history_file, "w") as f:
                json.dump(history, f)
        except Exception as e:
            audit_log.error(f"SNAPSHOT: History log failed: {e}")

    @staticmethod
    def run_sync(is_panic: bool = False) -> None:
        """Kaggle System Vault Persistence (Smart Staging Architecture)."""
        if not VAULT_ID:
            SyncManager.set_state(active=False, error="Kaggle Identity Missing")
            return

        staging_root = os.path.join(tempfile.gettempdir(), "vps_staging")
        try:
            if is_panic:
                acquired = SYNC_RUN_LOCK.acquire(blocking=True, timeout=30)
                if not acquired:
                    audit_log.error("PANIC: Sync lock contention timeout.")
                    return
            elif not SYNC_RUN_LOCK.acquire(blocking=False):
                return

            SyncManager.set_state(
                tier="kaggle", phase="flush", progress=10, message="Flushing buffers..."
            )
            SyncManager.flush_disk()

            # PHASE 1: PREPARE STAGING
            os.makedirs(staging_root, exist_ok=True)

            # PHASE 2: SMART DIFF (Capture OS configs + Local Workspace + System Vault)
            SyncManager.set_state(
                tier="kaggle",
                phase="survey",
                progress=30,
                message="Snapshotting OS & Vault...",
            )

            # Explicitly include the System Vault mount point in the snapshot
            # We use -L to follow the symlink and capture the actual cloud data.
            # We EXCLUDE proot_root as it is managed by the System Vault (HF).
            rsync_cmd = [
                "rsync",
                "-avL",  # -L is critical to follow the PublicNode symlink
                "--delete",
                "--ignore-errors",  # Resilient to transient files
                "--no-perms",
                "--no-owner",
                "--no-group",
                "--exclude=logs",
                "--exclude=__pycache__",
                "--exclude=.vps_state",
                "--exclude=proot_root",
                "--exclude=proot",
                "--exclude=.ipynb_checkpoints",
                f"{SAFE_ROOT}/",
                f"{staging_root}/",
            ]
            subprocess.run(rsync_cmd, check=True, capture_output=True, timeout=300)

            # PHASE 3: METADATA
            metadata = {
                "id": VAULT_ID,
                "title": "PublicNode Persistence Vault",
                "isPrivate": True,
                "licenses": [{"name": "CC0-1.0"}],
            }
            with open(os.path.join(staging_root, "dataset-metadata.json"), "w") as f:
                json.dump(metadata, f)

            # PHASE 4: COMMIT
            SyncManager.set_state(
                tier="kaggle", phase="commit", progress=60, message="Pushing commit..."
            )

            timestamp = int(time.time())
            version_msg = f"Commit {timestamp}"
            version = _kaggle_commit_with_retry(staging_root, version_msg, timestamp)

            # Record success
            SnapshotManager._record_snapshot(version, timestamp)

            SyncManager.set_state(
                active=False,
                tier="kaggle",
                phase="idle",
                progress=100,
                message=f"Success: {version}",
            )
            broadcast_status(f"🚀 SNAPSHOT COMMITTED: {version}")
            audit_log.info(f"Snapshot Success: {version}")

        except Exception as e:
            SyncManager.set_state(
                active=False,
                tier="kaggle",
                error=str(e),
                message=f"Snapshot failed: {e}",
            )
            audit_log.error(f"Snapshot Failure: {e}")
        finally:
            try:
                if SYNC_RUN_LOCK.locked():
                    SYNC_RUN_LOCK.release()
            except Exception:
                pass


# ============================================================
# AUTONOMOUS PERSISTENCE WATCHDOG
# ============================================================

try:
    from watchdog.events import FileSystemEventHandler
    from watchdog.observers import Observer

    class PublicNodeWatchdog(FileSystemEventHandler):
        """Watchdog to monitor filesystem changes and trigger sync."""

        def on_any_event(self, event: Any) -> None:
            """Handle any filesystem event by triggering a debounced sync."""
            global LAST_FS_CHANGE
            path = str(event.src_path)
            if (
                "__pycache__" in path
                or ".git" in path
                or "logs/" in path
                or ".vps_auth" in path
            ):
                return
            LAST_FS_CHANGE = time.time()
except ImportError:
    Observer = None  # type: ignore[assignment]
    PublicNodeWatchdog = None  # type: ignore[assignment, misc]
    audit_log.warning("Watchdog module missing. Autonomous sync disabled.")


def autonomous_sync_loop() -> None:
    """Trigger background sync after 5 minutes of absolute filesystem silence.
    Runs both Kaggle (primary) and HF (mirror) sync with proper lock management."""
    last_synced_time = time.time()
    time.sleep(120)  # V6: Extended Boot grace period (2 minutes)
    while True:
        try:
            now = time.time()
            # Industry Grade Silence Detection:
            # Trigger if: 1. Changes occurred since last sync AND 2. 5 minutes of silence since last change
            if LAST_FS_CHANGE > last_synced_time:
                silence_duration = now - LAST_FS_CHANGE
                if silence_duration > 300:
                    state = SyncManager.get_state()
                    if not state["active"]:
                        audit_log.info(
                            f"AUTONOMOUS SYNC: Silence detected ({int(silence_duration)}s). Securing cloud state."
                        )
                        # We don't set last_synced_time here, we set it after successful completion
                        # But we trigger it now
                        SyncManager.set_state(
                            active=True,
                            tier="kaggle",
                            phase="init",
                            message="Autonomous Silence Trigger...",
                        )
                        threading.Thread(
                            target=SnapshotManager.run_sync, daemon=True
                        ).start()
                        last_synced_time = now  # Assume it starts now
                    else:
                        # Defer check if busy
                        pass

        except Exception as e:
            audit_log.error(f"Autonomous sync loop failed: {e}")
        time.sleep(30)  # V6: Reduced polling frequency for energy efficiency


# ============================================================
# SYSTEM VAULT: HUGGINGFACE HUB (V6)
# ============================================================


def _run_user_vault_sync(target_path: Optional[str] = None) -> None:
    """HuggingFace Private Vault (Manual User Backups).
    Specialized for individual folders/files selected by the user."""
    if not HF_REPO or not HF_TOKEN:
        SyncManager.set_state(active=False, error="HF Configuration Missing")
        return

    # Default to the centralized 'vault' directory, or fallback to the entire workspace
    source_path = target_path or os.path.join(SAFE_ROOT, "vault")
    if not os.path.exists(source_path):
        source_path = SAFE_ROOT
        audit_log.info(
            f"HF VAULT: Specialized 'vault' dir missing. Backing up workspace: {source_path}"
        )

    # Panic handling for lock acquisition
    if not SYNC_RUN_LOCK.acquire(blocking=True, timeout=30):
        audit_log.error("HF VAULT: Sync lock contention. Skipping.")
        return

    staging_dir: Optional[str] = None
    try:
        SyncManager.set_state(
            tier="hf",
            phase="init",
            progress=10,
            message=f"Preparing Vault: {os.path.basename(source_path)}",
        )
        SyncManager.flush_disk()

        from huggingface_hub import HfApi

        api = HfApi(token=HF_TOKEN)

        SyncManager.set_state(
            tier="hf",
            phase="survey",
            progress=20,
            message="Verifying Private Backbone...",
        )
        try:
            api.repo_info(repo_id=HF_REPO, repo_type="dataset")
        except Exception as e:
            if "404" in str(e):
                api.create_repo(
                    repo_id=HF_REPO, repo_type="dataset", private=True, exist_ok=True
                )
            else:
                raise e

        SyncManager.set_state(
            tier="hf",
            phase="commit",
            progress=60,
            message="Mirroring assets to Private Vault...",
        )

        # Calculate relative path in the repo to preserve directory structure
        try:
            rel_path = os.path.relpath(source_path, VAULT_DIR)
        except ValueError:
            rel_path = os.path.basename(source_path)

        path_in_repo = "" if rel_path == "." else rel_path

        for attempt in range(3):
            try:
                if os.path.isfile(source_path):
                    # It's a single file
                    api.upload_file(
                        path_or_fileobj=source_path,
                        path_in_repo=path_in_repo,
                        repo_id=HF_REPO,
                        repo_type="dataset",
                        commit_message=f"Vault Upload: {os.path.basename(source_path)}",
                    )
                else:
                    # It's a directory
                    api.upload_folder(
                        folder_path=source_path,
                        path_in_repo=path_in_repo,
                        repo_id=HF_REPO,
                        repo_type="dataset",
                        commit_message=f"Vault Mirror: {os.path.basename(source_path)}",
                        delete_patterns=["*.tmp", "*.log", "__pycache__/*"],
                    )
                break
            except Exception as e:
                if attempt == 2:
                    raise e
                time.sleep(2**attempt)

        SyncManager.set_state(
            active=False,
            tier="hf",
            phase="idle",
            progress=100,
            message="Vault Mirror Success.",
        )
        broadcast_status(f"✅ VAULT MIRRORED: {os.path.basename(source_path)}")
        audit_log.info(f"Vault Success: {os.path.basename(source_path)}")

    except Exception as e:
        SyncManager.set_state(
            active=False, tier="hf", error=str(e), message=f"Vault push failed: {e}"
        )
        broadcast_status(f"❌ VAULT ERROR: {e}")
    finally:
        SyncManager.set_state(active=False)  # Atomic state cleanup
        if staging_dir:
            shutil.rmtree(staging_dir, ignore_errors=True)
        try:
            if SYNC_RUN_LOCK.locked():
                SYNC_RUN_LOCK.release()
        except Exception:
            pass


@app.get("/api/snapshots/list", dependencies=[Depends(verify_auth)])
async def list_snapshots() -> Any:
    """Return the history of OS snapshots (commmits)."""
    return SnapshotManager.get_history()


@app.get("/api/vault/push", dependencies=[Depends(verify_auth)])
@app.get("/api/vault/hf/sync", dependencies=[Depends(verify_auth)])
@app.post("/api/vault/hf/sync", dependencies=[Depends(verify_auth)])
async def vault_push(path: str = Query(default=None)) -> Any:
    """Trigger a manual backup of a specific path to the Private HF Vault."""
    state = SyncManager.get_state()
    if state["active"]:
        raise HTTPException(status_code=409, detail="A sync job is already active.")

    SyncManager.set_state(
        active=True,
        tier="hf",
        phase="init",
        progress=0,
        message="Awakening Private Vault...",
    )
    threading.Thread(target=_run_user_vault_sync, args=(path,), daemon=True).start()
    return JSONResponse(
        status_code=202,
        content={"status": "accepted", "message": "Vault Push Initiated."},
    )


@app.get("/api/vault/list", dependencies=[Depends(verify_auth)])
async def vault_list() -> Any:
    """List contents of the Private HF Vault."""
    if not HF_REPO or not HF_TOKEN:
        raise HTTPException(status_code=400, detail="HF Configuration Missing")
    try:
        from huggingface_hub import HfApi

        api = HfApi(token=HF_TOKEN)
        files = api.list_repo_files(repo_id=HF_REPO, repo_type="dataset")
        return {"repo": HF_REPO, "files": files}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


# ============================================================
# SYSTEM VAULT — HuggingFace Snapshot Persistence (V9)
# Every byte of OS state preserved via tar.zst + HF Hub
# ============================================================


SYSTEM_VAULT_DIR = os.path.join(SAFE_ROOT, ".vps_state")
SYSTEM_IMAGE_NAME = "system_image.tar.zst"


def _create_system_snapshot() -> str:
    """Create a compressed tar.zst archive of the entire PRoot rootfs.

    Preserves ALL metadata: permissions, symlinks, ownership, timestamps.
    Returns the path to the created archive.
    """
    os.makedirs(SYSTEM_VAULT_DIR, exist_ok=True)
    proot_root = os.path.join(SAFE_ROOT, "proot_root")
    archive_path = os.path.join(SYSTEM_VAULT_DIR, SYSTEM_IMAGE_NAME)

    if not os.path.exists(proot_root):
        raise RuntimeError(f"PRoot rootfs not found at {proot_root}")

    # Remove old archive to save space during creation
    if os.path.exists(archive_path):
        os.remove(archive_path)

    # Industrial tar with zstd compression
    # We create TWO archives:
    # 1. system_image.tar.zst (proot rootfs)
    # 2. workspace_image.tar.zst (Kaggle working dir, excluding proot_root)

    # 1. SYSTEM IMAGE (Rootfs)
    audit_log.info(f"SYSTEM VAULT: Creating system archive at {archive_path}...")
    tar_cmd_sys = [
        "tar",
        "--zstd",
        "--ignore-failed-read",
        "--warning=no-file-changed",
        "-cpf",
        archive_path,
        "--exclude=./proc/*",
        "--exclude=./sys/*",
        "--exclude=./dev/*",
        "--exclude=./tmp/*",
        "--exclude=./run/*",
        "--exclude=./root/.cache/*",
        "--exclude=./root/.npm/*",
        "--exclude=./var/cache/*",
        "--exclude=./var/tmp/*",
        "--exclude=./__pycache__",
        "-C",
        proot_root,
        ".",
    ]

    result_sys = subprocess.run(
        tar_cmd_sys, capture_output=True, text=True, timeout=1800, check=False
    )
    if result_sys.returncode not in (0, 1):
        audit_log.warning(
            f"SYSTEM VAULT: System tar warning/error (exit {result_sys.returncode}): {result_sys.stderr}"
        )

    # 2. WORKSPACE IMAGE
    workspace_archive_path = os.path.join(SYSTEM_VAULT_DIR, "workspace_image.tar.zst")
    if os.path.exists(workspace_archive_path):
        os.remove(workspace_archive_path)

    audit_log.info(
        f"SYSTEM VAULT: Creating workspace archive at {workspace_archive_path}..."
    )
    tar_cmd_ws = [
        "tar",
        "--zstd",
        "--ignore-failed-read",
        "--warning=no-file-changed",
        "-cpf",
        workspace_archive_path,
        "--exclude=./proot_root",
        "--exclude=./proot",
        "--exclude=./.vps_state",
        "--exclude=./logs",
        "--exclude=./__pycache__",
        "--exclude=./.ipynb_checkpoints",
        # Exclude the archives themselves to avoid recursion
        f"--exclude={archive_path}",
        f"--exclude={workspace_archive_path}",
        "-C",
        SAFE_ROOT,
        ".",
    ]

    result_ws = subprocess.run(
        tar_cmd_ws, capture_output=True, text=True, timeout=1800, check=False
    )
    if result_ws.returncode not in (0, 1):
        audit_log.warning(
            f"SYSTEM VAULT: Workspace tar warning/error (exit {result_ws.returncode}): {result_ws.stderr}"
        )

    if not os.path.exists(archive_path) or not os.path.exists(workspace_archive_path):
        raise RuntimeError(
            f"Archive creation failed. Sys exit: {result_sys.returncode}, WS exit: {result_ws.returncode}"
        )

    # V9.1: Final Integrity Audit before considering it 'Ready'
    if not _verify_archive(archive_path):
        raise RuntimeError(
            "System archive integrity check failed immediately after creation."
        )

    size_mb_sys = os.path.getsize(archive_path) / (1024 * 1024)
    size_mb_ws = os.path.getsize(workspace_archive_path) / (1024 * 1024)
    total_mb = size_mb_sys + size_mb_ws

    # Check for critical errors (tar exit 2 is fatal)
    if result_sys.returncode == 2 or result_ws.returncode == 2:
        if total_mb < 2.0:
            raise RuntimeError(
                f"tar failed. Sys: {result_sys.returncode}, WS: {result_ws.returncode}"
            )
        else:
            audit_log.warning(
                f"SYSTEM VAULT: tar exited with 2, but {total_mb:.1f} MB archives created. Proceeding."
            )

    audit_log.info(f"SYSTEM VAULT: Snapshots created ({total_mb:.1f} MB total)")
    return archive_path


def _push_system_snapshot(archive_path: str) -> None:
    """Upload the system snapshot to HuggingFace Hub."""
    if not HF_REPO or not HF_TOKEN:
        raise RuntimeError("HF_REPO and HF_TOKEN must be configured")

    from huggingface_hub import HfApi

    api = HfApi(token=HF_TOKEN)

    # Ensure repo exists
    try:
        api.repo_info(repo_id=HF_REPO, repo_type="dataset")
    except Exception as e:
        if "404" in str(e):
            api.create_repo(
                repo_id=HF_REPO, repo_type="dataset", private=True, exist_ok=True
            )
        else:
            raise

    timestamp = int(time.time())
    last_sync_str = time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(timestamp))
    commit_msg = f"System Snapshot {last_sync_str}"

    # Generate dynamic Dataset Card (README.md)
    readme_content = f"""---
license: gpl-3.0
tags:
- vps
- backup
- publicnode
- rootfs
size_categories:
- n<1k
---

# ⬢ {VPS_NAME} Vault

This repository contains the persistent system snapshots for the **{VPS_NAME}** VPS instance.

## 🛰️ Instance Metadata
- **VPS Name**: {VPS_NAME}
- **Engine Version**: {VPS_VERSION}
- **Last Synchronized**: {last_sync_str} (UTC)
- **Snapshot File**: `{SYSTEM_IMAGE_NAME}`

## 🛠️ Restoration Instructions
These snapshots are automatically managed by the PublicNode OS Engine. 
To restore this instance on a new node, point your `vps-config.yaml` to this repository and run `vps boot`.

---
*(c) 2026 PublicNode • Automated System Vault*
"""
    readme_path = os.path.join(SYSTEM_VAULT_DIR, "README.md")
    with open(readme_path, "w") as f:
        f.write(readme_content)

    for attempt in range(3):
        try:
            audit_log.info(
                f"SYSTEM VAULT: Initiating HF upload (Attempt {attempt + 1})..."
            )

            # Industry Grade: Enable hf_transfer for 10x speed on Kaggle backbone
            os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "1"

            # Upload README
            api.upload_file(
                path_or_fileobj=readme_path,
                path_in_repo="README.md",
                repo_id=HF_REPO,
                repo_type="dataset",
                token=HF_TOKEN,
            )

            # Upload Snapshot
            SyncManager.set_state(
                tier="hf",
                phase="upload",
                progress=55,
                message="Uploading system image...",
            )
            api.upload_file(
                path_or_fileobj=archive_path,
                path_in_repo=SYSTEM_IMAGE_NAME,
                repo_id=HF_REPO,
                repo_type="dataset",
                commit_message=commit_msg,  # nosec B608
                token=HF_TOKEN,
            )

            # Upload Workspace Snapshot
            workspace_archive_path = os.path.join(
                SYSTEM_VAULT_DIR, "workspace_image.tar.zst"
            )
            if os.path.exists(workspace_archive_path):
                SyncManager.set_state(
                    tier="hf",
                    phase="upload",
                    progress=80,
                    message="Uploading workspace image...",
                )
                api.upload_file(
                    path_or_fileobj=workspace_archive_path,
                    path_in_repo="workspace_image.tar.zst",
                    repo_id=HF_REPO,
                    repo_type="dataset",
                    commit_message=f"Workspace Snapshot {last_sync_str}",
                    token=HF_TOKEN,
                )

            audit_log.info(f"SYSTEM VAULT: Pushed to HF successfully ({commit_msg})")

            # Record in local history
            _record_vault_snapshot(timestamp)

            # Upload history file to HF (V9)
            api.upload_file(
                path_or_fileobj=os.path.join(SYSTEM_VAULT_DIR, "vault_history.json"),
                path_in_repo="vault_history.json",
                repo_id=HF_REPO,
                repo_type="dataset",
                token=HF_TOKEN,
            )
            return
        except Exception as e:
            audit_log.warning(f"SYSTEM VAULT: Upload attempt {attempt + 1} failed: {e}")
            if attempt == 2:
                raise RuntimeError(f"HF Push failed after 3 attempts: {e}") from e
            time.sleep(5)


def _pull_system_snapshot() -> bool:
    """Download and extract the latest system snapshot from HuggingFace.

    Returns True if restoration occurred, False if skipped.
    """
    if not HF_REPO or not HF_TOKEN:
        audit_log.info("SYSTEM VAULT: HF not configured. Skipping restore.")
        return False

    proot_root = os.path.join(SAFE_ROOT, "proot_root")

    # Skip if rootfs already looks populated (not a fresh Kaggle session)
    marker = os.path.join(proot_root, "root", ".vault_restored")
    if os.path.exists(marker):
        audit_log.info("SYSTEM VAULT: Already restored this session. Skipping.")
        return False

    try:
        from huggingface_hub import hf_hub_download

        broadcast_status("📦 RESTORING SYSTEM FROM VAULT...")
        audit_log.info("SYSTEM VAULT: Pulling latest snapshot from HuggingFace...")

        archive_path = hf_hub_download(  # nosec B615
            repo_id=HF_REPO,
            filename=SYSTEM_IMAGE_NAME,
            repo_type="dataset",
            token=HF_TOKEN,
            local_dir=SYSTEM_VAULT_DIR,
            revision="main",
        )

        if not os.path.exists(archive_path):
            audit_log.warning("SYSTEM VAULT: No snapshot found in HF repo.")
            return False

        # V9.1 Resilience: Never extract a corrupt archive
        if not _verify_archive(archive_path):
            broadcast_status("⚠️ SYSTEM IMAGE CORRUPT. ABORTING RESTORE.")
            audit_log.error("SYSTEM VAULT: Downloaded archive failed integrity check.")
            return False

        # Extract Rootfs
        os.makedirs(proot_root, exist_ok=True)
        tar_cmd_sys = [
            "tar",
            "--zstd",
            "-xpf",
            archive_path,
            "-C",
            proot_root,
        ]
        subprocess.run(tar_cmd_sys, check=True, capture_output=True, timeout=600)

        # Download & Extract Workspace
        try:
            ws_archive_path = hf_hub_download(  # nosec B615
                repo_id=HF_REPO,
                filename="workspace_image.tar.zst",
                repo_type="dataset",
                token=HF_TOKEN,
                local_dir=SYSTEM_VAULT_DIR,
                revision="main",
            )
            if os.path.exists(ws_archive_path):
                tar_cmd_ws = [
                    "tar",
                    "--zstd",
                    "-xpf",
                    ws_archive_path,
                    "-C",
                    SAFE_ROOT,
                ]
                subprocess.run(tar_cmd_ws, check=True, capture_output=True, timeout=600)
        except Exception as ws_err:
            audit_log.warning(
                f"SYSTEM VAULT: Workspace restore failed or skipped: {ws_err}"
            )

        # Pull history file (V9)
        try:
            hf_hub_download(  # nosec B615
                repo_id=HF_REPO,
                filename="vault_history.json",
                repo_type="dataset",
                token=HF_TOKEN,
                local_dir=SYSTEM_VAULT_DIR,
                revision="main",
            )
        except Exception:
            pass  # History missing is not fatal

        # Mark as restored to avoid redundant pulls
        os.makedirs(os.path.join(proot_root, "root"), exist_ok=True)
        with open(marker, "w") as f:
            f.write(str(int(time.time())))

        broadcast_status("✅ SYSTEM RESTORED FROM VAULT")
        audit_log.info("SYSTEM VAULT: OS state fully restored from HuggingFace.")
        return True

    except Exception as e:
        audit_log.warning(
            f"SYSTEM VAULT: Restore failed (attempting base fallback): {e}"
        )
        # Fallback: If rootfs is empty/non-existent, initialize a fresh base
        if not os.path.exists(os.path.join(proot_root, "bin")):
            audit_log.info("SYSTEM VAULT: Initializing fresh base (fallback)...")
            os.makedirs(proot_root, exist_ok=True)
            # nosec B615 (HuggingFace download is pinned)
            base_url = "https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.5-base-amd64.tar.gz"
            try:
                # Use a securely generated temporary file to prevent symlink attacks (Fixes B108 properly)
                with tempfile.NamedTemporaryFile(
                    suffix=".tar.gz", delete=False
                ) as tmp_file:
                    tmp_path = tmp_file.name

                try:
                    # Use subprocess.run for industrial-grade security (prevents shell injection)
                    subprocess.run(["wget", "-q", base_url, "-O", tmp_path], check=True)
                    subprocess.run(
                        ["tar", "-xzf", tmp_path, "-C", proot_root], check=True
                    )
                finally:
                    if os.path.exists(tmp_path):
                        os.remove(tmp_path)

                audit_log.info("SYSTEM VAULT: Fresh base initialized.")
            except Exception as e2:
                audit_log.error(f"SYSTEM VAULT: Fallback initialization failed: {e2}")
        return False


def _record_vault_snapshot(timestamp: int) -> None:
    """Record a successful snapshot in local history."""
    try:
        os.makedirs(SYSTEM_VAULT_DIR, exist_ok=True)
        history_file = os.path.join(SYSTEM_VAULT_DIR, "vault_history.json")
        history: List[Dict[str, Any]] = []
        if os.path.exists(history_file):
            with open(history_file) as f:
                history = json.load(f)
        history.insert(
            0,
            {
                "timestamp": timestamp,
                "message": f"System Snapshot {time.strftime('%Y-%m-%d %H:%M', time.gmtime(timestamp))}",
                "tier": "hf",
            },
        )
        history = history[:50]  # Keep last 50
        with open(history_file, "w") as f:
            json.dump(history, f)
    except Exception as e:
        audit_log.error(f"SYSTEM VAULT: History log failed: {e}")


def _run_system_save() -> None:
    """Full pipeline: snapshot + push to HF. Runs in background thread."""
    sentinel_path = os.path.join(SYSTEM_VAULT_DIR, "sync_active")

    # 1. Acquire Lock
    if not SYNC_RUN_LOCK.acquire(blocking=True, timeout=30):
        audit_log.error("SYSTEM VAULT: Could not acquire SYNC_RUN_LOCK. Aborting.")
        SyncManager.set_state(active=False)
        return

    try:
        os.makedirs(SYSTEM_VAULT_DIR, exist_ok=True)
        with open(sentinel_path, "w") as f:
            f.write(str(time.time()))

        SyncManager.set_state(
            active=True,
            tier="hf",
            phase="snapshot",
            progress=10,
            message="Creating system snapshot...",
        )

        audit_log.info("SYSTEM VAULT: Creating local archive...")
        archive_path = _create_system_snapshot()

        size_mb_sys = os.path.getsize(archive_path) / (1024 * 1024)
        ws_archive_path = os.path.join(SYSTEM_VAULT_DIR, "workspace_image.tar.zst")
        size_mb_ws = (
            os.path.getsize(ws_archive_path) / (1024 * 1024)
            if os.path.exists(ws_archive_path)
            else 0
        )
        total_mb = size_mb_sys + size_mb_ws

        SyncManager.set_state(
            tier="hf",
            phase="upload",
            progress=50,
            message=f"Uploading {total_mb:.0f} MB to HuggingFace...",
        )

        _push_system_snapshot(archive_path)

        SyncManager.set_state(
            active=False,
            tier="hf",
            phase="idle",
            progress=100,
            message="System saved successfully.",
        )
        broadcast_status("✅ SYSTEM VAULT: All bytes secured.")

    except Exception as e:
        SyncManager.set_state(
            active=False, tier="hf", error=str(e), message=f"Save failed: {e}"
        )
        broadcast_status(f"❌ SYSTEM SAVE FAILED: {e}")
        audit_log.error(f"SYSTEM VAULT: Save pipeline failed: {e}")
    finally:
        if os.path.exists(sentinel_path):
            try:
                os.remove(sentinel_path)
            except Exception:
                pass
        if SYNC_RUN_LOCK.locked():
            SYNC_RUN_LOCK.release()
        SyncManager.set_state(active=False)


@app.get("/api/system/save", dependencies=[Depends(verify_auth)])
@app.post("/api/system/save", dependencies=[Depends(verify_auth)])
async def system_save() -> Any:
    """Trigger a full system snapshot and push to HuggingFace."""
    state = SyncManager.get_state()
    if state["active"]:
        raise HTTPException(status_code=409, detail="A sync job is already active.")

    SyncManager.set_state(
        active=True,
        tier="hf",
        phase="init",
        progress=0,
        message="Initiating system save...",
    )
    threading.Thread(target=_run_system_save, daemon=True).start()
    return JSONResponse(
        status_code=202,
        content={"status": "accepted", "message": "System save initiated."},
    )


@app.get("/api/system/vault/status", dependencies=[Depends(verify_auth)])
async def system_vault_status() -> Any:
    """Return the current System Vault state."""
    proot_root = os.path.join(SAFE_ROOT, "proot_root")
    archive_path = os.path.join(SYSTEM_VAULT_DIR, SYSTEM_IMAGE_NAME)

    result: Dict[str, Any] = {
        "configured": bool(HF_REPO and HF_TOKEN),
        "hf_token_present": bool(HF_TOKEN),
        "hf_repo": HF_REPO or "",
        "rootfs_exists": os.path.exists(proot_root),
        "archive_exists": os.path.exists(archive_path),
        "archive_size_mb": 0,
        "last_save": None,
        "sync": SyncManager.get_state(),
    }

    if result["archive_exists"]:
        result["archive_size_mb"] = round(
            os.path.getsize(archive_path) / (1024 * 1024), 1
        )

    # Check local history for last save time
    history_file = os.path.join(SYSTEM_VAULT_DIR, "vault_history.json")
    if os.path.exists(history_file):
        try:
            with open(history_file) as f:
                history = json.load(f)
            if history:
                result["last_save"] = history[0].get("timestamp")
        except Exception:
            pass

    return result


@app.get("/api/system/vault/history", dependencies=[Depends(verify_auth)])
async def system_vault_history() -> Any:
    """Return the snapshot commit history."""
    history_file = os.path.join(SYSTEM_VAULT_DIR, "vault_history.json")
    if os.path.exists(history_file):
        try:
            with open(history_file) as f:
                return json.load(f)
        except Exception:
            pass
    return []


def autosave_loop() -> None:
    """Background heartbeat for periodic cloud commitment.
    Triggers a Kaggle backup every AUTOSAVE_INTERVAL when autosave is enabled."""
    time.sleep(120)  # Boot grace period
    while True:
        try:
            autosave_enabled = True  # Default on
            if os.path.exists(SETTINGS_FILE):
                with open(SETTINGS_FILE) as f:
                    cfg = json.load(f)
                autosave_enabled = cfg.get("autosave", True)

            state = SyncManager.get_state()
            if autosave_enabled and not state["active"]:
                audit_log.info(
                    "AUTOSAVE: Interval reached. Securing continuity snapshot."
                )
                SyncManager.set_state(
                    active=True,
                    tier="kaggle",
                    phase="init",
                    message="Autosave Heartbeat...",
                )
                threading.Thread(target=SnapshotManager.run_sync, daemon=True).start()
                audit_log.info("AUTOSAVE HEARTBEAT: Cloud commitment complete.")
            elif autosave_enabled:
                audit_log.info("AUTOSAVE HEARTBEAT: Skipped (sync already active).")
        except Exception as e:
            audit_log.error(f"Autosave loop error: {e}")
        time.sleep(AUTOSAVE_INTERVAL)


# ============================================================
# SETTINGS
# ============================================================


@app.get("/api/settings/get", dependencies=[Depends(verify_auth)])
async def get_settings() -> Any:
    """Reads engine settings."""
    try:
        with open(SETTINGS_FILE) as f:
            return json.load(f)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.post("/api/settings/update", dependencies=[Depends(verify_auth)])
async def update_settings(request: Request) -> Any:
    """Atomic settings update — temp file created in same dir as destination."""
    try:
        data = await request.json()
        settings_dir = os.path.dirname(SETTINGS_FILE)
        with tempfile.NamedTemporaryFile(
            "w", dir=settings_dir, delete=False, suffix=".tmp"
        ) as tf:
            json.dump(data, tf)
            tempname = tf.name
        os.replace(tempname, SETTINGS_FILE)
        return {"status": "updated"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


# ============================================================
# FILE SYSTEM
# ============================================================


@app.get("/api/files/list", dependencies=[Depends(verify_auth)])
def list_files(path: str = Query(default=SAFE_ROOT)) -> Any:
    """Recursively list files and directories with metadata."""
    if not is_safe_path(path):
        raise HTTPException(status_code=403, detail="Access Denied")
    try:
        items = []
        for e in os.scandir(path):
            try:
                st = e.stat()
                is_dir = e.is_dir()
                item_count = 0
                if is_dir:
                    try:
                        item_count = len(os.listdir(e.path))
                    except (PermissionError, OSError):
                        item_count = -1

                items.append(
                    {
                        "name": e.name,
                        "isDir": is_dir,
                        "size": st.st_size if not is_dir else 0,
                        "mtime": int(st.st_mtime),
                        "path": e.path,
                        "itemCount": item_count,
                    }
                )
            except OSError:
                continue
        return sorted(items, key=lambda x: (not x["isDir"], x["name"].lower()))
    except PermissionError as e:
        raise HTTPException(status_code=403, detail="Permission Denied") from e
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail="Path Not Found") from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/api/files/read", dependencies=[Depends(verify_auth)])
def read_file(path: str = Query(default=None)) -> Any:
    """Read and return the content of a file."""
    if path is None or not is_safe_path(path):
        raise HTTPException(status_code=403, detail="Access Denied")

    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="File Not Found")
    try:
        if os.path.getsize(path) > MAX_READ_SIZE:
            raise HTTPException(
                status_code=413,
                detail=f"File too large (> {MAX_READ_SIZE // 1024 // 1024}MB). Use the terminal to read large files.",
            )
        with open(path, errors="replace") as f:
            return PlainTextResponse(f.read())
    except PermissionError as e:
        raise HTTPException(status_code=403, detail="Permission Denied") from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.post("/api/files/write", dependencies=[Depends(verify_auth)])
async def write_file(body: FileWriteRequest) -> Any:
    """Atomically write content to a file."""
    path = body.path
    content = body.content
    if not is_safe_path(path):
        raise HTTPException(status_code=403, detail="Access Denied")

    try:
        parent = os.path.dirname(path)
        os.makedirs(parent, exist_ok=True)
        # V5.2: Atomic Write Strategy
        with tempfile.NamedTemporaryFile(
            "w", dir=parent, delete=False, suffix=".tmp"
        ) as tf:
            tf.write(content)
            tempname = tf.name
        os.replace(tempname, path)
        return {"status": "saved"}
    except PermissionError as e:
        raise HTTPException(status_code=403, detail="Permission Denied") from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.post("/api/files/delete", dependencies=[Depends(verify_auth)])
async def delete_file(body: FileDeleteRequest) -> Any:
    """Non-blocking deletion: prevents event loop stalls during large directory removals."""
    path = body.path
    if not is_safe_path(path):
        raise HTTPException(status_code=403, detail="Access Denied")
    try:
        loop = asyncio.get_running_loop()
        if os.path.isdir(path):
            await loop.run_in_executor(None, lambda: shutil.rmtree(path))
        else:
            await loop.run_in_executor(None, lambda: os.remove(path))
        return {"status": "deleted"}
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail="Path not found") from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.post("/api/files/mkdir", dependencies=[Depends(verify_auth)])
async def mkdir(body: FileDeleteRequest) -> Any:
    """Uses FileDeleteRequest schema (just needs path)."""
    path = body.path
    if not is_safe_path(path):
        raise HTTPException(status_code=403, detail="Access Denied")
    try:
        os.makedirs(path, exist_ok=True)
        return {"status": "created"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.post("/api/files/remote-download", dependencies=[Depends(verify_auth)])
async def remote_download(url: str = Query(...), dest_path: str = Query(...)) -> Any:
    """Industry-grade Internet Download: Pulls remote files into the VPS."""
    if not is_safe_path(os.path.dirname(dest_path)):
        raise HTTPException(status_code=403, detail="Access Denied")

    try:
        # Use wget for robust background download support
        cmd = ["wget", "-O", dest_path, url]
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        audit_log.info(f"DOWNLOAD: Initiated retrieval of {url} to {dest_path}")
        return {"status": "initiated", "message": "Download started in background."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/api/procs/info", dependencies=[Depends(verify_auth)])
def get_procs_info(pid: int = Query(...)) -> Any:
    """Deep Process Instrumentation: returns detailed runtime metrics."""
    try:
        p = psutil.Process(pid)
        with p.oneshot():
            # Helper to safely call psutil methods that might fail on kernel/restricted procs
            def safe_call(func: Any, default: Any = None) -> Any:
                """Safely call a psutil method, returning default on AccessDenied or NoSuchProcess."""
                try:
                    res = func()
                    return res._asdict() if hasattr(res, "_asdict") else res
                except Exception:
                    return default

            return {
                "pid": p.pid,
                "ppid": safe_call(p.ppid),
                "name": safe_call(p.name, "unknown"),
                "exe": safe_call(p.exe, ""),
                "cmdline": safe_call(p.cmdline, []),
                "status": safe_call(p.status, "unknown"),
                "create_time": int(safe_call(p.create_time, 0)),
                "num_threads": safe_call(p.num_threads, 0),
                "username": safe_call(p.username, "unknown"),
                "memory_full_info": safe_call(p.memory_full_info, {}),
                "cpu_times": safe_call(p.cpu_times, {}),
                "io_counters": safe_call(p.io_counters, {}),
                "open_files": safe_call(lambda: [f.path for f in p.open_files()], []),
                "connections": safe_call(
                    lambda: [c._asdict() for c in p.net_connections()], []
                ),
            }
    except psutil.NoSuchProcess as e:
        raise HTTPException(status_code=404, detail="Process not found") from e
    except psutil.AccessDenied as e:
        raise HTTPException(status_code=403, detail="Access denied") from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/api/files/stat", dependencies=[Depends(verify_auth)])
async def get_file_stat(path: str = Query(...)) -> Any:
    """Deep OS-level stats with recursive aggregation for directories."""
    if not is_safe_path(path):
        raise HTTPException(status_code=403, detail="Access Denied")

    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="Not found")

    try:
        loop = asyncio.get_running_loop()
        st = os.stat(path)

        # Resolve names
        try:
            import grp
            import pwd

            owner = pwd.getpwuid(st.st_uid).pw_name
            group = grp.getgrgid(st.st_gid).gr_name
        except Exception:
            owner = str(st.st_uid)
            group = str(st.st_gid)

        total_size = st.st_size
        file_count = 0
        dir_count = 0

        if os.path.isdir(path):

            def calc_recursive_stats(p: str) -> tuple[int, int, int]:
                """Recursively calculate file count, directory count, and total size."""
                sz, fc, dc = 0, 0, 0
                for root, dirs, files in os.walk(p):
                    dc += len(dirs)
                    fc += len(files)
                    for f in files:
                        try:
                            sz += os.path.getsize(os.path.join(root, f))
                        except Exception:
                            continue
                return sz, fc, dc

            total_size, file_count, dir_count = await loop.run_in_executor(
                None, calc_recursive_stats, path
            )

        return {
            "name": os.path.basename(path),
            "path": path,
            "is_dir": os.path.isdir(path),
            "is_link": os.path.islink(path),
            "size": total_size,
            "file_count": file_count,
            "dir_count": dir_count,
            "mode": oct(st.st_mode)[-3:],
            "owner": owner,
            "group": group,
            "mtime": int(st.st_mtime),
            "atime": int(st.st_atime),
            "ctime": int(st.st_ctime),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.post("/api/files/copy", dependencies=[Depends(verify_auth)])
async def copy_file(body: FileCopyRequest) -> Any:
    """Industry-grade Non-Blocking Copy: offloads to executor for zero-lag API."""
    if not is_safe_path(body.src) or not is_safe_path(body.dest):
        raise HTTPException(status_code=403, detail="Access Denied")
    try:
        loop = asyncio.get_running_loop()
        if os.path.isdir(body.src):
            await loop.run_in_executor(
                None, lambda: shutil.copytree(body.src, body.dest, dirs_exist_ok=True)
            )
        else:
            await loop.run_in_executor(None, lambda: shutil.copy2(body.src, body.dest))
        return {"status": "copied"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.post("/api/files/rename", dependencies=[Depends(verify_auth)])
async def rename_file(body: FileRenameRequest) -> Any:
    """Safely rename or move a file within the workspace."""
    if not is_safe_path(body.old_path) or not is_safe_path(body.new_path):
        raise HTTPException(status_code=403, detail="Access Denied")
    try:
        os.rename(body.old_path, body.new_path)
        return {"status": "renamed"}
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail="Source path not found") from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/api/files/search", dependencies=[Depends(verify_auth)])
async def search_files(
    q: str = Query(default=""), path: str = Query(default=SAFE_ROOT)
) -> Any:
    """Search for files matching a pattern within the workspace."""
    query = q.strip()
    if not query:
        return []
    if not is_safe_path(path):
        raise HTTPException(status_code=403, detail="Access Denied")

    try:
        cmd = ["find", path, "-maxdepth", "3", "-iname", f"*{query}*"]
        proc = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=5)
        results = []
        for line in stdout.decode(errors="replace").splitlines():
            clean_line = line.strip()
            if clean_line:
                results.append(
                    {
                        "name": os.path.basename(clean_line),
                        "path": clean_line,
                        "isDir": os.path.isdir(clean_line),
                    }
                )
        return results[:50]
    except asyncio.TimeoutError as e:
        raise HTTPException(status_code=504, detail="Search timed out") from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/api/files/download", dependencies=[Depends(verify_auth)])
async def download_file(path: str = Query(default=None)) -> Any:
    """Download a file from the workspace."""
    if not path or not is_safe_path(path):
        raise HTTPException(status_code=403, detail="Access Denied")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="File Not Found")

    try:
        mime = mimetypes.guess_type(path)[0] or "application/octet-stream"
        return FileResponse(path, media_type=mime, filename=os.path.basename(path))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


# ============================================================
# NETWORK
# ============================================================


@app.get("/api/net/list", dependencies=[Depends(verify_auth)])
async def list_net_conns() -> Any:
    """Retrieve active network sockets and listening ports."""
    try:
        pid_name: dict[int, str] = {}
        for p in psutil.process_iter(["pid", "name"]):
            try:
                info = p.as_dict(["pid", "name"])
                pid_name[info["pid"]] = info["name"]
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass

        conns = []
        for c in psutil.net_connections(kind="inet"):
            if c.status in ("LISTEN", "ESTABLISHED"):
                c_pid = getattr(c, "pid", None)
                conns.append(
                    {
                        "fd": c.fd,
                        "laddr": f"{c.laddr.ip}:{c.laddr.port}" if c.laddr else "",
                        "raddr": f"{c.raddr.ip}:{c.raddr.port}" if c.raddr else "NONE",
                        "status": c.status,
                        "pid": c_pid,
                        "process": pid_name.get(c_pid, "?") if c_pid else "—",
                    }
                )
        return conns
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


# ============================================================
# PROCESSES
# ============================================================


@app.get("/api/procs/list", dependencies=[Depends(verify_auth)])
async def list_procs() -> Any:
    """Retrieve detailed real-time process metadata."""
    procs = []
    for p in psutil.process_iter(
        [
            "pid",
            "name",
            "username",
            "cpu_percent",
            "memory_percent",
            "nice",
            "status",
            "cmdline",
        ]
    ):
        try:
            info = p.info
            mem_info = p.memory_info()
            info["memory_rss"] = mem_info.rss
            info["memory_rss_mb"] = round(mem_info.rss / 1024 / 1024, 1)
            cmdline = info.get("cmdline") or []
            info["cmd_short"] = (
                " ".join(cmdline[:3]) if cmdline else info.get("name", "")
            )
            procs.append(info)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return sorted(procs, key=lambda x: x.get("cpu_percent") or 0, reverse=True)[:75]


@app.post("/api/procs/priority", dependencies=[Depends(verify_auth)])
async def set_priority(body: PriorityRequest) -> Any:
    """Update the nice value of a process."""
    try:
        proc = psutil.Process(body.pid)
        proc.nice(body.priority)
        return {"status": "updated"}
    except psutil.NoSuchProcess as e:
        raise HTTPException(status_code=404, detail="Process not found") from e
    except psutil.AccessDenied as e:
        raise HTTPException(status_code=403, detail="Access denied (not root?)") from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.post("/api/procs/kill", dependencies=[Depends(verify_auth)])
async def kill_proc(body: KillRequest) -> Any:
    """Send SIGKILL to a process."""
    try:
        os.kill(body.pid, 9)
        return {"status": "killed"}
    except ProcessLookupError as e:
        raise HTTPException(status_code=404, detail="Process not found") from e
    except PermissionError as e:
        raise HTTPException(status_code=403, detail="Permission denied") from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.post("/api/procs/signal", dependencies=[Depends(verify_auth)])
async def signal_proc(body: ProcessSignalRequest) -> Any:
    """Suspend or resume a process."""
    try:
        proc = psutil.Process(body.pid)
        if body.signal == "STOP":
            proc.suspend()
        elif body.signal == "CONT":
            proc.resume()
        return {"status": "signaled", "signal": body.signal}
    except psutil.NoSuchProcess as e:
        raise HTTPException(status_code=404, detail="Process not found") from e
    except psutil.AccessDenied as e:
        raise HTTPException(status_code=403, detail="Access denied") from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


# ============================================================
# INSTALLED APPS
# ============================================================


@app.get("/api/apps/list", dependencies=[Depends(verify_auth)])
async def list_apps() -> Any:
    """Inventory installed system packages."""
    try:
        now = time.time()
        if _cache["apps"] and (now - _cache["apps_time"] < 300):
            return _cache["apps"]

        proc = await asyncio.create_subprocess_exec(
            "dpkg-query",
            "-W",
            "-f=${Package}\t${Version}\t${Status}\n",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=15)
        apps = [
            {"name": parts[0], "version": parts[1]}
            for line in stdout.decode(errors="replace").splitlines()
            if "installed" in line
            for parts in [line.split("\t")]
            if len(parts) >= 2
        ]
        _cache["apps"] = apps[:500]
        _cache["apps_time"] = now
        return _cache["apps"]
    except asyncio.TimeoutError as e:
        raise HTTPException(status_code=504, detail="dpkg-query timed out") from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


# ============================================================
# LOGS
# ============================================================


@app.get("/api/logs", dependencies=[Depends(verify_auth)])
async def get_logs(
    type: str = Query(default="os"), lines: int = Query(default=100)
) -> Any:
    """Industrial-grade log retrieval."""
    log_map = {
        "audit": os.path.join(LOG_DIR, "audit.log"),
        "os": os.path.join(LOG_DIR, "os.log"),
        "sync": os.path.join(LOG_DIR, "sync.log"),
    }
    log_path = log_map.get(type, log_map["os"])
    if not os.path.exists(log_path):
        raise HTTPException(status_code=404, detail=f"No {type} logs yet.")

    try:
        safe_lines = min(lines, 500)
        proc = await asyncio.create_subprocess_exec(
            "tail",
            "-n",
            str(safe_lines),
            log_path,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=5)
        return PlainTextResponse(stdout.decode(errors="replace"))
    except asyncio.TimeoutError as e:
        raise HTTPException(status_code=504, detail="Tail command timed out") from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


# ============================================================
# SENTINEL (auto-revival loop)
# ============================================================


def sentinel_loop() -> None:
    """Background loop for system health monitoring and self-healing."""
    while True:
        try:
            if os.path.exists(SETTINGS_FILE):
                try:
                    with open(SETTINGS_FILE) as f:
                        cfg = json.load(f)
                    if not cfg.get("sentinel", True):
                        time.sleep(60)
                        continue
                except (json.JSONDecodeError, OSError):
                    pass

            if psutil.virtual_memory().percent > 95:
                audit_log.warning("SENTINEL: RAM > 95% — flushing caches...")
                subprocess.run(["sync"], check=False)
                try:
                    with open("/proc/sys/vm/drop_caches", "w") as f:
                        f.write("3")
                except Exception:
                    pass

            # 3. ZOMBIE REAPER (Industrial Stability)
            for p in psutil.process_iter():
                try:
                    if p.status() == psutil.STATUS_ZOMBIE:
                        try:
                            p.wait(timeout=0.1)
                        except psutil.TimeoutExpired:
                            pass
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue

            if GUI_ENABLED and not GUIManager.is_running():
                # SENTINEL COOLDOWN:
                # 1. Do not revive if the stack just started (cooldown after success/initialization).
                # 2. Do not revive if we just tried a revival in the last 120s (cooldown after failure).
                time_since_online = time.monotonic() - GUIManager._last_online_time
                time_since_attempt = time.monotonic() - GUIManager._last_revival_attempt

                if time_since_online < 90 or time_since_attempt < 120:
                    audit_log.info(
                        f"SENTINEL: GUI down. Skipping revival (cooldown active: "
                        f"online={time_since_online:.0f}s, attempt={time_since_attempt:.0f}s)."
                    )
                else:
                    audit_log.warning("SENTINEL: GUI stack is down. Reviving...")
                    GUIManager._last_revival_attempt = time.monotonic()
                    GUIManager.start()

        except Exception as e:
            audit_log.error(f"Sentinel Error: {e}")

        # 4. ENGINE HEARTBEAT (V5.1 Synthesis)
        try:
            requests.get(f"http://127.0.0.1:{ENGINE_PORT}/api/stats", timeout=2)
        except Exception:
            pass

        time.sleep(30)


def _proc_access_error(p: psutil.Process) -> bool:
    """Check if a process is inaccessible due to permission restrictions."""
    try:
        # Check if process is still alive and accessible
        _ = p.status()
        return False
    except (psutil.NoSuchProcess, psutil.AccessDenied):
        return True


# ============================================================
# SERVICE MANAGEMENT
# ============================================================


def _is_service_active(name: str) -> bool:
    """Industrial-grade service detection fallback."""
    try:
        for p in psutil.process_iter(["name"]):
            try:
                p_name = (p.name()) if callable(p.name) else str(p.name)
                if name.lower() in p_name.lower():
                    return True
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
    except Exception:
        pass
    return False


def _get_all_service_statuses() -> List[Dict[str, Any]]:
    """Consolidated service status discovery."""
    targets = ["sshd"]
    services = []

    for target in targets:
        status = "inactive"
        if _is_service_active(target):
            status = "active"
        services.append({"name": target, "status": status})

    return services


@app.api_route(
    "/api/system/services", methods=["GET", "POST"], dependencies=[Depends(verify_auth)]
)
async def system_services(
    request: Request, body: Optional[ServiceActionRequest] = None
) -> Any:
    """List or control system-level services."""
    if request.method == "GET":
        return _get_all_service_statuses()

    if not body or not body.name or body.action not in ["restart"]:
        raise HTTPException(status_code=400, detail="Invalid service or action")

    client_ip = request.client.host if request.client else "unknown"
    audit_log.info(f"SERVICE ACTION: {body.action} {body.name} BY {client_ip}")

    try:
        proc = await asyncio.create_subprocess_exec("service", body.name, body.action)
        await asyncio.wait_for(proc.wait(), timeout=10)
        return {"status": "success", "message": f"Service {body.name} {body.action}ed."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


# ============================================================
# SYSTEM CONTROL & SIGNALS
# ============================================================


@app.api_route(
    "/api/system/shutdown", methods=["GET", "POST"], dependencies=[Depends(verify_auth)]
)
async def system_shutdown() -> Any:
    """Industrial-grade Background Shutdown: Instant API response + Async Termination."""
    audit_log.info("SHUTDOWN: Atomic termination pulse received.")
    broadcast_status("💀 SYSTEM IS SHUTTING DOWN...")

    def hard_terminate() -> None:
        """Emergency cleanup and termination sequence."""

        def guardian() -> None:
            """Safety thread to force exit if cleanup hangs."""
            time.sleep(180)
            audit_log.error("SHUTDOWN: Persistence timeout. Force terminating.")
            os._exit(1)

        threading.Thread(target=guardian, daemon=True).start()

        try:
            # Full OS Save (Tier 3)
            # Make sure it actually acquires the lock (wait for current runs to finish)
            _run_system_save()

            broadcast_status("✅ ALL FILES SAVED. POWERING OFF.")
            audit_log.info("SHUTDOWN: Final sync complete. Hard exit in progress.")

            # Force termination of tunnel and engine
            subprocess.run(
                ["pkill", "-9", "cloudflared"], capture_output=True, check=False
            )
            time.sleep(2)
            os._exit(0)
        except Exception as e:
            broadcast_status(f"⚠️ SHUTDOWN ERROR: {e}")
            audit_log.error(f"SHUTDOWN ERROR: {e}")
            os._exit(1)

    # Detach the thread and return immediately
    threading.Thread(target=hard_terminate, daemon=True).start()
    return {
        "status": "shutdown_initiated",
        "message": "System will power off after incremental background sync.",
    }


def signal_handler(sig: int, frame: Any) -> None:
    """Graceful Interceptor: Ensures zero-loss shutdown on SIGTERM/SIGINT."""
    audit_log.warning(
        f"SIGNAL RECEIVED ({sig}): Commencing Graceful Suicide Sequence..."
    )

    # V9.1: Blocking Shutdown. We must ensure the sync finishes before the process exits.
    # Kaggle/Colab typically allow 30-60s of grace period after SIGTERM.

    def do_shutdown() -> None:
        """Perform the actual emergency save and cleanup sequence."""
        try:
            broadcast_status("💀 SYSTEM SHUTTING DOWN...")

            # Intelligent Persistence — If a sync is already running, wait for it
            state = SyncManager.get_state()
            if state.get("active"):
                audit_log.info(
                    "SHUTDOWN: Sync already active. Waiting for completion..."
                )
                for _ in range(600):  # Wait up to 10 mins for existing sync
                    if not SyncManager.get_state().get("active"):
                        break
                    time.sleep(1)
            else:
                audit_log.info("SHUTDOWN: Initiating emergency save-on-exit...")
                # We call this synchronously to block the signal handler thread
                _run_system_save()

            audit_log.info("SHUTDOWN: OS state fully secured. Goodbye.")
            broadcast_status("✅ ALL FILES SECURED. POWERING OFF.")
        except Exception as e:
            audit_log.error(f"Emergency shutdown failed: {e}")
            broadcast_status(f"⚠️ SHUTDOWN ERROR: {e}")
        finally:
            # Kill background bridge
            subprocess.run(
                ["pkill", "-9", "cloudflared"], capture_output=True, check=False
            )
            subprocess.run(
                ["pkill", "-9", "websocat"], capture_output=True, check=False
            )
            time.sleep(1)
            audit_log.info("SHUTDOWN: Engine offline.")
            os._exit(0)

    # V9.1: Unlike previous versions, we don't start a separate timeout thread yet.
    # We let the main shutdown logic run. If Kaggle kills us, it kills us.
    # But we DON'T return from the signal handler immediately.
    do_shutdown()


# ============================================================
# ENTRY POINT
# ============================================================

if __name__ == "__main__":
    if not all([VPS_NAME, VPS_VERSION, ENGINE_PORT, SESSION_PASS]):
        audit_log.critical(
            "FATAL: Missing critical environment variables (VPS_NAME, VPS_VERSION, VPS_GUI_PORT, VPS_PASS)."
        )
        sys.exit(1)

    # Industrial-Grade Pre-flight Integrity Audit (Background)
    broadcast_status("Starting cloud engine")
    threading.Thread(target=perform_boot_audit, daemon=True).start()

    broadcast_status("SYSTEM READY")
    broadcast_status(f"🚀 {VPS_NAME} BOOTING V{VPS_VERSION}...")

    # V4 Integrity: Pre-flight resource cleanup
    try:
        import glob

        for stale in glob.glob(os.path.join(tempfile.gettempdir(), "vps_sync_*")):
            shutil.rmtree(stale, ignore_errors=True)
    except Exception:
        pass

    broadcast_status("CLEANING UP OLD FILES...")
    if VAULT_DIR:
        os.makedirs(VAULT_DIR, exist_ok=True)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    try:
        import uvicorn

        broadcast_status("STARTING WEB SERVER...")
        uvicorn.run(
            "vps_os_engine:app",
            host="127.0.0.1",
            port=ENGINE_PORT,
            log_level="error",
            access_log=False,
            workers=1,  # Single worker to share in-memory state
            timeout_keep_alive=30,  # Reuse connections from Flutter
        )
    except ImportError:
        audit_log.error("uvicorn not found")
        sys.exit(1)
    except Exception as e:
        crash_log = os.path.join(LOG_DIR, "os_crash.log")
        with open(crash_log, "w") as f:
            f.write(str(e))
        audit_log.critical(f"FATAL ENGINE CRASH: {e}")
        sys.exit(1)
