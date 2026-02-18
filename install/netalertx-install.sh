#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/netalertx/NetAlertX

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y --no-install-recommends \
    nginx \
    sqlite3 \
    dnsutils \
    net-tools \
    mtr \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    iproute2 \
    nmap \
    fping \
    zip \
    usbutils \
    traceroute \
    nbtscan \
    avahi-daemon \
    avahi-utils \
    build-essential \
    git \
    curl \
    wget \
    arp-scan \
    perl \
    libwww-perl \
    apt-utils \
    cron \
    sudo \
    ca-certificates \
    tini \
    snmp \
    libcap2-bin \
    gettext-base \
    lsb-release \
    gnupg2 \
    debian-archive-keyring
msg_ok "Installed Dependencies"

PHP_VERSION="8.4" \
PHP_MODULE="cgi,fpm,sqlite3,curl,gd,mbstring,xml,intl,zip" \
setup_php

CLEAN_INSTALL=1 fetch_and_deploy_gh_release "netalertx" "netalertx/NetAlertX" "tarball" "latest" "/opt/netalertx"

msg_info "Creating Directory Structure"
INSTALL_DIR="/app"

# Ensure directory is empty
rm -rf ${INSTALL_DIR}
mkdir -p ${INSTALL_DIR}

# Copy tarball files to installation directory
cp -r /opt/netalertx/* ${INSTALL_DIR}/

# Create a /data symlink as a fail-safe for application hardcoded paths
if [ ! -e /data ]; then
  ln -sf ${INSTALL_DIR} /data
fi

# Remove symlink placeholders from the repository to ensure they become persistent directories
rm -rf ${INSTALL_DIR}/api ${INSTALL_DIR}/log ${INSTALL_DIR}/db ${INSTALL_DIR}/config

# Create persistent directories
mkdir -p ${INSTALL_DIR}/api ${INSTALL_DIR}/log ${INSTALL_DIR}/db ${INSTALL_DIR}/config
mkdir -p ${INSTALL_DIR}/log/plugins

# Create symlinks in /tmp as well for double fail-safe (some PHP modules use /tmp/api)
ln -sf ${INSTALL_DIR}/api /tmp/
ln -sf ${INSTALL_DIR}/log /tmp/

# Create buildtimestamp if it doesn't exist
if [ ! -f "${INSTALL_DIR}/front/buildtimestamp.txt" ]; then
  date +%s > "${INSTALL_DIR}/front/buildtimestamp.txt"
fi
msg_ok "Created Directory Structure"

msg_info "Installing Python Dependencies"
# Python venv creation
$STD python3 -m venv /opt/netalertx-env
# shellcheck disable=SC1091
source /opt/netalertx-env/bin/activate
$STD python -m pip install --upgrade pip
if [ -f "${INSTALL_DIR}/requirements.txt" ]; then
    $STD python -m pip install -r "${INSTALL_DIR}/requirements.txt"
fi
deactivate
# Create missing __init__.py files for Python package recognition
touch "${INSTALL_DIR}/front/__init__.py"
touch "${INSTALL_DIR}/front/plugins/__init__.py"
msg_ok "Installed Python Dependencies"

msg_info "Applying Security Capabilities"
# Dynamically find binary paths as they can vary between /usr/bin and /usr/sbin
BINARY_NMAP=$(command -v nmap)
BINARY_ARPSCAN=$(command -v arp-scan)
BINARY_NBTSCAN=$(command -v nbtscan)
BINARY_TRACEROUTE=$(command -v traceroute)
#BINARY_PYTHON=$(readlink -f /opt/netalertx-env/bin/python)

[[ -n "$BINARY_NMAP" ]] && setcap cap_net_raw,cap_net_admin+eip "$BINARY_NMAP" || true
[[ -n "$BINARY_ARPSCAN" ]] && setcap cap_net_raw,cap_net_admin+eip "$BINARY_ARPSCAN" || true
[[ -n "$BINARY_NBTSCAN" ]] && setcap cap_net_raw,cap_net_admin,cap_net_bind_service+eip "$BINARY_NBTSCAN" || true
[[ -n "$BINARY_TRACEROUTE" ]] && setcap cap_net_raw,cap_net_admin+eip "$BINARY_TRACEROUTE" || true
# Dropped setcap on python binary as it is a security risk. Sudoers is used instead.
msg_ok "Applied Security Capabilities"

msg_info "Configuring Sudoers"
# Configure sudoers for www-data (Needed for Init Checks & Tools)
# Build allowed commands list dynamically (filtering out empty detected paths)
SUDO_CMDS="/opt/netalertx-env/bin/python, /usr/bin/python3"
for cmd in "$BINARY_NMAP" "$BINARY_ARPSCAN" "$BINARY_NBTSCAN" "$BINARY_TRACEROUTE"; do
  if [[ -n "$cmd" ]]; then
    SUDO_CMDS="${SUDO_CMDS}, ${cmd}"
  fi
done

# Write to temp file for validation
cat > /etc/sudoers.d/netalertx.tmp <<EOF
www-data ALL=(ALL) NOPASSWD: ${SUDO_CMDS}
EOF

# Validate syntax with visudo
if visudo -cf /etc/sudoers.d/netalertx.tmp >/dev/null; then
  mv /etc/sudoers.d/netalertx.tmp /etc/sudoers.d/netalertx
  chmod 440 /etc/sudoers.d/netalertx
  msg_ok "Configured Sudoers"
else
  rm /etc/sudoers.d/netalertx.tmp
  msg_error "Sudoers syntax validation failed"
  # Don't exit, just warn, as app might still run partially
fi

msg_info "Setting up Database and Configuration"
# Copy starter database and config files
cp -u "${INSTALL_DIR}/back/app.conf" "${INSTALL_DIR}/config/app.conf"
cp -u "${INSTALL_DIR}/back/app.db" "${INSTALL_DIR}/db/app.db"

# Sync timezone from system
LXC_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC")
if [[ -n "$LXC_TZ" ]]; then
  msg_info "Syncing Timezone: $LXC_TZ"
  sed -i "s|TIMEZONE.*=.*|TIMEZONE = '$LXC_TZ'|g" "${INSTALL_DIR}/config/app.conf"
  # Also update PHP's fallbacks if necessary (NetAlertX uses the one from app.conf mostly)
fi
msg_ok "Database and Configuration Ready"

msg_info "Checking Hardware Vendor Database"
OUI_FILE="/usr/share/arp-scan/ieee-oui.txt"

if [ ! -f "$OUI_FILE" ]; then
  msg_info "Updating Hardware Vendor Database"
  if [ -f "${INSTALL_DIR}/back/update_vendors.sh" ]; then
    $STD "${INSTALL_DIR}/back/update_vendors.sh"
    msg_ok "Updated Hardware Vendor Database"
  else
    msg_warn "update_vendors.sh not found, skipping"
  fi
else
  msg_ok "Hardware Vendor Database Already Present"
fi

msg_info "Configuring NGINX"
# Set default port
PORT="${PORT:-20211}"

# Remove default NGINX site
if [ -L /etc/nginx/sites-enabled/default ]; then
  rm /etc/nginx/sites-enabled/default
elif [ -f /etc/nginx/sites-enabled/default ]; then
  mv /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default.bkp_netalertx
fi

# Create web directory and symbolic link
mkdir -p /var/www/html
ln -sf "${INSTALL_DIR}/front" /var/www/html/netalertx

# Copy and configure NGINX config
cp "${INSTALL_DIR}/install/proxmox/netalertx.conf" "${INSTALL_DIR}/config/netalertx.conf"

# Update port in NGINX config
sed -i "s/listen 20211;/listen ${PORT};/g" "${INSTALL_DIR}/config/netalertx.conf"

# Create symbolic link to NGINX configuration
ln -sf "${INSTALL_DIR}/config/netalertx.conf" /etc/nginx/conf.d/netalertx.conf

# Postpone PHP-FPM socket detection until after service start, or use a fallback.
# For now, we configure a default and assume the standard Debian 13/Ubuntu 24 location.
if [ -S "/run/php/php8.4-fpm.sock" ]; then
    sed -i "s|unix:/var/run/php/php-fpm.sock;|unix:/run/php/php8.4-fpm.sock;|g" /etc/nginx/conf.d/netalertx.conf
else
    # Fallback pattern for detection during startup if possible
    msg_warn "PHP-FPM socket not found at standard location, will rely on service startup"
fi
msg_ok "Configured NGINX"

msg_info "Setting up Directory Permission and Ownership"
# Set permissions FIRST so www-data can create files (Fixes Turn 499)
# NetAlertX needs write access to front/ for some features, and broad access to /app
chgrp -R www-data ${INSTALL_DIR}
chmod -R a+rwx ${INSTALL_DIR}
chown -R www-data:www-data "${INSTALL_DIR}/db/app.db" "${INSTALL_DIR}/log" "${INSTALL_DIR}/api"
chmod -R ug+rwX "${INSTALL_DIR}/log" "${INSTALL_DIR}/api"
# Create log and API files as www-data user
sudo -u www-data touch ${INSTALL_DIR}/log/{app.log,execution_queue.log,app_front.log,app.php_errors.log,stderr.log,stdout.log,db_is_locked.log}
sudo -u www-data touch ${INSTALL_DIR}/api/user_notifications.json
msg_ok "Setup Directory Permission and Ownership"

msg_info "Starting NGINX"
$STD systemctl enable nginx
$STD systemctl restart nginx
msg_ok "Started NGINX"

msg_info "Starting PHP-FPM"
$STD systemctl enable php8.4-fpm
$STD systemctl start php8.4-fpm
msg_ok "Started PHP-FPM"

msg_info "Configuring NetAlertX Service"

# Detect server IP
SERVER_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
if [ -z "${SERVER_IP}" ]; then
  SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi
if [ -z "${SERVER_IP}" ]; then
  SERVER_IP="127.0.0.1"
fi

# Create startup script
cat > "${INSTALL_DIR}/start.netalertx.sh" <<EOF
#!/usr/bin/env bash

# NetAlertX environment variables
export NETALERTX_CONFIG=${INSTALL_DIR}/config
export NETALERTX_LOG=${INSTALL_DIR}/log
export NETALERTX_DATA=${INSTALL_DIR}
export NETALERTX_API=${INSTALL_DIR}/api
export NETALERTX_TMP=${INSTALL_DIR}/tmp
export PORT=${PORT}
export PYTHONPATH=${INSTALL_DIR}

# Create symlinks in /tmp as well for double fail-safe (some PHP modules use /tmp/api)
ln -sf ${INSTALL_DIR}/api /tmp/
ln -sf ${INSTALL_DIR}/log /tmp/

# Ensure package structure exists (Self-healing)
touch ${INSTALL_DIR}/front/__init__.py
touch ${INSTALL_DIR}/front/plugins/__init__.py

# Activate the virtual python environment
source /opt/netalertx-env/bin/activate

# Dynamically get IP for banner
SERVER_IP=\$(hostname -I 2>/dev/null | awk '{print \$1}')
if [ -z "\${SERVER_IP}" ]; then SERVER_IP="127.0.0.1"; fi

echo -e "--------------------------------------------------------------------------"
echo -e "Starting NetAlertX - navigate to http://\${SERVER_IP}:\${PORT}"
echo -e "--------------------------------------------------------------------------"

# Start the NetAlertX python script
cd ${INSTALL_DIR}
python server/
EOF

chmod +x "${INSTALL_DIR}/start.netalertx.sh"

# Create systemd service
cat > /etc/systemd/system/netalertx.service <<EOF
[Unit]
Description=NetAlertX Service
After=network-online.target nginx.service
Wants=network-online.target

[Service]
Type=simple
User=www-data
Group=www-data
ExecStart=${INSTALL_DIR}/start.netalertx.sh
WorkingDirectory=${INSTALL_DIR}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

# Create runtime directory in tmpfs for systemd-managed volatile files
RuntimeDirectory=netalertx
RuntimeDirectoryMode=0750

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
$STD systemctl daemon-reload
$STD systemctl enable netalertx.service
$STD systemctl start netalertx.service

# Verify service is running
if systemctl is-active --quiet netalertx.service; then
  msg_ok "NetAlertX Service Started Successfully"
else
  msg_error "NetAlertX Service Failed to Start"
  systemctl status netalertx.service --no-pager -l
  exit 1
fi

motd_ssh
customize
cleanup_lxc
