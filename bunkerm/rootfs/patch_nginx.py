#!/usr/bin/env python3
"""
Patch the nginx site config to return a static JSON response for
/api/settings/activation-status.

This intercepts the endpoint *before* it reaches Next.js / agent-api,
so the ActivationBanner never fires regardless of whether agent-api has
finished starting, whether it can reach the internet, or whether it is
running at all.

The banner condition is: !activated && !instance_id
Returning {"activated":true,"instance_id":"BKMR-ha-local"} suppresses it.
"""

import sys

CONF   = "/etc/nginx/http.d/default.conf"
MARKER = "BKMR-ha-local"
INSERT = (
    '    location = /api/settings/activation-status {\n'
    '        add_header Content-Type "application/json";\n'
    '        return 200 \'{"activated":true,"instance_id":"BKMR-ha-local"}\';\n'
    '    }\n\n'
)
# Target the catch-all comment that exists in default-next.conf
TARGET = "    # --- Next.js catch-all"

try:
    with open(CONF) as f:
        content = f.read()

    if MARKER in content:
        print("[BunkerM] nginx activation-status override already in place")
        sys.exit(0)

    if TARGET in content:
        content = content.replace(TARGET, INSERT + TARGET, 1)
    elif "    location / {" in content:
        # Fallback: insert before the catch-all location block
        content = content.replace("    location / {", INSERT + "    location / {", 1)
    else:
        print("[BunkerM] Warning: nginx conf target not found — skipping activation patch")
        sys.exit(0)

    with open(CONF, "w") as f:
        f.write(content)

    print("[BunkerM] nginx activation-status override applied")

except Exception as e:
    print(f"[BunkerM] nginx patch error (non-fatal): {e}")
    sys.exit(0)  # Non-fatal: let init continue
