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
export STEPHOME=$STEPHOME

sed  -i '1i export STEPPATH=/etc/step-ca' /etc/profile
sed  -i '1i export STEPHOME=/etc/step' /etc/profile

mkdir -p "$STEPHOME"

# Patch for making $STD happy (/usr/bin/step is a symlink to /usr/bin/step-cli)
STEPBIN="$(which step)"
rm -f "$STEPBIN"
cp -f "$(which step-cli)" "$STEPBIN"

setcap CAP_NET_BIND_SERVICE=+eip "$(which step-ca)"

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

msg_info "Initializing step-ca"
DeploymentType="standalone"
FQDN="$(hostname -f)"
IP="${LOCAL_IP}"
LISTENER=":443"

EncryptionPwdDir="$(step path)/encryption"
PwdFile="$EncryptionPwdDir/ca.pwd"
ProvisionerPwdFile="$EncryptionPwdDir/provisioner.pwd"
mkdir -p "$EncryptionPwdDir"
gpg -q --gen-random --armor 2 32 >"$PwdFile"
gpg -q --gen-random --armor 2 32 >"$ProvisionerPwdFile"

$STD step ca init --deployment-type="$DeploymentType" --ssh --name="$PKIName" --dns="$FQDN" --dns="$IP" --address="$LISTENER" --provisioner="$PKIProvisioner" --password-file="$PwdFile" --provisioner-password-file="$ProvisionerPwdFile"

ln -s "$PwdFile" "$(step path)/password.txt"

mkdir -p "$(step path)/templates/ca"
mkdir -p "$(step path)/templates/x509"
CAIntermediateTemplate="$(step path)/templates/ca/intermediate_ca.tpl"
X509LeafTemplate="$(step path)/templates/x509/leaf.tpl"
X509LeafTemplateData="$(step path)/templates/x509/leaf_data.tpl"

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
		"maxPathLen": 1
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
	"issuingCertificateURL": {{ toJson .Insecure.User.issuingCertificateURL }},
{{- else }}
	"issuingCertificateURL": {{ toJson .issuingCertificateURL }},
{{- end }}
{{- if .Insecure.User.crlDistributionPoints }}
	"crlDistributionPoints": {{ toJson .Insecure.User.crlDistributionPoints }}
{{- else }}
	"crlDistributionPoints": {{ toJson .crlDistributionPoints }}
{{- end }}
}
EOF

cat <<EOF >"$X509LeafTemplateData"
{
	"country": "${PKICountry}",
	"organization": "${PKIName}",
	"organizationalUnit": "${PKIOrganizationalUnit}",
	"issuingCertificateURL": "https://${FQDN}${LISTENER}/1.0/intermediates.pem",
	"crlDistributionPoints": "https://${FQDN}${LISTENER}/1.0/crl"
}
EOF

$STD step ca provisioner add "$AcmeProvisioner" --type ACME --admin-name "$AcmeProvisioner"
$STD step ca provisioner update "$PKIProvisioner" --x509-min-dur="$X509MinDur" --x509-max-dur="$X509MaxDur" --x509-default-dur="$X509DefaultDur" --x509-template="$X509LeafTemplate" --allow-renewal-after-expiry
$STD step ca provisioner update "$AcmeProvisioner" --x509-min-dur="$X509MinDur" --x509-max-dur="$X509MaxDur" --x509-default-dur="$X509DefaultDur" --x509-template="$X509LeafTemplate" --x509-template-data="$X509LeafTemplateData" --allow-renewal-after-expiry
$STD step certificate install --all "$(step path)/certs/root_ca.crt"
$STD update-ca-certificates

chown -R step:step "$(step path)"
chmod -R 700 "$(step path)"
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

fetch_and_deploy_gh_release "step-badger" "lukasz-lobocki/step-badger" "prebuild" "latest" "/opt/step-badger" "step-badger_Linux_x86_64.tar.gz"
ln -s /opt/step-badger/step-badger /usr/local/bin/step-badger

motd_ssh
customize
cleanup_lxc
