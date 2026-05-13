#!/usr/bin/env bash
# v1.0 developed by GreggyGB
# v2.0-v5.x by Mister R

set -o errexit
set -o nounset
set -o pipefail

script_basedir=$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")
install_root_bin_dir=$HOME
install_root_service='/etc/systemd/system'
readonly script_basedir install_root_bin_dir install_root_service

source "${script_basedir}/common.sh"
load_config "${script_basedir}/install.conf" config

service_name="xeqmnode_${config[running_user]}.service"
service_file="${install_root_service}/${service_name}"
readonly service_name service_file

port_params=
if ! default_ports_configured; then
  port_params="--p2p-bind-port ${config[p2p_bind_port]} --rpc-bind-port ${config[rpc_bind_port]}"
fi
readonly port_params

active_user=${USER:=$(/usr/bin/id -run)}
readonly active_user

service_template="${script_basedir}/xeqmnode.service.template"
readonly service_template

daemon_start_time=

main() {
  case "$1" in
    install)            install_node ;;
    open_firewall)      open_firewall ;;
    prepare_sn)         prepare_sn ;;
    start)              start ;;
    stop)               stop_all_nodes ;;
    status)             status ;;
    log)                log ;;
    fakerun)            sleep 300 ;;
    setup_service)     build_and_install_service_file ;;
    fork_update)        fork_update ;;
    print_sn_key)       print_sn_key ;;
    print_sn_status)    print_sn_status ;;
    * ) usage
  esac
}

install_node() {
  init
  install_manager
}

init() {
  if [ "${config[running_user]}" != "${active_user}" ]; then
    printf "\033[0;31mFATAL\033[0m: Wrong user running '%s'. Expected user: '%s'. Current user: '%s'!\n" "${BASH_SOURCE[0]}" "${config[running_user]}" "${active_user}"
    echo -e "Please run this script with the correct user or modify 'install.conf'.\n"

    if [ "${active_user}" = 'root' ]; then
      echo -e "\033[0;33mIn case you simply need to quickly install the Equilibria service node. Please run below command as root user instead, especially if you have not used this command for this install before\033[0m:\n\tbash install.sh\n"
    fi
    exit 1
  fi

  if ! [[ -f "${installer_session_state_file}" ]]; then
    set_install_session_state "${installer_state[started]}"
  fi
}

install_manager() {
  local current_install_state="$(read_install_session_state)"

  if [ "${current_install_state}" != "${installer_state[started]}" ]; then
    echo -e "Skipping ahead to previous exit point...\n"
  fi

  # ';&' fall-through case, based on installer_session_state_file.
  case "${current_install_state}" in
    "${installer_state[started]}")            ;&
    "${installer_state[install_packages]}")   install_required_packages ;&
    "${installer_state[checkout_git]}")       checkout_git_repo ;&
    "${installer_state[compile_move]}")       compile_and_move_binaries ;&
    "${installer_state[install_service]}")    build_and_install_service_file ;&
    "${installer_state[enable_service]}")     enable_service_on_boot ;&
    "${installer_state[start_service]}")      start_service ;&
    "${installer_state[watch_daemon]}")       watch_daemon_status ;&
    "${installer_state[finished_xeqmnode_install]}")  finish_xeqmnode_install ;;
    *) printf "Unknown installer state '%s' found in '%s'. Aborting..." "${current_install_state}" "${installer_session_state_file}"
       exit 1 ;;
  esac
}

install_required_packages() {
  set_install_session_state "${installer_state[install_packages]}"

  echo -e "\n\033[1mInstalling tool packages...\033[0m"
  sudo apt update
  sudo apt -y install wget unzip git

  sudo apt-get -y install bc build-essential cmake pkg-config libboost-all-dev libssl-dev libzmq3-dev libunbound-dev libsodium-dev libunwind8-dev liblzma-dev libreadline6-dev libldns-dev libexpat1-dev doxygen graphviz libpgm-dev qttools5-dev-tools libhidapi-dev libusb-dev libprotobuf-dev protobuf-compiler
}

checkout_git_repo() {
  set_install_session_state "${installer_state[checkout_git]}"

  if [[ -d "${install_root_bin_dir}/bin" ]]; then
    echo -e "\n\033[1mSkipped checked out Equilibria git repo, using existing binaries...\033[0m"
    return 0
  fi

  if [ "${config[install_version]}" = 'auto' ]; then
    echo -e "\033[1mRetrieving latest version tag from Github...\033[0m"
    config[install_version]="$(get_latest_equilibria_version_number)"
  fi
  echo -e "\n\033[1mChecking Out Equilibra Repository Files...\033[0m"
  git clone --recursive "${config[git_repository]}" equilibria && cd equilibria
  git submodule init && git submodule update
  git checkout "${config[install_version]}"
}

compile_and_move_binaries() {
  set_install_session_state "${installer_state[compile_move]}"

  if [[ -d "${install_root_bin_dir}/bin" ]]; then
    echo -e "\n\033[1mSkipped compiling Equilibria binaries, using existing binaries...\033[0m"
    return 0
  fi

  echo -e "\n\033[1mCompiling Equilibria binaries...\033[0m"
  make

  echo -e "\n\033[1mMoving Equilibria binaries to installation directory...\033[0m"
  cd "$(get_make_release_base_dir)" && mv bin "${install_root_bin_dir}"
}

get_make_release_base_dir() {
   build_directory="$(ls "${script_basedir}"/equilibria/build/Linux)"
   echo "build/Linux/${build_directory}/release"
}

build_and_install_service_file() {
  set_install_session_state "${installer_state[install_service]}"

  if [[ -f "${service_file}" ]]; then
    echo -e "\n\033[1mRemoving existing '${service_file}' file...\033[0m"
    sudo rm "${service_file}"
  fi

  echo -e "\n\033[1mGenerating service file '${service_file}'...\033[0m"

  local opt_params=
  if [[ "${config[daemon_no_fluffy_blocks]}" -eq 1 ]]; then
    opt_params+=" --no-fluffy-blocks"
  fi
  if [[ -n "${config[daemon_log_level]}" ]]; then
    opt_params+=" --log-level ${config[daemon_log_level]}"
  fi

  # shellcheck disable=SC2002
  cat "${service_template}" | sed -e "s/%INSTALL_USERNAME%/${config[running_user]}/g" -e "s#%INSTALL_ROOT%#${install_root_bin_dir}#g" -e "s/%PORT_PARAMS%/${port_params}/g"  -e "s/%OPT_PARAMS%/${opt_params}/g" | sudo tee "${service_file}"

  echo -e "\n\033[1mReloading service manager...\033[0m"
  sudo systemctl daemon-reload
}

enable_service_on_boot() {
  set_install_session_state "${installer_state[enable_service]}"

  echo -e "\n\033[1mEnabling service to start automatically upon boot...\033[0m"
  sudo systemctl enable "${service_name}"
}

start_service() {
  set_install_session_state "${installer_state[start_service]}"
  daemon_start_time=$(date +%s)
  start
}

wait_daemon_start() {
   sleep 10
   local timeout_time=30
   local polling_time_passed=0

   while [ $polling_time_passed -lt $timeout_time ]; do
     sleep 1
     if ps aux | grep -q "[d]aemon --non-interactive --service-node" ; then
       break
     fi
     polling_time_passed=$((polling_time_passed + 1))

     if [[ $polling_time_passed -eq $timeout_time ]]; then
       echo -e "\033[0;31mOops, the Equilibria daemon seems to be not started or crashed.\033[0m\nExiting service node installer\n"
       exit 1
     fi
   done
}

watch_daemon_status() {
  set_install_session_state "${installer_state[watch_daemon]}"

  echo -e "\n\033[1mWaiting till daemon is detected...\033[0m"
  wait_daemon_start

  local start_time=${daemon_start_time}
  local start_block=0
  local estimate_time_remaining='Estimating time remaining...'
  local blocks_done= ; local total_blocks= ; local perc=
  local delta_blocks_done=$((blocks_done-start_block))
  local blocks_per_sec=
  local blocks_remaining=
  local sec_left_till_completion=
  local hours_left= ; local mins_left=
  local hour_word= ; local min_word=
  local current_time=
  local delta_time=

  echo -e "\n\033[1mMonitoring blockchain download progress by daemon:\033[0m\n"

  while true; do
    read blocks_done total_blocks perc <<< "$("${install_root_bin_dir}"/bin/daemon status ${port_params} | grep -o 'Height:.*' | sed -n 's/^Height: \([0-9]*\)\/\([0-9]*\) (\([0-9.]*\).*/\1 \2 \3/p')"

    # skip output of odd total number of blocks like 0 or 1
    [[ "${total_blocks}" -lt 1000 ]] && continue

    current_time=$(date +%s)
    delta_time=$((current_time - start_time))

    # calculate new ETR every 60 sec
    if [[ $delta_time -ge 60 ]]; then
      delta_blocks_done=$((blocks_done-start_block))
      blocks_per_sec=$(bc -l <<< "($delta_blocks_done/$delta_time)")
      blocks_remaining=$((total_blocks - blocks_done))
      sec_left_till_completion=$(bc <<< "($blocks_remaining/$blocks_per_sec)")
      hours_left=$((sec_left_till_completion/3600))
      mins_left=$((sec_left_till_completion%3600/60))
      [[ $hours_left -eq 1 ]] && hour_word='hour' || hour_word='hours'
      [[ $mins_left -eq 1 ]] && min_word='minute' || min_word='minutes'
      estimate_time_remaining=$(printf "ETR: ~ %d %s and %d %s left @ %d blocks p/min" "$hours_left" "$hour_word" "$mins_left" "$min_word" "$delta_blocks_done")
      start_time=$current_time
      start_block=$blocks_done
    fi

    tput cuu1 # put cursor up at beginning of previous line
    printf "\r\t(%.01f%%) - %d/%d (%s)%-18s\n" "${perc}" "${blocks_done}" "${total_blocks}" "${estimate_time_remaining}" ""

    if [[ $blocks_done -eq $total_blocks ]]; then
      tput cuu1 # put cursor up at beginning of previous line
      printf "\r\t(%.01f%%) - %d/%d (%s)%-25s\n" "${perc}" "${blocks_done}" "${total_blocks}" "Completed" ""
      break
    fi
    sleep 10 # sleep for 10 seconds
  done
}

finish_xeqmnode_install() {
  set_install_session_state "${installer_state[finished_xeqmnode_install]}"

  if [[ "${config[open_firewall]}" -eq 1 ]]; then
    open_firewall
  fi
}

open_firewall() {
  local firewall_mode='iptables'
  local p2p_port="${config[p2p_bind_port]}"
  local quorumnet_port="${config[quorumnet_port]:-$((p2p_port + 2))}"
  local oxenmq_port="${config[oxenmq_port]:-$((p2p_port + 3))}"
  local public_ports=("${p2p_port}" "${quorumnet_port}" "${oxenmq_port}")

  [[ -x "$(command -v ufw)" ]] && firewall_mode='ufw'

  if [[ "${firewall_mode}" = 'iptables' ]]; then
    echo -e "\n\033[1mOpening firewall ports [iptables]: ${public_ports[*]}...\033[0m"
    check_iptables_dependencies

    for port in "${public_ports[@]}"; do
      sudo iptables -A INPUT -p tcp --dport "${port}" -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
      sudo iptables -A OUTPUT -p tcp --sport "${port}" -m conntrack --ctstate ESTABLISHED -j ACCEPT
    done
    sudo iptables-save | uniq | sudo tee /etc/iptables/rules.v4 | sudo iptables-restore
    sudo ip6tables-save | uniq | sudo tee /etc/iptables/rules.v6 | sudo ip6tables-restore

  elif [[ "${firewall_mode}" = 'ufw' ]]; then
    echo -e "\n\033[1mOpening firewall ports [ufw]: ${public_ports[*]}...\033[0m"
    sudo ufw --force enable
    sudo ufw allow ssh
    for port in "${public_ports[@]}"; do
      sudo ufw allow "${port}"
      sudo ufw allow out "${port}"
    done
  fi
}

check_iptables_dependencies() {
    if ! [[ -x "$(command -v iptables)" && -x "$(command -v iptables-save)" ]]; then
      echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
      echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

      sudo apt-get -y install iptables iptables-persistent

      # make sure ssh port is open
      sudo iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
      sudo iptables -A OUTPUT -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT
      sudo iptables-save | uniq | sudo tee /etc/iptables/rules.v4 | sudo iptables-restore
      sudo ip6tables-save | uniq | sudo tee /etc/iptables/rules.v6 | sudo ip6tables-restore
    fi
}

prepare_sn() {
  ~/bin/daemon prepare_sn ${port_params}
}

start() {
  echo "Starting XEQ node"
  sudo systemctl start "${service_name}"
  echo "Service node started. To view logs run: bash xeqm-node.sh log"
}

status() {
  ~/bin/daemon status ${port_params}
  #systemctl status "${service_name}"
}

stop_all_nodes() {
  echo "Stopping XEQ node"
  sudo systemctl stop "${service_name}"
}

log() {
  sudo journalctl -u "${service_name}" -af
}

print_sn_key() {
  ~/bin/daemon print_sn_key ${port_params}
}

print_sn_status() {
  ~/bin/daemon print_sn_status ${port_params}
}

fork_update() {
  echo -e "\033[1mUpgrading to ${config[install_version]}...\033[0m"

  rm -Rf "${script_basedir}/equilibria"
  git clone --recursive "${config[git_repository]}" equilibria && cd equilibria
  git submodule init && git submodule update
  git checkout "${config[install_version]}"
  make

  stop_all_nodes
  sudo rm -Rf ~/bin
  cd "$(get_make_release_base_dir)"
  sudo mv bin ~/

  build_and_install_service_file
  start

  if [[ "${config[open_firewall]}" -eq 1 ]]; then
    open_firewall
  fi
}

usage() {
  cat <<USAGEMSG
bash $0 [COMMAND...] [OPTION...]

Commands:
  install                         Install of Equilibria service node
  open_firewall [iptables|ufw]    Open firewall for p2p in/out ports
  start                           Start Equilibria service node
  stop                            Stop Equilibria service node
  prepare_sn                      Prepare Equilibria service node for staking
  print_sn_key                    Print service node key
  setup_service                   Generate and install new service file based on install.conf
  print_sn_status                 Print service node registered status
  status                          Check service status
  log                             View service log

Options:
  -h  --help                      Show this help text

USAGEMSG
}

usage_help_is_needed() {
  [[ ( "${#}" -ge "1" && ( "$1" = '-h' || "$1" = '--help' )) || "${#}" -eq "0" ]]
}

if usage_help_is_needed "$@"; then
  usage
  exit 0
fi

main "${@}"
