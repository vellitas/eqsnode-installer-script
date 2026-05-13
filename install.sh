#!/usr/bin/env bash
# by Mister R

set -euo pipefail

script_basedir=$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")
readonly script_basedir

source "${script_basedir}/common.sh"
source "${script_basedir}/discovery.sh"

typeset -A command_options_set
command_options_set=(
  [help]=0
  [copy_blockchain]=0
  [copy_binaries]=0
  [inspect_auto_magic]=0
  [one_passwd_file]=0
  [nodes]=0
  [ports]=0
  [user]=0
  [version]=0
  [daemon_no_fluffy_blocks]=0
  [daemon_log_level]=0
  [git_repository]=0
  [open_firewall]=0
  [quiet]=0
)
copy_binaries_option_value=
copy_blockchain_option_value=
nodes_option_value=
ports_option_value=
user_option_value=
version_option_value=
daemon_log_level_option_value=
git_repository_option_value=

declare -A system_info

main() {
  install_dependencies
  print_splash_screen "Service Node Installer" "${xeqmnode_installer_version}"
  discover_system system_info
  process_command_line_args "$@"

  pre_install_checks
  install_manager
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
  args="$(getopt -a -n installer -o "hiob:c:n:p:qu:v:" --long help,inspect-auto-magic,one-passwd-file,copy-binaries:,copy-blockchain:,nodes:,ports:,quiet,user:,version:,set-daemon-log-level:,set-daemon-no-fluffy-blocks,git-repository:,open-firewall -- "$@")"
  eval set -- "${args}"

  while :
  do
    case "$1" in
      -h | --help)                    command_options_set[help]=1 ; shift ;;
      -b | --copy-binaries)           command_options_set[copy_binaries]=1; copy_binaries_option_value="$2"; shift 2 ;;
      -c | --copy-blockchain)         command_options_set[copy_blockchain]=1; copy_blockchain_option_value="$2"; shift 2 ;;
      -i | --inspect-auto-magic)      command_options_set[inspect_auto_magic]=1; shift ;;
      -n | --nodes)                   command_options_set[nodes]=1; nodes_option_value="$2"; shift 2 ;;
      -o | --one-passwd-file)         command_options_set[one_passwd_file]=1; shift 1 ;;
      -p | --ports)                   command_options_set[ports]=1; ports_option_value="$2"; shift 2 ;;
      -q | --quiet)                   command_options_set[quiet]=1; shift ;;
      -u | --user)                    command_options_set[user]=1; user_option_value="$2"; shift 2 ;;
      -v | --version)                 command_options_set[version]=1; version_option_value="$2"; shift 2 ;;
      --set-daemon-no-fluffy-blocks)  command_options_set[daemon_no_fluffy_blocks]=1; shift ;;
      --set-daemon-log-level)         command_options_set[daemon_log_level]=1; daemon_log_level_option_value="$2"; shift 2 ;;
      --git-repository)               command_options_set[git_repository]=1; git_repository_option_value="$2"; shift 2 ;;
      --open-firewall)                command_options_set[open_firewall]=1; shift ;;
      --)                             shift ; break ;;
      *)                              echo "Unexpected option: $1" ;
                                      usage
                                      exit 0 ;;
    esac
  done
}

set_config_and_execute_info_commands() {
  [[ "${command_options_set[help]}" -eq 1 ]] && usage && exit 0
  [[ "${command_options_set[one_passwd_file]}" -eq 1 ]] && one_password_file_option_handler && exit 0

  # set options first that effect other options and the parsing of their option value(s)
  if [[ "${command_options_set[nodes]}" -eq 1 ]]; then nodes_option_handler "${nodes_option_value}"; else nodes_option_handler 1; fi

  # info commands, exit 0 must be first listed options in this function
  [[ "${command_options_set[inspect_auto_magic]}" -eq 1 ]] && inspect_auto_magic_option_handler && exit 0

  if [[ "${command_options_set[quiet]}" -eq 1 ]]; then config[quiet_mode]=1; fi
  if [[ "${command_options_set[daemon_no_fluffy_blocks]}" -eq 1 ]]; then config[daemon_no_fluffy_blocks]=1; fi

  # process more complex set config
  if [[ "${command_options_set[version]}" -eq 1 ]]; then version_option_handler "${version_option_value}"; else version_option_handler "auto"; fi
  if [[ "${command_options_set[ports]}" -eq 1 ]]; then ports_option_handler "${ports_option_value}"; else ports_option_handler "auto"; fi
  if [[ "${command_options_set[user]}" -eq 1 ]]; then user_option_handler "${user_option_value}"; else user_option_handler "auto"; fi
  if [[ "${command_options_set[copy_blockchain]}" -eq 1 ]]; then
    copy_blockchain_option_handler "${copy_blockchain_option_value}"
  elif [[ "${config[quiet_mode]}" -eq 1 ]]; then
    copy_blockchain_option_handler "bootstrap"
  else
    blockchain_selection_menu
  fi
  if [[ "${command_options_set[copy_binaries]}" -eq 1 ]]; then copy_binaries_option_handler "${copy_binaries_option_value}"; fi
  if [[ "${command_options_set[daemon_log_level]}" -eq 1 ]]; then daemon_log_level_option_handler "${daemon_log_level_option_value}"; fi
  if [[ "${command_options_set[git_repository]}" -eq 1 ]]; then git_repository_option_handler "${git_repository_option_value}"; fi
  if [[ "${command_options_set[open_firewall]}" -eq 1 ]]; then config[open_firewall]=1; fi

  # necessary return 0
  return 0
}

validate_parsed_command_line_args() {
  local valid_option_combinations=(
    "<no_options_set>"
    "copy_blockchain copy_binaries nodes ports user version daemon_no_fluffy_blocks daemon_log_level git_repository open_firewall quiet"
    "inspect_auto_magic nodes"
    "one_passwd_file"
    "help"
  )
  validate_command_line_option_combinations valid_option_combinations
}

nodes_option_handler() {
  local max_nodes_by_free_space max_nodes_by_memory max_nodes

  if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo -e "\033[0;33merror: Invalid --nodes option value. Numbers only.\033[0m\n"
    usage
    exit 1
  fi

  max_nodes_by_free_space="$((system_info[free_space_home_mount] / 1024 / 38000))"
  # reserved 768MB memory for system use
  max_nodes_by_memory="$((((system_info[memory] / 1024) - 768) / 1300))"
  [[ "${max_nodes_by_memory}" -lt "$max_nodes_by_free_space" ]] && max_nodes="${max_nodes_by_memory}" || max_nodes="${max_nodes_by_free_space}"

  if [[ "$1" -gt "${max_nodes}" ]]; then
    echo -e "\033[0;33merror: Too many nodes set as --nodes option value. Max nodes: ${max_nodes}. Check system specifications (memory/disk space).\033[0m\n"
    exit 1
  fi
  config[nodes]="$1"

  # init node specific config placeholders
  local idx=1
  while [ "${idx}" -le "${config[nodes]}" ]; do
    config["snode${idx}__running_user"]=
    config["snode${idx}__copy_blockchain"]=
    config["snode${idx}__copy_binaries"]=
    config["snode${idx}__p2p_bind_port"]=0
    config["snode${idx}__rpc_bind_port"]=0
    config["snode${idx}__quorumnet_port"]=0
    config["snode${idx}__oxenmq_port"]=0
    idx=$((idx + 1))
  done

  return 0
}

copy_binaries_option_handler() {
  local fixed_value binaries_version
  local idx=1
  local option_value="$1"

  if [[ -f "${option_value}/daemon" ]]; then
      binaries_version="$("${option_value}"/daemon --version | grep -oP '(?<=\()+v[0-9.]+')"

      # if version option is set to a specific version or auto (already resolved to latest version), check if daemon version matches this version
      if [[ "${command_options_set[version]}" -eq 1 && "${config[install_version]}" != "${binaries_version}" ]]; then
        echo -e "\n\033[0;33merror: ${option_value}/daemon version '${binaries_version}' does not match version '${config[install_version]}'\033[0m\n"
        exit 1
      fi

      while [ "${idx}" -le "${config[nodes]}" ]; do
        config["snode${idx}__copy_binaries"]="${option_value}"
        idx=$((idx + 1))
      done
  else
    echo -e "\n\033[0;33merror: daemon not found in --copy-binaries directory '$1'\033[0m\n"
    exit 1
  fi
}

blockchain_selection_menu() {
  local choice
  prompt_menu "How should this node get its blockchain?" choice 1 \
    "Download bootstrap  (fastest, ~15 min  —  https://bootstrap.xeqmlabs.com)" \
    "Copy from an existing active node on this server  (auto-detect)" \
    "Sync from the network  (slowest, may take many hours)"

  case "${choice}" in
    1) copy_blockchain_option_handler "bootstrap" ;;
    2) copy_blockchain_option_handler "auto" ;;
    3) copy_blockchain_option_handler "no" ;;
  esac
}

copy_blockchain_option_handler() {
  local blockchain
  local idx=1
  local option_value="$1"

  if [[ "${option_value}" = "bootstrap" ]]; then
    while [ "${idx}" -le "${config[nodes]}" ]; do
      config["snode${idx}__copy_blockchain"]="bootstrap"
      idx=$((idx + 1))
    done
    echo -e "\n\033[1mBlockchain: download bootstrap from https://bootstrap.xeqmlabs.com\033[0m"
    return 0
  fi

  if [[ "${option_value}" = "auto" ]]; then
    blockchain="$(discover_biggest_blockchain)"
    if [[ -d "${blockchain}" ]]; then option_value="${blockchain}"; else option_value="no,auto"; fi
  fi

  if [[ "${option_value}" = "no" || -f "${option_value}/lmdb/data.mdb" ]]; then
      while [ "${idx}" -le "${config[nodes]}" ]; do
        config["snode${idx}__copy_blockchain"]="${option_value}"
        idx=$((idx + 1))
      done
  elif [[ "${option_value}" = "no,auto" ]]; then
      while [ "${idx}" -le "${config[nodes]}" ]; do
        if [[ "${idx}" -eq 1 ]]; then
            config["snode${idx}__copy_blockchain"]="no"
        else
            config["snode${idx}__copy_blockchain"]="/home/${config["snode1__running_user"]}/.equilibria"
        fi
        idx=$((idx + 1))
      done
  else
    echo -e "\n\033[0;33merror: invalid --copy-blockchain value or directory '$1'\033[0m\n"
    usage
    exit 1
  fi

  idx=1
  echo -e "\n\033[1mBlockchain copy settings...\033[0m"
  while [ "${idx}" -le "${config[nodes]}" ]; do
    [[ "${config[nodes]}" -gt 1 ]] && echo -e "\nService Node ${idx}:"
    echo -e "  Copy blockchain: ${config["snode${idx}__copy_blockchain"]}"
    idx=$((idx + 1))
  done
}

download_bootstrap() {
  local target_dir="$1"
  local username="$2"
  local bootstrap_url="https://bootstrap.xeqmlabs.com/lmdb.tar.gz"
  local tmp_file="/tmp/xeqm-bootstrap-$$.tar.gz"

  echo -e "\n\033[1mDownloading XEQM bootstrap blockchain...\033[0m"
  echo -e "  Source: ${bootstrap_url}\n"

  wget --progress=bar:force:noscroll -O "${tmp_file}" "${bootstrap_url}"

  echo -e "\n\033[1mExtracting bootstrap to '${target_dir}'...\033[0m"

  if [[ -d "${target_dir}" ]]; then
    sudo mv "${target_dir}" "${target_dir}_$(echo $RANDOM | md5sum | head -c 8)"
  fi
  sudo mkdir -p "${target_dir}"
  sudo tar -xzf "${tmp_file}" -C "${target_dir}"
  sudo rm -f "${tmp_file}"
  sudo chown -R "${username}:${username}" "${target_dir}"

  echo -e "\033[1;32mBootstrap extracted successfully.\033[0m"
}

auto_ports_option_handler() {
  echo -e "\n\033[1mAuto-detecting available ports...\033[0m"
  declare -A discovered_sets
  discover_free_port_sets discovered_sets "${config[nodes]}"

  local idx=1
  while [ "${idx}" -le "${config[nodes]}" ]; do
    config["snode${idx}__p2p_bind_port"]="${discovered_sets["set${idx}__p2p_bind_port"]}"
    config["snode${idx}__rpc_bind_port"]="${discovered_sets["set${idx}__rpc_bind_port"]}"
    config["snode${idx}__quorumnet_port"]="${discovered_sets["set${idx}__quorumnet_port"]}"
    config["snode${idx}__oxenmq_port"]="${discovered_sets["set${idx}__oxenmq_port"]}"

    [[ "${config[nodes]}" -gt 1 ]] && echo -e "\nService Node ${idx}:"
    echo -e "  p2p_bind_port  -> ${config["snode${idx}__p2p_bind_port"]}"
    echo -e "  rpc_bind_port  -> ${config["snode${idx}__rpc_bind_port"]}"
    echo -e "  quorumnet_port -> ${config["snode${idx}__quorumnet_port"]}"
    echo -e "  oxenmq_port    -> ${config["snode${idx}__oxenmq_port"]}"

    idx=$((idx + 1))
  done
}

inspect_auto_magic_option_handler() {
  version_option_handler "auto"
  ports_option_handler "auto"
  user_option_handler "auto"
  copy_blockchain_option_handler "auto"

  echo -e "\nIf needed you can alter these settings manually by one of the following example commands (or combination):\n\033[0;33m"
  echo -e "    bash install.sh --version ${config[install_version]}"
  echo -e "    bash install.sh --ports p2p:9330,rpc:9331"
  echo -e "    bash install.sh --user mysnodeuser"
  echo -e "    bash install.sh --copy_blockchain no\033[0m\n"
}

one_password_file_option_handler() {
  echo -e "\n\033[1mSet one password for all new service node users. Will be stored encrypted!\033[0m"
  while true; do read -sp $'\rPassword: ' pwd; read -sp $'\rRe-passwd: ' re_pwd; [[ "${pwd}" = "${re_pwd}" ]] && echo "${pwd}" && break; done | openssl passwd -6 -stdin > "${script_basedir}/.onepasswd"

  if [[ -f "${script_basedir}/.onepasswd" ]]; then
    echo -e "\n\nsucces: .onepasswd file created. Remove this file to enable manual password input again."
  else
    echo -e "\n\nerror: .onepasswd file could not be created"
  fi
}

user_option_handler() {
  if [[ "$1" = "auto" ]]; then
    auto_search_available_username

  elif validate_manual_user_string_format "$1"; then
    validate_manual_users_and_set_config_if_valid "$1"
  else
    echo -e "\n\033[0;33merror: Invalid --user value '$1'\033[0m\n"
    usage
    exit 1
  fi
}

validate_manual_users_and_set_config_if_valid() {
  local usernames idx
  read -a usernames <<< "${1//,/ }"

  idx=1
  for username in "${usernames[@]}"
  do
    if running_user_has_active_daemon "${username}"; then
      echo -e "\n\033[0;33mSAFETY POLICY VIOLATION: User '${username}' is already running an active service node daemon. Please install with a different user!\033[0m"
      echo -e "\nInstallation aborted."
      exit 1
    elif running_user_has_active_installation "${username}"; then
      echo -e "\n\033[0;33mSAFETY POLICY VIOLATION: User '${username}' is running an active installation. Please install with a different user!\033[0m"
      echo -e "\nInstallation aborted."
      exit 1
    fi
    config["snode${idx}__running_user"]="${username}"
    idx=$((idx + 1))
  done
}

running_user_has_active_daemon() {
   [[ "$(sudo ps aux | egrep '[b]in/daemon.*--service-node' | gawk '{ print $1 }' | natsort | uniq | grep -o "^${1}$" | wc -l)" -gt 0 ]]
}

ports_option_handler() {
  if [[ "$1" = "auto" ]]; then
    auto_ports_option_handler
  elif valid_manual_port_string_format "$1" ; then
    parse_manual_port_string_and_set_config_if_valid "$1"
  else
    echo -e "\033[0;33merror: Invalid --ports config format '$1'\033[0m\n"
    usage
    exit 1
  fi
}

# TODO: can probably be simplified
valid_manual_port_string_format() {
  [[
    # check if basic format is valid either p2p:[0-9+],rpc:[0-9]+ or in reversed order rpc:[0-9+],p2p:[0-9]+
    "$(echo "$1" | grep -oP -e "^[a-z2]{3}:[0-9+]+,[a-z2]{3}:[0-9+]+$" | grep -oE -e "p2p:[0-9+]+" -e "rpc:[0-9+]+" | wc -l )" -eq 2 &&

    # check if number of p2p: ports equals the number of nodes
    "$(echo "$1" | grep -oP -e 'p2p:[0-9+]+' | grep -oP -e "(?<=p2p:|\+)[0-9]+" | wc -l )" -eq "${config[nodes]}" &&

    # check if number of rpc: ports equals the number of nodes
    "$(echo "$1" | grep -oP -e 'rpc:[0-9+]+' | grep -oP -e "(?<=rpc:|\+)[0-9]+" | wc -l )" -eq "${config[nodes]}" &&

    # Since all ports should be unique. Check if total number of unique ports equals (number of nodes * 2 ports(p2p+rpc) each)
    "$(echo "$1" | grep -oP -e '(?<=p2p:|rpc:|\+)+[0-9]+' | natsort | uniq | wc -l)" -eq "$((config[nodes] * 2))"
  ]]
}

running_user_has_active_installation() {
   [[ "$(sudo ps aux | grep '[b]ash.*xeqm-node.sh' | grep -v '[s]udo' | gawk '{ printf("%s\n", $1) }' | grep -c "$1")" -gt 0 ]]
}

parse_manual_port_string_and_set_config_if_valid() {
  typeset -A key_to_config_param
  key_to_config_param=(
    [p2p]='p2p_bind_port'
    [rpc]='rpc_bind_port'
  )
  local params validation_result port_error port_key port_values port_value_string single_port_value

  # shellcheck disable=SC2207
  # basically split manual port string on separator ','
  read -a params <<< "${1//,/ }"
  port_error=0

  echo -e "\n\033[1mAnalyzing manual port configuration...\033[0m"

  for key_value in "${params[@]}"
  do
    local idx=1
    # split key_value pair on divider ':'
    read -r port_key port_value_string <<< "${key_value//:/ }"

    read -a port_values <<< "${port_value_string//+/ }"

    for single_port_value in "${port_values[@]}"
    do
      validation_result="$(validate_port "${single_port_value}")"

      case "${validation_result}" in
        'outside_port_range') printf "%s: %d -> \033[0;33mOut of range [allowed between 5000-49151]\033[0m\n" "${key_to_config_param[${port_key}]}" "${single_port_value}"
                              port_error=1 ;;

        'port_used')          printf "%s: %d -> \033[0;33mIn use\033[0m\n" "${key_to_config_param[${port_key}]}" "${single_port_value}"
                              port_error=1 ;;

        'free_port')          printf "%s: %d -> OK\n" "${key_to_config_param[${port_key}]}" "${single_port_value}"
                              config["snode${idx}__${key_to_config_param[${port_key}]}"]="${single_port_value}" ;;

        *)                    echo "Unknown port validation result" ; exit 1 ;;
      esac
      idx=$((idx + 1))
    done
  done
  if [[ "${port_error}" -eq 1 ]]; then
    exit 1
  fi

  # derive quorumnet (p2p+2) and oxenmq (p2p+3) for each node
  local qidx=1
  while [ "${qidx}" -le "${config[nodes]}" ]; do
    config["snode${qidx}__quorumnet_port"]=$((config["snode${qidx}__p2p_bind_port"] + 2))
    config["snode${qidx}__oxenmq_port"]=$((config["snode${qidx}__p2p_bind_port"] + 3))
    qidx=$((qidx + 1))
  done
}

auto_search_available_username() {
  echo -e "\n\033[1mAuto-searching for an unused username to run the service node...\033[0m"

  declare -A discovered_usernames
  discover_available_usernames discovered_usernames "${config[nodes]}" "${config[running_user]}"

  local idx=1
  while [ "${idx}" -le "${config[nodes]}" ]; do
    config["snode${idx}__running_user"]="${discovered_usernames["${idx}"]}"

    [[ "${config[nodes]}" -gt 1 ]] && echo -e "\nService Node ${idx}:"
    echo -e "Detected unused username -> ${discovered_usernames["${idx}"]}"
    idx=$((idx + 1))
  done
}

install_manager() {
  declare -A node_config
  local source_dir target_dir
  local idx=1

  setup_all_running_users

  while [ "${idx}" -le "${config[nodes]}" ]; do
    generate_node_config node_config "${idx}"
    tput rev; echo -e "\n\033[1m "${node_config[running_user]}" \033[0m"; tput sgr0
    # if existing binaries directory is set, copy these for the first node
    if [[ "${idx}" -eq 1 && "${node_config[copy_binaries]}" != "" ]]; then
       target_dir="/home/${config["snode1__running_user"]}/bin"
       copy_binaries_to_directory "${node_config[copy_binaries]}" "${target_dir}"

    # for second and subsequent nodes, copy binaries from first node
    elif [[ "${idx}" -gt 1 ]]; then
      source_dir="/home/${config["snode1__running_user"]}/bin"
      target_dir="/home/${node_config[running_user]}/bin"
      copy_binaries_to_directory "${source_dir}" "${target_dir}"
    fi
    copy_blockchain_to_user_home_if_needed node_config
    copy_installer_to_installer_home node_config
    install_node_with_running_user "${node_config[running_user]}"
    finish_node_install "${node_config[running_user]}"

    echo -e "\n\033[1mInstallation of Service Node ${idx} completed.\033[0m"
    idx=$((idx + 1))
  done
  next_steps

  echo -e "\n\033[1mGoodbye!\033[0m\n"
}

setup_all_running_users() {
  local idx=1

  while [ "${idx}" -le "${config[nodes]}" ]; do
    echo -e "\n\033[1mSetting up user '${config["snode${idx}__running_user"]}' to run service node ${idx}...\033[0m\n"
    setup_running_user "${config["snode${idx}__running_user"]}"
    idx=$((idx + 1))
  done
}

setup_running_user () {
  local running_user="$1"
  create_user_if_needed "${running_user}"
  sudoers_user_nopasswd 'add' "${running_user}"
}

create_user_if_needed() {
  local user="$1"
  # shellcheck disable=SC2154
  if ! id -u "${user}" >/dev/null 2>&1; then
    if [[ -f "${script_basedir}/.onepasswd" ]]; then
      sudo adduser --disabled-password --gecos "${user}" "${user}"
      sudo usermod -p "$(cat "${script_basedir}/.onepasswd")" "${user}"
    else
      sudo adduser --gecos "${user}" "${user}"
    fi
    sudo usermod -aG sudo "${user}"
  fi
}

sudoers_user_nopasswd() {
  local action="$1"
  local user="$2"
  local sudoers_file="/etc/sudoers.d/xeqmnode-${user}"

  if [[ "${action}" = 'add' ]]; then
    echo "${user} ALL=(ALL) NOPASSWD:ALL" | sudo tee "${sudoers_file}" > /dev/null
    sudo chmod 440 "${sudoers_file}"
  else
    [[ -f "${sudoers_file}" ]] && sudo rm "${sudoers_file}"
  fi
}

generate_node_config() {
  local -n gnc__node_config_ref="$1"
  local node_id="$2"
  gnc__node_config_ref=(
    [node_id]="${node_id}"
    [install_version]="${config[install_version]}"
    [git_repository]="${config[git_repository]}"
    [running_user]="${config["snode${node_id}__running_user"]}"
    [p2p_bind_port]="${config["snode${node_id}__p2p_bind_port"]}"
    [rpc_bind_port]="${config["snode${node_id}__rpc_bind_port"]}"
    [quorumnet_port]="${config["snode${node_id}__quorumnet_port"]}"
    [oxenmq_port]="${config["snode${node_id}__oxenmq_port"]}"
    [copy_blockchain]="${config["snode${node_id}__copy_blockchain"]}"
    [copy_binaries]="${config["snode${node_id}__copy_binaries"]}"
    [daemon_no_fluffy_blocks]="${config[daemon_no_fluffy_blocks]}"
    [daemon_log_level]="${config[daemon_log_level]}"
    [open_firewall]="${config[open_firewall]}"
    [installer_home]="/home/${config["snode${node_id}__running_user"]}/xeqm-installer"
  )
}

copy_blockchain_to_user_home_if_needed() {
  local -n cbtuhin__node_config_ref="$1"
  local target_dir="/home/${cbtuhin__node_config_ref[running_user]}/.equilibria"
  local blockchain_value="${cbtuhin__node_config_ref[copy_blockchain]}"

  if [[ "${blockchain_value}" = "bootstrap" ]]; then
    download_bootstrap "${target_dir}" "${cbtuhin__node_config_ref[running_user]}"
    return 0
  fi

  if [[ -d "${blockchain_value}" ]]; then
    echo -e "\n\033[1mCopying blockchain from '${blockchain_value}'... (takes 1-5 minutes)\033[0m"

    if [[ -d "${target_dir}" ]]; then
      sudo mv "${target_dir}" "${target_dir}_$(echo $RANDOM | md5sum | head -c 8)"
    fi
    sudo mkdir "${target_dir}"
    sudo chmod "$(stat --format '%a' "${blockchain_value}")" "${target_dir}"
    sudo cp -R "${blockchain_value}/lmdb" "${target_dir}"
    sudo chown -R "${cbtuhin__node_config_ref[running_user]}":"${cbtuhin__node_config_ref[running_user]}" "${target_dir}"
  fi
}

copy_installer_to_installer_home() {
  local -n citih__node_config_ref="$1"
  local install_file_conf_path
  [[ -d "${citih__node_config_ref[installer_home]}" ]] && echo -e "\033[1mDeleting old installer files...\033[0m" && sudo rm --recursive --force -- "${citih__node_config_ref[installer_home]}"

  echo -e "\n\033[1mCopying installer to '${citih__node_config_ref[installer_home]}'...\033[0m"
  sudo mkdir "${citih__node_config_ref[installer_home]}"
  sudo cp xeqm-node.sh xeqmnode.service.template common.sh "${citih__node_config_ref[installer_home]}"

  local install_config_file_path="${citih__node_config_ref[installer_home]}/install.conf"

  echo -e "\n\033[1mGenerating new install.conf in '${install_config_file_path}'...\033[0m"
  write_config citih__node_config_ref "${install_config_file_path}"

  sudo chown -R "${citih__node_config_ref[running_user]}":root "${citih__node_config_ref[installer_home]}"
}

install_node_with_running_user() {
  local running_user="$1"
  sudo -H -u "${running_user}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh install'
}

finish_node_install() {
  local user="$1"
  sudoers_user_nopasswd 'remove' "${user}"
}

print_firewall_port_table() {
  echo -e "\n\033[1mFirewall ports required per service node:\033[0m"
  local idx=1
  while [ "${idx}" -le "${config[nodes]}" ]; do
    [[ "${config[nodes]}" -gt 1 ]] && echo -e "\n  \033[1mService Node ${idx}\033[0m"
    local p2p="${config["snode${idx}__p2p_bind_port"]}"
    local quorum="${config["snode${idx}__quorumnet_port"]}"
    local oxenmq="${config["snode${idx}__oxenmq_port"]}"
    printf "\n  %-18s %-8s %-10s %s\n" "Service" "Port" "Protocol" "Notes"
    printf "  %-18s %-8s %-10s %s\n" "──────────────────" "────────" "──────────" "──────────────────────────────"
    printf "  %-18s %-8s %-10s %s\n" "P2P" "${p2p}" "TCP" "Inbound — peer discovery"
    printf "  %-18s %-8s %-10s %s\n" "Quorumnet" "${quorum}" "TCP" "SN-to-SN consensus (public)"
    printf "  %-18s %-8s %-10s %s\n" "OxenMQ" "${oxenmq}" "TCP" "Public"
    idx=$((idx + 1))
  done
  echo ""
}

next_steps() {
  tput rev; echo -e "\n\033[1m IMPORTANT: COMPLETE THESE STEPS TO FINISH SERVICE NODE SETUP \033[0m"; tput sgr0
  echo -e "\nTo complete setup, link a wallet to each node as operator using the command(s) below."
  echo -e "\033[0;33m(Run each command and follow the presented instructions carefully)\033[0m"
  local idx=1

  while [ "${idx}" -le "${config[nodes]}" ]; do
    echo -e "\nService Node ${idx}:"
    echo -e "\033[1msudo -H -u ${config["snode${idx}__running_user"]} bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh prepare_sn'\033[0m"
    idx=$((idx + 1))
  done

  print_firewall_port_table
}


print_config() {
  echo -e "\n"
  local keys=( $( echo ${!config[@]} | tr ' ' $'\n' | natsort) )
  for key in "${keys[@]}"
  do
    echo -e "${key}=${config[${key}]}"
  done
}

usage() {
  cat <<USAGEMSG

bash $0 [OPTIONS...]

Options:
  -b --copy-binaries [path]             Copy previously compiled binaries. If --version is
                                        set to a specific version it verifies the match.

                                        Example: --copy-binaries /home/snode/bin

  -c --copy-blockchain [bootstrap|no|auto|path]
                                        How to seed the blockchain. 'bootstrap' downloads
                                        from https://bootstrap.xeqmlabs.com (~15 min).
                                        'auto' copies from an existing node on this server.
                                        'no' syncs fresh from the network (many hours).
                                        'no,auto' = first node syncs fresh, subsequent
                                        nodes copy from it (multi-node installs).

                                        Examples: --copy-blockchain bootstrap
                                                  --copy-blockchain auto
                                                  --copy-blockchain /home/snode/.equilibria
                                                  --copy-blockchain no
                                                  --copy-blockchain no,auto

  -i --inspect-auto-magic               Preview auto-detected ports, users, and version.

  -n --nodes [number]                   Number of nodes to install (default: 1).

  -p  --ports [auto|config]             Port configuration. Format:
                                        p2p:<port[+port+...]>,rpc:<port[+port+...]>
                                        Quorumnet and OxenMQ are derived as p2p+2 / p2p+3.

                                        Examples:
                                        --ports p2p:9230,rpc:9231
                                        --nodes 2 --ports p2p:9230+9330,rpc:9231+9331

  -o --one-passwd-file                  Pre-generate an encrypted password file used for
                                        all new service node users. Run this first for a
                                        fully non-interactive install.

  -q --quiet                            Non-interactive mode. All decisions use defaults
                                        or supplied flags. Exits with an error if a
                                        required flag is missing. Blockchain defaults to
                                        'bootstrap'.

  -u --user [auto|name,...]             Username(s) to run the service node(s). 'auto'
                                        finds an unused name automatically.

                                        Examples:   --user snode2
                                                    --user auto
                                                    --nodes 2 --user snode,snode2

  -v --version [auto|version|hash]      XEQM version tag (v0.0.0), 'master', or git hash.
                                        'auto' installs the latest release.

                                        Examples:   --version auto
                                                    --version v20.0.0
                                                    --version 122d5f6a6

  --set-daemon-log-level [level]        Set daemon --log-level in the service file.

                                        Example:   --set-daemon-log-level 0,stacktrace:FATAL

  --open-firewall                       Auto-configure UFW/iptables for all required ports.

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
