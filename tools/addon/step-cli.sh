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
StepCSR="$CONFIG_PATH/step-certificate-signing-request.sh"
StepBootstrap="$CONFIG_PATH/step-ca-bootstrap.sh"

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

function install_helper_scripts() {
  mkdir -p "$CONFIG_PATH"
  $STD cat <<'EOF' >$StepCSR
#!/usr/bin/env bash
#

echo "Requesting system certificate"
echo

StepCertDir="/etc/ssl"

VALID_TO="168h"
FQDN=$(hostname -f)
HOST=$(hostname)
DomainName=$(hostname -d)
IP=$(dig +short "$FQDN")
if [[ -z "$IP" ]]; then
    echo "Resolution failed for $FQDN"
    exit
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

FQDN=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Certificate Signing Request (CSR)" --inputbox 'FQDN (e.g. MyLXC.example.com)' 10 50 "$FQDN" 3>&1 1>&2 2>&3)
IP=$(dig +short "$FQDN")
if [[ -z "$IP" ]]; then
    echo "Resolution failed for $FQDN"
    exit
fi
HOST=$(echo "$FQDN" | awk -F'.' '{print $1}')
IP=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Certificate Signing Request (CSR)" --inputbox 'IP Address (e.g. x.x.x.x)' 10 50 "$IP" 3>&1 1>&2 2>&3)
HOST=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Certificate Signing Request (CSR)" --inputbox 'Hostname (e.g. MyHostName)' 10 50 "$HOST" 3>&1 1>&2 2>&3)
SAN=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Certificate Signing Request (CSR)" --inputbox 'Subject Alternative Name(s) (SAN) (e.g. MyApp.example.com)' 10 50 "$SAN" 3>&1 1>&2 2>&3)
VALID_TO=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Certificate Signing Request (CSR)" --inputbox 'Validity (e.g. 168h)' 10 50 "$VALID_TO" 3>&1 1>&2 2>&3)
AcmeProvisioner=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Certificate Signing Request (CSR)" --inputbox 'ACME Provisioner (e.g. acme@example.com)' 10 50 "$AcmeProvisioner" 3>&1 1>&2 2>&3)

done

SAN="$FQDN, $HOST, $IP, $SAN"

IFS=', ' read -r -a array <<< "$SAN"
for element in "${array[@]}"
do
    SAN_ARRAY+=(--san "$element")
done

step ca certificate "$FQDN" \
  "$StepCertDir"/certs/"$FQDN".crt \
  "$StepCertDir"/private/"$FQDN".key \
  --provisioner="$AcmeProvisioner" \
  --not-after="$VALID_TO" \
  "${SAN_ARRAY[@]}"

step certificate inspect $StepCertDir/certs/$FQDN.crt
EOF

  $STD cat <<'EOF' >$StepBootstrap
#!/usr/bin/env bash
#

echo "Installing root CA certificate"
echo

while true;
do

CA_FQDN=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "step-ca Bootstrap Options" --inputbox '\nCA FQDN (e.g. step-ca.example.com)' 10 50 "$CA_FQDN" 3>&1 1>&2 2>&3)
IP=$(dig +short "$CA_FQDN")
if [[ -z "$IP" ]]; then
    echo "Resolution failed for $CA_FQDN"
    exit
fi
FINGERPRINT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "step-ca Bootstrap Options" --inputbox '\nCA Fingerprint' 10 50 "$FINGERPRINT" 3>&1 1>&2 2>&3)

if whiptail_yesno=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "step-ca Bootstrap Options" --yesno "Continue with below?\n
CA FQDN: $CA_FQDN
CA Fingerprint: $FINGERPRINT" --no-button "Change" --yes-button "Continue" 15 70 3>&1 1>&2 2>&3); then
break
fi

done

step ca bootstrap -f --ca-url https://"$CA_FQDN" --install --fingerprint "$FINGERPRINT"
step certificate install --all ~/.step/certs/root_ca.crt
update-ca-certificates
EOF
  chmod 700 $StepCSR
  chmod 700 $StepBootstrap
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
    msg_error "Unsupported OS. Exiting."
    exit 1
  fi
}

function uninstall() {
  msg_info "Uninstalling $APP"
  $PKG_UNINSTALL $APP
  $PKG_AUTOREMOVE
  rm -rf $CONFIG_PATH
  rm -f "/usr/local/bin/update_${APP,,}"
  msg_ok "Uninstalled $APP"
}

function update() {
  if [[ ! -e $BINARY_PATH ]]; then
    msg_error "$APP is not installed"
    exit 1
  fi
  msg_info "Updating $APP"
    $PKG_UPDATE
    $PKG_UPGRADE $APP
  msg_ok "Updated successfully"
}

function install() {
  msg_info "Installing dependencies"
  $STD $PKG_UPDATE
  $STD $PKG_INSTALL curl whiptail dnsutils jq
  msg_ok "Installed dependencies"

  msg_info "Installing $APP"
  $STD $PKG_INSTALL $APP
  if [[ ! -e $BINARY_PATH ]]; then
    ln -s /usr/bin/step-cli $BINARY_PATH
  fi 
  msg_ok "Installed $APP"

  msg_info "Installing step helper scripts"
  install_helper_scripts
  msg_ok "Installed step helper scripts"

  msg_info "Installing root CA certificate"
  $STD $StepBootstrap
  $STD step certificate inspect https://"$CA_FQDN"
  msg_ok "Installed root CA certificate"

  msg_info "Requesting system certificate"
  #$STD $StepCSR
  #$STD step certificate inspect $StepCertDir/certs/"$FQDN".crt
  msg_ok "Requested system certificate"

  msg_info "Starting step as a Daemon"
  cat <<EOF >/etc/systemd/system/step.service
[Unit]
Description=Automated certificate management
Documentation=https://smallstep.com/docs/step-cli/reference/ca/renew/
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
ExecStart=/usr/bin/step ca renew --daemon $StepCertDir/certs/$FQDN.crt $StepCertDir/private/$FQDN.key

[Install]
WantedBy=multi-user.target
EOF
  #$STD systemctl enable -q --now step.service
  #systemctl status step.service
  msg_ok "Started step as a Daemon"
}

header_info
detect_os

# options menu
OPTIONS=(Install "Install $APP"
  Update "Update $APP"
  Uninstall "Uninstall $APP")

CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "$APP" --menu "Select an option:" 12 58 3 \
  "${OPTIONS[@]}" 3>&1 1>&2 2>&3 || true)

case "$CHOICE" in
  Install) install ;;
  Update) update ;;
  Uninstall) uninstall ;;
  *) exit 0 ;;
esac
