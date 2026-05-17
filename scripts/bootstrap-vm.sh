#!/bin/bash
# ============================================================
# Metl Platform — VM Bootstrap Script
# Run this ON EACH VM after creation
# ============================================================
set -euo pipefail

METL_VERSION="1.0.0"
LOG_FILE="/var/log/metl-bootstrap.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Metl Platform VM Bootstrap v$METL_VERSION ==="

# Detect VM role from Azure tags or hostname
HOSTNAME=$(hostname)
if [[ "$HOSTNAME" == *"app"* ]]; then
    VM_ROLE="app"
elif [[ "$HOSTNAME" == *"data"* ]]; then
    VM_ROLE="data"
elif [[ "$HOSTNAME" == *"ai"* ]]; then
    VM_ROLE="ai"
else
    log "WARNING: Could not detect VM role from hostname ($HOSTNAME)."
    log "Assuming app server. Set VM_ROLE env var if incorrect."
    VM_ROLE="${VM_ROLE:-app}"
fi

log "Detected VM role: $VM_ROLE"

# ============================================
# 1. System Update
# ============================================
log "=== Updating system packages ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y
apt-get install -y \
    curl wget git htop jq unzip \
    ca-certificates gnupg lsb-release \
    ufw fail2ban \
    unattended-upgrades \
    net-tools dnsutils iputils-ping

# ============================================
# 2. Install Docker
# ============================================
log "=== Installing Docker ==="
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker metladmin || true
    systemctl enable docker
    systemctl start docker
    log "Docker installed successfully"
else
    log "Docker already installed"
fi

# Install Docker Compose plugin
if ! docker compose version &> /dev/null; then
    DOCKER_CONFIG="${DOCKER_CONFIG:-$HOME/.docker}"
    mkdir -p "$DOCKER_CONFIG/cli-plugins"
    curl -SL "https://github.com/docker/compose/releases/download/v2.27.1/docker-compose-linux-x86_64" -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
    chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
    log "Docker Compose installed"
else
    log "Docker Compose already installed"
fi

# Create docker-compose symlink for backward compatibility
if [[ ! -f /usr/local/bin/docker-compose ]]; then
    ln -s "$(which docker)" /usr/local/bin/docker-compose 2>/dev/null || \
    ln -sf "$DOCKER_CONFIG/cli-plugins/docker-compose" /usr/local/bin/docker-compose 2>/dev/null || \
    echo '#!/bin/bash\ndocker compose "$@"' > /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
    log "docker-compose symlink created"
fi

# ============================================
# 3. System Hardening
# ============================================
log "=== Hardening system ==="

# Firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp

# App server gets additional ports
if [[ "$VM_ROLE" == "app" ]]; then
    ufw allow 8080/tcp  # Traefik dashboard (localhost-only in practice)
fi

ufw --force enable
log "UFW configured"

# SSH hardening
cat > /etc/ssh/sshd_config.d/metl-hardening.conf <<'SSHCONF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
SSHCONF

systemctl restart sshd
log "SSH hardened"

# Fail2ban
cat > /etc/fail2ban/jail.local <<'F2BCONF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
F2BCONF

systemctl enable fail2ban
systemctl restart fail2ban
log "Fail2ban configured"

# Automatic security updates
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'UPGRADES'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Verbose "false";
UPGRADES

dpkg-reconfigure -plow unattended-upgrades -f noninteractive || true
log "Auto-updates configured"

# ============================================
# 4. Create Metl Directory Structure
# ============================================
log "=== Creating Metl directories ==="
mkdir -p /opt/metl/{data,backups,logs,certs}
mkdir -p /opt/metl/metl-ops
chown -R metladmin:metladmin /opt/metl

# ============================================
# 5. Install Monitoring Tools (optional)
# ============================================
log "=== Installing monitoring tools ==="

# Node Exporter
if [[ "$VM_ROLE" == "app" || "$VM_ROLE" == "data" ]]; then
    NODE_EXPORTER_VERSION="1.8.1"
    if [[ ! -f /usr/local/bin/node_exporter ]]; then
        cd /tmp
        wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
        tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
        cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
        useradd --no-create-home --shell /bin/false node_exporter || true

        cat > /etc/systemd/system/node_exporter.service <<'SERVICE'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

        systemctl daemon-reload
        systemctl enable node_exporter
        systemctl start node_exporter
        log "Node Exporter installed"
    fi
fi

# ============================================
# 6. Docker Log Rotation
# ============================================
log "=== Configuring Docker log rotation ==="
cat > /etc/docker/daemon.json <<'DOCKERCONF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  },
  "live-restore": true,
  "storage-driver": "overlay2"
}
DOCKERCONF

systemctl restart docker
log "Docker configured"

# ============================================
# 7. VM-Specific Setup
# ============================================
if [[ "$VM_ROLE" == "data" ]]; then
    log "=== Data Server: Tuning PostgreSQL prerequisites ==="
    # Increase shared memory limits for PostgreSQL
    sysctl -w kernel.shmmax=17179869184 || true
    sysctl -w kernel.shmall=4194304 || true
    echo "kernel.shmmax=17179869184" >> /etc/sysctl.conf
    echo "kernel.shmall=4194304" >> /etc/sysctl.conf
    sysctl -p

    # Allow database connections from VNet subnet
    ufw allow from 10.0.1.0/24 to any port 5432
    ufw allow from 10.0.1.0/24 to any port 6379
    ufw allow from 10.0.1.0/24 to any port 4222
    ufw allow from 10.0.1.0/24 to any port 8222
    ufw allow from 10.0.1.0/24 to any port 9000
    ufw allow from 10.0.1.0/24 to any port 9090
    ufw allow from 10.0.1.0/24 to any port 3001
fi

if [[ "$VM_ROLE" == "app" ]]; then
    log "=== App Server: Creating Traefik directories ==="
    mkdir -p /opt/metl/metl-ops/traefik
    touch /opt/metl/metl-ops/traefik/acme.json
    chmod 600 /opt/metl/metl-ops/traefik/acme.json
fi

# ============================================
# 8. Summary
# ============================================
log "=== Bootstrap Complete ==="
log ""
log "VM Role:    $VM_ROLE"
log "Hostname:   $(hostname)"
log "Public IP:  $(curl -s ifconfig.me || echo 'N/A')"
log "Docker:     $(docker --version)"
log "Compose:    $(docker compose version)"
log ""
log "Next steps:"
log "  1. Copy your .env file to /opt/metl/metl-ops/.env"
log "  2. Copy docker-compose files to /opt/metl/metl-ops/"
log "  3. Run: docker compose up -d"
