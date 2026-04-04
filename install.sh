#!/bin/bash
set -e

REPO_ROOT="/srv/network-stack"
PKG_DIR="$REPO_ROOT/packages"
DIFF_DIR="$REPO_ROOT/diffs"

mkdir -p "$PKG_DIR" "$DIFF_DIR"

cd "$REPO_ROOT"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  echo "[$(timestamp)] $*"
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
}

sync_pihole_configs() {
  mkdir -p "$PKG_DIR/pihole/configs"
  cp -a /etc/pihole/* "$PKG_DIR/pihole/configs/" 2>/dev/null || true
  git add "$PKG_DIR/pihole/configs" || true
  git commit -m "Pi-hole installed/updated on $(timestamp)" || true
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

  # Only create our pi-hole config if it doesn't exist
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

# ---------- NetAlertX ----------

install_or_upgrade_netalertx() {
  if [ -d /opt/netalertx ]; then
    log "NetAlertX detected, upgrading..."
    cd /opt/netalertx
    git pull
    pip3 install -r requirements.txt
  else
    log "NetAlertX not found, installing..."
    apt update
    apt install -y git python3 python3-pip nmap arp-scan sqlite3 curl
    git clone https://github.com/jokob-sk/NetAlertX.git /opt/netalertx
    cd /opt/netalertx
    pip3 install -r requirements.txt

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
ExecStart=/usr/bin/python3 /opt/netalertx/netalertx.py --config /etc/netalertx/config.yaml
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now netalertx
  fi

  systemctl restart netalertx
}

sync_netalertx_configs() {
  mkdir -p "$PKG_DIR/netalertx/configs"
  if [ -f /etc/netalertx/config.yaml ]; then
    cp /etc/netalertx/config.yaml "$PKG_DIR/netalertx/configs/config.yaml"
    git add "$PKG_DIR/netalertx/configs/config.yaml" || true
    git commit -m "NetAlertX installed/updated on $(timestamp)" || true
  fi
}

# ---------- Run ----------

install_or_upgrade_pihole
install_or_upgrade_unbound
install_or_upgrade_netalertx

sync_pihole_configs
sync_unbound_configs
sync_netalertx_configs

log "Install/upgrade complete."