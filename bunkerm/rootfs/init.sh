#!/bin/sh
set -e

OPTIONS_FILE="/data/options.json"
MOSQUITTO_CONF="/etc/mosquitto/mosquitto.conf"

# ── Read HA options (if running under Supervisor) ─────────────────────────────
if [ -f "$OPTIONS_FILE" ]; then
    echo "[BunkerM] Reading options from Home Assistant..."
    MQTT_USERNAME=$(jq -r '.mqtt_username // "bunker"'       "$OPTIONS_FILE")
    MQTT_PASSWORD=$(jq -r '.mqtt_password // "bunker"'       "$OPTIONS_FILE")
    ADMIN_EMAIL=$(jq -r   '.admin_email    // "admin@bunker.local"' "$OPTIONS_FILE")
    ADMIN_PASSWORD=$(jq -r '.admin_password // "admin123"'   "$OPTIONS_FILE")
else
    echo "[BunkerM] No options.json — using environment defaults..."
    MQTT_USERNAME="${MQTT_USERNAME:-bunker}"
    MQTT_PASSWORD="${MQTT_PASSWORD:-bunker}"
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@bunker.local}"
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin123}"
fi

export MQTT_USERNAME MQTT_PASSWORD ADMIN_EMAIL ADMIN_PASSWORD

# ── Persist data in /data (HA mounts this as a volume) ────────────────────────
mkdir -p /data
if [ -d /nextjs/data ] && [ ! -L /nextjs/data ]; then
    # First run: copy any seed files then replace with symlink
    cp -a /nextjs/data/. /data/ 2>/dev/null || true
    rm -rf /nextjs/data
    ln -sf /data /nextjs/data
elif [ ! -e /nextjs/data ]; then
    ln -sf /data /nextjs/data
fi

# ── Switch Mosquitto from port 1900 → 1883 ────────────────────────────────────
if [ -f "$MOSQUITTO_CONF" ]; then
    # Replace the listener line for MQTT (not the 8080 HTTP one)
    sed -i 's/^listener 1900$/listener 1883/' "$MOSQUITTO_CONF"
fi

echo "[BunkerM] Starting..."
echo "[BunkerM]  Web UI  → http://<ha-ip>:2000  (login: $ADMIN_EMAIL)"
echo "[BunkerM]  MQTT    → <ha-ip>:1883          (user: $MQTT_USERNAME)"

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
