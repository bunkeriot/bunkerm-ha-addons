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

# ── Silent BunkerAI Cloud registration ────────────────────────────────────────
# Run before supervisord so connector-agent finds the config on its first start.
# Skipped if bunkerai_config.json already exists (persisted across restarts).
INSTANCE_FILE="/data/instance_id"
ACTIVATION_FILE="/data/activation.json"
CONFIG_FILE="/data/bunkerai_config.json"
_CLOUD_URL="https://api.bunkerai.dev"

if [ ! -f "$CONFIG_FILE" ]; then
    # Get or create instance ID (same format as agent-api: BKMR-XXXXXXXX)
    if [ -f "$INSTANCE_FILE" ]; then
        _INSTANCE_ID=$(cat "$INSTANCE_FILE")
    else
        _INSTANCE_ID="BKMR-$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]')"
        echo "$_INSTANCE_ID" > "$INSTANCE_FILE"
        echo "[BunkerM] Generated instance ID: $_INSTANCE_ID"
    fi

    # Step 1: Get activation key (reuse stored one if available)
    _ACTIVATION_KEY=""
    if [ -f "$ACTIVATION_FILE" ]; then
        _ACTIVATION_KEY=$(jq -r '.key // ""' "$ACTIVATION_FILE" 2>/dev/null || true)
    fi

    if [ -z "$_ACTIVATION_KEY" ]; then
        echo "[BunkerM] Requesting BunkerAI activation key..."
        _ACTIVATE_PAYLOAD=$(jq -n --arg id "$_INSTANCE_ID" '{"instance_id":$id}')
        _ACTIVATE_RESP=$(curl -sf --max-time 8 -X POST "$_CLOUD_URL/activate" \
            -H "Content-Type: application/json" -d "$_ACTIVATE_PAYLOAD" 2>/dev/null || true)
        if [ -n "$_ACTIVATE_RESP" ]; then
            _ACTIVATION_KEY=$(echo "$_ACTIVATE_RESP" | jq -r '.key // ""' 2>/dev/null || true)
            if [ -n "$_ACTIVATION_KEY" ]; then
                echo "{\"key\":\"$_ACTIVATION_KEY\"}" > "$ACTIVATION_FILE"
                echo "[BunkerM] Activation successful."
            fi
        else
            echo "[BunkerM] BunkerAI activation unavailable — cloud features inactive until next restart."
        fi
    fi

    # Step 2: Register tenant and get cloud API key
    if [ -n "$_ACTIVATION_KEY" ]; then
        echo "[BunkerM] Registering with BunkerAI Cloud..."
        _REGISTER_PAYLOAD=$(jq -n \
            --arg key "$_ACTIVATION_KEY" \
            --arg id  "$_INSTANCE_ID"    \
            --arg email "$ADMIN_EMAIL"   \
            '{"activation_key":$key,"instance_id":$id,"email":$email}')
        _REGISTER_RESP=$(curl -sf --max-time 10 -X POST "$_CLOUD_URL/register" \
            -H "Content-Type: application/json" -d "$_REGISTER_PAYLOAD" 2>/dev/null || true)
        if [ -n "$_REGISTER_RESP" ]; then
            _CLOUD_API_KEY=$(echo "$_REGISTER_RESP" | jq -r '.api_key  // ""' 2>/dev/null || true)
            _TENANT_ID=$(    echo "$_REGISTER_RESP" | jq -r '.tenant_id // ""' 2>/dev/null || true)
            if [ -n "$_CLOUD_API_KEY" ]; then
                jq -n \
                    --arg cloud_url "$_CLOUD_URL"            \
                    --arg ws_url    "$BUNKERAI_WS_URL"       \
                    --arg api_key   "$_CLOUD_API_KEY"        \
                    --arg tenant_id "$_TENANT_ID"            \
                    '{"cloud_url":$cloud_url,"ws_url":$ws_url,"api_key":$api_key,"tenant_id":$tenant_id}' \
                    > "$CONFIG_FILE"
                chmod 600 "$CONFIG_FILE"
                echo "[BunkerM] BunkerAI Cloud connected (tenant: $_TENANT_ID)."
            else
                echo "[BunkerM] Cloud registration skipped (email may already be registered — connect manually via Settings)."
            fi
        else
            echo "[BunkerM] Cloud registration unavailable — will retry on next restart."
        fi
    fi
fi

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
