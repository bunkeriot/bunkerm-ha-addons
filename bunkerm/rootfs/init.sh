#!/bin/sh
set -e

OPTIONS_FILE="/data/options.json"
MOSQUITTO_CONF="/etc/mosquitto/mosquitto.conf"

# ── Read HA options ────────────────────────────────────────────────────────────
if [ -f "$OPTIONS_FILE" ]; then
    echo "[BunkerM] Reading options from Home Assistant..."
    MQTT_USERNAME=$(jq -r '.mqtt_username // "bunker"'        "$OPTIONS_FILE")
    MQTT_PASSWORD=$(jq -r '.mqtt_password // "bunker"'        "$OPTIONS_FILE")
    ADMIN_EMAIL=$(jq -r   '.admin_email    // "admin@bunker.local"' "$OPTIONS_FILE")
    ADMIN_PASSWORD=$(jq -r '.admin_password // "admin123"'    "$OPTIONS_FILE")
else
    echo "[BunkerM] No options.json — using defaults..."
    MQTT_USERNAME="${MQTT_USERNAME:-bunker}"
    MQTT_PASSWORD="${MQTT_PASSWORD:-bunker}"
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@bunker.local}"
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin123}"
fi

export MQTT_USERNAME MQTT_PASSWORD ADMIN_EMAIL ADMIN_PASSWORD

# ── Link /data → /nextjs/data for persistence ─────────────────────────────────
if [ -d /nextjs/data ] && [ ! -L /nextjs/data ]; then
    cp -a /nextjs/data/. /data/ 2>/dev/null || true
    rm -rf /nextjs/data
fi
ln -sfn /data /nextjs/data

# ── Switch Mosquitto to port 1883 ─────────────────────────────────────────────
if [ -f "$MOSQUITTO_CONF" ]; then
    sed -i 's/^listener 1900$/listener 1883/' "$MOSQUITTO_CONF"
fi

# ── Tell all internal services to use port 1883 ───────────────────────────────
export MQTT_PORT=1883
export MOSQUITTO_PORT=1883

echo "[BunkerM] Starting services..."
echo "[BunkerM]  Web UI  → http://<ha-ip>:2000  (login: $ADMIN_EMAIL)"
echo "[BunkerM]  MQTT    → <ha-ip>:1883  (user: $MQTT_USERNAME)"

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
