#!/bin/bash
set -e

REPO_ROOT="/srv/network-stack"
PKG_DIR="$REPO_ROOT/packages"

cd "$REPO_ROOT"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

sync_if_changed() {
  local live="$1"
  local repo="$2"
  local label="$3"

  [ -f "$live" ] || return

  mkdir -p "$(dirname "$repo")"

  if [ ! -f "$repo" ] || ! diff -q "$live" "$repo" >/dev/null 2>&1; then
    cp "$live" "$repo"
    git add "$repo"
    git commit -m "$label updated on $(timestamp)" || true
    echo "$label: synced $live → $repo"
  fi
}

# Pi-hole
for f in /etc/pihole/*; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  sync_if_changed "$f" "$PKG_DIR/pihole/configs/$base" "Pi-hole config $base"
done

# Unbound
for f in /etc/unbound/unbound.conf.d/*; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  sync_if_changed "$f" "$PKG_DIR/unbound/configs/$base" "Unbound config $base"
done

# NetAlertX
if [ -f /etc/netalertx/config.yaml ]; then
  sync_if_changed "/etc/netalertx/config.yaml" \
                  "$PKG_DIR/netalertx/configs/config.yaml" \
                  "NetAlertX config"
fi

echo "Config sync complete."