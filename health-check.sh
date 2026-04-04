#!/bin/bash
set -e

ok() { echo "[OK]   $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*"; }

# Pi-hole FTL
if systemctl is-active --quiet pihole-FTL; then
  ok "Pi-hole FTL is running"
else
  fail "Pi-hole FTL is NOT running"
fi

# Pi-hole DNS
if dig @127.0.0.1 google.com +short >/dev/null 2>&1; then
  ok "Pi-hole DNS resolving external domains"
else
  fail "Pi-hole DNS not resolving external domains"
fi

# Unbound service
if systemctl is-active --quiet unbound; then
  ok "Unbound is running"
else
  fail "Unbound is NOT running"
fi

# Unbound recursion
if dig @127.0.0.1 -p 5335 com. NS +dnssec +short >/dev/null 2>&1; then
  ok "Unbound recursive queries working"
else
  fail "Unbound recursion failed"
fi

# Pi-hole DHCP
if grep -q "DHCP_ACTIVE=true" /etc/pihole/setupVars.conf 2>/dev/null; then
  ok "Pi-hole DHCP appears enabled"
else
  warn "Pi-hole DHCP not enabled (or not detected)"
fi

# NetAlertX service
if systemctl is-active --quiet netalertx; then
  ok "NetAlertX service is running"
else
  fail "NetAlertX service is NOT running"
fi

# NetAlertX HTTP
if curl -sSf http://127.0.0.1:20211 >/dev/null 2>&1; then
  ok "NetAlertX web interface reachable"
else
  warn "NetAlertX web interface not reachable on http://127.0.0.1:20211"
fi

# Root hints freshness
if [ -f /var/lib/unbound/root.hints ]; then
  age_days=$(( ( $(date +%s) - $(stat -c %Y /var/lib/unbound/root.hints) ) / 86400 ))
  if [ "$age_days" -le 30 ]; then
    ok "Unbound root.hints is fresh (${age_days} days old)"
  else
    warn "Unbound root.hints is ${age_days} days old (consider refreshing)"
  fi
else
  warn "Unbound root.hints file missing"
fi

echo "Health check complete."