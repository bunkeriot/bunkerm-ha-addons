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

# ── Fast-fail cloud activation URL ────────────────────────────────────────────
# agent-api calls BUNKERAI_ACTIVATION_URL on startup (default: api.bunkerai.dev).
# If unreachable it hangs for 8 s, blocking uvicorn from accepting connections.
# The browser's first page load races that window → activation-status catches
# "connection refused" and returns {activated:false, instance_id:null} → banner.
#
# Fix: point the URL at a closed local port so httpx fails in <1 ms.
# We set it two ways to be certain agent-api sees it:
#   1. export  — supervisord inherits and passes to children
#   2. sed     — inject it directly into the agent-api environment= line
export BUNKERAI_ACTIVATION_URL="http://127.0.0.1:19876"

SUPERVISORD_CONF="/etc/supervisor/conf.d/supervisord.conf"
if [ -f "$SUPERVISORD_CONF" ]; then
    # Only patch if not already patched
    if ! grep -q "BUNKERAI_ACTIVATION_URL" "$SUPERVISORD_CONF"; then
        sed -i 's|PYTHONPATH="/app",API_KEY|PYTHONPATH="/app",BUNKERAI_ACTIVATION_URL="http://127.0.0.1:19876",API_KEY|' "$SUPERVISORD_CONF"
    fi
fi

echo "[BunkerM] Starting services..."
echo "[BunkerM]  Web UI  → http://<ha-ip>:2000  (login: $ADMIN_EMAIL)"
echo "[BunkerM]  MQTT    → <ha-ip>:1883  (user: $MQTT_USERNAME)"

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
