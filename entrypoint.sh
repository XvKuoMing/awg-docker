#!/usr/bin/env bash
set -euo pipefail

AWG_INTERFACE="${AWG_INTERFACE:-wg0}"
AWG_CONFIG="/etc/amnezia/amneziawg/${AWG_INTERFACE}.conf"

# ── Sanity checks ───────────────────────────────────────────────────────────
if [ ! -f "$AWG_CONFIG" ]; then
    echo "ERROR: Config not found at $AWG_CONFIG"
    echo "Mount your config: -v /path/to/wg0.conf:/etc/amnezia/wg0.conf"
    exit 1
fi

if [ ! -e /dev/net/tun ]; then
    echo "Creating /dev/net/tun …"
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
fi

# ── Bring up VPN ────────────────────────────────────────────────────────────
echo "Starting AmneziaWG interface ${AWG_INTERFACE} …"
awg-quick up "$AWG_INTERFACE"

echo "Interface ${AWG_INTERFACE} is up."
awg show "$AWG_INTERFACE"

# ── Handle shutdown gracefully ──────────────────────────────────────────────
shutdown() {
    echo "Shutting down ${AWG_INTERFACE} …"
    awg-quick down "$AWG_INTERFACE" 2>/dev/null || true
    exit 0
}
trap shutdown SIGTERM SIGINT SIGQUIT

# ── Keep container alive & periodically show status ─────────────────────────
while true; do
    sleep 300 &
    wait $!
done
