#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/smallstep/cli

#source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE/main/misc/core.func)
#source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/heinemannj/ProxmoxVE/main/misc/tools.func)

APP="step-cli"
BINARY_PATH="/usr/bin/step"
CONFIG_PATH="/root/.step"
StepCertDir="/etc/ssl"

function header_info {
  clear
  cat <<"EOF"
         __                        ___
   _____/ /____  ____        _____/ (_)
  / ___/ __/ _ \/ __ \______/ ___/ / /
 (__  ) /_/  __/ /_/ /_____/ /__/ / /
/____/\__/\___/ .___/      \___/_/_/
             /_/

EOF
}

YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
RD=$(echo "\033[01;31m")
BL=$(echo "\033[36m")
CL=$(echo "\033[m")
CM="${GN}✔️${CL}"
CROSS="${RD}✖️${CL}"
INFO="${BL}ℹ️${CL}"
TAB="  "

function msg_info() { echo -e "${INFO} ${YW}${1}...${CL}"; }
function msg_ok() { echo -e "${CM} ${GN}${1}${CL}"; }
function msg_error() { echo -e "${CROSS} ${RD}${1}${CL}"; }
function msg_warn() { echo -e "⚠️  ${YW}${1}${CL}"; }

function die() {
  echo -e "\n${BL}[ERROR]${GN} ${RD}${1}${CL}\n"
  exit 1
}

function renew() {
  local FQDN=$1
  step certificate inspect $StepCertDir/localcerts/"$FQDN".crt  || die "Certificate renew failed!"
}

function revoke() {
  local FQDN=$1
  step certificate inspect $StepCertDir/localcerts/"$FQDN".crt  || die "Certificate revoke failed!"
}

function inspect() {
  local FQDN=$1
  step certificate inspect $StepCertDir/localcerts/"$FQDN".crt  || die "Certificate inspect failed!"
}

function bootstrap() {
  msg_info "Installing root CA certificate"
  while true;
  do
    CA_FQDN=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "step-ca Bootstrap Options" --inputbox '\nCA FQDN (e.g. step-ca.example.com)' 10 50 "$CA_FQDN" 3>&1 1>&2 2>&3)
    IP=$(dig +short "$CA_FQDN")
    if [[ -z "$IP" ]]; then
      die "Resolution failed for $CA_FQDN!"
    fi
    FINGERPRINT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "step-ca Bootstrap Options" --inputbox '\nCA Fingerprint' 10 50 "$FINGERPRINT" 3>&1 1>&2 2>&3)

    if whiptail_yesno=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "step-ca Bootstrap Options" --yesno "Continue with below?\n
      CA FQDN: $CA_FQDN
      CA Fingerprint: $FINGERPRINT" --no-button "Change" --yes-button "Continue" 15 70 3>&1 1>&2 2>&3); then
      break
    fi
  done

  $STD step ca bootstrap -f --ca-url https://"$CA_FQDN" --install --fingerprint "$FINGERPRINT"  || die "CA Bootstrapping failed!"
  $STD step certificate install --all ~/.step/certs/root_ca.crt || die "Installation of root CA Certificate failed!"
  $STD update-ca-certificates  || die "Update of System CA Certificates failed!"
  $STD step certificate inspect https://"$CA_FQDN" || die "Inspection of root CA Certificate failed!"
  msg_ok "Installed root CA certificate"
}

function request() {
  msg_info "Requesting System Certificate"
  VALID_TO="168h"
  FQDN=$(hostname -f)
  HOST=$(hostname)
  DomainName=$(hostname -d)
  IP=$(dig +short "$FQDN")
  if [[ -z "$IP" ]]; then
    die "Resolution failed for $FQDN!"
  fi
  AcmeProvisioner="acme@$DomainName"

  while true;
  do
    if whiptail_yesno=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Certificate Signing Request (CSR)" --yesno "Continue with below?\n
      FQDN: $FQDN
      Hostname: $HOST
      IP Address: $IP
      Subject Alternative Name(s) (SANs): $SAN
      Validity: $VALID_TO
      ACME Provisioner: $AcmeProvisioner" --no-button "Change" --yes-button "Continue" 15 70 3>&1 1>&2 2>&3); then
      break
    fi

    FQDN=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Certificate Signing Request (CSR)" --inputbox '\nFQDN (e.g. MyLXC.example.com)' 10 50 "$FQDN" 3>&1 1>&2 2>&3)
    IP=$(dig +short "$FQDN")
    if [[ -z "$IP" ]]; then
      die "Resolution failed for $FQDN!"
    fi
    HOST=$(echo "$FQDN" | awk -F'.' '{print $1}')
    IP=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Certificate Signing Request (CSR)" --inputbox '\nIP Address (e.g. x.x.x.x)' 10 50 "$IP" 3>&1 1>&2 2>&3)
    HOST=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Certificate Signing Request (CSR)" --inputbox '\nHostname (e.g. MyHostName)' 10 50 "$HOST" 3>&1 1>&2 2>&3)
    SAN=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Certificate Signing Request (CSR)" --inputbox '\nSubject Alternative Name(s) (SAN) (e.g. MyApp.example.com)' 10 50 "$SAN" 3>&1 1>&2 2>&3)
    VALID_TO=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Certificate Signing Request (CSR)" --inputbox '\nValidity (e.g. 168h)' 10 50 "$VALID_TO" 3>&1 1>&2 2>&3)
    AcmeProvisioner=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Certificate Signing Request (CSR)" --inputbox '\nACME Provisioner (e.g. acme@example.com)' 10 50 "$AcmeProvisioner" 3>&1 1>&2 2>&3)
  done

  SAN="$FQDN, $HOST, $IP, $SAN"

  IFS=', ' read -r -a array <<< "$SAN"
  for element in "${array[@]}"
  do
    SAN_ARRAY+=(--san "$element")
  done

  step ca certificate "$FQDN" \
    "$StepCertDir"/localcerts/"$FQDN".crt \
    "$StepCertDir"/private/"$FQDN".key \
    --provisioner="$AcmeProvisioner" \
    --not-after="$VALID_TO" \
    -f \
    "${SAN_ARRAY[@]}" || die "Certificate Signing Request (CSR) failed!"

  inspect "$FQDN"
  msg_ok "Requested system certificate"

  msg_info "Starting step as a Daemon"
  cat <<EOF >/etc/systemd/system/step.service
[Unit]
Description=Automated Certificate Management
Documentation=https://smallstep.com/docs/step-cli/reference/ca/renew/
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
ExecStart=/usr/bin/step ca renew --daemon $StepCertDir/localcerts/$FQDN.crt $StepCertDir/private/$FQDN.key

[Install]
WantedBy=multi-user.target
EOF
  $STD systemctl daemon-reload
  $STD systemctl enable -q --now step.service
  sleep 5
  systemctl status step.service
  msg_ok "Started step as a Daemon"
}

function detect_os() {
  if grep -qi "alpine" /etc/os-release; then
    OS="Alpine"
    PKG_UPDATE=""
    PKG_INSTALL="apk add --no-cache"
    PKG_UPGRADE="apk update"
    PKG_UNINSTALL="apk del"
    PKG_AUTOREMOVE=""
  elif grep -qi "arch" /etc/os-release; then
    OS="Arch"
    PKG_UPDATE=""
    PKG_INSTALL="pacman -S"
    PKG_UPGRADE="pacman -Syu"
    PKG_UNINSTALL="pacman -Rs"
    PKG_AUTOREMOVE=""
  elif grep -qi "debian" /etc/os-release; then
    OS="Debian"
    PKG_UPDATE="apt update"
    PKG_INSTALL="apt -y install"
    PKG_UPGRADE="apt -y upgrade"
    PKG_UNINSTALL="apt -y --purge remove"
    PKG_AUTOREMOVE="apt -y --purge autoremove"
    setup_deb822_repo \
      "smallstep" \
      "https://packages.smallstep.com/keys/apt/repo-signing-key.gpg" \
      "https://packages.smallstep.com/stable/debian" \
      "debs" \
      "main"
  elif grep -qi "ubuntu" /etc/os-release; then
    OS="Ubuntu"
    PKG_UPDATE="apt update"
    PKG_INSTALL="apt -y install"
    PKG_UPGRADE="apt -y upgrade"
    PKG_UNINSTALL="apt -y --purge remove"
    PKG_AUTOREMOVE="apt -y --purge autoremove"
    setup_deb822_repo \
      "smallstep" \
      "https://packages.smallstep.com/keys/apt/repo-signing-key.gpg" \
      "https://packages.smallstep.com/stable/debian" \
      "debs" \
      "main"
  else
    die "Unsupported OS. Exiting."
  fi
}

function uninstall() {
  msg_info "Uninstalling $APP"
  systemctl stop step.service
  systemctl disable step.service
  $PKG_UNINSTALL $APP
  $PKG_AUTOREMOVE
  rm -rf $CONFIG_PATH
  rm -f "/usr/local/bin/update_${APP,,}"
  rm -f /etc/systemd/system/step.service
  msg_ok "Uninstalled $APP"
}

function update() {
  if [[ ! -e $BINARY_PATH ]]; then
    die "$APP is not installed"
  fi
  msg_info "Updating $APP"
  $STD systemctl stop step.service
  $PKG_UPDATE
  $PKG_UPGRADE $APP
  $STD systemctl start step.service
  sleep 5
  systemctl status step.service
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
  mkdir -p "$CONFIG_PATH"
  mkdir -p /etc/ssl/localcerts
  msg_ok "Installed $APP"

  $STD bootstrap || die "Main - CA Bootstrap failed!"
  $STD request || die "Main - Request System Certificate failed!"
}

header_info
detect_os

# options menu
OPTIONS=(Install "Install $APP"
  Update "Update $APP"
  Uninstall "Uninstall $APP"
  Bootstrap "Install root CA Certificate"
  Request "Certificate Signing Request (CSR)"
  Renew "Renew Certificate"
  Revoke "Revoke Certificate"
  Inspect "Inspect Certificate")

CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "$APP" --menu "\nSelect an option:" 12 58 8 \
  "${OPTIONS[@]}" 3>&1 1>&2 2>&3 || true)

case "$CHOICE" in
  Install) install ;;
  Update) update ;;
  Uninstall) uninstall ;;
  Bootstrap) bootstrap ;;
  Request) request ;;
  Renew) renew ;;
  Revoke) revoke ;;
  Inspect) inspect ;;
  *) exit 0 ;;
esac
