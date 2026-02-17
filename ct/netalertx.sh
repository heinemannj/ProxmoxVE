#!/usr/bin/env bash
# source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE/netalertx/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/netalertx/NetAlertX

APP="netalertx"
var_tags="${var_tags:-monitoring;network;security}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /app ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  if check_for_gh_release "netalertx" "netalertx/NetAlertX"; then
    msg_info "Stopping Services"
    systemctl stop netalertx php8.4-fpm nginx
    msg_ok "Stopped Services"

    fetch_and_deploy_gh_release "netalertx" "netalertx/NetAlertX" "tarball" "latest" "/opt/netalertx" "*.tar.gz"

    #msg_info "Updating ${APP}"
    #cd /app || exit 1
    ## Get current branch (default to main if detection fails)
    #BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    #
    ## Ensure clean state before pulling from the detected branch
    #git fetch origin "${BRANCH}" || exit 1
    #git reset --hard "origin/${BRANCH}" || exit 1
    #msg_ok "Updated ${APP}"

    #msg_info "Updating Python Dependencies"
    ## shellcheck disable=SC1091  # venv activation script
    #source /opt/netalertx-env/bin/activate
    ## Suppress pip output unless verbose
    #$STD pip install -r install/proxmox/requirements.txt || exit 1
    #deactivate
    #msg_ok "Updated Python Dependencies"

    msg_info "Starting Services"
    systemctl start netalertx php8.4-fpm nginx
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:${PORT:-20211}${CL}"
