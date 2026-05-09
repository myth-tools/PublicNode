"""
==============================================================================
 PUBLICNODE MASTER BUILD SCRIPT
Generates the Kaggle notebook (vps_setup.ipynb) and kernel-metadata.json
from the master vps-config.yaml configuration file.

Usage:
    python3 scripts/master_build_vps.py
    python3 scripts/master_build_vps.py --config vps-config-node2.yaml

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
import base64
import json
import os
import secrets
import sys
from typing import Any, List

import yaml

# Suppress bytecode generation for a clean workspace
sys.dont_write_bytecode = True

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_config(config_path: str) -> dict[str, Any]:
    """Load and validate the YAML config."""
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Config file not found: {config_path}")

    try:
        with open(config_path) as f:
            cfg = yaml.safe_load(f)
        if not isinstance(cfg, dict):
            raise ValueError("Config YAML must be a mapping at the top level.")
        return cfg
    except ImportError:
        # PyYAML not available — parse the subset of values we need via simple grep
        cfg_fallback: dict[str, Any] = {}
        with open(config_path) as f:
            for line in f:
                clean_line = line.strip()
                if clean_line.startswith("#") or ":" not in clean_line:
                    continue
                key, _, val = clean_line.partition(":")
                val = val.split("#")[0].strip()  # Strip inline comments
                cfg_fallback[key.strip()] = val.strip().strip('"').strip("'")
        return cfg_fallback


def load_pyproject(toml_path: str) -> dict[str, Any]:
    """Load project metadata from pyproject.toml via simple line parsing."""
    if not os.path.exists(toml_path):
        raise FileNotFoundError(f"pyproject.toml not found at {toml_path}")

    meta: dict[str, Any] = {}
    current_section = None
    with open(toml_path) as f:
        for line in f:
            clean_line = line.strip()
            if not clean_line or clean_line.startswith("#"):
                continue
            if clean_line.startswith("[") and clean_line.endswith("]"):
                current_section = clean_line[1:-1].strip()
                continue
            if "=" in clean_line and current_section == "project":
                _key, _, val = clean_line.partition("=")
                meta[_key.strip()] = val.strip().strip('"').strip("'")
    return meta


def get(cfg: dict[str, Any], *keys: str, default: Any = None) -> Any:
    """Safely navigate nested dict keys with explicit type support."""
    node: Any = cfg
    for k in keys:
        if not isinstance(node, dict):
            return default
        node = node.get(k, default)
        if node is None:
            return default
    return node


def compute_signal_topic(username: str, topic_prefix: str) -> str:
    """Generate a deterministic signal topic using SHA256."""
    import hashlib

    h = hashlib.sha256(username.encode()).hexdigest()[:12]
    return f"{topic_prefix}-{h}".lower()


def save_session_pass(auth_dir: str, password: str) -> None:
    """Persist the generated session password so 'vps connect' can display it."""
    os.makedirs(auth_dir, exist_ok=True)
    pass_path = os.path.join(auth_dir, "vps.pass")
    with open(pass_path, "w") as f:
        f.write(password)


def ensure_ssh_keys(auth_dir: str) -> str:
    """Ensure a project-specific SSH key pair exists and return the public key."""
    os.makedirs(auth_dir, exist_ok=True)
    priv_path = os.path.join(auth_dir, "id_vps")
    pub_path = priv_path + ".pub"

    if not os.path.exists(priv_path):
        import subprocess

        print("[BUILD] Generating PublicNode SSH keys (Ed25519)...", flush=True)
        try:
            subprocess.run(
                ["ssh-keygen", "-t", "ed25519", "-f", priv_path, "-N", ""],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            os.chmod(priv_path, 0o600)
        except Exception as e:
            print(
                f"[WARN] SSH key generation failed: {e}. Falling back to password-only."
            )
            return ""

    with open(pub_path) as f:
        return f.read().strip()


def prune_stale_logs(log_dir: str) -> None:
    """Remove stale logs from a previous session for a clean build."""
    import shutil

    if os.path.exists(log_dir):
        shutil.rmtree(log_dir)
    os.makedirs(log_dir, exist_ok=True)


def encode_file(path: str) -> str:
    """Read a file and return its content as a Base64 string."""
    if not os.path.exists(path):
        raise FileNotFoundError(f"Asset not found: {path}")
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode()


def build_notebook(
    cfg: dict[str, Any], project_meta: dict[str, Any], auth_dir: str
) -> dict[str, Any]:
    """Build the Kaggle notebook JSON from config values."""
    vps_name = str(get(cfg, "identity", "vps_name"))
    username = str(get(cfg, "identity", "kaggle_username"))
    vps_version = str(get(cfg, "engine", "version"))
    topic_prefix = str(get(cfg, "signal", "topic_prefix"))
    engine_port = 5003  # Internal headless API port
    creator = str(get(cfg, "identity", "creator") or "Unknown")
    organization = str(get(cfg, "identity", "organization") or "Unknown")

    if not all([vps_name, username, vps_version, topic_prefix]):
        raise ValueError("Missing critical identity/version fields in config.")

    ssh_enabled_raw = get(cfg, "engine", "ssh_enabled", default=True)
    ssh_enabled = str(ssh_enabled_raw).lower() in ["true", "1", "yes"]
    ssh_port = get(cfg, "engine", "ssh_port", default=22)

    # GUI configuration is now managed dynamically by the mobile app
    # Placeholder values are used in the notebook and replaced at runtime
    gui_enabled_placeholder = "{{GUI_ENABLED}}"

    gui_resolution = str(get(cfg, "gui", "resolution", default="1920x1080"))
    gui_display = str(get(cfg, "gui", "display", default=":1"))
    gui_port = get(cfg, "gui", "port", default=6080)

    # --- PublicNode SSH Keys ---
    pub_key = ""
    if ssh_enabled:
        pub_key = ensure_ssh_keys(auth_dir)

    boot_timeout = get(cfg, "engine", "engine_boot_timeout_sec", default=120)

    # --- System Vault Auth ---
    hf_repo = str(get(cfg, "identity", "hf_repo") or "vps-vault")
    hf_token = ""
    hf_token_path = os.path.join(auth_dir, "hf.token")
    if os.path.exists(hf_token_path):
        with open(hf_token_path) as f:
            hf_token = f.read().strip()

    # --- Dynamic HF Repo Normalization (Industry Grade) ---
    if hf_repo and "/" not in hf_repo and hf_token:
        try:
            print(f"[BUILD] Pre-flight: Resolving HF Username for {hf_repo}...")
            # Use hf_hub_whoami for lightweight username resolution
            from huggingface_hub import HfApi

            api = HfApi(token=hf_token)
            user_info = api.whoami()
            username_hf = user_info.get("name")
            if username_hf:
                normalized = f"{username_hf}/{hf_repo}"
                print(f"[BUILD] ✅ Normalized HF Repo: {hf_repo} -> {normalized}")
                hf_repo = normalized
        except Exception as e:
            print(f"[BUILD] ⚠️ HF Normalization skipped: {e}")
    # --- Build-Time Geolocation Hint (Ultra-Accurate) ---
    build_tz = "UTC"
    try:
        import requests

        # Detect the builder's location (user's machine) to provide a deployment hint
        res = requests.get("https://freeipapi.com/api/json", timeout=3).json()
        build_tz = res.get("timezone", "UTC")
    except Exception:
        # Fallback to local system timezone if API fails
        try:
            import time

            build_tz = time.tzname[0]
        except Exception:
            pass

    default_sys_pkgs = [
        "curl",
        "wget",
        "git",
        "sudo",
        "zsh",
        "zstd",
        "tar",
        "fzf",
        "bat",
        "fd-find",
        "htop",
        "jq",
        "xz-utils",
        "git-lfs",
    ]
    gui_sys_pkgs = [
        "thunar",
        "xfwm4",
        "xfce4-panel",
        "xfce4-session",  # Fixes SESSION_MANAGER missing warnings
        "xfdesktop4",  # Native XFCE desktop background manager
        "xfce4-settings",  # Needed for xfwm4 themes and settings daemon
        "tumbler",  # Fixes 'Thumbnailer failed' warnings
        "pm-utils",  # Fixes 'pm-is-supported' missing warnings
        "upower",  # Fixes 'Couldn't connect to proxy' warnings
        "xfce4-terminal",  # Native XFCE terminal, silences 'limited support' warnings
        "x11-utils",
        "x11-xserver-utils",
        "dbus-x11",
        "xfonts-base",
        "python3-xdg",
        "materia-gtk-theme",  # High-end Dark Theme
        "papirus-icon-theme",  # Modern clean icons
        "fonts-roboto",  # Professional typography
        "mousepad",  # Modern lightweight text editor
    ]

    sys_pkgs_list: List[str] = get(
        cfg,
        "packages",
        "system",
        default=default_sys_pkgs,
    )
    if ssh_enabled and "openssh-server" not in sys_pkgs_list:
        sys_pkgs_list.append("openssh-server")

    sys_pkgs = " ".join(p for p in sys_pkgs_list)

    py_pkgs_list: List[str] = get(
        cfg,
        "packages",
        "python",
        default=[
            "kaggle",
            "huggingface_hub",
            "psutil",
            "requests",
            "fastapi",
            "uvicorn[standard]",
            "python-multipart",
            "watchdog",
            "hf_transfer",
        ],
    )
    if "huggingface_hub" not in py_pkgs_list:
        py_pkgs_list.append("huggingface_hub")
    if "hf_transfer" not in py_pkgs_list:
        py_pkgs_list.append("hf_transfer")
    if "fastapi" not in py_pkgs_list:
        py_pkgs_list.append("fastapi")
    if "uvicorn[standard]" not in py_pkgs_list:
        py_pkgs_list.append("uvicorn[standard]")
    if "python-multipart" not in py_pkgs_list:
        py_pkgs_list.append("python-multipart")
    py_pkgs = " ".join(p for p in py_pkgs_list)

    signal_topic = compute_signal_topic(username, topic_prefix)
    vault_slug = get(cfg, "persistence", "vault_slug", default="vps-storage")
    vps_pass = secrets.token_urlsafe(12)

    # --- PublicNode Inlining (Read OS Assets) ---
    engine_path = os.path.join(REPO_ROOT, "vps-os", "vps_os_engine.py")
    print(f"[DEBUG] Reading engine from: {engine_path}")
    with open(engine_path) as f:
        preview = f.read(5000)
        if 'app.get("/", methods=' in preview:
            print("[DEBUG] WARNING: STILL HAS APP.GET IN SOURCE!")
        elif 'app.api_route("/", methods=' in preview:
            print("[DEBUG] SUCCESS: SOURCE HAS API_ROUTE.")
        else:
            print("[DEBUG] NEITHER FOUND IN PREVIEW.")

    os_engine_b64 = encode_file(engine_path)

    save_session_pass(auth_dir, vps_pass)

    log_dir = os.path.join(REPO_ROOT, "publicnode-vps-engine", "vps-os", "logs")
    prune_stale_logs(log_dir)

    nb = {
        "cells": [
            {
                "cell_type": "markdown",
                "metadata": {},
                "source": [f"# {vps_name} (PERSISTENT DYNAMIC-EDGE)\n"],
            },
            {
                "cell_type": "markdown",
                "metadata": {},
                "source": ["## ⚙️ Stage 0: Global Runtime Config\n"],
            },
            {
                "cell_type": "code",
                "execution_count": None,
                "metadata": {},
                "outputs": [],
                "source": [
                    "# --- PublicNode Core Config ---\n",
                    "import base64\n",
                    "import os\n",
                    "import secrets\n",
                    "import subprocess\n",
                    "import sys\n",
                    "import threading\n",
                    "import time\n",
                    "from pathlib import Path\n",
                    "\n",
                    "os.environ['PYDEVD_DISABLE_FILE_VALIDATION'] = '1'\n",
                    "os.environ['PYTHONPATH'] = '/kaggle/working:/kaggle/working/vps-os'\n",
                    f"VPS_NAME    = '{vps_name}'\n",
                    f"VPS_VERSION = '{vps_version}'\n",
                    "\n",
                    f"SIGNAL_TOPIC   = '{signal_topic}'\n",
                    f"VPS_PASS_B64   = '{base64.b64encode(vps_pass.encode()).decode()}'\n",
                    "VPS_PASS       = base64.b64decode(VPS_PASS_B64).decode()\n",
                    f"ENGINE_PORT    = {engine_port}\n",
                    f"GUI_PKGS       = '{' '.join(gui_sys_pkgs)}'\n",
                    f"BOOT_TIMEOUT   = {boot_timeout}\n",
                    f"KAG_USER       = '{username}'\n",
                    f"VAULT_SLUG     = '{vault_slug}'\n",
                    f"HF_REPO        = '{hf_repo}'\n",
                    f"HF_TOKEN       = '{hf_token}'\n",
                    f"CREATOR        = '{creator}'\n",
                    f"ORGANIZATION   = '{organization}'\n",
                    f"BUILD_TZ       = '{build_tz}'\n",
                    f"GUI_ENABLED    = '{gui_enabled_placeholder}'\n",
                    "HEADLESS_MODE  = str(GUI_ENABLED).lower() != 'true'\n",
                    f"GUI_RESOLUTION = '{gui_resolution}'\n",
                    f"GUI_DISPLAY    = '{gui_display}'\n",
                    f"GUI_PORT       = {gui_port}\n",
                    "BOOT_TIME      = time.time()\n",
                    "\n",
                    "SESSION_ID     = secrets.token_hex(4)\n",
                    "os.environ['SESSION_ID'] = SESSION_ID\n",
                    "os.environ['VPS_PASS'] = VPS_PASS\n",
                    "os.environ['VPS_NAME'] = VPS_NAME\n",
                    "os.environ['VPS_VERSION'] = VPS_VERSION\n",
                    "os.environ['VPS_SIGNAL_TOPIC'] = SIGNAL_TOPIC\n",
                    "os.environ['KAG_USER'] = KAG_USER\n",
                    "os.environ['VAULT_SLUG'] = VAULT_SLUG\n",
                    "os.environ['HF_REPO'] = HF_REPO\n",
                    "os.environ['HF_TOKEN'] = HF_TOKEN\n",
                    "os.environ['CREATOR'] = CREATOR\n",
                    "os.environ['ORGANIZATION'] = ORGANIZATION\n",
                    "os.environ['GUI_ENABLED'] = GUI_ENABLED\n",
                    "os.environ['GUI_RESOLUTION'] = GUI_RESOLUTION\n",
                    "os.environ['GUI_DISPLAY'] = GUI_DISPLAY\n",
                    "os.environ['GUI_PORT'] = str(GUI_PORT)\n",
                    "os.environ['ORGANIZATION'] = ORGANIZATION\n",
                    "\n",
                    "def _acquire_singleton_lock():\n",
                    "    pid_file = '/tmp/vps_master.pid'\n",
                    "    if os.path.exists(pid_file):\n",
                    "        try:\n",
                    "            with open(pid_file) as f:\n",
                    "                old_pid = int(f.read().strip())\n",
                    "            os.kill(old_pid, 0)\n",
                    "            print(f'\\n[SYSTEM] Master process already active (PID: {old_pid}). Exiting silently.\\n', flush=True)\n",
                    "            os._exit(0)\n",
                    "        except (OSError, ValueError):\n",
                    "            os.remove(pid_file)\n",
                    "    with open(pid_file, 'w') as f:\n",
                    "        f.write(str(os.getpid()))\n",
                    "\n",
                    "_acquire_singleton_lock()\n",
                    "sys.dont_write_bytecode = True\n",
                    "os.system('mkdir -p logs && truncate -s 0 logs/master.log')\n",
                    "# --- Pre-flight: purge any stale processes and MOTD noise ---\n",
                    "os.system('pkill -9 cloudflared || true')\n",
                    "os.system('pkill -9 sshd || true')\n",
                    "os.system('pkill -9 tmux || true')\n",
                    "os.system('rm -rf /tmp/tmux* /tmp/vps_tmux.sock || true')\n",
                    "# Industrial MOTD & Ubuntu Detail Purge (V7.0)\n",
                    "os.system('touch /root/.hushlogin')\n",
                    "\n",
                    "# --- Build Shell Profile (V5.3: Robust tmux Backbone) ---\n",
                    'Path(\'/root/.bashrc\').write_text("""\n',
                    "export PS1='-(root@PublicNode)-[\\\\w]\\\\n-\\\\${debian_chroot:+(\\\\${debian_chroot})} \\\\$ '\n",
                    "alias l='lsd -l --group-directories-first'\n",
                    "alias ll='lsd -la --group-directories-first'\n",
                    "\n",
                    "# Auto-attach to persistent tmux session on login (inside PRoot)\n",
                    'if [[ -z "$TMUX" && "$TERM" != "screen" ]]; then\n',
                    "    exec /usr/local/bin/proot -r /kaggle/working/proot_root -b /kaggle/working -b /proc -b /dev -b /sys -w /root tmux -S /tmp/vps_tmux.sock -u new -A -s vps\n",
                    "fi\n",
                    '""")\n',
                ],
            },
            {
                "cell_type": "markdown",
                "metadata": {},
                "source": ["## ⚔️ Stage 1: Kernel Tuning\n"],
            },
            {
                "cell_type": "code",
                "execution_count": None,
                "metadata": {},
                "outputs": [],
                "source": [
                    "import os\n",
                    "import time\n",
                    "\n",
                    "\n",
                    "class VpsArmor:\n",
                    "    @staticmethod\n",
                    "    def log(m, s='◢◤'):\n",
                    "        msg = f'{s} {m}'\n",
                    "        print(f'\\n{msg}\\n', flush=True)\n",
                    "        try:\n",
                    "            os.makedirs('logs', exist_ok=True)\n",
                    "            with open('logs/master.log', 'a') as f:\n",
                    "                f.write(f'[{time.strftime(\"%H:%M:%S\")}] {msg}\\n')\n",
                    "        except Exception:\n",
                    "            pass\n",
                    "        try:\n",
                    "            os.system(f'curl -s -d \"STATUS: [{SESSION_ID}] {msg}\" https://ntfy.sh/{SIGNAL_TOPIC}')\n",
                    "        except Exception:\n",
                    "            pass\n",
                    "\n",
                    "    @staticmethod\n",
                    "    def broadcast(m):\n",
                    '        """Send a base64-encoded signal for WS/PASS as expected by the mobile app."""\n',
                    "        b64 = base64.b64encode(m.encode()).decode()\n",
                    "        try:\n",
                    "            os.system(f'curl -s -d \"{b64}\" https://ntfy.sh/{SIGNAL_TOPIC}')\n",
                    "        except Exception:\n",
                    "            pass\n",
                    "\n",
                    "    @staticmethod\n",
                    "    def wait_locks():\n",
                    "        VpsArmor.log('WAITING FOR SYSTEM PACKAGE LOCKS...', '⏳')\n",
                    "        for _ in range(30):  # Wait max 60s\n",
                    "            if os.system('pgrep -x \"apt|apt-get|dpkg\"') != 0:\n",
                    "                return\n",
                    "            time.sleep(2)\n",
                    "        VpsArmor.log('FORCING LOCK RELEASE (TIMED OUT)...', '⚔️')\n",
                    "        os.system('pkill -9 apt || true')\n",
                    "        os.system('pkill -9 apt-get || true')\n",
                    "        os.system('pkill -9 dpkg || true')\n",
                    "        os.system('rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock* || true')\n",
                    "        os.system('dpkg --configure -a || true')\n",
                    "    @staticmethod\n",
                    "    def robust_install():\n",
                    "        if os.path.exists('/tmp/.vps_provisioning_active'):\n",
                    "            VpsArmor.log('PROVISIONING ALREADY IN PROGRESS. SKIPPING REDUNDANT CALL.', '⏳')\n",
                    "            return\n",
                    "        os.system('touch /tmp/.vps_provisioning_active')\n",
                    "        VpsArmor.log('SYNCING PUBLICNODE ASSETS...')\n",
                    "        VpsArmor.wait_locks()\n",
                    "        # Purge broken or unreachable sources that often hang Kaggle boots\n",
                    "        os.system('rm -f /etc/apt/sources.list.d/*r2u* || true')\n",
                    "        # V9.2: Aggressively nuke any source mentioning launchpad if it's causing timeouts\n",
                    "        os.system('grep -l \"launchpad\" /etc/apt/sources.list.d/*.list | xargs rm -f || true')\n",
                    "        os.system('sed -i \"s/^deb-src/# deb-src/\" /etc/apt/sources.list /etc/apt/sources.list.d/* || true')\n",
                    "        \n",
                    "        # V11.0: Industrial-Grade Mirror Optimization\n",
                    "        VpsArmor.log('OPTIMIZING APT MIRRORS (mirrors.kernel.org)...', '🚀')\n",
                    "        os.system('sed -i \"s|http://archive.ubuntu.com/ubuntu/|http://mirrors.kernel.org/ubuntu/|g\" /etc/apt/sources.list || true')\n",
                    "        os.system('sed -i \"s|http://security.ubuntu.com/ubuntu/|http://mirrors.kernel.org/ubuntu/|g\" /etc/apt/sources.list || true')\n",
                    "        \n",
                    "        # V11.1: Persistent APT Cache Redirection\n",
                    "        VpsArmor.log('CONFIGURING PERSISTENT APT CACHE...', '📦')\n",
                    "        os.system('mkdir -p /kaggle/working/.cache/apt/archives/partial && rm -rf /var/cache/apt/archives && ln -s /kaggle/working/.cache/apt/archives /var/cache/apt/archives')\n",
                    "        \n",
                    "        # APT/UV Resilience: Prevent redundant work across kernel restarts\n",
                    "        if os.path.exists('/tmp/.provisioning_done'):\n",
                    "            VpsArmor.log('PROVISIONING ALREADY COMPLETE. SKIPPING.', '✅')\n",
                    "            return\n",
                    "\n",
                    "        # V10.4: ET Provisioning moved to background for speed.\n",
                    "\n",
                    "        # V10.5: Optimized Sprint-Mode Provisioning (Parallel Wget, Zero Lock Contention)\n",
                    "        VpsArmor.log('STARTING BACKGROUND PROVISIONING (uv, cloudflared, websocat, proot)...', '⚡')\n",
                    "        os.system('mkdir -p /usr/local/bin /root/.cache/huggingface || true')\n",
                    "        os.system('''\n",
                    "            (\n",
                    "                # 1. UV Engine\n",
                    "                [ ! -f /usr/local/bin/uv ] && wget -q https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-unknown-linux-musl.tar.gz -O uv.tar.gz && \\\n",
                    "                tar -xzf uv.tar.gz && mv uv-x86_64-unknown-linux-musl/uv /usr/local/bin/uv && rm -rf uv.tar.gz uv-x86_64-unknown-linux-musl &\n",
                    "                \n",
                    "                # 2. Cloudflared\n",
                    "                [ ! -f /usr/local/bin/cloudflared ] && wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared &\n",
                    "                \n",
                    "                # 3. Websocat\n",
                    "                [ ! -f /usr/local/bin/websocat ] && wget -q https://github.com/vi/websocat/releases/latest/download/websocat.x86_64-unknown-linux-musl -O /usr/local/bin/websocat && chmod +x /usr/local/bin/websocat &\n",
                    "                \n",
                    "                # 4. PRoot Engine\n",
                    "                [ ! -f /usr/local/bin/proot ] && wget -q https://proot.gitlab.io/proot/bin/proot -O /usr/local/bin/proot && chmod +x /usr/local/bin/proot &\n",
                    "                \n",
                    "                wait\n",
                    "                touch /tmp/.provisioning_done\n",
                    "            ) &''')\n",
                    "        # Eternal Terminal: High-Resilience Multi-Mirror Download\n",
                    "        if not os.path.exists('/usr/bin/et'):\n",
                    "             VpsArmor.log('PREPARING ETERNAL TERMINAL...', '📡')\n",
                    "             distro = os.popen('lsb_release -cs').read().strip()\n",
                    "             if distro == 'jammy':\n",
                    "                 mirrors = [\n",
                    '                     "https://raw.githubusercontent.com/myth-tools/PublicNode/main/Packages/et_6.2.10-jammy1_amd64.deb",\n',
                    '                     "https://launchpad.net/~jgmath2000/+archive/ubuntu/et/+files/et_6.2.10-jammy1_amd64.deb",\n',
                    '                     "https://ppa.launchpadcontent.net/jgmath2000/et/ubuntu/pool/main/e/et/et_6.2.10-jammy1_amd64.deb"\n',
                    "                 ]\n",
                    "             else:\n",
                    "                 mirrors = [\n",
                    '                     "https://launchpad.net/~jgmath2000/+archive/ubuntu/et/+files/et_6.2.8-focal2_amd64.deb"\n',
                    "                 ]\n",
                    "             for url in mirrors:\n",
                    "                 VpsArmor.log(f'TRYING ET MIRROR: {url[:50]}...', '📡')\n",
                    "                 # Use curl with 20s timeout and auto-redirect following\n",
                    "                 if os.system(f'curl -L -s -m 20 -f {url} -o /tmp/et.deb') == 0:\n",
                    "                     if os.path.exists('/tmp/et.deb') and os.path.getsize('/tmp/et.deb') > 102400:\n",
                    "                         VpsArmor.log(f'ET DOWNLOAD SUCCESSFUL: {url[:50]}...', '✅')\n",
                    "                         break\n",
                    "             \n",
                    "             if os.path.exists('/tmp/et.deb') and os.path.getsize('/tmp/et.deb') > 102400:\n",
                    "                 VpsArmor.log('INSTALLING ETERNAL TERMINAL...', '📡')\n",
                    "                 os.system('DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/et.deb || true')\n",
                    "             else:\n",
                    "                 VpsArmor.log('ET INSTALLATION SKIPPED: ALL MIRRORS TIMED OUT OR FAILED.', '⚠️')\n",
                    "             os.system('rm -f /tmp/et.deb || true')\n",
                    "             os.system('pkill -9 -f Xvfb; pkill -9 -f x11vnc; true')\n",
                    "        \n",
                    "        # APT Resilience: Set timeouts and aggressive retries for connection issues\n",
                    '        apt_opts = \'-o Acquire::Retries=3 -o Acquire::http::Timeout="30" -o Acquire::https::Timeout="30"\'\n',
                    "        \n",
                    "        # V9.3: Run update ONCE before the loop to save time (Kaggle apt mirrors are slow)\n",
                    "        os.system(f'apt-get update {apt_opts}')\n",
                    "        \n",
                    "        # V10.5: Single Atomic Install (Conditional GUI)\n",
                    "        VpsArmor.log('INSTALLING SYSTEM PACKAGES...')\n",
                    "        extra_pkgs = f'{GUI_PKGS if not HEADLESS_MODE else \"\"}'\n",
                    f"        install_res = os.system(f'DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --fix-missing {{apt_opts}} {sys_pkgs} {{extra_pkgs}}')\n",
                    "        VpsArmor.log(f'PACKAGE INSTALLATION FINISHED (Exit Code: {install_res})', '📦')\n",
                    "        os.system('rm -f /tmp/et.deb || true')\n",
                    "        \n",
                    "        # Move MOTD/SSH Purge HERE (After openssh-server is installed)\n",
                    "        os.system('rm -f /etc/update-motd.d/* /etc/motd /etc/legal /var/run/motd.dynamic || true')\n",
                    "        os.system('truncate -s 0 /etc/motd /etc/legal /var/run/motd.dynamic || true')\n",
                    "        os.system('sed -i \"s/PrintMotd yes/PrintMotd no/\" /etc/ssh/sshd_config || true')\n",
                    "        os.system('sed -i \"s/PrintLastLog yes/PrintLastLog no/\" /etc/ssh/sshd_config || true')\n",
                    "        os.system('sed -i \"/Banner/d\" /etc/ssh/sshd_config || true')\n",
                    "        \n",
                    "        # Final Stabilization: Wait for background tasks (uv, cloudflared)\n",
                    "        VpsArmor.log('STABILIZING ENGINES...', '⏳')\n",
                    "        for _ in range(60):\n",
                    "            if os.path.exists('/tmp/.provisioning_done'): break\n",
                    "            time.sleep(1)\n",
                    "\n",
                    "        if not os.path.exists('/tmp/.vps_py_ready'):\n",
                    "            VpsArmor.log('FINALIZING PYTHON ENVIRONMENT...', '🐍')\n",
                    f"            os.system('/usr/local/bin/uv pip install --system --upgrade --no-cache {py_pkgs}')\n",
                    "            os.system('touch /tmp/.vps_py_ready')\n",
                    "        \n",
                    "\n",
                    "        # --- PublicNode System Vault Pre-flight ---\n",
                    "        os.makedirs('/root/.cache/huggingface', exist_ok=True)\n",
                    "        # --- PublicNode Persistence Prep ---\n",
                    "        os.system('mkdir -p /root/.ssh && chmod 700 /root/.ssh')\n",
                    "        if HF_TOKEN:\n",
                    "            with open('/root/.cache/huggingface/token', 'w') as f:\n",
                    "                f.write(HF_TOKEN)\n",
                    "\n",
                    "        VpsArmor.log('SYSTEM VAULT: Ready for boot-time restoration.', '🔐')\n",
                    "\n",
                    "        if not os.path.exists('/kaggle/working/proot_root'):\n",
                    "            os.makedirs('/kaggle/working/proot_root', exist_ok=True)\n",
                    "            # SMART RECOVERY: The Engine will pull the latest snapshot from HuggingFace on boot.\n",
                    "            # Here we just initialize a fresh base if nothing exists yet.\n",
                    "            recovered = False\n",
                    "            if not recovered:\n",
                    "                VpsArmor.log('SYSTEM VAULT: Initializing ephemeral environment...', '📦')\n",
                    "\n",
                    "        # Fail-safe checks for critical system binaries\n",
                    "        if not os.path.exists('/usr/bin/zsh'):\n",
                    "            os.system(f'apt-get install -y --no-install-recommends {apt_opts} zsh')\n",
                    "        os.system('chsh -s /usr/bin/zsh root || true')\n",
                    "        if not os.path.exists('/usr/sbin/sshd'):\n",
                    "            os.system(f'apt-get install -y --no-install-recommends {apt_opts} openssh-server')\n",
                    "\n",
                    "        # Robust Oh-My-Zsh installation\n",
                    "        if not os.path.exists('/root/.oh-my-zsh'):\n",
                    '            os.system(\'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended\')\n',
                    "\n",
                    "        VpsArmor.log('POLISHING SHELL ARCHITECTURE...', '🐚')\n",
                    "        os.system(f'hostname {VPS_NAME} 2>/dev/null || true')\n",
                    "        os.system('mkdir -p /root/.oh-my-zsh/custom/plugins')\n",
                    "        os.system('git clone -q https://github.com/zsh-users/zsh-autosuggestions /root/.oh-my-zsh/custom/plugins/zsh-autosuggestions')\n",
                    "        os.system('git clone -q https://github.com/zsh-users/zsh-syntax-highlighting /root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting')\n",
                    "        \n",
                    "        # Premium PublicNode Zsh Configuration\n",
                    "        bashrc_parts = [\n",
                    "            'export ZSH=\"/root/.oh-my-zsh\"',\n",
                    "            'ZSH_THEME=\"\"',\n",
                    "            'plugins=(git zsh-autosuggestions zsh-syntax-highlighting fzf)',\n",
                    "            'source $ZSH/oh-my-zsh.sh',\n",
                    "            'export TERM=xterm-256color',\n",
                    "            '',\n",
                    "            '# PublicNode Premium Prompt',\n",
                    "            'NEWLINE=$' + \"'\" + '\\\\n' + \"'\" + '',\n",
                    f"            \"PROMPT='%F{{81}}┌──(%B%F{{33}}%n%b%f%F{{81}}⬢%B%F{{33}}{vps_name}%b%f%F{{81}})─[%B%F{{white}}%~%b%F{{81}}]${{NEWLINE}}└─%B%F{{33}}$%b%f '\",\n",
                    "            '',\n",
                    "            '# Modern CLI Aliases (with fallback checks)',\n",
                    '            \'[ -x "$(command -v lsd)" ] && alias ls="lsd" || alias ls="ls --color=auto"\',\n',
                    '            \'[ -x "$(command -v lsd)" ] && alias l="lsd -l" || alias l="ls -l"\',\n',
                    '            \'[ -x "$(command -v lsd)" ] && alias la="lsd -a" || alias la="ls -A"\',\n',
                    '            \'[ -x "$(command -v lsd)" ] && alias ll="lsd -la" || alias ll="ls -la"\',\n',
                    '            \'[ -x "$(command -v batcat)" ] && alias cat="batcat --paging=never"\',\n',
                    '            \'[ -x "$(command -v fdfind)" ] && alias find="fdfind"\',\n',
                    "            'alias top=\"htop\"',\n",
                    "            '',\n",
                    "            '# PublicNode Industrial Telemetry Banner (V8.1)',\n",
                    "            'OS_NAME=$(grep ^NAME= /etc/os-release | cut -d \"=\" -f 2 | tr -d \\'\"\\')',\n",
                    "            'OS_VER=$(grep ^VERSION_ID= /etc/os-release | cut -d \"=\" -f 2 | tr -d \\'\"\\')',\n",
                    "            'KERNEL=$(uname -r)',\n",
                    "            'UPTIME=$(uptime -p | sed \"s/up //\")',\n",
                    '            \'CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -n 1 | cut -d ":" -f 2 | xargs || uname -m)\',\n',
                    "            'CPU_CORES=$(nproc)',\n",
                    "            'MEM_TOTAL=$(free -h | grep Mem | awk \\'{print $2}\\')',\n",
                    "            'STR_WORK=$(df -h /kaggle/working | tail -1 | awk \\'{print $3 \" / \" $2}\\')',\n",
                    "            'STR_ROOT=$(df -h / | tail -1 | awk \\'{print $2}\\')',\n",
                    "            '# V9: Ultra-Accurate Sync Status (Aware of active background saves)',\n",
                    "            'if [ -f /kaggle/working/logs/vps_save_history.log ]; then STR_INF=\"SYNCED\"; ',\n",
                    "            'elif [ -f /tmp/vps_sync_lock ]; then STR_INF=\"SYNCING...\"; ',\n",
                    "            'else STR_INF=\"UNSYNCED\"; fi',\n",
                    "            'echo -e \"\\033[1;36m◣◥◤◢  \\033[1;37mPUBLICNODE OS \\033[1;32mONLINE \\033[1;36m ◣◥◤◢\\033[0m\"',\n",
                    "            'echo -e \"\\033[1;36mDISTRIBUTION: \\033[0m$OS_NAME $OS_VER ($KERNEL)\"',\n",
                    "            'echo -e \"\\033[1;36mUPTIME:       \\033[0m$UPTIME\"',\n",
                    "            'echo -e \"\\033[1;36mPROCESSOR:    \\033[0m$CPU_MODEL ($CPU_CORES Cores)\"',\n",
                    "            'echo -e \"\\033[1;36mMEMORY:       \\033[0m$MEM_TOTAL\"',\n",
                    "            'echo -e \"\\033[1;36mSTORAGE:      \\033[0mWORKSPACE: $STR_WORK • SYSTEM: $STR_ROOT\"',\n",
                    "            'echo -e \"\\033[1;36mSYSTEM VAULT: \\033[1;32m$STR_INF\\033[0m\"',\n",
                    f"            'echo -e \"\\033[1;36mCREATOR:      \\033[0m{creator}\"',\n",
                    f"            'echo -e \"\\033[1;36mORGANIZATION: \\033[0m{organization}\"',\n",
                    "            '# --- Master PublicNode GUI & Environment Bridge ---',\n",
                    "            'export XDG_RUNTIME_DIR=/tmp/runtime-root',\n",
                    "            'mkdir -p $XDG_RUNTIME_DIR && chmod 700 $XDG_RUNTIME_DIR',\n",
                    "            'if [ -S /tmp/.X11-unix/X1 ]; then',\n",
                    "            '    export DISPLAY=:1',\n",
                    "            '    [ -f /tmp/vps_dbus_env ] && . /tmp/vps_dbus_env > /dev/null 2>&1',\n",
                    "            '    [ -f /tmp/vps_electron_env ] && . /tmp/vps_electron_env > /dev/null 2>&1',\n",
                    "            '    # Self-Healing: Verify D-Bus process is actually alive',\n",
                    "            '    if ! ps -p \"$DBUS_SESSION_BUS_PID\" > /dev/null 2>&1; then eval $(dbus-launch --sh-syntax); fi',\n",
                    "            '    export NO_AT_BRIDGE=1',\n",
                    "            'fi',\n",
                    "            '# --- Universal Forensic Aliases ---',\n",
                    "            'alias sudo=\"sudo -E\"',\n",
                    "            '# --- End Master Bridge ---',\n",
                    "            'echo \"\"'\n",
                    "        ]\n",
                    "        bashrc_content = chr(10).join(bashrc_parts)\n",
                    "        for f_path in ['/root/.bashrc', '/root/.zshrc']:\n",
                    "            try:\n",
                    "                with open(f_path, 'a') as f:\n",
                    "                    f.write(chr(10) + bashrc_content + chr(10))\n",
                    "            except Exception: pass\n",
                    "        VpsArmor.log('RESOURCES ARMORED')\n",
                    "\n",
                    "os.chdir('/kaggle/working')\n",
                    "VpsArmor.log(f'WORKSPACE AUDIT: {os.listdir(\".\")}', '🔍')\n",
                    "for d in ['logs', 'vps-os']:\n",
                    "    Path(d).mkdir(exist_ok=True, parents=True)\n",
                    "\n",
                    "VpsArmor.log('MATERIALIZING ASSETS...', '')\n",
                    f"OS_ENGINE_B64 = '{os_engine_b64}'\n",
                    "with open('vps-os/vps_os_engine.py', 'wb') as f:\n",
                    "    f.write(base64.b64decode(OS_ENGINE_B64))\n",
                    "VpsArmor.log('OS CORE MATERIALIZED')\n",
                    "\n",
                    "# --- Injection: Universal 'vps' CLI for remote use ---\n",
                    "tpl_vps = r'''#!/bin/bash\n",
                    'C_CYAN="\\033[1;36m"\n',
                    'C_NC="\\033[0m"\n',
                    'C_RED="\\033[1;31m"\n',
                    'C_YELLOW="\\033[1;33m"\n',
                    'C_GREEN="\\033[1;32m"\n',
                    'case "$1" in\n',
                    "  sync)   \n",
                    '       echo -e "${C_CYAN}[VAULT]${C_NC} Triggering System Vault Sync..."\n',
                    "       res=$(curl -s localhost:__PORT__/api/sync)\n",
                    '       if [[ $(echo "$res" | jq -r ".status") != "accepted" ]]; then\n',
                    '           echo -e "${C_RED}[ERROR]${C_NC} Sync rejected: $(echo "$res" | jq -r ".message")" ; exit 1\n',
                    "       fi\n",
                    '       echo -e "${C_YELLOW}[SYNC]${C_NC} Job system-vault-sync initiated. Polling status..."\n',
                    "       while true; do\n",
                    "           job=$(curl -s localhost:__PORT__/api/sync/status)\n",
                    '           active=$(echo "$job" | jq -r ".active")\n',
                    '           phase=$(echo "$job" | jq -r ".phase")\n',
                    '           progress=$(echo "$job" | jq -r ".progress")\n',
                    '           msg=$(echo "$job" | jq -r ".message")\n',
                    '           ver=$(echo "$job" | jq -r ".version")\n',
                    '           err_msg=$(echo "$job" | jq -r ".error")\n',
                    '           if [[ "$active" == "false" ]]; then\n',
                    '               if [[ "$err_msg" != "null" && -n "$err_msg" ]]; then\n',
                    '                   echo -e "\\n${C_RED}[CRITICAL]${C_NC} Sync Failed: $err_msg" ; exit 1\n',
                    "               fi\n",
                    '               echo -e "\\n${C_GREEN}[SUCCESS]${C_NC} System Vault Sync Complete (Version: $ver). Backbone locked." ; break\n',
                    "           fi\n",
                    '           printf "\\r${C_CYAN}[%3d%%]${C_NC} Phase: %-10s | %-45s" "$progress" "$phase" "$msg" ; sleep 2\n',
                    "       done ;;\n",
                    "  vault)\n",
                    '    case "$2" in\n',
                    '      push)  echo -e "${C_CYAN}[VAULT]${C_NC} Pushing $3 to Private Vault..."; curl -s "localhost:__PORT__/api/vault/push?path=$3" ;;\n',
                    '      list)  echo -e "${C_CYAN}[VAULT]${C_NC} Listing Private Vault contents:"; curl -s "localhost:__PORT__/api/vault/list" | jq -r \'.files[]\' ;;\n',
                    '      *)     echo -e "Usage: vps vault [push <path> | list]" ;;\n',
                    "    esac ;;\n",
                    '  top)    echo -e "${C_CYAN}[PULSE]${C_NC} Recent Processes:"; curl -s localhost:__PORT__/api/system/pulse | grep -oP \'\\{"pid":\\d+,"name":"[^"]+","cpu_percent":[\\d.]+\' | head -n 12 | sed \'s/\\{"pid"://; s/,"name":"/ | /; s/", "cpu_percent":/ | CPU: /; s/$/% /\' ;;\n',
                    '  logs)   echo -e "${C_CYAN}[SYSTEM]${C_NC} Streaming Telemetry..."; tail -f /kaggle/working/logs/master.log ;;\n',
                    "  status) curl -s localhost:__PORT__/api/stats ;;\n",
                    '  *)      echo -e "◢◤ PublicNode Remote CLI v__VER__\\nUsage: vps [sync|vault|top|logs|status]" ;;\n',
                    "esac\n",
                    "'''\n",
                    f"remote_cli = tpl_vps.replace('__PORT__', '{engine_port}').replace('__VER__', '{vps_version}')\n",
                    'with open("/usr/local/bin/vps", "w") as f:\n',
                    "    f.write(remote_cli)\n",
                    'os.system("chmod +x /usr/local/bin/vps")\n',
                    "\n",
                    "# --- Injection: Autonomous Interceptors (apt/pip/npm) ---\n",
                    "SYSTEM_STATE_DIR = '/kaggle/working/vault/system_state'\n",
                    "os.system(f'mkdir -p {SYSTEM_STATE_DIR}')\n",
                    "tpl_wrapper = r'''#!/bin/bash\n",
                    'CMD=$(basename "$0")\n',
                    'REAL_CMD=""\n',
                    "for p in /usr/bin /bin /usr/sbin /sbin; do\n",
                    '  if [[ -x "$p/$CMD" && "$p" != "/usr/local/bin" ]]; then REAL_CMD="$p/$CMD"; break; fi\n',
                    "done\n",
                    'if [[ -z "$REAL_CMD" ]]; then REAL_CMD=$(which -a "$CMD" | grep -v "/usr/local/bin" | head -n 1); fi\n',
                    'if [[ -z "$REAL_CMD" ]]; then echo "Command not found"; exit 1; fi\n',
                    '"$REAL_CMD" "$@"\n',
                    "RET=$?\n",
                    "if [ $RET -eq 0 ]; then\n",
                    '  if [[ " $* " =~ " install " || " $* " =~ " upgrade " || " $* " =~ " remove " ]]; then\n',
                    '    echo "$CMD $@" >> __STATE_DIR__/restore.sh\n',
                    "  fi\n",
                    "fi\n",
                    "exit $RET\n",
                    "'''\n",
                    "wrapper = tpl_wrapper.replace('__STATE_DIR__', SYSTEM_STATE_DIR)\n",
                    "for cmd in ['apt', 'apt-get', 'pip', 'npm']:\n",
                    "    with open(f'/usr/local/bin/{cmd}', 'w') as f:\n",
                    "        f.write(wrapper)\n",
                    "os.system('chmod +x /usr/local/bin/apt /usr/local/bin/apt-get /usr/local/bin/pip /usr/local/bin/npm')\n",
                    "\n",
                    "\n",
                    "if os.path.exists('.vps_auth/kaggle.json'):\n",
                    "    os.system('mkdir -p ~/.kaggle && cp .vps_auth/kaggle.json ~/.kaggle/kaggle.json && chmod 600 ~/.kaggle/kaggle.json')\n",
                    "try:\n",
                    "    VpsArmor.robust_install()\n",
                    "except Exception as e:\n",
                    "    VpsArmor.log(f'CRITICAL BOOT FAILURE: {e}', '❌')\n",
                    "    import traceback\n",
                    "    traceback.print_exc()\n",
                    "    sys.exit(1)\n",
                ],
            },
            {
                "cell_type": "markdown",
                "metadata": {},
                "source": ["## 🔄 Stage 2: PublicNode Restoration\n"],
            },
            {
                "cell_type": "code",
                "execution_count": None,
                "metadata": {},
                "outputs": [],
                "source": [
                    "if os.path.exists('/kaggle/input/vps-storage'):\n",
                    "    # Kaggle mounts datasets as uncompressed directories automatically\n",
                    "    # We just need to sync the contents back to /kaggle/working\n",
                    "    VpsArmor.log('RESTORE PULSE: Synchronizing State from Vault', '📦')\n",
                    "    ret = os.system('rsync -a /kaggle/input/vps-storage/ /kaggle/working/')\n",
                    "    if ret == 0:\n",
                    "        VpsArmor.log('RESTORE COMPLETE')\n",
                    "    else:\n",
                    "        VpsArmor.log(f'RESTORE FAILED (exit {ret}). Continuing with clean workspace.', '⚠️')\n",
                    "    if os.path.exists('/kaggle/working/vault/system_state/restore.sh'):\n",
                    "        VpsArmor.log('RESTORING SYSTEM STATE...', '⚙️')\n",
                    "        os.system('bash /kaggle/working/vault/system_state/restore.sh > logs/restore_state.log 2>&1 &')\n",
                    "\n",
                    "    # User Vault Sync from HuggingFace is now handled by the VPS OS Engine sentinel\n",
                    "    # to ensure background auto-revival and atomic updates.\n",
                ],
            },
            {
                "cell_type": "markdown",
                "metadata": {},
                "source": ["## 🛰️ Stage 3: Launch Engines\n"],
            },
            {
                "cell_type": "code",
                "execution_count": None,
                "metadata": {},
                "outputs": [],
                "source": [
                    "VpsArmor.log('LAUNCHING ENGINE...')\n",
                    "# Ensure no stale processes conflict\n",
                    "os.system('pkill -9 uvicorn || true; pkill -9 cloudflared || true; true')\n",
                    f"def start_os(): os.system(f'GUI_ENABLED={{GUI_ENABLED}} PYDEVD_DISABLE_FILE_VALIDATION=1 VPS_VERSION={vps_version} VPS_ENGINE_PORT={{ENGINE_PORT}} VPS_PASS={{VPS_PASS}} SESSION_ID={{SESSION_ID}} VPS_SIGNAL_TOPIC={{SIGNAL_TOPIC}} VPS_CONTROL_TOPIC={{SIGNAL_TOPIC}}-control HF_TOKEN={{HF_TOKEN}} HF_REPO={{HF_REPO}} python3 -Xfrozen_modules=off -u vps-os/vps_os_engine.py')\n",
                    "if not os.path.exists('/tmp/.vps_engine_ignited'):\n",
                    "    os.system('touch /tmp/.vps_engine_ignited')\n",
                    "    threading.Thread(target=start_os, daemon=True).start()\n",
                    "else:\n",
                    "    VpsArmor.log('ENGINE ALREADY IGNITED. ATTACHING TO EXISTING INSTANCE.', '🔗')\n",
                    "\n",
                    "def start_sshd():\n",
                    f"    if {ssh_enabled}:\n",
                    "        VpsArmor.log('ARMORING SSH ARCHITECTURE...', '🔑')\n",
                    f"        os.system('mkdir -p /root/.ssh && echo \"{pub_key}\" >> /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys')\n",
                    "        os.system(f'echo \"root:{VPS_PASS}\" | chpasswd')\n",
                    "        os.system('mkdir -p /run/sshd')\n",
                    "        os.system('rm -f /etc/motd /etc/update-motd.d/*')\n",
                    "        os.system('sed -i \"s/^[# ]*PermitRootLogin.*/PermitRootLogin yes/\" /etc/ssh/sshd_config')\n",
                    "        os.system('sed -i \"s/^[# ]*PasswordAuthentication.*/PasswordAuthentication yes/\" /etc/ssh/sshd_config')\n",
                    '        os.system(\'sed -i "s/^#UseDNS.*/UseDNS no/" /etc/ssh/sshd_config || echo "UseDNS no" >> /etc/ssh/sshd_config\')\n',
                    '        os.system(\'sed -i "s/^PrintMotd.*/PrintMotd no/" /etc/ssh/sshd_config || echo "PrintMotd no" >> /etc/ssh/sshd_config\')\n',
                    '        os.system(\'sed -i "s/^PrintLastLog.*/PrintLastLog no/" /etc/ssh/sshd_config || echo "PrintLastLog no" >> /etc/ssh/sshd_config\')\n',
                    '        os.system(\'sed -i "s/^#ClientAliveInterval.*/ClientAliveInterval 300/" /etc/ssh/sshd_config || echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config\')\n',
                    '        os.system(\'sed -i "s/^#TCPKeepAlive.*/TCPKeepAlive yes/" /etc/ssh/sshd_config || echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config\')\n',
                    '        os.system(\'sed -i "s/^#IPQoS.*/IPQoS lowdelay throughput/" /etc/ssh/sshd_config || echo "IPQoS lowdelay throughput" >> /etc/ssh/sshd_config\')\n',
                    f"        os.system('/usr/sbin/sshd -p {ssh_port}')\n",
                    "        if os.path.exists('/usr/bin/et'):\n",
                    "            os.system('mkdir -p logs')\n",
                    "            os.system('etserver --daemon --port 2022 --log_dir logs > logs/et_init.log 2>&1')\n",
                    "        # WebSocket-to-SSH Bridge for mobile app clients (localhost only)\n",
                    "        if os.path.exists('/usr/local/bin/websocat'):\n",
                    f"            os.system('/usr/local/bin/websocat -E -b ws-l:127.0.0.1:40008 tcp:127.0.0.1:{ssh_port} &')\n",
                    "            VpsArmor.log('WEBSOCKET BRIDGE ARMED (127.0.0.1:40008)', '📱')\n",
                    "\n",
                    "threading.Thread(target=start_sshd, daemon=True).start()\n",
                ],
            },
            {
                "cell_type": "markdown",
                "metadata": {},
                "source": ["## 📊 Stage 4: PublicNode Backbone\n"],
            },
            {
                "cell_type": "code",
                "execution_count": None,
                "metadata": {},
                "outputs": [],
                "source": [
                    "import re\n",
                    "import socket\n",
                    "import time\n",
                    "\n",
                    "import requests\n",
                    "\n",
                    "# Inherit global config\n",
                    f"BOOT_TIMEOUT = {boot_timeout}\n",
                    "BOOT_TIME    = int(time.time())\n",
                    "for _ in range(BOOT_TIMEOUT):\n",
                    "    try:\n",
                    "        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:\n",
                    "            s.settimeout(1)\n",
                    f"            if s.connect_ex(('127.0.0.1', {ssh_port})) == 0:\n",
                    "                VpsArmor.log('SSH DAEMON READY. IGNITING BACKBONE...', '🚀')\n",
                    "                break\n",
                    "    except Exception:\n",
                    "        pass\n",
                    "    time.sleep(1)\n",
                    "else:\n",
                    "    VpsArmor.log('SSH FAILED TO RESPOND. BACKBONE MAY FAIL.', '⚠️')\n",
                    "\n",
                    "VpsArmor.log('LAUNCHING TRIPLE BACKBONE (SSH + ET + WS)...', '🚀')\n",
                    "# Start tunnels\n",
                    "for f in ['logs/cf_ssh.log', 'logs/cf_ws.log', 'logs/cf_et.log', 'logs/cf_api.log', 'logs/cf_gui.log']: \n",
                    "    if os.path.exists(f):\n",
                    "        os.remove(f)\n",
                    "\n",
                    f"if {ssh_enabled}:\n",
                    f"    os.system('/usr/local/bin/cloudflared tunnel --no-autoupdate --url tcp://127.0.0.1:{ssh_port} > logs/cf_ssh.log 2>&1 &')\n",
                    "    if os.path.exists('/usr/bin/et'):\n",
                    "        os.system('/usr/local/bin/cloudflared tunnel --no-autoupdate --url tcp://127.0.0.1:2022 > logs/cf_et.log 2>&1 &')\n",
                    "    if os.path.exists('/usr/local/bin/websocat'):\n",
                    "        os.system('/usr/local/bin/cloudflared tunnel --no-autoupdate --url http://127.0.0.1:40008 > logs/cf_ws.log 2>&1 &')\n",
                    "    if GUI_ENABLED == 'true':\n",
                    f"        os.system(f'/usr/local/bin/cloudflared tunnel --no-autoupdate --url http://127.0.0.1:{gui_port} > logs/cf_gui.log 2>&1 &')\n",
                    f"    os.system('/usr/local/bin/cloudflared tunnel --no-autoupdate --url http://127.0.0.1:{engine_port} > logs/cf_api.log 2>&1 &')\n",
                    "\n",
                    "def get_cf_url(log_file):\n",
                    "    if os.path.exists(log_file):\n",
                    "        with open(log_file) as f:\n",
                    "            content = f.read()\n",
                    "            # V9.9: Broad-Spectrum Regex for Cloudflare URL Detection\n",
                    "            match = re.search(r'((?:https|tcp)://[a-zA-Z0-9.-]+\\.(?:trycloudflare\\.com|cloudflareaccess\\.com|direct))', content)\n",
                    "            if match:\n",
                    "                return match.group(1)\n",
                    "    return None\n",
                    "\n",
                    "ssh_url = None\n",
                    "et_url = None\n",
                    "ws_url = None\n",
                    "api_url = None\n",
                    "gui_url = None\n",
                    "\n",
                    "VpsArmor.log('WAITING FOR BACKBONE LOCKS...', '⏳')\n",
                    "for i in range(15):\n",
                    "    if not ssh_url:\n",
                    "        ssh_url = get_cf_url('logs/cf_ssh.log')\n",
                    "    if not et_url:\n",
                    "        et_url = get_cf_url('logs/cf_et.log')\n",
                    "    if not ws_url:\n",
                    "        ws_url = get_cf_url('logs/cf_ws.log')\n",
                    "    if not api_url:\n",
                    "        api_url = get_cf_url('logs/cf_api.log')\n",
                    "    if GUI_ENABLED == 'true' and not gui_url:\n",
                    "        gui_url = get_cf_url('logs/cf_gui.log')\n",
                    "    if ws_url:\n",
                    "        ws_url = ws_url.replace('http://', 'wss://').replace('https://', 'wss://')\n",
                    "    if i % 3 == 0:\n",
                    "        VpsArmor.log(f'SCANNING CHANNELS (ATTEMPT {i+1}/45)...', '📡')\n",
                    "    if (ssh_url and ws_url and api_url and (not os.path.exists('/usr/bin/et') or et_url)):\n",
                    "        break\n",
                    "    time.sleep(2)\n",
                    "\n",
                    "if not ssh_url:\n",
                    "    VpsArmor.log('SSH BACKBONE LOCK FAILED. DUMPING DIAGNOSTICS:', '❌')\n",
                    "    os.system('tail -n 20 logs/cf_ssh.log')\n",
                    "    raise RuntimeError('SSH BACKBONE LOCK FAILED')\n",
                    "if not api_url:\n",
                    "    VpsArmor.log('API BACKBONE LOCK FAILED. DUMPING DIAGNOSTICS:', '❌')\n",
                    "    os.system('tail -n 20 logs/cf_api.log')\n",
                    "    raise RuntimeError('API BACKBONE LOCK FAILED')\n",
                    "\n",
                    "def check_backbone(url):\n",
                    "    try:\n",
                    "        # Use curl to check for 'online' status in JSON response\n",
                    "        cmd = ['curl', '-s', '-L', '--max-time', '5', url]\n",
                    "        res = subprocess.run(cmd, capture_output=True, text=True, timeout=7, check=False)\n",
                    "        return 'online' in res.stdout.lower()\n",
                    "    except Exception:\n",
                    "        return False\n",
                    "\n",
                    "VpsArmor.log('STABILIZING BACKBONE...', '⚖️')\n",
                    "for _ in range(20):\n",
                    "    # Ensure the API engine is fully responsive before unlocking the backbone\n",
                    "    if check_backbone(api_url):\n",
                    "        time.sleep(3) # Final stabilization buffer\n",
                    "        break\n",
                    "    time.sleep(2)\n",
                    "\n",
                    "VpsArmor.log(f'SSH BRIDGE LOCKED -> {ssh_url}', '')\n",
                    "VpsArmor.broadcast(f'SSH:[{SESSION_ID}]{ssh_url}')\n",
                    "if et_url:\n",
                    "    VpsArmor.log(f'ECHO BRIDGE LOCKED -> {et_url}', '')\n",
                    "    VpsArmor.broadcast(f'ET:[{SESSION_ID}]{et_url}')\n",
                    "if ws_url:\n",
                    "    VpsArmor.log(f'APP BRIDGE LOCKED -> {ws_url}', '📱')\n",
                    "    VpsArmor.broadcast(f'WS:[{SESSION_ID}]{ws_url}')\n",
                    "if api_url:\n",
                    "    VpsArmor.log(f'API BRIDGE LOCKED -> {api_url}', '⚡')\n",
                    "    VpsArmor.broadcast(f'API:[{SESSION_ID}]{api_url}')\n",
                    "if gui_url:\n",
                    "    VpsArmor.log(f'GUI BRIDGE LOCKED -> {gui_url}', '🖥️')\n",
                    "    VpsArmor.broadcast(f'GUI:[{SESSION_ID}]{gui_url}')\n",
                    "VpsArmor.broadcast(f'PASS:[{SESSION_ID}]{VPS_PASS}')\n",
                    "\n",
                    "VpsArmor.log('PUBLICNODE PERSISTENCE ONLINE', '✅')\n",
                    "VpsArmor.log(f'SSH URL: {ssh_url}', '')\n",
                    "if et_url:\n",
                    "    import re\n",
                    "    et_host = re.sub(r'^.*?://', '', et_url)\n",
                    "    ssh_host = re.sub(r'^.*?://', '', ssh_url)\n",
                    "    VpsArmor.log(f'ET COMMAND: et --ssh-option=\"Hostname={ssh_host}\" --ssh-option=\"Port=443\" root@{et_host}:443', '🐚')\n",
                    "def notebook_sentinel():\n",
                    "    while True:\n",
                    "        try:\n",
                    "            r = requests.get(f'https://ntfy.sh/{SIGNAL_TOPIC}-control/raw?poll=1', timeout=10)\n",
                    "            for line in r.text.splitlines():\n",
                    "                if 'KILL:' in line:\n",
                    "                    try:\n",
                    "                        t = int(line.split(':')[1])\n",
                    "                        if t > BOOT_TIME:\n",
                    "                            VpsArmor.log('PUBLICNODE KILL SIGNAL RECEIVED. SECURING VAULT...', '🛑')\n",
                    "                            try:\n",
                    f"                                requests.get('http://localhost:{engine_port}/api/system/save', timeout=120)\n",
                    "                                # Poll for completion before exiting\n",
                    "                                for _ in range(60):\n",
                    f"                                    res = requests.get('http://localhost:{engine_port}/api/sync/status', timeout=10)\n",
                    "                                    state = res.json()\n",
                    "                                    if not state.get('active'):\n",
                    "                                        break\n",
                    "                                    time.sleep(5)\n",
                    "                            except Exception as sync_err:\n",
                    "                                VpsArmor.log(f'VAULT SECURE FAILED: {sync_err}', '❌')\n",
                    "                            VpsArmor.log('VAULT SECURED. GOODBYE.', '⚰️')\n",
                    "                            os._exit(0)\n",
                    "                    except (IndexError, ValueError):\n",
                    "                        pass\n",
                    "                elif 'SAVE:' in line:\n",
                    "                    try:\n",
                    "                        VpsArmor.log('PUBLICNODE SAVE SIGNAL RECEIVED. SECURING VAULT...', '💾')\n",
                    f"                        requests.get('http://localhost:{engine_port}/api/system/save', timeout=120)\n",
                    "                    except Exception:\n",
                    "                        pass\n",
                    "        except Exception:\n",
                    "            pass\n",
                    "        time.sleep(15)\n",
                    "\n",
                    "threading.Thread(target=notebook_sentinel, daemon=True).start()\n",
                    "try:\n",
                    "    while True:\n",
                    "        time.sleep(60)\n",
                    "except KeyboardInterrupt:\n",
                    "    VpsArmor.log('KEYBOARD INTERRUPT — Shutting down gracefully.')\n",
                ],
            },
        ],
        "metadata": {
            "kernelspec": {
                "display_name": "Python 3",
                "language": "python",
                "name": "python3",
            },
            "language_info": {"name": "python", "version": "3.12"},
        },
        "nbformat": 4,
        "nbformat_minor": 4,
    }
    return nb


def build_kernel_metadata(cfg: dict[str, Any]) -> dict[str, Any]:
    """Generate kernel-metadata.json from config."""
    username = get(cfg, "identity", "kaggle_username", default="mohammadhasanulislam")
    kernel_slug = get(cfg, "identity", "kernel_slug", default="publicnode-vps-engine")
    vault_slug = get(cfg, "identity", "vault_slug", default="vps-storage")
    return {
        "id": f"{username}/{kernel_slug}",
        "title": kernel_slug,
        "code_file": "vps_setup.ipynb",
        "language": "python",
        "kernel_type": "notebook",
        "is_private": True,
        "enable_gpu": False,
        "enable_internet": True,
        "dataset_sources": [f"{username}/{vault_slug}"],
        "competition_sources": [],
        "kernel_sources": [],
    }


def main() -> None:
    """Orchestrate the build process: load config, build notebook, and generate metadata."""
    parser = argparse.ArgumentParser(description="VPS Build Script")
    parser.add_argument(
        "--config",
        default=os.path.join(REPO_ROOT, "vps-config.yaml"),
        help="Path to the YAML configuration file (default: vps-config.yaml)",
    )
    args = parser.parse_args()

    print(f"[BUILD] Loading config from: {args.config}", flush=True)
    cfg = load_config(args.config)

    # --- Load Project Meta ---
    project_meta = load_pyproject(os.path.join(REPO_ROOT, "pyproject.toml"))

    auth_dir = os.path.join(REPO_ROOT, "publicnode-vps-engine", ".vps_auth")

    # --- Generate notebook ---
    print("[BUILD] Generating vps_setup.ipynb...", flush=True)
    nb = build_notebook(cfg, project_meta, auth_dir)
    nb_path = os.path.join(REPO_ROOT, "publicnode-vps-engine", "vps_setup.ipynb")
    with open(nb_path, "w") as f:
        json.dump(nb, f, indent=2, ensure_ascii=False)
    print(f"[BUILD] ✅ Notebook written to: {nb_path}", flush=True)

    # --- Generate kernel metadata ---
    print("[BUILD] Generating kernel-metadata.json...", flush=True)
    meta = build_kernel_metadata(cfg)
    meta_path = os.path.join(REPO_ROOT, "publicnode-vps-engine", "kernel-metadata.json")
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"[BUILD] ✅ Metadata written to: {meta_path}", flush=True)

    print("[BUILD]  BUILD COMPLETE — Ready for 'kaggle kernels push'", flush=True)


if __name__ == "__main__":
    main()
