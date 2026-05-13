#!/usr/bin/env bash
# by Mister R

set -o errexit
set -o nounset
set -o pipefail

script_basedir=$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")
readonly script_basedir

source "${script_basedir}/discovery.sh"

eqnode_doctor_version='v1.5'
readonly eqnode_doctor_version

typeset -A doctor_config
doctor_config=(
  [fix_mode]='interactive'
)

typeset -A command_options_set
command_options_set=(
  [help]=0
  [auto_fix]=0
)


main() {
  install_dependencies
  print_splash_screen
  process_command_line_args "$@"

  analyze_and_fix
}

print_splash_screen() {
  print_splash_screen "Service Node Doctor" "${eqnode_doctor_version}"
}

install_dependencies() {
  if ! [[ -x "$(command -v ss)" && -x "$(command -v openssl)" && -x "$(command -v natsort)" && -x "$(command -v grep)" && -x "$(command -v getopt)" && -x "$(command -v gawk)" ]]; then
    echo -e "\n\033[1mFixing required dependencies....\033[0m"
    sudo apt -y install iproute2 openssl python3-natsort grep util-linux gawk
  fi
}

process_command_line_args() {
  parse_command_line_args "$@"
  validate_parsed_command_line_args
  set_config_and_execute_info_commands
}

parse_command_line_args() {
  args="$(getopt -a -n installer -o "hf" --long help,auto-fix -- "$@")"
  eval set -- "${args}"

  while :
  do
    case "$1" in
      -h | --help)                  command_options_set[help]=1 ; shift ;;
      -f | --auto-fix)              command_options_set[auto_fix]=1; shift ;;
      --)                           shift ; break ;;
      *)                            echo "Unexpected option: $1" ;
                                    usage
                                    exit 0 ;;
    esac
  done
}

validate_parsed_command_line_args() {
  local friendly_option_groupings group_option_count command_options_set_string unique_count valid_option_combi_found
  valid_option_combi_found=0

  friendly_option_groupings=(
    "<no_options_set>"
    "auto_fix"
    "help"
  )
  command_options_set_string="$(generate_set_options_string)"
  [[ "${command_options_set_string}" = '' ]] && command_options_set_string='<no_options_set>'

  for option_string in "${friendly_option_groupings[@]}"
  do
    group_option_count="$(echo "${option_string}" | egrep -o '[^ ]+' | wc -l)"
    unique_count="$(echo "${option_string} ${command_options_set_string}" | egrep -o '[^ ]+' | natsort | uniq | wc -l)"

    [[ "${unique_count}" -le "${group_option_count}" ]] && valid_option_combi_found=1 && break
  done

  if [[ "${valid_option_combi_found}" -eq 0 && "${command_options_set_string}" != '<no_options_set>' ]]; then
    echo -e "\033[0;33merror: Invalid parameter combination\033[0m\n"
    usage
    exit 1
  fi
}

set_config_and_execute_info_commands() {
  [[ "${command_options_set[help]}" -eq 1 ]] && usage && exit 0
  [[ "${command_options_set[auto_fix]}" -eq 1 ]] && auto_fix_mode_option_handler

  # necessary return 0
  return 0
}

generate_set_options_string() {
  local result=''
  for option in "${!command_options_set[@]}"
  do
    [[ "${command_options_set[$option]}" -eq 1 ]] && result+="${option} "
  done
  echo "${result}"
}

auto_fix_mode_option_handler() {
  doctor_config[fix_mode]='auto'
}

analyze_and_fix() {
  declare -A daemon_users
  echo -e "\n\033[1mAnalyzing active service nodes...\033[0m"
  discover_daemons daemon_users 'user'

  if [[ "${#daemon_users[@]}" -eq 0 ]]; then
    echo -e "\n\033[0;33mNo active XEQM service node daemons found on this server.\033[0m"
    exit 0
  fi

  # --- Global checks ---
  echo -e "\n\033[1mRunning global checks...\033[0m"

  # NTP check
  local ntp_ok=1
  if [[ -x "$(command -v timedatectl)" ]]; then
    if [[ $(sudo timedatectl | grep -o -e 'synchronized: yes' -e 'service: active' | wc -l) -ne 2 ]]; then
      echo -e "  \033[0;31m[FAIL]\033[0m NTP not synchronized — clock drift can cause node deregistration"
      ntp_ok=0
    else
      echo -e "  \033[0;32m[ OK ]\033[0m NTP synchronized"
    fi
  fi

  # Disk space check (warn if < 20 GB free on /home)
  local free_gb
  free_gb=$(( $(df /home | awk 'END{ print $4 }') / 1024 / 1024 ))
  if [[ "${free_gb}" -lt 20 ]]; then
    echo -e "  \033[0;31m[WARN]\033[0m Low disk space: ${free_gb} GB free on /home (recommended: 50+ GB)"
  else
    echo -e "  \033[0;32m[ OK ]\033[0m Disk space: ${free_gb} GB free on /home"
  fi

  # --- Fetch external block height ---
  echo -e "\n\033[1mFetching external blockchain state...\033[0m"
  local current_block
  current_block="$(wget --quiet https://explorer.equilibria.cc/ -O - | grep -o 'XEQ as of block .*' | sed -n 's/^XEQ as of block \([0-9]*\).*/\1/p')"
  if [[ -z "${current_block}" || ! "${current_block}" =~ ^[0-9]+$ ]]; then
    echo -e "\033[0;31mFATAL\033[0m: Could not retrieve current block height from explorer. Check network connectivity."
    exit 1
  fi
  echo -e "  Explorer current block: ${current_block}"

  local allowed_block_difference=2
  local current_block_with_margin=$((current_block - allowed_block_difference))
  declare -A healthy_blockchains
  declare -A bad_blockchains
  local badidx=1
  local healthyidx=1
  # Remediation plan lines collected here
  local -a remediation_lines=()

  # --- Per-node checks ---
  local blocks_done total_blocks perc service_node_key service_status

  for username in "${daemon_users[@]}"; do
    tput rev; printf "\n\033[1m  %s  \033[0m\n" "${username}"; tput sgr0

    # Service status
    local svc_name="eqnode_${username}.service"
    if sudo systemctl is-active --quiet "${svc_name}" 2>/dev/null; then
      echo -e "  \033[0;32m[ OK ]\033[0m Service ${svc_name}: active"
    else
      echo -e "  \033[0;31m[FAIL]\033[0m Service ${svc_name}: not running"
      remediation_lines+=("${username}: service not running")
      remediation_lines+=("  → sudo systemctl start ${svc_name}")
    fi

    # Disk space per user
    local user_disk_gb
    user_disk_gb=$(( $(df "/home/${username}" | awk 'END{ print $4 }') / 1024 / 1024 ))
    if [[ "${user_disk_gb}" -lt 10 ]]; then
      echo -e "  \033[0;31m[WARN]\033[0m Disk space for ${username}: ${user_disk_gb} GB free"
      remediation_lines+=("${username}: low disk space (${user_disk_gb} GB free)")
      remediation_lines+=("  → du -sh /home/${username}/.equilibria")
    fi

    # SN key and registration status
    service_node_key="$(sudo -H -u "${username}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh print_sn_key 2>/dev/null' | grep 'Public Key:' | grep -oP '(?<=: )+.*' || true)"
    if [[ -n "${service_node_key}" ]]; then
      echo -e "  \033[0;32m[ OK ]\033[0m Public key: ${service_node_key}"
      echo -e "\n  \033[1mNetwork registration status:\033[0m"
      sudo -H -u "${username}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh print_sn_status 2>/dev/null' | sed 's/^/  /' || true
    else
      echo -e "  \033[0;33m[WARN]\033[0m Could not retrieve public key (daemon may be down or unregistered)"
      remediation_lines+=("${username}: unable to read public key")
      remediation_lines+=("  → sudo -H -u ${username} bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh prepare_sn'")
    fi

    # Blockchain sync state
    read -r blocks_done total_blocks perc <<< "$(sudo -H -u "${username}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh status 2>/dev/null' | grep -o 'Height:.*' | sed -n 's/^Height: \([0-9]*\)\/\([0-9]*\) (\([0-9.]*\).*/\1 \2 \3/p' || true)"

    echo -e "\n  Local blockchain height: ${blocks_done:-unknown} / ${total_blocks:-unknown} (${perc:-?}%)"

    if [[ -z "${blocks_done}" ]]; then
      echo -e "  \033[0;31m[FAIL]\033[0m Cannot determine blockchain state"
      bad_blockchains["$badidx"]="${username}"
      badidx=$((badidx + 1))
      remediation_lines+=("${username}: daemon not responding to status")
      remediation_lines+=("  → sudo journalctl -u ${svc_name} -n 50")
    elif [[ "${blocks_done}" -lt "${current_block_with_margin}" && "${perc}" = "100.0" ]]; then
      echo -e "  \033[0;31m[FAIL]\033[0m Blockchain state: CORRUPT / STUCK"
      bad_blockchains["$badidx"]="${username}"
      badidx=$((badidx + 1))
      remediation_lines+=("${username}: blockchain corrupt/stuck at block ${blocks_done} (expected ${current_block})")
      remediation_lines+=("  → sudo -H -u ${username} bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh stop'")
      remediation_lines+=("  → # replace /home/${username}/.equilibria/lmdb with bootstrap or healthy donor")
      remediation_lines+=("  → sudo -H -u ${username} bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh start'")
    elif [[ "${blocks_done}" -lt "${current_block_with_margin}" ]]; then
      echo -e "  \033[0;33m[SYNC]\033[0m Blockchain syncing (${blocks_done} / ${current_block})"
    else
      echo -e "  \033[0;32m[ OK ]\033[0m Blockchain: HEALTHY (${blocks_done} / ${total_blocks})"
      healthy_blockchains["$healthyidx"]="${username}"
      healthyidx=$((healthyidx + 1))
    fi
  done

  # --- Remediation plan ---
  if [[ "${#remediation_lines[@]}" -gt 0 ]]; then
    echo ""
    tput rev; echo -e "\033[1m  REMEDIATION PLAN  \033[0m"; tput sgr0
    echo ""
    for line in "${remediation_lines[@]}"; do
      echo -e "  ${line}"
    done
    echo ""
  fi

  # --- Auto-fix bad blockchains from healthy donors ---
  if [[ "${#bad_blockchains[@]}" -gt 0 && "${#healthy_blockchains[@]}" -gt 0 ]]; then
    if [[ "${doctor_config[fix_mode]}" = "interactive" ]]; then
      while true; do
        read -rp $'\n\033[1mCorrupt/stuck blockchains found. Auto-fix from healthy donor?\e[0m [Y/N]: ' yn
        yn="${yn:-N}"
        case "${yn}" in
          [Yy]*) break ;;
          [Nn]*) exit 0 ;;
          *) echo "(Please answer Y or N)" ;;
        esac
      done
    fi

    local healthy_blockchain_dir="/home/${healthy_blockchains[1]}/.equilibria"
    for username_bad in "${bad_blockchains[@]}"; do
      echo -e "\n\033[1mFixing blockchain for '${username_bad}'...\033[0m"
      sudo -H -u "${username_bad}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh stop'

      local bad_blockchain_dir="/home/${username_bad}/.equilibria"
      echo -e "  Replacing lmdb from donor '${healthy_blockchains[1]}'... (may take several minutes)"
      sudo rm -Rf "${bad_blockchain_dir}/lmdb"
      sudo cp -R "${healthy_blockchain_dir}/lmdb" "${bad_blockchain_dir}"
      sudo chown -R "${username_bad}:${username_bad}" "${bad_blockchain_dir}"

      sudo -H -u "${username_bad}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh start'
      echo -e "  \033[0;32mDone.\033[0m"
    done

  elif [[ "${#bad_blockchains[@]}" -gt 0 ]]; then
    echo -e "\n\033[0;33mCorrupt/stuck nodes found but no healthy donor available on this server.\033[0m"

    local fix_choice
    prompt_menu "How would you like to fix the corrupt node(s)?" fix_choice 1 \
      "Download bootstrap from https://bootstrap.xeqmlabs.com  (~15 min)" \
      "Skip — I will fix manually later"

    if [[ "${fix_choice}" -eq 1 ]]; then
      for username_bad in "${bad_blockchains[@]}"; do
        echo -e "\n\033[1mFixing '${username_bad}' via bootstrap...\033[0m"
        sudo -H -u "${username_bad}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh stop' 2>/dev/null || true

        local bootstrap_url="https://bootstrap.xeqmlabs.com/lmdb.tar.gz"
        local tmp_file="/tmp/xeqm-bootstrap-$$.tar.gz"
        local target_dir="/home/${username_bad}/.equilibria"

        echo -e "  Downloading bootstrap..."
        wget --progress=bar:force:noscroll -O "${tmp_file}" "${bootstrap_url}"

        echo -e "  Replacing blockchain data..."
        sudo rm -Rf "${target_dir}/lmdb"
        sudo tar -xzf "${tmp_file}" -C "${target_dir}"
        sudo rm -f "${tmp_file}"
        sudo chown -R "${username_bad}:${username_bad}" "${target_dir}"

        sudo -H -u "${username_bad}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh start'
        echo -e "  \033[0;32mDone.\033[0m"
      done
    else
      echo -e "\nSkipped. See the remediation plan above for manual steps."
    fi
  else
    echo -e "\n\033[1;32mAll nodes healthy.\033[0m"
  fi
}

usage() {
  cat <<USAGEMSG

bash $0 [OPTIONS...]

Options:
  -f --auto-fix                         Scans for "corrupted" blockchains of active service
                                        nodes and will attempt to fix it without user interaction

  -h  --help                            Show this help text

USAGEMSG
}

finally() {
  result=$?
  echo ""
  exit ${result}
}
trap finally EXIT ERR INT

main "${@}"
exit 0

