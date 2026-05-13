xeqmnode_installer_version='v6.2'
readonly xeqmnode_installer_version

version_regex="^v[0-9]+.[0-9]+.[0-9]+$"
readonly version_regex

rev_hash_regex="^[0-9a-f]{5,40}$"
readonly rev_hash_regex

installer_session_state_file="${script_basedir}/.installsessionstate"
readonly installer_session_state_file

typeset -A config
config=(
  [nodes]=1
  [install_version]='auto'
  [running_user]='snode'
  [required_cmake_version]='3.28'
  [git_repository]='https://github.com/EquilibriaCC/Equilibria.git'
  [p2p_bind_port]=9230
  [rpc_bind_port]=9231
  [daemon_log_level]=
  [daemon_no_fluffy_blocks]=0
  [open_firewall]=0
  [quiet_mode]=0
)

typeset -A installer_state
installer_state=(
  [started]='started'
  [install_packages]='install_packages'
  [checkout_git]='checkout_git'
  [compile_move]='compile_move'
  [install_service]='install_service'
  [enable_service]='enable_service'
  [start_service]='start_service'
  [watch_daemon]='watch_daemon'
  [ask_prepare]='ask_prepare'
  [finished_xeqmnode_install]='finished_xeqmnode_install'
)
readonly installer_state

typeset -A default_service_node_ports
default_service_node_ports=(
  [p2p_bind_port]=9230
  [rpc_bind_port]=9231
)
readonly default_service_node_ports

load_config() {
  local config_file="$1"
  local -n lc__config_ref="$2"
  if [[ -f "${config_file}" ]]; then
    while IFS= read -r line; do
      if echo "${line}" | grep -q "="; then
        varname=$(echo "${line}" | cut -d '=' -f 1)
        varvalue=$(echo "${line}" | cut -d '=' -f 2-)
        lc__config_ref[${varname}]=${varvalue}
      fi
    done < "${config_file}"
  fi
}

write_config() {
  local -n wc__node_config_ref="$1"
  local install_file_conf_path="$2"

  if [[ -f "${install_file_conf_path}" ]]; then
    sudo rm -Rf "${install_file_conf_path}"
  fi
  sudo touch "${install_file_conf_path}"

  for key in "${!wc__node_config_ref[@]}"
  do
    echo -e "${key}=${wc__node_config_ref[${key}]}" | sudo tee -a "${install_file_conf_path}"
  done
  sudo chown "${wc__node_config_ref[running_user]}":root "${install_file_conf_path}"
}

#### Common command line option handlers for upgrade.sh & install.sh ###
version_option_handler() {
  if [[ "$1" = "auto" ]]; then
    echo -e "\n\033[1mAuto-detecting latest XEQM version tag...\033[0m"
    config[install_version]="$(get_latest_equilibria_version_number)"
  elif [[ "$1" = "master" || "$1" =~ ${version_regex} || "$1" =~ ${rev_hash_regex} ]]; then
    echo -e "\n\033[1mUsing manually set XEQM branch/version/hash:\033[0m"
    config[install_version]="$1"
  else
    echo -e "\033[0;33merror: Invalid --version value '$1'\033[0m\n"
    usage
    exit 1
  fi
  echo -e "-> ${config[install_version]}"
}

daemon_log_level_option_handler() {
  if [[ -n "$1" ]]; then
    config[daemon_log_level]="$1"
  fi
}

git_repository_option_handler() {
  if [[ -n "$1" ]]; then
    config[git_repository]="$1"
  fi
}

#### END Common command line option handlers
pre_install_checks () {
  echo -e "\n\033[1mExecuting pre-install checks...\033[0m"
  inspect_time_services
  upgrade_cmake_if_needed
}

inspect_time_services () {
  echo -e "\n\033[1mChecking clock NTP synchronisation...\033[0m"

  if  [[ -x "$(command -v timedatectl)" ]]; then
    if [[ $(sudo timedatectl | grep -o -e 'synchronized: yes' -e 'service: active' | wc -l) -ne 2 ]]; then
      echo -e "\n\033[0;33mERROR: Clock NTP synchronisation is not working correctly. This is required to run a stable service node. Please fix 'timedatectl' before continuing.\033[0m\n"
      timedatectl
      exit 1
    fi
  else
    echo -e "\033[0;33mWARNING: Clock NTP synchronisation could not be verified.\nPlease check and make sure this is working before continuing!\033[0m\n"
    if [[ "${config[quiet_mode]:-0}" -eq 1 ]]; then
      echo -e "\033[0;33mQuiet mode: continuing without NTP confirmation.\033[0m"
      return 0
    fi
    while true; do
      read -p $'\033[1mAre you sure you want to continue?\e[0m (NOT RECOMMENDED) [Y/N]: ' yn
      yn=${yn:-N}

      case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit 1;;
            * ) echo -e "(Please answer Y or N)";;
      esac
    done
  fi
}

upgrade_cmake_if_needed() {
  local current_cmake_version

  # skip upgrade cmake when we do not need the compile binaries
  if [[ ! -z "${command_options_set[copy_binaries]:-}" && "${command_options_set[copy_binaries]}" -eq 1 ]]; then
    echo -e "\n\033[1mSkipping cmake upgrade checks, using existing binaries...\033[0m"
    return 0
  fi

  [[ -x "$(command -v cmake)" ]] && current_cmake_version="$(cmake --version | awk 'NR==1 { print $3  }')" || current_cmake_version='not installed'

  if [[ "${system_info[distro]}" = "ubuntu" && ( "${current_cmake_version}" = 'not installed' || "$(version2num "${current_cmake_version}")" -lt "$(version2num "${config[required_cmake_version]}")" ) ]]; then
    echo -e "\n\033[1mUpgrading cmake (${current_cmake_version}) to newest version...\033[0m"
    sudo apt-get update
    sudo apt-get -y install gpg wget
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | sudo tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ ${system_info[codename]} main" | sudo tee /etc/apt/sources.list.d/kitware.list >/dev/null
    sudo apt-get update
    sudo apt-get -y install cmake
  fi
}

validate_command_line_option_combinations() {
  local -n vcloc__valid_option_combination_ref=$1
  local group_option_count command_options_set_string unique_count valid_option_combi_found
  valid_option_combi_found=0

  command_options_set_string="$(generate_set_options_string)"
  [[ "${command_options_set_string}" = '' ]] && command_options_set_string='<no_options_set>'

  for option_string in "${vcloc__valid_option_combination_ref[@]}"
  do
    group_option_count="$(echo "${option_string}" | egrep -o '[^ ]+' | wc -l)"
    unique_count="$(echo "${option_string} ${command_options_set_string}" | egrep -o '[^ ]+' | natsort | uniq | wc -l)"

    [[ "${unique_count}" -le "${group_option_count}" ]] && valid_option_combi_found=1 && break
  done

  if [[ "${valid_option_combi_found}" -eq 0 && "${command_options_set_string}" != '<no_options_set>' ]]; then
    echo -e "\033[0;33merror: Invalid option combination\033[0m\n"
    usage
    exit 1
  fi
}

generate_set_options_string() {
  local result=''
  for option in "${!command_options_set[@]}"
  do
    [[ "${command_options_set[$option]}" -eq 1 ]] && result+="${option} "
  done
  echo "${result}"
}

copy_binaries_to_directory(){
  local source_dir="$1"
  local target_dir="$2"

  if [[ -d "${target_dir}" ]]; then
    # move existing bin directory just to be safe
    sudo mv "${target_dir}" "${target_dir}_$(echo $RANDOM | md5sum | head -c 8)"
  fi
  echo -e "\n\033[1mCopying binaries from '${source_dir}' to '${target_dir}'.\033[0m"
  sudo cp -R "${source_dir}" "${target_dir}"
}

validate_manual_user_string_format() {
  [[ "$(echo "$1" | grep -oP -e "(?<=,|^)+[a-zA-Z][a-zA-Z0-9]+(?=,|$)+" | natsort | uniq | wc -l)" -gt 0 ]]
}

set_install_session_state() {
  local newstate="${1}"
  printf "%s" "${newstate}" > "${installer_session_state_file}"
}

read_install_session_state() {
  cat "${installer_session_state_file}"
}

default_ports_configured() {
  [[
    "${config[p2p_bind_port]}" -eq "${default_service_node_ports[p2p_bind_port]}" &&
    "${config[rpc_bind_port]}" -eq "${default_service_node_ports[rpc_bind_port]}"
  ]]
}

get_latest_equilibria_version_number() {
  local version
  version="$(git ls-remote --tags "${config[git_repository]}" 2>/dev/null | grep -o 'v.*' | sort -V | tail -1)"
  if [[ -z "${version}" ]]; then
    printf "\033[0;31mFATAL\033[0m: Could not retrieve latest version from '%s'. Check network connectivity.\n" "${config[git_repository]}" >&2
    exit 1
  fi
  echo "${version}"
}

version2num() {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1, $2, $3, $4); }'
}

# prompt_menu <title> <nameref-result> <default-index> <option1> [option2 ...]
# In quiet mode uses the default without prompting.
prompt_menu() {
  local title="$1"
  local -n pm__result="$2"
  local default="${3:-1}"
  shift 3
  local options=("$@")

  if [[ "${config[quiet_mode]:-0}" -eq 1 ]]; then
    pm__result="${default}"
    return 0
  fi

  echo -e "\n\033[1m${title}\033[0m\n"
  local idx=1
  for option in "${options[@]}"; do
    printf "  \033[1;33m[%d]\033[0m %s\n" "${idx}" "${option}"
    idx=$((idx + 1))
  done
  echo ""

  local choice
  while true; do
    read -rp "  Choice [${default}]: " choice
    choice="${choice:-${default}}"
    if [[ "${choice}" =~ ^[0-9]+$ && "${choice}" -ge 1 && "${choice}" -le "${#options[@]}" ]]; then
      pm__result="${choice}"
      return 0
    fi
    echo -e "  \033[0;33mPlease enter a number between 1 and ${#options[@]}\033[0m"
  done
}

print_splash_screen() {
  local subtitle="${1:-Service Node Installer}"
  local ver="${2:-${xeqmnode_installer_version}}"
  local inner="XEQM Labs  ·  ${subtitle}  ·  ${ver}"
  local inner_len=${#inner}
  local box_inner_width=54
  local pad_left=$(( (box_inner_width - inner_len) / 2 ))
  local pad_right=$(( box_inner_width - inner_len - pad_left ))
  local border
  border="$(printf '═%.0s' $(seq 1 ${box_inner_width}))"
  echo ""
  echo -e "\033[1;36m  ╔${border}╗\033[0m"
  echo -e "\033[1;36m  ║\033[0m$(printf ' %.0s' $(seq 1 ${box_inner_width}))\033[1;36m║\033[0m"
  printf "\033[1;36m  ║\033[0m%*s\033[1;37m%s\033[0m%*s\033[1;36m║\033[0m\n" \
    "${pad_left}" "" "${inner}" "${pad_right}" ""
  echo -e "\033[1;36m  ║\033[0m$(printf ' %.0s' $(seq 1 ${box_inner_width}))\033[1;36m║\033[0m"
  echo -e "\033[1;36m  ╚${border}╝\033[0m"
  echo ""
}
