# BunkerM Add-on Documentation

## Overview

BunkerM is an open-source MQTT broker management platform. It bundles Eclipse Mosquitto with a full web dashboard — client/ACL management, real-time monitoring, connection logs, and an AI-powered assistant (via BunkerAI Cloud).

## Installation

1. Add this repository to your Home Assistant Add-on Store:
   **Settings → Add-ons → Add-on Store → ⋮ → Repositories**
   Paste: `https://github.com/BunkerM/bunkerm-ha-addons`

2. Find **BunkerM** in the store and click **Install**.

3. Configure your credentials in the **Configuration** tab before starting.

4. Click **Start**.

## Configuration

| Option | Default | Description |
|---|---|---|
| `mqtt_username` | `bunker` | MQTT broker username |
| `mqtt_password` | `bunker` | MQTT broker password |
| `admin_email` | `admin@bunker.local` | BunkerM web UI login email |
| `admin_password` | `admin123` | BunkerM web UI login password |

**Change the defaults before starting for the first time.**

## Access

- **Web UI**: `http://<your-ha-ip>:2000`
- **MQTT Broker**: `<your-ha-ip>:1883`

## Connecting Home Assistant to BunkerM's MQTT broker

In Home Assistant go to **Settings → Devices & Services → Add Integration → MQTT** and enter:

- **Broker**: `localhost` (since add-on runs on the same host)
- **Port**: `1883`
- **Username**: your configured `mqtt_username`
- **Password**: your configured `mqtt_password`

## Support

- GitHub: https://github.com/BunkerM/bunkerm-ha-addons
- Issues: https://github.com/BunkerM/bunkerm-ha-addons/issues
