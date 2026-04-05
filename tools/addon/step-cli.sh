#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/smallstep/cli

#source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/core.func)
# shellcheck disable=SC1090
source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE/main/misc/core.func)
#source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE/main/misc/tools.func)

APP="step-cli"
APP_TITLE="step-cli ACME Client"
APP_BACKTITLE="Proxmox VE Helper Scripts"
BINARY_PATH="/usr/bin/step"
CONFIG_PATH="/etc/step"
CERT_PATH="${CONFIG_PATH}/certs"
KEY_PATH="${CONFIG_PATH}/private"
export STEPPATH=${CONFIG_PATH}
sed  -i '1i export STEPPATH=/etc/step' /etc/profile

function header_info {
  clear
  cat <<"EOF"
         __                        ___    ___   ________  _________   _________            __ 
   _____/ /____  ____        _____/ (_)  /   | / ____/  |/  / ____/  / ____/ (_)__  ____  / /_
  / ___/ __/ _ \/ __ \______/ ___/ / /  / /| |/ /   / /|_/ / __/    / /   / / / _ \/ __ \/ __/
 (__  ) /_/  __/ /_/ /_____/ /__/ / /  / ___ / /___/ /  / / /___   / /___/ / /  __/ / / / /_  
/____/\__/\___/ .___/      \___/_/_/  /_/  |_\____/_/  /_/_____/   \____/_/_/\___/_/ /_/\__/  
             /_/                                                                              

EOF
}

# shellcheck disable=SC2116
# shellcheck disable=SC2028
YW=$(echo "\033[33m")
# shellcheck disable=SC2116
# shellcheck disable=SC2028
GN=$(echo "\033[1;92m")
# shellcheck disable=SC2116
# shellcheck disable=SC2028
RD=$(echo "\033[01;31m")
# shellcheck disable=SC2116
# shellcheck disable=SC2028
BL=$(echo "\033[36m")
# shellcheck disable=SC2028
# shellcheck disable=SC2116
CL=$(echo "\033[m")
CM="${GN}✔️${CL}"
CROSS="${RD}✖️${CL}"
INFO="${BL}ℹ️${CL}"
# shellcheck disable=SC2034
TAB="  "

function msg_info() { echo -e "${INFO} ${YW}${1}...${CL}"; }
function msg_ok() { echo -e "${CM} ${GN}${1}${CL}"; }
function msg_error() { echo -e "${CROSS} ${RD}${1}${CL}"; }
function msg_warn() { echo -e "⚠️  ${YW}${1}${CL}"; }

function die() {
  echo -e "\n${BL}[ERROR]${GN} ${RD}${1}${CL}\n"
  exit 1
}

function whiptail_checklist() {
  local TITLE=$1
  local TEXT=$2
  local -n LIST=$3
  local CHOICE
  local OPTIONS=()
  local WIDTH=$(( ${#TITLE} + 16 ))
  local WIDTH_OFFSET=12

  for ((i=0; i<${#LIST[@]}; i+=2)); do
    local j=$(( i+1 ))
    (( ${#LIST[i]} > MAX_LEFT )) && MAX_LEFT=${#LIST[i]}
	(( ${#LIST[j]} > MAX_RIGHT )) && MAX_RIGHT=${#LIST[j]}
    OPTIONS+=("${LIST[i]}" "${LIST[j]}" "OFF")  
  done
  (( MAX_LEFT + MAX_RIGHT + WIDTH_OFFSET > WIDTH )) && WIDTH=$(( MAX_LEFT + MAX_RIGHT + WIDTH_OFFSET ))
  local LEN=$(( ${#OPTIONS[@]} / 2 ))
  local HIGHT=$(( LEN + 9 ))

  CHOICE=$(whiptail --backtitle "$APP_BACKTITLE" --title "$TITLE" --checklist "$TEXT" \
    "$HIGHT" "$WIDTH" "$LEN" "${OPTIONS[@]}" 3>&1 1>&2 2>&3 | tr -d '"')
  echo "$CHOICE"
}

function whiptail_menu() {
  local TITLE=$1
  local TEXT="\nSelect an option:"
  local LEN=$(( ${#OPTIONS[@]} / 2 ))
  local HIGHT=$(( LEN + 9 ))
  local WIDTH=$(( ${#TITLE} + 16 ))
  local WIDTH_OFFSET=5
  local CHOICE
  local MAX_LEFT=0
  local MAX_RIGHT=0

  for ((i=0; i<${#OPTIONS[@]}; i+=2)); do
    (( ${#OPTIONS[i]} > MAX_LEFT )) && MAX_LEFT=${#OPTIONS[i]}
	(( ${#OPTIONS[$(( i+1 ))]} > MAX_RIGHT )) && MAX_RIGHT=${#OPTIONS[$(( i+1 ))]}
  done
  (( MAX_LEFT + MAX_RIGHT + WIDTH_OFFSET > WIDTH )) && WIDTH=$(( MAX_LEFT + MAX_RIGHT + WIDTH_OFFSET ))

  CHOICE=$(whiptail --backtitle "$APP_BACKTITLE" --title "$TITLE" --menu "$TEXT" \
    "$HIGHT" "$WIDTH" "$LEN" "${OPTIONS[@]}" 3>&1 1>&2 2>&3 || true)
  echo "$CHOICE"
}

function whiptail_inputbox() {
  local TITLE=$1
  local TEXT=$2
  local VALUE_INIT=$3
  local VALUE_INPUT
  local HIGHT=10
  local WIDTH=$(( ${#TITLE} + 16 ))
  local WIDTH_ARRAY=( "$WIDTH" $(( ${#TEXT} + 4 )) $(( ${#VALUE_INIT} + 8 )) )
  for i in "${WIDTH_ARRAY[@]}"; do
    (( i > WIDTH )) && WIDTH=$i
  done

  VALUE_INPUT=$(whiptail --backtitle "$APP_BACKTITLE" --title "$TITLE" --inputbox "\n$TEXT" \
    "$HIGHT" "$WIDTH" "$VALUE_INIT" 3>&1 1>&2 2>&3)
  # shellcheck disable=SC2181
  [ $? = 0 ] && echo "$VALUE_INPUT" || echo "$VALUE_INIT"
}

function resolve_ip() {
  local FQDN=$1
  local IP
  IP=$(dig +short "$FQDN")
 [[ -z "$IP" ]] && exit 1 || echo "$IP"
}

function renew() {
  local BACK_TO_MENU="$1"
  certs_menu "Renew"

  msg_info "Renewing Certificate(s)"
  for CERT_SUBJECT in "${CERT_ARRAY[@]}"; do
    local CRT=${CERT_PATH}/${CERT_SUBJECT}.crt
    local KEY=${KEY_PATH}/${CERT_SUBJECT}.key
    echo -e "${BL}[Info]${GN} Renew x509 Certificate with Subject ${BL}${CERT_SUBJECT}${GN}:${CL}"
    step ca renew --force "${CRT}" "${KEY}" || die "Failed to renew certificate!"
    inspect "$CERT_SUBJECT"
  done
  msg_ok "Renewed Certificate(s)"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function revoke() {
  local BACK_TO_MENU="$1"
  certs_menu "Revoke"
  msg_info "Revoking Certificate(s)"
  for CERT_SUBJECT in "${CERT_ARRAY[@]}"; do
    local CRT=${CERT_PATH}/${CERT_SUBJECT}.crt
    local KEY=${KEY_PATH}/${CERT_SUBJECT}.key
    echo -e "${BL}[Info]${GN} Revoke x509 Certificate with Subject ${BL}${CERT_SUBJECT}${GN}:${CL}"
    step ca revoke --cert "${CRT}" --key "${KEY}" || die "Failed to revoke certificate!"
    rm -f "${CRT}" || die "Failed to delete ${CRT}!"
    rm -f "${KEY}" || die "Failed to delete ${KEY}!"
  done
  msg_ok "Revoked Certificate(s)"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function inspect() {
  CERT_ARRAY=("$1")
  [[ -z ${CERT_ARRAY[*]} ]] && certs_menu "Inspect"
  local BACK_TO_MENU="$2"

  msg_info "Inspecting Certificate(s)"
  for CERT_SUBJECT in "${CERT_ARRAY[@]}"; do
    local CRT=${CERT_PATH}/${CERT_SUBJECT}.crt
    local KEY=${KEY_PATH}/${CERT_SUBJECT}.key
    echo -e "${BL}[Info]${GN} Inspect x509 Certificate with Subject ${BL}${CERT_SUBJECT}${GN}:${CL}"
    step certificate inspect "${CRT}" || die "Failed to inspect certificate!"
    echo -e "${BL}[Info]${GN} Public Key:${CL}"
    cat "${CRT}"
    echo -e "${BL}[Info]${GN} Private Key:${CL}"
    cat "${KEY}"
  done
  msg_ok "Inspected Certificate(s)"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function bootstrap_fqdn_check() {
  if [[ -z $CA_FQDN ]]; then
    CA_FQDN="Please change!"
    return 1
  else
    CA_IP=$(resolve_ip "${CA_FQDN}")
    if [[ -z $CA_IP ]]; then
      CA_FQDN="DNS Resolution failed - Please change!"
      return 1
    fi
  fi
}

function bootstrap_fingerprint_check() {
  if [[ -z $CA_FINGERPRINT ]]; then
    CA_FINGERPRINT="Please change!"
    return 1
  fi
}

function bootstrap() {
  local BACK_TO_MENU="$1"
  bootstrap_menu
  msg_info "Installing step-ca Root Certificate"
  $STD step ca bootstrap -f --ca-url https://"$CA_FQDN" --install --fingerprint "$CA_FINGERPRINT"  || die "step-ca Bootstrapping failed!"
  $STD step certificate install --all "${CERT_PATH}"/root_ca.crt || die "Installation of step-ca Root Certificate failed!"
  $STD update-ca-certificates  || die "Update of System CA Certificates failed!"
  $STD step certificate inspect https://"$CA_FQDN" || die "Inspection of step-ca Root Certificate failed!"
  msg_ok "Installed step-ca Root Certificate"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function request() {
  local BACK_TO_MENU="$1"
  VALID_TO="168h"
  FQDN=$(hostname -f)
  HOST=$(hostname)
  DomainName=$(hostname -d)
  IP=$(resolve_ip "${FQDN}") || die "Resolution failed for ${FQDN}!"
  AcmeProvisioner="acme@$DomainName"
  SAN=""

  request_menu

  msg_info "Requesting System Certificate by ACME"
  local SAN_ITEMS=("$FQDN" "$HOST" "$IP" "$SAN")
  local SAN_FLAGS=()
  for item in "${SAN_ITEMS[@]}"; do
    SAN_FLAGS+=(--san "$item")
  done

  step ca certificate "$FQDN" \
    "${CERT_PATH}"/"$FQDN".crt \
    "${KEY_PATH}"/"$FQDN".key \
    --provisioner="$AcmeProvisioner" \
    --not-after="$VALID_TO" \
    -f \
    "${SAN_FLAGS[@]}" || die "Certificate Signing Request (CSR) by ACME failed!"

  inspect "$FQDN"
  msg_ok "Requested System Certificate by ACME"

  msg_info "Starting Certificate Renewal as a Daemon"
  $STD systemctl enable --now cert-renewer@"${FQDN}".timer
  systemctl list-units cert-renewer@\*.timer
  msg_ok "Started Certificate Renewal as a Daemon"
  [[ "$BACK_TO_MENU" ]] && read -n 1 -r -s -p $'\nPress any key to continue...\n' && "$BACK_TO_MENU" || true
}

function detect_os() {
  if grep -qi "alpine" /etc/os-release; then
    #OS="Alpine"
    PKG_UPDATE=""
    PKG_INSTALL="apk add --no-cache"
    PKG_UPGRADE="apk update"
    PKG_UNINSTALL="apk del"
    PKG_AUTOREMOVE=""
  elif grep -qi "arch" /etc/os-release; then
    #OS="Arch"
    PKG_UPDATE=""
    PKG_INSTALL="pacman -S"
    PKG_UPGRADE="pacman -Syu"
    PKG_UNINSTALL="pacman -Rs"
    PKG_AUTOREMOVE=""
  elif grep -qi "debian" /etc/os-release; then
    #OS="Debian"
    PKG_UPDATE="apt update"
    PKG_INSTALL="apt -y install"
    PKG_UPGRADE="apt -y upgrade"
    PKG_UNINSTALL="apt -y --purge remove"
    PKG_AUTOREMOVE="apt -y --purge autoremove"
    if ! [[ -f /etc/apt/sources.list.d/smallstep.sources ]]; then
      setup_deb822_repo \
        "smallstep" \
        "https://packages.smallstep.com/keys/apt/repo-signing-key.gpg" \
        "https://packages.smallstep.com/stable/debian" \
        "debs" \
        "main"
    fi
  elif grep -qi "ubuntu" /etc/os-release; then
    #OS="Ubuntu"
    PKG_UPDATE="apt update"
    PKG_INSTALL="apt -y install"
    PKG_UPGRADE="apt -y upgrade"
    PKG_UNINSTALL="apt -y --purge remove"
    PKG_AUTOREMOVE="apt -y --purge autoremove"
    if ! [[ -f /etc/apt/sources.list.d/smallstep.sources ]]; then
      setup_deb822_repo \
        "smallstep" \
        "https://packages.smallstep.com/keys/apt/repo-signing-key.gpg" \
        "https://packages.smallstep.com/stable/debian" \
        "debs" \
        "main"
    fi
  else
    die "Unsupported OS. Exiting."
  fi
}

function uninstall() {
  msg_info "Uninstalling $APP"
  systemctl disable cert-renewer@.timer
  systemctl disable cert-renewer@.service
  systemctl stop cert-renewer@*.timer
  systemctl stop cert-renewer@*.service
  $PKG_UNINSTALL $APP
  $PKG_AUTOREMOVE
  rm -rf "${CONFIG_PATH}"
  rm -f "/usr/local/bin/update_${APP,,}"
  rm -f "/etc/systemd/system/cert-renewer@.service"
  rm -f "/etc/systemd/system/cert-renewer@.timer"
  $STD systemctl daemon-reload
  msg_ok "Uninstalled $APP"
}

function update() {
  if [[ ! -e $BINARY_PATH ]]; then
    die "$APP is not installed"
  fi
  msg_info "Updating $APP"
  $PKG_UPDATE
  $PKG_UPGRADE $APP
  msg_ok "Updated $APP successfully"
}

function install() {
  msg_info "Installing dependencies"
  $PKG_UPDATE
  $PKG_INSTALL curl whiptail dnsutils jq
  msg_ok "Installed dependencies"

  msg_info "Installing $APP"
  $PKG_INSTALL $APP
  if [[ ! -e $BINARY_PATH ]]; then
    ln -s /usr/bin/step-cli $BINARY_PATH
  fi
  mkdir -p "$CONFIG_PATH"/certs
  mkdir -p "$CONFIG_PATH"/private
  
  cat <<'EOF' >/etc/systemd/system/cert-renewer@.service
[Unit]
Description=Certificate renewer for %i
After=network-online.target
Documentation=https://smallstep.com/docs/step-ca/certificate-authority-server-production
StartLimitIntervalSec=0
; PartOf=cert-renewer.target

[Service]
Type=oneshot
User=root

Environment=STEPPATH="/etc/step" CERT_LOCATION="/etc/step/certs/%i.crt" KEY_LOCATION="/etc/step/private/%i.key"

; ExecCondition checks if the certificate is ready for renewal,
; based on the exit status of the command.
; (In systemd <242, you can use ExecStartPre= here.)
ExecCondition=/usr/bin/step certificate needs-renewal "${CERT_LOCATION}"

; ExecStart renews the certificate, if ExecStartPre was successful.
ExecStart=/usr/bin/step ca renew --force "${CERT_LOCATION}" "${KEY_LOCATION}"

; Try to reload or restart the systemd service that relies on this cert-renewer
; If the relying service doesn't exist, forge ahead.
; (In systemd <229, use 'reload-or-try-restart' instead of 'try-reload-or-restart')
ExecStartPost=/usr/bin/env sh -c "! systemctl --quiet is-active %i.service || systemctl try-reload-or-restart %i"

[Install]
WantedBy=multi-user.target
EOF

  cat <<'EOF' >/etc/systemd/system/cert-renewer@.timer
[Unit]
Description=Timer for certificate renewal of %i
Documentation=https://smallstep.com/docs/step-ca/certificate-authority-server-production
; PartOf=cert-renewer.target

[Timer]
Persistent=true

; Run the timer unit every 2 minutes.
OnCalendar=*:1/2

; Always run the timer on time.
AccuracySec=1us

; Add jitter to prevent a "thundering hurd" of simultaneous certificate renewals.
RandomizedDelaySec=12s

[Install]
WantedBy=timers.target
EOF
  $STD systemctl daemon-reload
  msg_ok "Installed $APP"

  $STD bootstrap "" || die "Installation of step-ca Root Certificate failed!"
  $STD request "" || die "Main - Request System Certificate failed!"
}

function certs_menu() {
  local CERT_ACTION=$1
  local CERT_FILE_ARRAY=("${CERT_PATH}"/*.crt)
  local CERT_FILE
  local CERT_FQDN
  local CERT_LIST=()
  local CHOICE
  for CERT_FILE in "${CERT_FILE_ARRAY[@]}"; do
    CERT_FQDN=$(echo "$CERT_FILE" | awk -F '/' '{print $5}' | sed 's/.crt//g')
    CERT_LIST+=("${CERT_FQDN}" "${CERT_FILE}")
  done
  CHOICE=$(whiptail_checklist "Certificates by step" "\nSelect Certificate(s) to ${CERT_ACTION}:" "CERT_LIST")
  if [[ -z $CHOICE ]]; then
    maintenance_menu
  else
    # shellcheck disable=SC2206
    CERT_ARRAY=(${CHOICE})
  fi
}

function request_menu() {
  local CHOICE
  OPTIONS=("FQDN" "$FQDN"
    "Hostname" "$HOST"
    "IP Address" "$IP"
    "Subject Alternative Name(s) (SANs)" "$SAN"
    "Validity" "$VALID_TO"
    "ACME Provisioner" "$AcmeProvisioner"
	" " " "
    "<Continue>" "Request Certificate by ACME")
  local TITLE="Certificate Signing Request (CSR) by ACME"

  CHOICE=$(whiptail_menu "$TITLE")
  case "$CHOICE" in
    "FQDN")
      FQDN=$(whiptail_inputbox "$TITLE" "FQDN (e.g. MyLXC.example.com)" "$FQDN")
      request_menu
      ;;
    "Hostname")
      HOST=$(whiptail_inputbox "$TITLE" "Hostname (e.g. MyHostName)" "$HOST")
      request_menu
      ;;
    "IP Address")
      IP=$(whiptail_inputbox "$TITLE" "IP Address (e.g. x.x.x.x)" "$IP")
      request_menu
      ;;
    "Subject Alternative Name(s) (SANs)")
      SAN=$(whiptail_inputbox "$TITLE" "Subject Alternative Name(s) (SAN) (e.g. MyApp.example.com)" "$SAN")
      request_menu
      ;;
    "Validity")
      VALID_TO=$(whiptail_inputbox "$TITLE" "Validity (e.g. 168h)" "$VALID_TO")
      request_menu
      ;;
    "ACME Provisioner")
      AcmeProvisioner=$(whiptail_inputbox "$TITLE" "ACME Provisioner (e.g. acme@example.com)" "$AcmeProvisioner")
      request_menu
      ;;
    " ")
      request_menu
      ;;
    "<Continue>") ;;
    *) maintenance_menu ;;
    esac
}

function bootstrap_menu() {
  local CHOICE
  bootstrap_fqdn_check
  bootstrap_fingerprint_check

  OPTIONS=("step-ca FQDN" "$CA_FQDN"
    "step-ca Fingerprint" "$CA_FINGERPRINT"
	" " " "
    "<Continue>" "Install step-ca Root Certificate")
  local TITLE="step-ca Bootstrap Options"

  CHOICE=$(whiptail_menu "$TITLE")
  case "$CHOICE" in
    "step-ca FQDN")
      CA_FQDN=$(whiptail_inputbox "$TITLE" "step-ca FQDN (e.g. step-ca.example.com)" "$CA_FQDN")
      bootstrap_menu
      ;;
    "step-ca Fingerprint")
      CA_FINGERPRINT=$(whiptail_inputbox "$TITLE" "step-ca Fingerprint" "$CA_FINGERPRINT")
      bootstrap_menu
      ;;
    " ")
      bootstrap_menu
      ;;
    "<Continue>")
      bootstrap_fqdn_check || bootstrap_menu
      ;;
    *) maintenance_menu ;;
    esac
}

function maintenance_menu() {
  if [[ ! -e $BINARY_PATH ]]; then
    die "$APP is not installed"
  fi
  local CHOICE
  OPTIONS=(Bootstrap "Install step-ca Root Certificate"
    Request "Certificate Signing Request (CSR) by ACME"
    Renew "Renew Certificate by ACME"
    Revoke "Revoke Certificate by ACME"
    Inspect "Inspect Certificate by ACME")

  CHOICE=$(whiptail_menu "$APP_TITLE")
  case "$CHOICE" in
    Bootstrap) bootstrap "maintenance_menu" ;;
    Request) request "maintenance_menu" ;;
    Renew) renew "maintenance_menu" ;;
    Revoke) revoke "maintenance_menu" ;;
    Inspect) inspect "" "maintenance_menu" ;;
    *) exit 0 ;;
  esac
}

function main_menu() {
  local CHOICE
  OPTIONS=(Install "Install $APP"
    Update "Update $APP"
    Uninstall "Uninstall $APP"
    Maintenance "Maintain Certificates")

  CHOICE=$(whiptail_menu "$APP_TITLE")
  case "$CHOICE" in
    Install) install ;;
    Update) update ;;
    Uninstall) uninstall ;;
    Maintenance) maintenance_menu ;;
    *) exit 0 ;;
  esac
}

header_info
detect_os
main_menu
