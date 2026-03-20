#!/bin/sh
set -e

OPTIONS_FILE="/data/options.json"
MOSQUITTO_CONF="/etc/mosquitto/mosquitto.conf"

# ── Read HA options ────────────────────────────────────────────────────────────
if [ -f "$OPTIONS_FILE" ]; then
    echo "[BunkerM] Reading options from Home Assistant..."
    MQTT_USERNAME=$(jq -r '.mqtt_username // "bunker"'              "$OPTIONS_FILE")
    MQTT_PASSWORD=$(jq -r '.mqtt_password // "bunker"'              "$OPTIONS_FILE")
    ADMIN_EMAIL=$(jq -r   '.admin_email    // "admin@bunker.local"' "$OPTIONS_FILE")
    ADMIN_PASSWORD=$(jq -r '.admin_password // "admin123"'          "$OPTIONS_FILE")
    BUNKERAI_API_KEY=$(jq -r '.bunkerai_api_key // ""'              "$OPTIONS_FILE")
else
    echo "[BunkerM] No options.json — using defaults..."
    MQTT_USERNAME="${MQTT_USERNAME:-bunker}"
    MQTT_PASSWORD="${MQTT_PASSWORD:-bunker}"
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@bunker.local}"
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin123}"
    BUNKERAI_API_KEY="${BUNKERAI_API_KEY:-}"
fi

export MQTT_USERNAME MQTT_PASSWORD ADMIN_EMAIL ADMIN_PASSWORD
export BUNKERAI_API_KEY
export BUNKERAI_WS_URL="${BUNKERAI_WS_URL:-wss://api.bunkerai.dev/connect}"
export BUNKERAI_CLOUD_URL="${BUNKERAI_CLOUD_URL:-https://api.bunkerai.dev}"

# ── API key bootstrap (same logic as Community start.sh) ───────────────────────
KEY_FILE="/data/.api_key"
DEFAULT_KEY="default_api_key_replace_in_production"

if [ -n "$API_KEY" ] && [ "$API_KEY" != "$DEFAULT_KEY" ]; then
    echo "$API_KEY" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    echo "[BunkerM] Using API key from environment variable."
elif [ -f "$KEY_FILE" ] && [ -s "$KEY_FILE" ]; then
    export API_KEY=$(cat "$KEY_FILE")
    echo "[BunkerM] Loaded existing API key from persistent storage."
else
    export API_KEY=$(openssl rand -hex 32)
    echo "$API_KEY" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    echo "[BunkerM] Generated new API key and saved to persistent storage."
fi

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


# ── Suppress ActivationBanner at nginx level ──────────────────────────────────
# Intercept /api/settings/activation-status in nginx and return a static
# {"activated":true} response, bypassing agent-api entirely.
# This is the most robust fix: works regardless of agent-api timing,
# network access, or port conflicts.
python3 /patch_nginx.py || true

echo "[BunkerM] Starting services..."
echo "[BunkerM]  Web UI  → http://<ha-ip>:2000  (login: $ADMIN_EMAIL)"
echo "[BunkerM]  MQTT    → <ha-ip>:1883  (user: $MQTT_USERNAME)"

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
