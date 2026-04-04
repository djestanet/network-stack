#!/bin/bash
set -e

REPO_ROOT="/srv/network-stack"
PKG_DIR="$REPO_ROOT/packages"
VENV_DIR="$REPO_ROOT/venv/netalertx"

mkdir -p "$PKG_DIR" "$VENV_DIR"

cd "$REPO_ROOT"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  echo "[$(timestamp)] $*"
}

# ---------- Unbound ----------

install_or_upgrade_unbound() {
  if dpkg -s unbound >/dev/null 2>&1; then
    log "Unbound detected, upgrading..."
    apt update
    apt install --only-upgrade -y unbound
  else
    log "Unbound not found, installing..."
    apt update
    apt install -y unbound
  fi

  mkdir -p /var/lib/unbound
  if [ ! -f /var/lib/unbound/root.hints ]; then
    wget -O /var/lib/unbound/root.hints https://www.internic.net/domain/named.root
  fi

  if [ ! -f /etc/unbound/unbound.conf.d/pi-hole.conf ]; then
    cat >/etc/unbound/unbound.conf.d/pi-hole.conf <<EOF
server:
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes

    root-hints: "/var/lib/unbound/root.hints"
    auto-trust-anchor-file: "/var/lib/unbound/root.key"

    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: yes

    prefetch: yes
    prefetch-key: yes
EOF
  fi

  systemctl restart unbound
}

sync_unbound_configs() {
  mkdir -p "$PKG_DIR/unbound/configs"
  cp -a /etc/unbound/unbound.conf.d/* "$PKG_DIR/unbound/configs/" 2>/dev/null || true
  git add "$PKG_DIR/unbound/configs" || true
  git commit -m "Unbound installed/updated on $(timestamp)" || true
}

# ---------- Pi-hole ----------

install_or_upgrade_pihole() {
  if command -v pihole >/dev/null 2>&1; then
    log "Pi-hole detected, upgrading..."
    pihole -up
  else
    log "Pi-hole not found, installing..."
    curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended
  fi

  # Force Pi-hole to use Unbound as upstream
  if grep -q "^PIHOLE_DNS_" /etc/pihole/setupVars.conf; then
    sed -i 's/^PIHOLE_DNS_/#PIHOLE_DNS_/g' /etc/pihole/setupVars.conf
  fi

  if ! grep -q "^PIHOLE_DNS_1=" /etc/pihole/setupVars.conf; then
    echo "PIHOLE_DNS_1=127.0.0.1#5335" >> /etc/pihole/setupVars.conf
  else
    sed -i 's/^PIHOLE_DNS_1=.*/PIHOLE_DNS_1=127.0.0.1#5335/' /etc/pihole/setupVars.conf
  fi

  # Disable Pi-hole DNSSEC (Unbound handles it)
  if grep -q "^DNSSEC=" /etc/pihole/setupVars.conf; then
    sed -i 's/^DNSSEC=.*/DNSSEC=false/' /etc/pihole/setupVars.conf
  else
    echo "DNSSEC=false" >> /etc/pihole/setupVars.conf
  fi

  pihole restartdns
}

sync_pihole_configs() {
  mkdir -p "$PKG_DIR/pihole/configs"
  cp -a /etc/pihole/* "$PKG_DIR/pihole/configs/" 2>/dev/null || true
  git add "$PKG_DIR/pihole/configs" || true
  git commit -m "Pi-hole installed/updated on $(timestamp)" || true
}

# ---------- NetAlertX (venv) ----------

install_or_upgrade_netalertx() {
  apt update
  apt install -y git python3 python3-venv nmap arp-scan sqlite3 curl

  if [ -d /opt/netalertx ]; then
    log "NetAlertX detected, upgrading..."
    cd /opt/netalertx
    git pull
  else
    log "NetAlertX not found, installing..."
    git clone https://github.com/jokob-sk/NetAlertX.git /opt/netalertx
    cd /opt/netalertx
  fi

  if [ ! -d "$VENV_DIR" ]; then
    log "Creating NetAlertX virtual environment at $VENV_DIR"
    python3 -m venv "$VENV_DIR"
  fi

  # shellcheck disable=SC1090
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip
  pip install -r requirements.txt
  deactivate

  mkdir -p /etc/netalertx
  if [ ! -f /etc/netalertx/config.yaml ]; then
    cp config/config.yaml /etc/netalertx/config.yaml
  fi

  cat >/etc/systemd/system/netalertx.service <<EOF
[Unit]
Description=NetAlertX Network Monitor
After=network.target

[Service]
WorkingDirectory=/opt/netalertx
ExecStart=$VENV_DIR/bin/python /opt/netalertx/netalertx.py --config /etc/netalertx/config.yaml
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now netalertx
}

sync_netalertx_configs() {
  mkdir -p "$PKG_DIR/netalertx/configs"
  if [ -f /etc/netalertx/config.yaml ]; then
    cp /etc/netalertx/config.yaml "$PKG_DIR/netalertx/configs/config.yaml"
    git add "$PKG_DIR/netalertx/configs/config.yaml" || true
    git commit -m "NetAlertX installed/updated on $(timestamp)" || true
  fi
}

# ---------- Run in correct order ----------

install_or_upgrade_unbound
install_or_upgrade_pihole
install_or_upgrade_netalertx

sync_unbound_configs
sync_pihole_configs
sync_netalertx_configs

log "Install/upgrade complete."