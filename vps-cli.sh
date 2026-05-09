#!/bin/bash
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

# ==============================================================================
#  PUBLICNODE MASTER CLOUD CLI (Headless Edition)
# Industry-Grade SSH-only Bridge Architecture | (c) 2026 mohammadhasanulislam
#
# Usage:  ./vps-cli.sh [command]   OR  vps [command]   (after 'vps alias')
# All configuration lives in vps-config.yaml
# ==============================================================================

# Hygiene: Absolute Bytecode & Cache Redirection
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPYCACHEPREFIX=/tmp/.pycache
set -euo pipefail

# --- Locate Repo Root ---
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT

# --- Config File (overridable with CONFIG env var) ---
CONFIG_FILE="${CONFIG:-${REPO_ROOT}/vps-config.yaml}"
readonly CONFIG_FILE

# --- Lightweight YAML Value Extractor (no external deps) ---
# Usage: yaml_get "identity" "kaggle_username"
yaml_get() {
    local section="$1"
    local key="$2"
    awk -v s="${section}:" -v k="  ${key}:" '
        $1 == s {p=1}
        /^[a-z]/ && $1 != s {p=0}
        p && $0 ~ k {
            sub(/.*:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, ""); 
            gsub(/^["\47]|["\47]$/, ""); print; exit 
        }
    ' "$CONFIG_FILE"
}

# --- Lightweight TOML Value Extractor (no external deps) ---
# Usage: toml_get "project" "version"
toml_get() {
    local section="$1"
    local key="$2"
    awk -v s="[${section}]" -v k="^${key} =" '
        $0 == s {p=1}
        $0 ~ /^\[.*\]/ && $0 != s {p=0}
        p && $0 ~ k {
            sub(/.*=[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "");
            gsub(/^["\47]|["\47]$/, ""); print; exit
        }
    ' "${REPO_ROOT}/pyproject.toml"
}

# --- Load Global Project Info from TOML ---
PROJECT_NAME="$(toml_get project name)"
readonly PROJECT_NAME
PROJECT_VERSION="$(toml_get project version)"
readonly PROJECT_VERSION

# --- Load Identity from YAML ---
USER_ID="$(yaml_get identity kaggle_username)"
readonly USER_ID
KERNEL_SLUG="$(yaml_get identity kernel_slug)"
readonly KERNEL_SLUG
VAULT_SLUG="$(yaml_get identity vault_slug)"
readonly VAULT_SLUG
readonly KERNEL_ID="${USER_ID}/${KERNEL_SLUG}"
readonly VAULT_ID="${USER_ID}/${VAULT_SLUG}"
VPS_NAME="$(yaml_get identity vps_name)"
readonly VPS_NAME
ENGINE_VERSION="$(yaml_get engine version)"
readonly ENGINE_VERSION
TOPIC_PREFIX="$(yaml_get signal topic_prefix)"
readonly TOPIC_PREFIX
AUTH_DIR="${REPO_ROOT}/publicnode-vps-engine/.vps_auth"
readonly AUTH_DIR

# --- Derive Signal Topic (mirrors Python logic in build script) ---
SIGNAL_TOPIC="${TOPIC_PREFIX}-$(echo -n "${USER_ID}" | sha256sum | head -c 12)"
readonly SIGNAL_TOPIC

# --- Load Port Config from YAML ---
ENGINE_PORT="$(yaml_get engine engine_port)"
[[ -z "${ENGINE_PORT}" ]] && ENGINE_PORT=5003
readonly ENGINE_PORT

# --- ANSI Colors ---
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_BLUE='\033[1;34m'
readonly C_CYAN='\033[1;36m'
readonly C_YELLOW='\033[1;33m'
readonly C_PURPLE='\033[1;35m'
readonly C_NC='\033[0m'

# --- Logging Helpers ---
log()  { echo -e "${C_CYAN}[${VPS_NAME}]${C_NC} $1"; }
ok()   { echo -e "${C_GREEN}[  OK  ]${C_NC} $1"; }
warn() { echo -e "${C_YELLOW}[ WARN ]${C_NC} $1"; }
err()  { echo -e "${C_RED}[FAILED]${C_NC} $1"; exit 1; }

# --- Port Checker (Python-based for portability) ---
check_port() {
    local port=$1
    python3 -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.settimeout(0.5); exit(0 if s.connect_ex(('127.0.0.1', $port)) == 0 else 1)"
}

# --- Force Kill processes on a port ---
force_kill_port() {
    local port=$1
    if check_port "${port}"; then
        warn "Port ${port} busy. Sweeping stale sessions..."
        # Use lsof if available, otherwise fallback to fuser
        if command -v lsof >/dev/null 2>&1; then
            lsof -ti :"${port}" | xargs kill -9 2>/dev/null || true
        elif command -v fuser >/dev/null 2>&1; then
            fuser -k "${port}/tcp" >/dev/null 2>&1 || true
        fi
        sleep 1
    fi
}

# --- Cleanup Handler ---
cleanup() {
    local pids=("$@")
    if [[ ${#pids[@]} -gt 0 ]]; then
        log "Cleaning up backbone bridges..."
        kill "${pids[@]}" 2>/dev/null || true
    fi
}

# --- Validate Config File Loaded Correctly ---
validate_config() {
    if [[ -z "${USER_ID}" ]]; then
        err "Failed to parse 'identity.kaggle_username' from ${CONFIG_FILE}. Is the file present?"
    fi
    if [[ -z "${KERNEL_SLUG}" ]]; then
        err "Failed to parse 'identity.kernel_slug' from ${CONFIG_FILE}."
    fi
    if [[ -z "${ENGINE_PORT}" ]]; then
        err "Engine port (engine_port) missing in ${CONFIG_FILE}."
    fi
}

# --- Dependency Checks ---
check_deps() {
    local missing=()
    command -v kaggle >/dev/null 2>&1 || missing+=("kaggle (pip install kaggle)")
    command -v curl   >/dev/null 2>&1 || missing+=("curl")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    command -v ssh     >/dev/null 2>&1 || missing+=("ssh (openssh-client)")
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing dependencies: ${missing[*]}"
    fi
}

# --- Environment Check ---
check_env() {
    log "Verifying local ${VPS_NAME} environment..."
    local py_ver
    py_ver=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    if ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" 2>/dev/null; then
        err "Python 3.8+ required. Found: ${py_ver}"
    fi
    ok "Local environment verified (Python ${py_ver})."
}

# --- Signal Tunnel Fetch (ntfy.sh) ---
# get_tunnel removed as Web backbone is decommissioned.

# --- SSH Signal Tunnel Fetch (ntfy.sh) ---
get_ssh_tunnel() {
    local history
    history=$(curl -s "https://ntfy.sh/${SIGNAL_TOPIC}/raw?since=1h&poll=1" || true)
    if [[ -n "${history}" ]]; then
        while read -r line; do
            [[ -z "${line}" || "${line}" == STATUS:* ]] && continue
            local decoded
            decoded=$(echo "${line}" | base64 -d 2>/dev/null || true)
            if [[ "${decoded}" == SSH:* ]]; then
                echo "${decoded#SSH:}"
                return 0
            fi
        done < <(echo "${history}" | tac)
    fi
    return 1
}

# --- ET Signal Tunnel Fetch (ntfy.sh) ---
get_et_tunnel() {
    local history
    history=$(curl -s "https://ntfy.sh/${SIGNAL_TOPIC}/raw?since=1h&poll=1" || true)
    if [[ -n "${history}" ]]; then
        while read -r line; do
            [[ -z "${line}" || "${line}" == STATUS:* ]] && continue
            local decoded
            decoded=$(echo "${line}" | base64 -d 2>/dev/null || true)
            if [[ "${decoded}" == ET:* ]]; then
                echo "${decoded#ET:}"
                return 0
            fi
        done < <(echo "${history}" | tac)
    fi
    return 1
}

# --- WS (App Bridge) Signal Tunnel Fetch (ntfy.sh) ---
get_ws_tunnel() {
    local history
    history=$(curl -s "https://ntfy.sh/${SIGNAL_TOPIC}/raw?since=1h&poll=1" || true)
    if [[ -n "${history}" ]]; then
        while read -r line; do
            [[ -z "${line}" || "${line}" == STATUS:* ]] && continue
            local decoded
            decoded=$(echo "${line}" | base64 -d 2>/dev/null || true)
            if [[ "${decoded}" == WS:* ]]; then
                echo "${decoded#WS:}"
                return 0
            fi
        done < <(echo "${history}" | tac)
    fi
    return 1
}

# ============================================================
# COMMANDS
# ============================================================

cmd_creds() {
    log "Armoring cloud credentials (Kaggle API)..."
    local local_json="${HOME}/.kaggle/kaggle.json"
    if [[ ! -f "${local_json}" ]]; then
        err "Kaggle API token not found at ${local_json}.\nDownload it from: https://www.kaggle.com/settings (Account → API)"
    fi
    mkdir -p "${AUTH_DIR}"
    cp "${local_json}" "${AUTH_DIR}/kaggle.json"
    chmod 600 "${AUTH_DIR}/kaggle.json"
    ok "Kaggle credentials secured in ${AUTH_DIR}/kaggle.json"
}

helper_install_et() {
    if ! command -v et >/dev/null 2>&1; then
        warn "Eternal Terminal (et) not found. Attempting industrial-grade installation..."
        
        # Identify OS
        local os_id codename
        if [[ -f /etc/os-release ]]; then
            os_id=$(grep -oP '^ID=\K\w+' /etc/os-release | tr -d '"')
            codename=$(grep -oP '^VERSION_CODENAME=\K[\w-]+' /etc/os-release | tr -d '"')
        else
            err "Unable to detect OS for automatic 'et' installation."
        fi

        case "${os_id}" in
            ubuntu)
                log "Strategy: Ubuntu PPA"
                sudo apt update
                sudo apt install -y software-properties-common
                sudo add-apt-repository ppa:jgmath2000/et -y
                sudo apt update
                sudo apt install -y et || err "Failed to install ET via PPA."
                ;;
            kali|debian)
                log "Strategy: Official Debian Repository (${os_id})"
                # Map Kali to a supported Debian codename
                if [[ "${os_id}" == "kali" ]]; then
                    # Kali rolling is usually based on Debian Testing (Trixie)
                    codename="trixie"
                fi
                
                # Fallback for empty codename
                [[ -z "${codename}" ]] && codename="bookworm"
                
                sudo apt update
                sudo apt install -y curl gpg
                sudo mkdir -p /etc/apt/keyrings
                
                # Download and dearmor GPG key
                curl -sSL https://github.com/MisterTea/debian-et/raw/master/et.gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/et-archive-keyring.gpg
                
                # Add Repository
                echo "deb [signed-by=/etc/apt/keyrings/et-archive-keyring.gpg] https://mistertea.github.io/debian-et/debian-source/ ${codename} main" | sudo tee /etc/apt/sources.list.d/et.list
                
                sudo apt update
                sudo apt install -y et || err "Failed to install ET via Debian repo."
                ;;
            *)
                warn "Unsupported OS (${os_id}) for automatic ET installation."
                err "Please install Eternal Terminal manually: https://eternalterminal.dev/"
                ;;
        esac
        ok "Eternal Terminal installed successfully."
    fi
}



cmd_ssh() {
    check_deps
    
    # Smart Entry: Check for Echo Mode (ET) signal first
    local et_url
    et_url=$(get_et_tunnel || true)
    if [[ -n "${et_url}" ]]; then
        log "PublicNode Echo Signal detected. Upgrading to zero-latency mode..."
        helper_install_et
        cmd_et
        return
    fi

    log "Verifying SSH Bridge Signal..."
    local ssh_url
    ssh_url=$(get_ssh_tunnel || true)

    if [[ -z "${ssh_url}" ]]; then
        err "No SSH bridge signal found. Is the VPS running with SSH enabled?"
    fi


    # Ensure local cloudflared is available
    local cf_bin="${AUTH_DIR}/cloudflared"
    if [[ ! -f "${cf_bin}" ]]; then
        log "Local cloudflared not found. Downloading for bridge..."
        local os_arch
        os_arch=$(uname -m)
        local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        [[ "${os_arch}" == "aarch64" ]] && cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
        
        curl -L -s -o "${cf_bin}" "${cf_url}" || err "Failed to download cloudflared."
        chmod +x "${cf_bin}"
    fi

    local l_port=2222
    log "Initiating Secure Bridge (localhost:${l_port})..."
    
    # Ensure local ports are free
    force_kill_port ${l_port}
    if check_port ${l_port}; then
        err "Local port ${l_port} is already in use by another application. Bridge cannot start."
    fi

    # Start the bridge in the background
    "${cf_bin}" access tcp --hostname "${ssh_url}" --listener "127.0.0.1:${l_port}" >/dev/null 2>&1 &
    local bridge_pid=$!
    
    # Register trap for cleanup
    trap 'cleanup '"${bridge_pid}"'; exit 1' INT TERM
    
    # Wait for bridge to be ready
    local max_wait=20
    while ! check_port ${l_port}; do
        sleep 0.5
        ((max_wait--))
        if [[ ${max_wait} -le 0 ]]; then
            cleanup ${bridge_pid}
            err "Local bridge failed to initialize. Check your internet connection."
        fi
    done

    ok "Backbone bridge established. Entering PublicNode Shell..."
    
    # Fetch password from vault if available
    local v_pass
    if [[ -f "${AUTH_DIR}/vps.pass" ]]; then
        v_pass=$(cat "${AUTH_DIR}/vps.pass")
        log "Using cached session password."
    else
        warn "Session password not cached locally."
    fi

    # PublicNode Key Auth
    local ssh_opts=(-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR)
    if [[ -f "${AUTH_DIR}/id_vps" ]]; then
        chmod 600 "${AUTH_DIR}/id_vps"
        ssh_opts+=(-i "${AUTH_DIR}/id_vps")
    fi

    # Connect
    ssh "${ssh_opts[@]}" \
        -o Compression=no -o IPQoS=lowdelay -o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=600 \
        -p ${l_port} "root@127.0.0.1"


    log "Cleaning up backbone bridge..."
    kill ${bridge_pid} 2>/dev/null || true
    ok "PublicNode session terminated."
}

cmd_et() {
    check_deps
    helper_install_et


    log "Verifying PublicNode Echo Signals..."
    local ssh_url et_url
    ssh_url=$(get_ssh_tunnel || true)
    et_url=$(get_et_tunnel || true)

    if [[ -z "${ssh_url}" || -z "${et_url}" ]]; then
        err "Echo backbone signals not found. Ensure the VPS is running version 0.1.0+ and SSH is enabled."
    fi

    local cf_bin="${AUTH_DIR}/cloudflared"
    if [[ ! -f "${cf_bin}" ]]; then
        log "Local cloudflared not found. Downloading for bridge..."
        local os_arch
        os_arch=$(uname -m)
        local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        [[ "${os_arch}" == "aarch64" ]] && cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
        curl -L -s -o "${cf_bin}" "${cf_url}" || err "Failed to download cloudflared."
        chmod +x "${cf_bin}"
    fi

    local s_port=2222
    local e_port=2022
    log "Initiating Dual-Backbone Bridge (localhost:${s_port} & ${e_port})..."

    force_kill_port ${s_port}
    force_kill_port ${e_port}
    
    if check_port ${s_port}; then err "Local port ${s_port} busy (SSH Bridge)."; fi
    if check_port ${e_port}; then err "Local port ${e_port} busy (Echo Bridge)."; fi

    "${cf_bin}" access tcp --hostname "${ssh_url}" --listener "127.0.0.1:${s_port}" >/dev/null 2>&1 &
    local s_pid=$!
    "${cf_bin}" access tcp --hostname "${et_url}" --listener "127.0.0.1:${e_port}" >/dev/null 2>&1 &
    local e_pid=$!
    trap 'cleanup '"${s_pid}"' '"${e_pid}"'; exit 1' INT TERM

    local max_wait=30
    while ! check_port ${s_port} || ! check_port ${e_port}; do
        sleep 0.5
        ((max_wait--))
        if [[ ${max_wait} -le 0 ]]; then
            cleanup ${s_pid} ${e_pid}
            err "Backbone synchronization failed. Check your internet connection."
        fi
    done

    ok "Echo Handshake Secured. Entering Zero-Latency Shell..."
    
    local et_opts=()
    if [[ -f "${AUTH_DIR}/id_vps" ]]; then
        chmod 600 "${AUTH_DIR}/id_vps"
        et_opts+=(--ssh-option "IdentityFile=${AUTH_DIR}/id_vps")
    fi

    et root@localhost -p ${e_port} "${et_opts[@]}" \
       --ssh-option "Port=${s_port}" \
       --ssh-option "UserKnownHostsFile=/dev/null" \
       --ssh-option "StrictHostKeyChecking=no" \
       --ssh-option "LogLevel=ERROR"

    kill ${s_pid} ${e_pid} 2>/dev/null || true
    ok "PublicNode Echo session terminated."
}


cmd_status() {
    check_deps
    if [[ "${1:-}" == "--all" ]]; then
        echo -e "${C_BLUE}--- PUBLICNODE KERNEL FLEET [${USER_ID}] ---${C_NC}"
        kaggle kernels list --mine --page-size 20
        echo -e "${C_BLUE}----------------------------------------------------${C_NC}"
        return
    fi

    echo -e "${C_BLUE}--- ${VPS_NAME} STATUS [v${ENGINE_VERSION}] ---${C_NC}"
    echo -e "    CONFIG: ${CONFIG_FILE}"
    echo -e "    KERNEL: ${KERNEL_ID}"
    echo -e "    VAULT:  ${VAULT_ID}"
    echo ""

    # Kernel status
    local k_status
    k_status=$(kaggle kernels status "${KERNEL_ID}" 2>/dev/null \
        | grep -ioP 'status\s*"?\s*(?:KernelWorkerStatus\.)?\K[a-zA-Z]+' | tr '[:upper:]' '[:lower:]' || echo "offline")
    
    local s_color="${C_RED}"
    [[ "${k_status}" == "running" ]] && s_color="${C_GREEN}"
    [[ "${k_status}" == "queued" ]] && s_color="${C_YELLOW}"

    echo -e "   [KERNEL]  ${C_CYAN}${KERNEL_ID}${C_NC} -> ${s_color}${k_status}${C_NC}"

    # Vault status
    local v_status
    v_status=$(kaggle datasets status "${VAULT_ID}" 2>/dev/null \
        | grep -oP "status\s+\K\w+" || echo "READY")
    echo -e "   [VAULT]   ${C_CYAN}${VAULT_ID}${C_NC} -> ${C_GREEN}${v_status}${C_NC}"



    # Tunnel signal
    local url
    if url=$(get_ssh_tunnel 2>/dev/null); then
        echo -e "   [SIGNAL]  ${url} -> ${C_GREEN}BACKBONE LOCKED${C_NC}"
    else
        echo -e "   [SIGNAL]  ${C_RED}NO BACKBONE SIGNAL DETECTED${C_NC}"
    fi

    # Local disk usage
    local storage_size
    storage_size=$(du -sh "${REPO_ROOT}" 2>/dev/null | cut -f1)
    echo -e "   [LOCAL]   Project Assets: ${storage_size}"
    echo -e "${C_BLUE}----------------------------------------------------${C_NC}"
    ok "Status audit complete."
}

cmd_alias() {
    log "Injecting 'vps' alias into shell config..."
    local rc_file
    case "${SHELL}" in
        */zsh)  rc_file="${HOME}/.zshrc" ;;
        */bash) rc_file="${HOME}/.bashrc" ;;
        *)      rc_file="${HOME}/.profile" ;;
    esac

    if grep -q "alias vps=" "${rc_file}" 2>/dev/null; then
        sed -i "/alias vps=/c\\alias vps='${REPO_ROOT}/vps-cli.sh'" "${rc_file}"
        ok "Alias updated in ${rc_file}."
    else
        echo "alias vps='${REPO_ROOT}/vps-cli.sh'" >> "${rc_file}"
        ok "Alias added to ${rc_file}. Run: source ${rc_file}"
    fi
}

cmd_boot() {
    validate_config
    check_deps
    check_env



    echo -e "\n${C_BLUE}════════════════════════════════════════════════════════════${C_NC}"
    echo -e "           ${VPS_NAME} ABSOLUTE PUBLICNODE BOOT"
    echo -e "${C_BLUE}════════════════════════════════════════════════════════════${C_NC}"

    log "Sending PublicNode Kill-Switch pulse to stale sessions..."
    local pulse
    pulse="KILL:$(date +%s)"
    curl -s -d "${pulse}" "https://ntfy.sh/${SIGNAL_TOPIC}-control" >/dev/null 2>&1 || true

    # Wait for the old kernel to actually stop (prevents tunnel conflicts)
    log "Waiting for old session to terminate..."
    local attempts=0
    while (( attempts < 12 )); do
        local k_status
        k_status=$(kaggle kernels status "${KERNEL_ID}" 2>/dev/null \
            | grep -ioE "(running|complete|error|cancel|offline)" | tr '[:upper:]' '[:lower:]' | head -n 1 || echo "offline")
        if [[ "${k_status}" == "offline" || "${k_status}" == "complete" || "${k_status}" == "error" || "${k_status}" == "cancelcomplete" ]]; then
            ok "Old session cleared (status: ${k_status})."
            break
        fi
        warn "Session still active (${k_status}). Forcing kernel deletion... (${attempts}/12)"
        kaggle kernels delete "${KERNEL_ID}" -y >/dev/null 2>&1 || true
        attempts=$(( attempts + 1 ))
        sleep 10
    done

    # Build the notebook and metadata from YAML config
    log "Constructing Persistence Engine from config..."
    python3 "${REPO_ROOT}/scripts/master_build_vps.py" --config "${CONFIG_FILE}"

    # Sync the vps-os OS layer into the kernel directory
    log "Syncing PublicNode OS Assets (vps-os)..."
    rm -rf "${REPO_ROOT}/publicnode-vps-engine/vps-os"
    cp -r "${REPO_ROOT}/vps-os" "${REPO_ROOT}/publicnode-vps-engine/"

    log "Pushing Persistent Kernel to Kaggle Edge..."
    kaggle kernels push -p "${REPO_ROOT}/publicnode-vps-engine"

    echo -e "${C_BLUE}════════════════════════════════════════════════════════════${C_NC}"
    ok "${VPS_NAME} Persistence Deployed. INITIALIZING TELEMETRY..."

    # V5.1: PUBLICNODE TELEMETRY STREAM
    # Listens to real-time status signals from the remote Kaggle node
    local success=false
    exec 3< <(curl -s --no-buffer -m 1800 "https://ntfy.sh/${SIGNAL_TOPIC}/raw")

    while true; do
        if read -t 10 -r line <&3; then
            if [[ "${line}" == STATUS:* ]]; then
                echo -e "   ${C_CYAN}➜${C_NC} ${line#STATUS:}"
            elif [[ "${line}" == ERROR:* || "${line}" == *DIAGNOSTIC* || "${line}" == "⚠️"* ]]; then
                 echo -e "   ${C_YELLOW}➜${C_NC} ${C_RED}${line}${C_NC}"
            elif [[ -n "${line}" ]]; then
                # V5.1: Decode the final Base64-encoded bridge signal
                local decoded
                decoded=$(echo "${line}" | base64 -d 2>/dev/null || true)
                if [[ "${decoded}" == SSH:* ]]; then
                     echo -e "\n${C_GREEN}════════════════════════════════════════════════════════════${C_NC}"
                     echo -e "         🚀  SUCCESS: PUBLICNODE VPS IS LIVE"
                     echo -e "         SSH Bridge: ${C_CYAN}${decoded#SSH:}${C_NC}"
                     echo -e "${C_GREEN}════════════════════════════════════════════════════════════${C_NC}"
                     echo -e "Run '${C_YELLOW}vps ssh${C_NC}' for local access.\n"
                     
                     success=true
                     break
                fi
            fi
        else
            local read_exit=$?
            if [[ ${read_exit} -gt 128 ]]; then
                # Timeout. Check if notebook failed early.
                local k_status
                k_status=$(kaggle kernels status "${KERNEL_ID}" 2>/dev/null \
                    | grep -ioE "(running|complete|error|cancel|offline)" | tr '[:upper:]' '[:lower:]' | head -n 1 || echo "unknown")
                if [[ "${k_status}" == "error" || "${k_status}" == "cancelcomplete" || "${k_status}" == "complete" ]]; then
                    exec 3<&-
                    err "Kernel execution failed on Kaggle (Status: ${k_status}). Please check Kaggle logs."
                fi
            else
                # EOF
                break
            fi
        fi
    done
    exec 3<&-

    if [[ "${success}" != "true" ]]; then
        err "Boot sequence timed out or engine failed. Please check 'vps status' and Kaggle logs."
    fi
}

cmd_audit() {
    log "Performing Master Integrity Audit..."
    local pass=true

    if [[ -f "${HOME}/.kaggle/kaggle.json" ]]; then
        ok "Kaggle API credentials: PRESENT"
    else
        warn "Kaggle API: MISSING (run 'vps creds')"; pass=false
    fi



    if kaggle datasets status "${VAULT_ID}" &>/dev/null; then
        ok "System Vault (${VAULT_ID}): REACHABLE"
    else
        warn "System Vault: OFFLINE or not yet created"; pass=false
    fi

    if [[ -f "${CONFIG_FILE}" ]]; then
        ok "Config file (${CONFIG_FILE}): PRESENT"
        # Check for PyYAML
        if ! python3 -c "import yaml" >/dev/null 2>&1; then
            warn "PyYAML not found. Using fallback line-parser (Industry recommendation: pip install pyyaml)"
        else
            ok "PyYAML: PRESENT"
        fi
    else
        warn "Config file missing: ${CONFIG_FILE}"; pass=false
    fi

    # Connectivity checks
    log "Testing Signal Bridge connectivity..."
    if curl -Is https://ntfy.sh/ >/dev/null; then
        ok "Signal Relay (ntfy.sh): REACHABLE"
    else
        warn "ntfy.sh: UNREACHABLE (Check your internet connection)"; pass=false
    fi

    if curl -Is https://www.kaggle.com/ >/dev/null; then
        ok "Kaggle Edge: REACHABLE"
    else
        warn "Kaggle: UNREACHABLE"; pass=false
    fi

    if [[ "${pass}" == "true" ]]; then
        ok "Audit Complete — Infrastructure is 100% Battle-Ready."
    else
        warn "Audit Complete — Some items need attention (see warnings above)."
        exit 1
    fi
}

cmd_poweroff() {
    log "Sending PublicNode Power-Off signal (Kill-Switch) to remote node..."
    local pulse
    pulse="KILL:$(date +%s)"
    curl -s -d "${pulse}" "https://ntfy.sh/${SIGNAL_TOPIC}-control" >/dev/null 2>&1 || true
    ok "Shutdown pulse transmitted. Secure Vault synchronization initiated on node."
    log "Deleting remote artifacts..."
    kaggle kernels delete "${KERNEL_ID}" -y >/dev/null 2>&1 || true
}

cmd_connect() {
    log "Verifying Backbone Signal..."
    local h
    if ! h=$(get_ssh_tunnel 2>/dev/null); then
        err "No tunnel signal found. Either:\n  1. The VPS is not running yet ('vps boot')\n  2. It is still in the 'PublicNode Telemetry' phase (check your 'vps boot' terminal)\n  3. Run 'vps link' to see the raw signal topic"
    fi

    echo -e "\n${C_BLUE}====================================================${C_NC}"
    echo -e "         📡 ${VPS_NAME} BACKBONE LOCKED"
    echo -e "${C_BLUE}====================================================${C_NC}"
    echo -e "Open in any browser to access your Root Console:"
    echo -e "${C_GREEN}${h}${C_NC}\n"
    echo -e "Login Credentials:"

    local v_pass="UNKNOWN — run 'vps boot' first"
    if [[ -f "${AUTH_DIR}/vps.pass" ]]; then
        v_pass=$(cat "${AUTH_DIR}/vps.pass")
    fi
    echo -e "  User: ${C_YELLOW}root${C_NC}  |  Pass: ${C_YELLOW}${v_pass}${C_NC}"
    echo -e "${C_BLUE}====================================================${C_NC}\n"

    # Auto-open in browser if available
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "${h}" >/dev/null 2>&1 &
    elif command -v open >/dev/null 2>&1; then
        open "${h}"
    fi
}

# vps sync removed from local CLI. Use 'vps sync' inside 'vps ssh' session.

cmd_logs() {
    local log_type="${1:-os}"
    log "Streaming remote Bridge Telemetry [${log_type}.log]..."
    
    local path="/kaggle/working/logs/os.log"
    [[ "${log_type}" == "--audit" ]] && path="/kaggle/working/logs/audit.log"
    [[ "${log_type}" == "--sync" ]] && path="/kaggle/working/logs/sync.log"

    # We use the SSH bridge logic to stream logs for zero-latency
    # This avoids polling API overhead and feels more 'PublicNode'
    local ssh_url
    ssh_url=$(get_ssh_tunnel || true)
    [[ -z "${ssh_url}" ]] && err "SSH backbone signals not found. Ensure the VPS is running version 0.1.0+."

    local cf_bin="${AUTH_DIR}/cloudflared"
    local l_port=2223 # Separate port from usual SSH to avoid conflicts
    
    log "Opening Log Bridge (localhost:${l_port})..."
    if check_port ${l_port}; then err "Local port ${l_port} busy (Log Bridge)."; fi

    "${cf_bin}" access tcp --hostname "${ssh_url}" --listener "127.0.0.1:${l_port}" >/dev/null 2>&1 &
    local l_pid=$!
    
    trap 'cleanup '"${l_pid}"'; exit 1' INT TERM

    # Wait for bridge
    local wait=20
    while ! check_port ${l_port}; do
        sleep 0.5; ((wait--)); [[ ${wait} -le 0 ]] && { cleanup ${l_pid}; err "Log bridge timed out."; }
    done

    ok "Telemetry Synchronized. Press Ctrl+C to close stream."
    ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR \
        -p ${l_port} "root@127.0.0.1" "tail -f ${path}" || true

    kill ${l_pid} 2>/dev/null || true
    ok "Stream closed."
}

cmd_vault() {
    log "Inspecting System Vault Architecture [${VAULT_ID}]..."
    local status
    status=$(kaggle datasets status "${VAULT_ID}" 2>/dev/null || echo "OFFLINE")
    echo -e "   Status: ${C_CYAN}${status}${C_NC}"
    
    echo -e "\n${C_CYAN}--- RECENT CLOUD STATES ---${C_NC}"
    # List files to show latest backup archives
    kaggle datasets files "${VAULT_ID}" | grep ".tar.zst" | tail -n 5 || echo "No backups found."
}

cmd_user_vault() {
    local action="${1:-usage}"
    case "${action}" in
        push)
            local path="${2:-vault}"
            log "Pushing [${path}] to Private System Vault..."
            curl -s "localhost:${ENGINE_PORT}/api/vault/push?path=${path}"
            ok "Vault push job accepted."
            ;;
        list)
            log "Listing Private System Vault contents..."
            curl -s "localhost:${ENGINE_PORT}/api/vault/list" | jq -r '.files[]'
            ;;
        *)
            echo "Usage: vps vault [push|list]"
            echo "  push <path>  Backup a folder/file to HF"
            echo "  list         List files in your private HF vault"
            ;;
    esac
}

cmd_stop() {
    log "Performing pre-flight state verification..."
    local k_status
    k_status=$(kaggle kernels status "${KERNEL_ID}" 2>/dev/null | grep -ioP 'status\s*"?\s*(?:KernelWorkerStatus\.)?\K[a-zA-Z]+' | tr '[:upper:]' '[:lower:]' || echo "offline")
    
    if [[ "${k_status}" == "offline" || "${k_status}" == "complete" || "${k_status}" == "cancelcomplete" || "${k_status}" == "error" ]]; then
        ok "Instance is already stopped. No action required."
        return
    fi

    echo -e "${C_RED}⚠️  WARNING: FORCED TERMINATION REQUESTED${C_NC}"
    echo -e "This will IMMEDIATELY stop and delete the session for ${C_CYAN}${KERNEL_ID}${C_NC}."
    
    if [[ "${1:-}" != "--force" ]]; then
        # Check if stdin is a terminal (don't prompt in CI/non-interactive)
        if [[ -t 0 ]]; then
            echo -en "${C_YELLOW}Are you sure? [y/N]: ${C_NC}"
            read -r confirm
            if [[ "${confirm}" != "y" ]]; then
                log "Stop aborted."
                return
            fi
        else
            err "Non-interactive shell detected. Use '--force' to terminate."
        fi
    fi

    log "Sending PublicNode Shutdown pulse..."
    # Atomic Signal Handler
    local pulse
    pulse="KILL:$(date +%s)"
    curl -s -d "${pulse}" "https://ntfy.sh/${SIGNAL_TOPIC}-control" >/dev/null 2>&1 || true
    
    log "Deleting Kaggle kernel (${KERNEL_ID})..."
    kaggle kernels delete "${KERNEL_ID}" -y >/dev/null 2>&1 || true
    ok "Instance terminated successfully."
}

cmd_new() {
    # Enhanced scaffolding with unique slug suggestions
    local name="${1:-}"
    if [[ -z "${name}" ]]; then
        err "Usage: vps new <instance-name>\nExample: vps new my-second-vps"
    fi
    local new_cfg="${REPO_ROOT}/vps-config-${name}.yaml"
    if [[ -f "${new_cfg}" ]]; then
        err "Config already exists: ${new_cfg}"
    fi

    # Suggest unique slugs manually based on the name
    local safe_name="${name//[^a-z0-9]/-}"
    
    cat > "${new_cfg}" <<EOF
identity:
  vps_name: "VPS-${safe_name}"
  kaggle_username: "${USER_ID}"
  kernel_slug: "vps-${safe_name}"
  vault_slug: "vps-storage-${safe_name}"

engine:
  version: "${ENGINE_VERSION}"
  engine_port: $((ENGINE_PORT + 1))
  ssh_enabled: true
  ssh_port: 22
  gui_enabled: false
  sentinel_enabled: true
  sentinel_interval_sec: 30
  max_file_read_mb: 5
  engine_boot_timeout_sec: 120

tunnel:
  provider: "cloudflared"

signal:
  service: "ntfy.sh"
  topic_prefix: "vps-${safe_name}"

persistence:
  backup_prefix: "auto_backup_"
  backup_compression: "gzip"
  vault_restore_path: "/kaggle/input/vps-storage-${safe_name}"
  workspace_root: "/kaggle/working"

packages:
  system: [curl, wget, git, sudo, zsh, zstd]
  python: [kaggle, psutil, requests]

terminal:
  shell: "/usr/bin/zsh"
  oh_my_zsh: true
EOF

    ok "New config scaffolded: ${new_cfg}"
    log "Slugs were auto-suggested: vps-${safe_name}"
    log "Next step: Create storage dataset 'vps-storage-${safe_name}' on Kaggle."
    log "Then boot with: CONFIG=${new_cfg} vps boot"
}

# ============================================================
# USAGE / HELP
# ============================================================
usage() {
    echo -e "${C_BLUE}====================================================${C_NC}"
    echo -e "          ${PROJECT_NAME} [${VPS_NAME}] v${PROJECT_VERSION}"
    echo -e "         ${C_PURPLE}Industry-Grade Kaggle PTY Architecture${C_NC}"
    echo -e "${C_BLUE}====================================================${C_NC}"
    echo "Usage: ./vps-cli.sh [command] [args]"
    echo ""
    echo -e "  ${C_YELLOW}creds${C_NC}      Copy Kaggle API credentials to auth vault"
    echo -e "  ${C_YELLOW}boot${C_NC}       Build notebook & deploy VPS kernel to Kaggle"
    echo -e "  ${C_YELLOW}ssh${C_NC}        Connect via local terminal (SSH backbone)"
    echo -e "  ${C_YELLOW}et${C_NC}         Zero-latency Echo Shell (Eternal Terminal)"
    echo -e "  ${C_YELLOW}logs${C_NC}       Stream live remote logs"
    echo -e "  ${C_YELLOW}status${C_NC}     Instance health audit (use '--all' for fleet view)"

    echo -e "  ${C_YELLOW}audit${C_NC}      Infrastructure pre-flight checklist"
    echo -e "  ${C_YELLOW}stop${C_NC}       Hard-terminate the cloud instance (use '--force' for CI)"
    echo -e "  ${C_YELLOW}poweroff${C_NC}   Clean remote shutdown (Kill-Pulse)"
    echo -e "  ${C_YELLOW}vault${C_NC}      Inspect System Vault status"
    echo -e "  ${C_YELLOW}link${C_NC}       Print the raw ntfy.sh tunnel URL"
    echo -e "  ${C_YELLOW}alias${C_NC}      Add 'vps' alias to your shell"
    echo -e "  ${C_YELLOW}clean${C_NC}      Purge local auth cache & build artifacts"
    echo -e "  ${C_YELLOW}new${C_NC}        Scaffold a new VPS config  (vps new <name>)"
    echo -e "  ${C_YELLOW}dist${C_NC}       Package app for [apk|linux]"
    echo -e "  ${C_YELLOW}release${C_NC}    Build ALL formats + publish to GitHub Releases"
    echo ""
    echo -e "  Config: ${CONFIG_FILE}"
    echo -e "${C_BLUE}====================================================${C_NC}"
}

cmd_app_url() {
    log "Fetching App Bridge URLs..."
    local ws_u ssh_u
    ws_u=$(get_ws_tunnel || true)
    ssh_u=$(get_ssh_tunnel || true)
    if [[ -n "${ws_u}" ]]; then
        echo -e "${C_GREEN}[APP-WS]${C_NC} ${ws_u}"
    else
        warn "No WebSocket bridge signal found."
    fi
    if [[ -n "${ssh_u}" ]]; then
        echo -e "${C_GREEN}[APP-SSH]${C_NC} ${ssh_u}"
    fi
    if [[ -f "${AUTH_DIR}/vps.pass" ]]; then
        echo -e "${C_YELLOW}[PASS]${C_NC} $(cat "${AUTH_DIR}/vps.pass")"
    fi
}

# ============================================================
# DISPATCH
# ============================================================
case "${1:-}" in
    creds)   cmd_creds ;;
    boot)    cmd_boot ;;
    connect)  err "GUI/Web Access has been removed from this project." ;;
    ssh)      cmd_ssh ;;
    et)       cmd_et ;;
    logs)     cmd_logs "${2:-}" ;;
    sync)     err "Local 'vps sync' removed. Use 'vps sync' inside the SSH session." ;;
    exec)     err "Local 'vps exec' removed. Use the 'vps' command inside SSH." ;;
    top)      err "Local 'vps top' removed. Use the 'vps top' command inside SSH." ;;
    vault)    cmd_vault ;;
    user-vault) cmd_user_vault "${2:-}" "${3:-}" ;;
    status)   cmd_status "${2:-}" ;;
    link)    log "Fetching backbone link..."; get_ssh_tunnel || warn "No signal found." ;;
    app-url) cmd_app_url ;;
    alias)   cmd_alias ;;
    clean)
        log "Purging generated build artifacts..."
        rm -f "${REPO_ROOT}/publicnode-vps-engine/vps_setup.ipynb"
        rm -rf "${REPO_ROOT}/publicnode-vps-engine/vps-os"
        rm -f "${AUTH_DIR}/vps.pass"
        ok "Generated artifacts cleared. Credentials preserved."
        ;;
    audit)    cmd_audit ;;
    stop)     cmd_stop "${2:-}" ;;
    poweroff) cmd_poweroff ;;
    new)     cmd_new "${2:-}" ;;
    dist)    uv run vps-dist "${2:-}" ;;
    release) uv run vps-release ;;
    *)       usage ;;
esac
