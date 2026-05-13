#!/usr/bin/env bash
# XEQM Labs — Service Node Key Transfer Tool
# Exports, imports, and transfers service node keys between users or servers.

set -euo pipefail

script_basedir=$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")
readonly script_basedir

source "${script_basedir}/common.sh"
source "${script_basedir}/discovery.sh"

transfer_version='v1.0'
readonly transfer_version

typeset -A command_options_set
command_options_set=(
  [help]=0
  [list]=0
  [export]=0
  [import]=0
  [transfer]=0
  [user]=0
  [from_user]=0
  [to_user]=0
  [key_file]=0
  [output_dir]=0
  [quiet]=0
)

user_option_value=
from_user_option_value=
to_user_option_value=
key_file_option_value=
output_dir_option_value=.

main() {
  install_dependencies
  print_splash_screen "Service Node Transfer" "${transfer_version}"
  process_command_line_args "$@"
  execute_command
}

install_dependencies() {
  if ! [[ -x "$(command -v ss)" && -x "$(command -v natsort)" && -x "$(command -v gawk)" ]]; then
    echo -e "\n\033[1mFixing required dependencies...\033[0m"
    sudo apt -y install iproute2 python3-natsort gawk
  fi
}

process_command_line_args() {
  parse_command_line_args "$@"
  validate_parsed_command_line_args
  set_config_options
}

parse_command_line_args() {
  args="$(getopt -a -n transfer -o "hqf:t:u:k:o:" \
    --long help,quiet,list,export,import,transfer,from:,to:,user:,key-file:,output-dir: -- "$@")"
  eval set -- "${args}"

  while :; do
    case "$1" in
      -h | --help)        command_options_set[help]=1; shift ;;
      -q | --quiet)       command_options_set[quiet]=1; shift ;;
      --list)             command_options_set[list]=1; shift ;;
      --export)           command_options_set[export]=1; shift ;;
      --import)           command_options_set[import]=1; shift ;;
      --transfer)         command_options_set[transfer]=1; shift ;;
      -f | --from)        command_options_set[from_user]=1; from_user_option_value="$2"; shift 2 ;;
      -t | --to)          command_options_set[to_user]=1; to_user_option_value="$2"; shift 2 ;;
      -u | --user)        command_options_set[user]=1; user_option_value="$2"; shift 2 ;;
      -k | --key-file)    command_options_set[key_file]=1; key_file_option_value="$2"; shift 2 ;;
      -o | --output-dir)  command_options_set[output_dir]=1; output_dir_option_value="$2"; shift 2 ;;
      --)                 shift; break ;;
      *)                  echo "Unexpected option: $1"; usage; exit 1 ;;
    esac
  done
}

validate_parsed_command_line_args() {
  local ops_set=0
  for op in list export import transfer; do
    [[ "${command_options_set[${op}]}" -eq 1 ]] && ops_set=$((ops_set + 1))
  done

  if [[ "${command_options_set[help]}" -eq 1 ]]; then usage; exit 0; fi

  if [[ "${ops_set}" -eq 0 ]]; then
    echo -e "\033[0;33merror: specify one of --list, --export, --import, or --transfer\033[0m\n"
    usage
    exit 1
  fi

  if [[ "${ops_set}" -gt 1 ]]; then
    echo -e "\033[0;33merror: only one of --list, --export, --import, --transfer may be used at a time\033[0m\n"
    exit 1
  fi
}

set_config_options() {
  [[ "${command_options_set[quiet]}" -eq 1 ]] && config[quiet_mode]=1
}

execute_command() {
  if   [[ "${command_options_set[list]}"     -eq 1 ]]; then list_nodes
  elif [[ "${command_options_set[export]}"   -eq 1 ]]; then export_key
  elif [[ "${command_options_set[import]}"   -eq 1 ]]; then import_key
  elif [[ "${command_options_set[transfer]}" -eq 1 ]]; then local_transfer
  fi
}

# ── list ──────────────────────────────────────────────────────────────────────

list_nodes() {
  declare -A daemon_users
  discover_daemons daemon_users 'user'

  if [[ "${#daemon_users[@]}" -eq 0 ]]; then
    echo -e "\nNo active XEQM service node daemons found on this server."
    exit 0
  fi

  echo ""
  printf "  %-16s %s\n" "User" "Public Key"
  printf "  %-16s %s\n" "────────────────" "$(printf '─%.0s' {1..64})"

  for username in "${daemon_users[@]}"; do
    local sn_key
    sn_key="$(sudo -H -u "${username}" bash -c \
      'cd ~/xeqm-installer/ && bash xeqm-node.sh print_sn_key 2>/dev/null' \
      | grep 'Public Key:' | grep -oP '(?<=: ).*' || echo 'unavailable')"
    printf "  %-16s %s\n" "${username}" "${sn_key}"
  done
  echo ""
}

# ── export ────────────────────────────────────────────────────────────────────

export_key() {
  local username="${user_option_value}"
  local output_dir="${output_dir_option_value}"

  if [[ -z "${username}" ]]; then
    echo -e "\033[0;33merror: --user is required for --export\033[0m\n"
    usage; exit 1
  fi

  if ! id -u "${username}" >/dev/null 2>&1; then
    echo -e "\033[0;31merror\033[0m: User '${username}' not found."
    exit 1
  fi

  local key_file="/home/${username}/.equilibria/key"
  if [[ ! -f "${key_file}" ]]; then
    echo -e "\033[0;31merror\033[0m: No key file at '${key_file}'."
    exit 1
  fi

  local timestamp; timestamp="$(date +%Y%m%d%H%M%S)"
  local archive="${output_dir}/xeqm-key-${username}-${timestamp}.tar.gz"

  echo -e "\n\033[1mExporting key for '${username}'...\033[0m"

  # Read public key before stopping (daemon still running)
  local pubkey
  pubkey="$(sudo -H -u "${username}" bash -c \
    'cd ~/xeqm-installer/ && bash xeqm-node.sh print_sn_key 2>/dev/null' \
    | grep 'Public Key:' | grep -oP '(?<=: ).*' || echo 'unavailable')"

  sudo tar -czf "${archive}" -C "/home/${username}/.equilibria" key
  sudo chmod 600 "${archive}"
  sudo chown "$(id -un):$(id -gn)" "${archive}"

  echo -e "\n\033[1;32mKey exported successfully.\033[0m"
  echo -e "  Archive:    ${archive}"
  echo -e "  Public Key: ${pubkey}"
  echo -e "\n\033[0;33mWARNING: This archive controls the service node. Keep it secure.\033[0m"
  echo -e "\nTo import on another server:"
  echo -e "  1. Copy '${archive##*/}' to the target server"
  echo -e "  2. bash transfer.sh --import --user <target_user> --key-file /path/to/${archive##*/}"
}

# ── import ────────────────────────────────────────────────────────────────────

import_key() {
  local username="${user_option_value}"
  local archive="${key_file_option_value}"

  if [[ -z "${username}" || -z "${archive}" ]]; then
    echo -e "\033[0;33merror: --user and --key-file are both required for --import\033[0m\n"
    usage; exit 1
  fi

  if ! id -u "${username}" >/dev/null 2>&1; then
    echo -e "\033[0;31merror\033[0m: User '${username}' not found. Run install.sh first to create the node."
    exit 1
  fi

  if [[ ! -f "${archive}" ]]; then
    echo -e "\033[0;31merror\033[0m: Key archive '${archive}' not found."
    exit 1
  fi

  if [[ "${config[quiet_mode]}" -eq 0 ]]; then
    echo -e "\n\033[0;33mWARNING: This will replace the current key for user '${username}'.\033[0m"
    while true; do
      read -rp $'\nProceed? [y/N]: ' yn
      yn="${yn:-N}"
      case "${yn}" in
        [Yy]*) break ;;
        [Nn]*) echo "Aborted."; exit 0 ;;
        *) echo "(Please answer Y or N)" ;;
      esac
    done
  fi

  local equilibria_dir="/home/${username}/.equilibria"

  echo -e "\n\033[1mStopping service node daemon for '${username}'...\033[0m"
  sudo -H -u "${username}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh stop' 2>/dev/null || true

  if [[ -f "${equilibria_dir}/key" ]]; then
    local backup="${equilibria_dir}/key.bak.$(date +%Y%m%d%H%M%S)"
    sudo mv "${equilibria_dir}/key" "${backup}"
    echo -e "  Existing key backed up to: ${backup}"
  fi

  echo -e "\033[1mImporting key...\033[0m"
  sudo mkdir -p "${equilibria_dir}"
  sudo tar -xzf "${archive}" -C "${equilibria_dir}"
  sudo chown "${username}:${username}" "${equilibria_dir}/key"
  sudo chmod 600 "${equilibria_dir}/key"

  echo -e "\n\033[1;32mKey imported successfully.\033[0m"
  echo -e "\nStarting service node daemon for '${username}'..."
  sudo -H -u "${username}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh start'

  echo -e "\n\033[1mNext step:\033[0m The daemon is running with the imported key."
  echo -e "If this is a new server, re-register the node with:"
  echo -e "  sudo -H -u ${username} bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh prepare_sn'"
}

# ── local transfer ────────────────────────────────────────────────────────────

local_transfer() {
  local from_user="${from_user_option_value}"
  local to_user="${to_user_option_value}"

  if [[ -z "${from_user}" || -z "${to_user}" ]]; then
    echo -e "\033[0;33merror: --from and --to are both required for --transfer\033[0m\n"
    usage; exit 1
  fi

  for u in "${from_user}" "${to_user}"; do
    if ! id -u "${u}" >/dev/null 2>&1; then
      echo -e "\033[0;31merror\033[0m: User '${u}' not found."
      exit 1
    fi
  done

  if [[ ! -f "/home/${from_user}/.equilibria/key" ]]; then
    echo -e "\033[0;31merror\033[0m: No key file found for user '${from_user}'."
    exit 1
  fi

  if [[ "${config[quiet_mode]}" -eq 0 ]]; then
    echo -e "\n\033[0;33mThis will transfer the key from '${from_user}' to '${to_user}'.\033[0m"
    echo -e "The '${to_user}' node will be stopped during the transfer.\n"
    while true; do
      read -rp "Proceed? [y/N]: " yn
      yn="${yn:-N}"
      case "${yn}" in
        [Yy]*) break ;;
        [Nn]*) echo "Aborted."; exit 0 ;;
        *) echo "(Please answer Y or N)" ;;
      esac
    done
  fi

  echo -e "\n\033[1mTransferring key from '${from_user}' to '${to_user}'...\033[0m"

  # Snapshot key to a temp archive
  local tmp_archive; tmp_archive="$(mktemp /tmp/xeqm-transfer-XXXXXX.tar.gz)"
  sudo tar -czf "${tmp_archive}" -C "/home/${from_user}/.equilibria" key

  # Stop destination node
  echo -e "  Stopping '${to_user}' daemon..."
  sudo -H -u "${to_user}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh stop' 2>/dev/null || true

  local to_dir="/home/${to_user}/.equilibria"
  if [[ -f "${to_dir}/key" ]]; then
    local backup="${to_dir}/key.bak.$(date +%Y%m%d%H%M%S)"
    sudo mv "${to_dir}/key" "${backup}"
    echo -e "  Existing key backed up to: ${backup}"
  fi

  sudo mkdir -p "${to_dir}"
  sudo tar -xzf "${tmp_archive}" -C "${to_dir}"
  sudo chown "${to_user}:${to_user}" "${to_dir}/key"
  sudo chmod 600 "${to_dir}/key"
  sudo rm -f "${tmp_archive}"

  echo -e "\n\033[1;32mKey transferred successfully.\033[0m"
  echo -e "\nStarting '${to_user}' daemon..."
  sudo -H -u "${to_user}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh start'
}

# ── usage ─────────────────────────────────────────────────────────────────────

usage() {
  cat <<USAGEMSG

bash $0 [COMMAND] [OPTIONS...]

Commands:
  --list                          List all active service nodes and their public keys.

  --export                        Export a node's key to a portable archive.
    -u --user [name]              User whose key to export.
    -o --output-dir [path]        Directory to write the archive (default: current dir).

  --import                        Import a key archive into a node user.
    -u --user [name]              Target user to receive the key.
    -k --key-file [path]          Path to the .tar.gz archive produced by --export.

  --transfer                      Transfer a key between two users on this server.
    -f --from [user]              Source user.
    -t --to   [user]              Destination user.

Global Options:
  -q --quiet                      Non-interactive: skip confirmation prompts.
  -h --help                       Show this help text.

Examples:
  # See all nodes and keys
  bash $0 --list

  # Export snode1's key for migration to another server
  bash $0 --export --user snode1 --output-dir /tmp

  # Import on the new server
  bash $0 --import --user snode2 --key-file /tmp/xeqm-key-snode1-20260513120000.tar.gz

  # Move key from snode1 to snode3 on the same server
  bash $0 --transfer --from snode1 --to snode3

USAGEMSG
}

finally() {
  result=$?
  echo ""
  exit "${result}"
}
trap finally EXIT ERR INT

main "${@}"
exit 0
