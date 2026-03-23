#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/smallstep/certificates

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_deb822_repo \
  "smallstep" \
  "https://packages.smallstep.com/keys/apt/repo-signing-key.gpg" \
  "https://packages.smallstep.com/stable/debian" \
  "debs" \
  "main"

msg_info "Installing step-ca and step-cli"
$STD apt install -y step-ca step-cli

STEPHOME="/root/.step"
$STD export STEPPATH=/etc/step-ca
$STD export STEPHOME=$STEPHOME

$STD sed  -i '1i export STEPPATH=/etc/step-ca' /etc/profile
$STD sed  -i '1i export STEPHOME=/root/.step' /etc/profile

$STD setcap CAP_NET_BIND_SERVICE=+eip $(which step-ca)

$STD useradd --user-group --system --home $(step path) --shell /bin/false step
msg_ok "Installed step-ca and step-cli"

DeploymentType="standalone"
FQDN=$(hostname -f)
DomainName=$(hostname -d)
IP=${LOCAL_IP}
LISTENER=":443"
PKIName="MyHomePKI"
PKIProvisioner="pki@$DomainName"
AcmeProvisioner="acme@$DomainName"
X509MinDur="48h"
X509MaxDur="87600h"
X509DefaultDur="168h"

$STD while true;
do

if $STD whiptail --backtitle "Proxmox VE Helper Scripts" --title "step ca init options" --yesno "Continue with below?\n
PKIName: $PKIName
PKIProvisioner: $PKIProvisioner
AcmeProvisioner: $AcmeProvisioner
X509MinDur: $X509MinDur
X509MaxDur: $X509MaxDur
X509DefaultDur: $X509DefaultDur" --no-button "Change" --yes-button "Continue" 15 70 3>&1 1>&2 2>&3; then
$STD break
fi

PKIName=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "step ca init options" --inputbox 'PKIName (e.g. MyHomePKI)' 10 50 "$PKIName" 3>&1 1>&2 2>&3)
PKIProvisioner=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "step ca init options" --inputbox 'PKIProvisioner (e.g. pki@$YourDomainName)' 10 50 "$PKIProvisioner" 3>&1 1>&2 2>&3)
AcmeProvisioner=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "step ca init options" --inputbox 'AcmeProvisioner (e.g. acme@YourDomainName)' 10 50 "$AcmeProvisioner" 3>&1 1>&2 2>&3)
X509MinDur=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "step ca init options" --inputbox 'X509MinDur (e.g. 48h)' 10 50 "$X509MinDur" 3>&1 1>&2 2>&3)
X509MaxDur=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "step ca init options" --inputbox 'X509MaxDur (e.g. 87600h)' 10 50 "$X509MaxDur" 3>&1 1>&2 2>&3)
X509DefaultDur=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "step ca init options" --inputbox 'X509DefaultDur (e.g. 168h)' 10 50 "$X509DefaultDur" 3>&1 1>&2 2>&3)

done

EncryptionPwdDir="$(step path)/encryption"
PwdFile="$EncryptionPwdDir/ca.pwd"
ProvisionerPwdFile="$EncryptionPwdDir/provisioner.pwd"

$STD mkdir -p "$EncryptionPwdDir"
$STD gpg --gen-random --armor 2 32 >"$PwdFile"
$STD gpg --gen-random --armor 2 32 >"$ProvisionerPwdFile"

msg_info "Initializing step-ca"
$STD step ca init \
  --deployment-type=$DeploymentType \
  --ssh \
  --name=$PKIName \
  --dns="$FQDN" \
  --dns="$IP" \
  --address=$LISTENER \
  --provisioner="$PKIProvisioner" \
  --password-file="$PwdFile" \
  --provisioner-password-file="$ProvisionerPwdFile" >/dev/null

$STD ln -s "$PwdFile" "$(step path)/password.txt"
$STD chown -R step:step $(step path)
$STD chmod -R 700 $(step path)

$STD step ca provisioner add "$AcmeProvisioner" --type ACME --admin-name "$AcmeProvisioner"
$STD step ca provisioner update "$PKIProvisioner" \
   --x509-min-dur=$X509MinDur \
   --x509-max-dur=$X509MaxDur \
   --x509-default-dur=$X509DefaultDur \
   --allow-renewal-after-expiry
$STD step ca provisioner update "$AcmeProvisioner" \
   --x509-min-dur=$X509MinDur \
   --x509-max-dur=$X509MaxDur \
   --x509-default-dur=$X509DefaultDur \
   --allow-renewal-after-expiry
msg_ok "Initialized step-ca"

msg_info "Start step-ca as a Daemon"
cat <<'EOF' >/etc/systemd/system/step-ca.service
[Unit]
Description=step-ca service
Documentation=https://smallstep.com/docs/step-ca
Documentation=https://smallstep.com/docs/step-ca/certificate-authority-server-production
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=30
StartLimitBurst=3
ConditionFileNotEmpty=/etc/step-ca/config/ca.json
ConditionFileNotEmpty=/etc/step-ca/password.txt

[Service]
Type=simple
User=step
Group=step
Environment=STEPPATH=/etc/step-ca
WorkingDirectory=/etc/step-ca
ExecStart=/usr/bin/step-ca config/ca.json --password-file password.txt
ExecReload=/bin/kill -USR1 $MAINPID
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitAction=reboot

; Process capabilities & privileges
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
SecureBits=keep-caps
NoNewPrivileges=yes

; Sandboxing
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@resources @privileged
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
PrivateMounts=yes
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/etc/step-ca/db

; Read only paths
ReadOnlyPaths=/etc/step-ca

[Install]
WantedBy=multi-user.target
EOF
$STD systemctl enable -q --now step-ca
msg_ok "Started step-ca as a Daemon"

msg_info "Install root CA certificate into system's default trust store"
$STD step certificate install --all $(step path)/certs/root_ca.crt
$STD update-ca-certificates
msg_ok "Installed root CA certificate into system's default trust store"

msg_info "Install step-batcher to export step-ca badger database"
StepBadgerX509Certs="$STEPHOME/step-badger-x509Certs.sh"
StepBadgerSshCerts="$STEPHOME/step-badger-sshCerts.sh"

fetch_and_deploy_gh_release "step-badger" "lukasz-lobocki/step-badger" "prebuild" "latest" "/opt/step-badger" "step-badger_Linux_x86_64.tar.gz"
ln -s /opt/step-badger/step-badger /usr/local/bin/step-badger

mkdir --parents "$STEPHOME/db-copy/"
mkdir --parents "$STEPHOME/certs/ca/"
mkdir --parents "$STEPHOME/certs/ssh/"
mkdir --parents "$STEPHOME/certs/x509/"

$STD cat <<'EOF' >$StepBadgerX509Certs
#!/usr/bin/env bash
#
# See: https://github.com/lukasz-lobocki/step-badger
#

cp --recursive --force "$(step path)/db/"* "$STEPHOME/db-copy/"
cp --recursive --force "$(step path)/certs/"* "$STEPHOME/certs/ca/"

step-badger x509Certs "$STEPHOME/db-copy" \
        --dnsnames \
        --emailaddresses \
        --ipaddresses \
        --uris \
        --issuer \
        --crl \
        --provisioner \
        --algorithm
EOF
$STD cat <<'EOF' >$StepBadgerSshCerts
#!/usr/bin/env bash
#
# See: https://github.com/lukasz-lobocki/step-badger
#

cp --recursive --force "$(step path)/db/"* "$STEPHOME/db-copy/"
cp --recursive --force "$(step path)/certs/"* "$STEPHOME/certs/ca/"

step-badger sshCerts "$STEPHOME/db-copy" \
        --algorithm
EOF
chmod 700 $StepBadgerX509Certs
chmod 700 $StepBadgerSshCerts
msg_ok "Installed step-batcher to export step-ca badger database"

msg_info "Install step-ca helper scripts"
StepRequest="$STEPHOME/step-ca-request.sh"
StepRevoke="$STEPHOME/step-ca-revoke.sh"
$STD cat <<'EOF' >$StepRequest
#!/usr/bin/env bash
#
StepCertDir="$STEPHOME/certs/x509"

HOST="brw4cd5770e36b4"
IP="192.168.178.136"
DOMAIN="fritz.box"
FQDN=$HOST.$DOMAIN
VALID_TO="2034-01-31T00:00:00Z"
PROVISIONER="pki@fritz.box"

step ca certificate $FQDN $StepCertDir/$FQDN.crt $StepCertDir/$FQDN.key \
  --provisioner=$PROVISIONER \
  --not-after=$VALID_TO \
  --san $FQDN \
  --san $HOST \
  --san $IP

step certificate inspect $StepCertDir/$FQDN.crt
EOF
$STD cat <<'EOF' >$StepRevoke
#!/usr/bin/env bash
#
# step ca revoke <serialnumber>
#
step ca revoke
EOF
chmod 700 $StepRequest
chmod 700 $StepRevoke
msg_ok "Installed step-ca helper scripts"

motd_ssh
customize
cleanup_lxc
