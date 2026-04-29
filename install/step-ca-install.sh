#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
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

STEPPATH="/etc/step-ca"
STEPHOME="/etc/step"

export STEPPATH=$STEPPATH
echo "export STEPPATH=${STEPPATH}" >> /etc/profile
export STEPHOME=$STEPHOME
echo "export STEPHOME=${STEPHOME}" >> /etc/profile

mkdir -p "$STEPHOME"

# Patch for making $STD happy (/usr/bin/step is a symlink to /usr/bin/step-cli)
STEPBIN="$(which step)"
rm -f "$STEPBIN"
cp -f "$(which step-cli)" "$STEPBIN"

# Patch for making systemd happy
mkdir -p "$(step path)/db"

# Low port-binding capabilities (ports < 1024)
# - Default step-ca listener port: 443
setcap CAP_NET_BIND_SERVICE=+eip "$(which step-ca)"

# Service User used by systemd step-ca.service
$STD useradd --user-group --system --home "$(step path)" --shell /bin/false step
msg_ok "Installed step-ca and step-cli"

DomainName="$(hostname -d)"

PKIName="$(prompt_input "Enter PKIName" "MyHomePKI" 30)"
PKICountry="$(prompt_input "Enter PKICountry" "DE" 30)"
PKIOrganizationalUnit="$(prompt_input "Enter PKIOrganizationalUnit" "MyHomeLab" 30)"
PKIProvisioner="$(prompt_input "Enter PKIProvisioner" "pki@$DomainName" 30)"
AcmeProvisioner="$(prompt_input "Enter AcmeProvisioner" "acme@$DomainName" 30)"
X509MinDur="$(prompt_input "Enter X509MinDur" "48h" 30)"
X509MaxDur="$(prompt_input "Enter X509MaxDur" "87600h" 30)"
X509DefaultDur="$(prompt_input "Enter X509DefaultDur" "168h" 30)"

DB_TYPE="$(prompt_input "Enter DBType (badgerv2, mysql or postgresql)" "badgerv2" 30)"

DB_NAME="stepca"
DB_USER="stepadmin"

case "$DB_TYPE" in
mysql)
  setup_mariadb
  MARIADB_DB_NAME="$DB_NAME" MARIADB_DB_USER="$DB_USER" setup_mariadb_db
  
  msg_info "Setup MariaDB"
  echo "MariaDB DB_NAME: $MARIADB_DB_NAME" > "/root/db_config.txt"
  echo "MariaDB DB_USER: $MARIADB_DB_USER" >> "/root/db_config.txt"
  echo "MariaDB DB_PASSWORD: $MARIADB_DB_PASS" >> "/root/db_config.txt"
  msg_ok "Setup MariaDB"
  ;;
postgresql)
  setup_postgresql
  PG_DB_NAME="$DB_NAME" PG_DB_USER="$DB_USER" setup_postgresql_db

  msg_info "Setup PostgreSQL"
  echo "PostgreSQL DB_NAME: $PG_DB_NAME" > "/root/db_config.txt"
  echo "PostgreSQL DB_USER: $PG_DB_USER" >> "/root/db_config.txt"
  echo "PostgreSQL DB_PASSWORD: $PG_DB_PASS" >> "/root/db_config.txt"
  msg_ok "Setup PostgreSQL"
  ;;
esac

msg_info "Initializing step-ca"

# Initialize step-ca
DeploymentType="standalone"
FQDN="$(hostname -f)"
IP="${LOCAL_IP}"
LISTENER=":443"
LISTENER_INSECURE=":80"
CAConfig="$(step path)/config/ca.json"

# Set different signing CA and Provisioner Passwords
EncryptionPwdDir="$(step path)/encryption"
PwdFile="$EncryptionPwdDir/ca.pwd"
ProvisionerPwdFile="$EncryptionPwdDir/provisioner.pwd"
mkdir -p "$EncryptionPwdDir"
gpg -q --gen-random --armor 2 32 >"$PwdFile"
gpg -q --gen-random --armor 2 32 >"$ProvisionerPwdFile"

# Used by systemd step-ca.service
ln -s "$PwdFile" "$(step path)/password.txt"

# Usage of:
# - SSH feature of step-ca
$STD step ca init \
  --deployment-type="$DeploymentType" \
  --no-db \
  --ssh \
  --name="$PKIName" \
  --dns="$FQDN" \
  --dns="$IP" \
  --address="$LISTENER" \
  --provisioner="Admin JWK" \
  --password-file="$PwdFile" \
  --provisioner-password-file="$ProvisionerPwdFile"

# Define enhanced x509 CA and Certificate Templates
mkdir -p "$(step path)/templates/ca"
mkdir -p "$(step path)/templates/x509"

CARootTemplate="$(step path)/templates/ca/root.tpl"
CAIntermediateTemplate="$(step path)/templates/ca/intermediate.tpl"
X509LeafTemplate="$(step path)/templates/x509/leaf.tpl"
X509LeafTemplateData="$(step path)/templates/x509/leaf_data.tpl"

cat <<'EOF' >"$CARootTemplate"
{
	"subject": {
		"country": {{ toJson .Insecure.User.country }},
		"organization": {{ toJson .Insecure.User.organization }},
		"organizationalUnit": {{ toJson .Insecure.User.organizationalUnit }},
		"commonName": {{ toJson .Subject.CommonName }}
	},
  "issuer": {{ toJson .Subject }},
	"keyUsage": ["certSign", "crlSign"],
	"basicConstraints": {
		"isCA": true,
		"maxPathLen": 1
	},
	"issuingCertificateURL": [{{ toJson .Insecure.User.issuingCertificateURL }}],
	"crlDistributionPoints": [{{ toJson .Insecure.User.crlDistributionPoints }}]
}
EOF

cat <<'EOF' >"$CAIntermediateTemplate"
{
	"subject": {
		"country": {{ toJson .Insecure.User.country }},
		"organization": {{ toJson .Insecure.User.organization }},
		"organizationalUnit": {{ toJson .Insecure.User.organizationalUnit }},
		"commonName": {{ toJson .Subject.CommonName }}
	},
	"keyUsage": ["certSign", "crlSign"],
	"basicConstraints": {
		"isCA": true,
		"maxPathLen": 0
	},
	"issuingCertificateURL": [{{ toJson .Insecure.User.issuingCertificateURL }}],
	"crlDistributionPoints": [{{ toJson .Insecure.User.crlDistributionPoints }}]
}
EOF

cat <<'EOF' >"$X509LeafTemplate"
{
	"subject": {
{{- if .Insecure.User.Country }}
		"country": {{ toJson .Insecure.User.country }},
{{- else }}
		"country": {{ toJson .country }},
{{- end }}
{{- if .Insecure.User.organization }}
		"organization": {{ toJson .Insecure.User.organization }},
{{- else }}
		"organization": {{ toJson .organization }},
{{- end }}
{{- if .Insecure.User.organizationalUnit }}
		"organizationalUnit": {{ toJson .Insecure.User.organizationalUnit }},
{{- else }}
		"organizationalUnit": {{ toJson .organizationalUnit }},
{{- end }}
		"commonName": {{ toJson .Subject.CommonName }}
	},
	"sans": {{ toJson .SANs }},
{{- if typeIs "*rsa.PublicKey" .Insecure.CR.PublicKey }}
	"keyUsage": ["keyEncipherment", "digitalSignature"],
{{- else }}
	"keyUsage": ["digitalSignature"],
{{- end }}
	"extKeyUsage": ["serverAuth", "clientAuth"],
{{- if .Insecure.User.issuingCertificateURL }}
	"issuingCertificateURL": [{{ toJson .Insecure.User.issuingCertificateURL }}],
{{- else }}
	"issuingCertificateURL": [{{ toJson .issuingCertificateURL }}],
{{- end }}
{{- if .Insecure.User.crlDistributionPoints }}
	"crlDistributionPoints": [{{ toJson .Insecure.User.crlDistributionPoints }}]
{{- else }}
	"crlDistributionPoints": [{{ toJson .crlDistributionPoints }}]
{{- end }}
}
EOF

cat <<EOF >"$X509LeafTemplateData"
{
	"country": "${PKICountry}",
	"organization": "${PKIName}",
	"organizationalUnit": "${PKIOrganizationalUnit}",
	"issuingCertificateURL": ["https://${FQDN}${LISTENER}/intermediates.pem"],
	"crlDistributionPoints": ["https://${FQDN}${LISTENER}/crl"]
}
EOF

# Configure DB and DB settings
case "$DB_TYPE" in
badgerv2)
  # - BadgerDB (badgerv2) => Default DB backend of step-ca
  # - badgerFileLoadingMode: FileIO (instead of MemoryMap) for LXC with low RAM
  # - NOT appropriate for load balancing, high availability deployments
  # - Works with 'step-badger'
  jq '.db.type = "badgerv2"' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq --arg a "$(step path)/db" '.db.dataSource = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq '.db.badgerFileLoadingMode = "FileIO"' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  ;;
mysql)
  # - MySQL => as a simple key-value store, not as a relational database
  # - Appropriate for load balancing, high availability deployments
  # - Works with 'LabCA'
  jq '.db.type = "mysql"' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq --arg a "${MARIADB_DB_USER}:${MARIADB_DB_PASS}@tcp(127.0.0.1:3306)/" '.db.dataSource = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq --arg a "${MARIADB_DB_NAME}" '.db.database = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  ;;
postgresql)
  # - PostgreSQL => as a simple key-value store, not as a relational database
  # - Appropriate for load balancing, high availability deployments
  # - Works with 'Step CA Admin'
  jq '.db.type = "postgresql"' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq --arg a "postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/" '.db.dataSource = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  jq --arg a "$PG_DB_NAME" '.db.database = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
  ;;
esac

# Configure Remote Provisioner Management
jq '.authority.enableAdmin = true' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"

# Configure CRL settings
jq --arg a "${PKICountry}" '.country = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
jq --arg a "${PKIName}" '.organization = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
jq --arg a "${PKIOrganizationalUnit}" '.organizationalUnit = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
jq --arg a "${PKIName} Online CA" '.commonName = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
jq '.crl.enabled = true' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
jq '.crl.generateOnRevoke = true' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
jq '.crl.cacheDuration = "24h0m0s"' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
jq '.crl.renewPeriod = "16h0m0s"' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
jq --arg a "https://${FQDN}${LISTENER}/crl" '.crl.idpURL = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"
jq --arg a "$LISTENER_INSECURE" '.insecureAddress = $a' "${CAConfig}" > "${CAConfig}_tmp" && mv "${CAConfig}_tmp" "${CAConfig}"

# Generate Root CA Certificate and Key
# - Validity: 219168h (~25 Years)
# - maxPathLen: 1 (Root -> Intermediate -> Leaf) => Only one Intermediate CA allowed below Root CA
# - Active revocation on Intermediate CA and Leaf Certificates by the usage of build-in Certificate Revocation List (CRL)
FLAGS=(--force
  --template="${CARootTemplate}"
  --not-after="219168h"
  --password-file="${PwdFile}"
  --set country="${PKICountry}"
  --set organization="${PKIName}"
  --set organizationalUnit="${PKIOrganizationalUnit}"
  --set issuingCertificateURL="https://${FQDN}${LISTENER}/roots.pem"
  --set crlDistributionPoints="https://${FQDN}${LISTENER}/crl")

$STD step certificate create "${PKIName} Root CA" \
  "$(step path)/certs/root_ca.crt" \
  "$(step path)/secrets/root_ca_key" \
  "${FLAGS[@]}"

# Generate Intermediate CA Certificate Bundle and Key
# - Validity: 175368h (~20 Years)
# - maxPathLen: 0 (Root -> Intermediate -> Leaf) => Intermediate CA is only allowed to issue Leaf Certificates
# - Active revocation on Leaf Certificates by the usage of build-in Certificate Revocation List (CRL)
# - Bundle: Certificate Chain (including Root CA Certificate)
FLAGS=(--force
  --template="${CAIntermediateTemplate}"
  --ca="$(step path)/certs/root_ca.crt"
  --ca-key="$(step path)/secrets/root_ca_key"
  --not-after="175368h"
  --ca-password-file="${PwdFile}"
  --password-file="${PwdFile}"
  --bundle
  --set country="${PKICountry}"
  --set organization="${PKIName}"
  --set organizationalUnit="${PKIOrganizationalUnit}"
  --set issuingCertificateURL="https://${FQDN}${LISTENER}/roots.pem"
  --set crlDistributionPoints="https://${FQDN}${LISTENER}/crl")

$STD step certificate create "${PKIName} Intermediate CA" \
  "$(step path)/certs/intermediate_ca.crt" \
  "$(step path)/secrets/intermediate_ca_key" \
  "${FLAGS[@]}"

# Install Root CA Certificate to System Trust Store
$STD step certificate install --all "$(step path)/certs/root_ca.crt"
$STD update-ca-certificates

chown -R step:step "$(step path)"
chmod -R 700 "$(step path)"
msg_ok "Initialized step-ca"

msg_info "Start step-ca as a Daemon"

# https://smallstep.com/docs/step-ca/certificate-authority-server-production/#running-step-ca-as-a-daemon
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
#$STD systemctl enable -q --now step-ca
#sleep 5
msg_ok "Started step-ca as a Daemon"
#
#msg_info "Configuring step-ca Admins and Provisioners"
#
## Configure CA Super-Admin, Admins and Provisioners settings
#AdminDir="$(step path)/admins"
#AdminCert="$AdminDir/admin.crt"
#AdminKey="$AdminDir/admin.key"
#mkdir -p "$AdminDir"
#
#$STD step ca certificate step \
#  "$AdminCert" \
#  "$AdminKey" \
#  --provisioner="Admin JWK" \
#  --provisioner-password-file="$ProvisionerPwdFile"
#
#$STD step ca provisioner add "$PKIProvisioner" \
#  --type JWK \
#  --admin-name="$PKIProvisioner" \
#  --create \
#  --password-file="$ProvisionerPwdFile" \
#  --admin-cert="$AdminCert" \
#  --admin-key="$AdminKey"
#
#$STD step ca provisioner add "$AcmeProvisioner" \
#  --type ACME \
#  --admin-name "$AcmeProvisioner" \
#  --admin-cert="$AdminCert" \
#  --admin-key="$AdminKey"
#
#$STD step ca provisioner update "$PKIProvisioner" \
#  --x509-min-dur="$X509MinDur" \
#  --x509-max-dur="$X509MaxDur" \
#  --x509-default-dur="$X509DefaultDur" \
#  --x509-template="$X509LeafTemplate" \
#  --x509-template-data="$X509LeafTemplateData" \
#  --allow-renewal-after-expiry \
#  --admin-cert="$AdminCert" \
#  --admin-key="$AdminKey"
#
#$STD step ca provisioner update "$AcmeProvisioner" \
#  --x509-min-dur="$X509MinDur" \
#  --x509-max-dur="$X509MaxDur" \
#  --x509-default-dur="$X509DefaultDur" \
#  --x509-template="$X509LeafTemplate" \
#  --x509-template-data="$X509LeafTemplateData" \
#  --allow-renewal-after-expiry \
#  --admin-cert="$AdminCert" \
#  --admin-key="$AdminKey"
#
chown -R step:step "$(step path)"
chmod -R 700 "$(step path)"
msg_ok "Configured step-ca Admins and Provisioners"

# Configure DB Frontend
case "$DB_TYPE" in
badgerv2)
  fetch_and_deploy_gh_release "step-badger" "lukasz-lobocki/step-badger" "prebuild" "latest" "/opt/step-badger" "step-badger_Linux_x86_64.tar.gz"
  ln -s /opt/step-badger/step-badger /usr/local/bin/step-badger
  ;;
mysql)
  fetch_and_deploy_gh_release "labca-gui" "hakwerk/labca" "binary"
  
  mkdir -p /etc/labca
  cat <<EOF >/etc/labca/config.json
{
    "standalone": true
}
EOF

  msg_info "Creating LabCA GUI Service"
  cat <<EOF >/etc/systemd/system/labca.service
[Unit]
Description=LabCA GUI Service
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=30
StartLimitBurst=3

[Service]
Type=simple
ExecStart=/usr/bin/labca-gui --init -config /etc/labca/config.json -port 3000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now labca
  msg_ok "Created LabCA GUI Service"
  ;;
postgresql)
  msg_warn "tbd"
  ;;
esac

motd_ssh
customize
cleanup_lxc
