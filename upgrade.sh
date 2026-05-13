#!/usr/bin/env bash
# by Mister R

set -o errexit
set -o nounset
set -euo pipefail

upgrade_session_token="$(echo $RANDOM | md5sum | head -c 8)"
readonly upgrade_session_token

script_basedir=$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")
readonly script_basedir

source "${script_basedir}/common.sh"
source "${script_basedir}/discovery.sh"

typeset -A command_options_set
command_options_set=(
  [help]=0
  [user]=0
  [version]=0
  [delete_key_file]=0
  [delete_p2pstate_file]=0
  [daemon_no_fluffy_blocks]=0
  [daemon_log_level]=0
  [git_repository]=0
  [open_firewall]=0
)
user_option_value=
version_option_value=
daemon_log_level_option_value=
git_repository_option_value=

declare -A system_info

main() {
  install_dependencies
  print_splash_screen "Service Node Upgrade" "${xeqmnode_installer_version}"
  discover_system system_info
  process_command_line_args "$@"

  pre_install_checks
  upgrade_manager
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
  args="$(getopt -a -n installer -o "hv:u:" --long help,set-daemon-no-fluffy-blocks,set-daemon-log-level:,delete-key-file,delete-p2pstate-file,version:,user:,git-repository:,open-firewall -- "$@")"
  eval set -- "${args}"

  while :
  do
    case "$1" in
      -h | --help)                    command_options_set[help]=1 ; shift ;;
      -u | --user)                    command_options_set[user]=1; user_option_value="$2"; shift 2 ;;
      -v | --version)                 command_options_set[version]=1; version_option_value="$2"; shift 2 ;;
      --delete-key-file)              command_options_set[delete_key_file]=1; shift ;;
      --delete-p2pstate-file)         command_options_set[delete_p2pstate_file]=1; shift ;;
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

  if [[ "${command_options_set[daemon_no_fluffy_blocks]}" -eq 1 ]]; then config[daemon_no_fluffy_blocks]=1; fi

  # process more complex set config
  if [[ "${command_options_set[version]}" -eq 1 ]]; then version_option_handler "${version_option_value}"; else version_option_handler "auto"; fi
  if [[ "${command_options_set[user]}" -eq 1 ]]; then user_option_handler "${user_option_value}"; else user_option_handler "auto"; fi
  if [[ "${command_options_set[daemon_log_level]}" -eq 1 ]]; then daemon_log_level_option_handler "${daemon_log_level_option_value}"; fi
  if [[ "${command_options_set[git_repository]}" -eq 1 ]]; then git_repository_option_handler "${git_repository_option_value}"; fi
  if [[ "${command_options_set[open_firewall]}" -eq 1 ]]; then config[open_firewall]=1; fi

  # necessary return 0
  return 0
}

validate_parsed_command_line_args() {
  local valid_option_combinations=(
    "user version delete_key_file delete_p2pstate_file daemon_no_fluffy_blocks daemon_log_level git_repository open_firewall"
    "help"
  )
  validate_command_line_option_combinations valid_option_combinations
}

user_option_handler() {
  if [[ "$1" = "auto" ]]; then
    echo -e "\n\033[0;33merror: Invalid --user option 'auto'. Not supported yet.\033[0m\n"
    usage
    exit 1
  elif validate_manual_user_string_format "$1"; then
    echo -e "\nBasic user string validation passed"
  else
    echo -e "\n\033[0;33merror: Invalid --user value '$1'\033[0m\n"
    usage
    exit 1
  fi
}

upgrade_manager() {
  local usernames first_username idx
  read -a usernames <<< "${user_option_value//,/ }"

  idx=1
  for username in "${usernames[@]}"
  do
    tput rev; echo -e "\n\033[1m "${username}" \033[0m"; tput sgr0
    echo -e "\033[1mUpgrading user '${username}'...\033[0m"
    if ! id -u "${username}" >/dev/null 2>&1; then
      echo -e "\033[0;33merror: Invalid username '${username}'. Skipping user!\033[0m\n"
      continue
    fi
    upgrade_installer_in_installer_home "/home/${username}/xeqm-installer" "${username}"

    if [[ "${command_options_set[delete_key_file]}" -eq 1 ]]; then
      delete_key_file_handler "${username}"
    fi
    if [[ "${command_options_set[delete_p2pstate_file]}" -eq 1 ]]; then
      delete_p2pstate_file_handler "${username}"
    fi
    
    if [[ "${idx}" -eq 1 ]]; then
      first_username="${username}"
      sudo -H -u "${username}" bash -c "cd ~/xeqm-installer/ && bash xeqm-node.sh fork_update"
    else
      sudo -H -u "${username}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh stop'

      source_dir="/home/${first_username}/bin"
      target_dir="/home/${username}/bin"
      copy_binaries_to_directory "${source_dir}" "${target_dir}"

      sudo -H -u "${username}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh setup_service'

      sudo -H -u "${username}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh start'

      if [[ "${config[open_firewall]}" -eq 1 ]]; then
        sudo -H -u "${username}" bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh open_firewall'
      fi
    fi
    idx=$((idx + 1))
  done
}

update_install_config() {
  local install_config_file_path="$1"
  declare -A node_config

  if [[ -f "${install_config_file_path}" ]]; then
    load_config "${install_config_file_path}" node_config
    node_config[install_version]="${config[install_version]}"
    node_config[daemon_log_level]="${config[daemon_log_level]}"
    node_config[daemon_no_fluffy_blocks]="${config[daemon_no_fluffy_blocks]}"
    node_config[git_repository]="${config[git_repository]}"
    node_config[open_firewall]="${config[open_firewall]}"
  fi

  echo -e "\n\033[1mUpdating install.conf in '${install_config_file_path}'...\033[0m"
  write_config node_config "${install_config_file_path}"
}

delete_key_file_handler() {
  local username="$1"
  local key_file_path="/home/${username}/.equilibria/key"

  if [[ -f "${key_file_path}" ]]; then
    echo -e "Removing file '${key_file_path}'..."
    sudo mv "${key_file_path}" ./"${upgrade_session_token}-${username}--key"
  fi
}

delete_p2pstate_file_handler() {
  local username="$1"
  local p2pstate_file_path="/home/${username}/.equilibria/p2pstate.bin"

  if [[ -f "${p2pstate_file_path}" ]]; then
    echo -e "Removing file '${p2pstate_file_path}'..."
    sudo mv "${p2pstate_file_path}" ./"${upgrade_session_token}-${username}--p2pstate.bin"
  fi
}

backup_key_before_upgrade() {
  local username="$1"
  local key_file="/home/${username}/.equilibria/key"
  local backup_dir="/home/${username}/.equilibria"
  local timestamp
  timestamp="$(date +%Y%m%d%H%M%S)"

  if [[ -f "${key_file}" ]]; then
    local backup="${backup_dir}/key.bak.${timestamp}"
    sudo cp "${key_file}" "${backup}"
    echo -e "  Key backed up to: ${backup}"
  fi
}

upgrade_installer_in_installer_home() {
  local installer_home="$1"
  local username="$2"

  echo -e "\n\033[1mBacking up service node key for '${username}'...\033[0m"
  backup_key_before_upgrade "${username}"

  echo -e "\n\033[1mUpdating installer in '${installer_home}'...\033[0m"
  sudo cp -f xeqm-node.sh xeqmnode.service.template common.sh "${installer_home}"

  update_install_config "${installer_home}/install.conf"

  sudo chown -R "${username}":root "${installer_home}"
}

usage() {
  cat <<USAGEMSG

bash $0 [OPTIONS...]

Options:
  -u --user [name,...]                  Set username(s) that will be upgraded

                                        Examples:   --user snode2
                                                    --user snode,snode2

  -v --version [auto|[version/hash]]    Set XEQM version tag with format 'v0.0.0'
                                        or 'master' or git hash. Use 'auto' to upgrade
                                        to the latest version tag. If you do not know which
                                        version to use choose 'auto' or remove --version
                                        option from command line

                                        Examples:   --version auto
                                                    --version master
                                                    --version v20.0.0
                                                    --version 122d5f6a6

  --set-daemon-log-level                Add --log-level parameter to daemon command in
                                        service file.

                                        Example:   --set-daemon-log-level 0,stacktrace:FATAL

  --delete-key-file                     Removes the '.equilibria/key' file.

                                        WARNING: Only use this option when the service
                                        node is deregistered! If still active, then all
                                        stakers will loose all future stake rewards
                                        till deregistration.

  --delete-p2pstate-file                Removes the '.equilibria/p2pstate.bin' file.

  --open-firewall                       Open firewall for p2p in/out ports. Default: no.

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
