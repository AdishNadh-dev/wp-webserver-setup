#!/bin/bash

set -euo pipefail

# ============================================================
# Cloudflare Trusted IP / Nginx Real IP Setup
# ============================================================

SCRIPT="/usr/local/sbin/update-cloudflare-nginx-realip.sh"
SERVICE="/etc/systemd/system/cloudflare-realip-update.service"
TIMER="/etc/systemd/system/cloudflare-realip-update.timer"
CF_CONF="/etc/nginx/conf.d/cloudflare-realip.conf"

CF_IPV4_URL="https://www.cloudflare.com/ips-v4"
CF_IPV6_URL="https://www.cloudflare.com/ips-v6"

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run this script as root."
    echo "Example: sudo $0"
    exit 1
fi

# ------------------------------------------------------------
# Dependency checks
# ------------------------------------------------------------

for cmd in nginx curl systemctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: $cmd is required."
        exit 1
    fi
done

mkdir -p /etc/nginx/conf.d

# ============================================================
# Cloudflare IP update script
# ============================================================

echo "Creating $SCRIPT ..."

cat > "$SCRIPT" <<'EOF'
#!/bin/bash

set -euo pipefail

CF_CONF="/etc/nginx/conf.d/cloudflare-realip.conf"
TMP_CONF="${CF_CONF}.tmp"
BACKUP_CONF="${CF_CONF}.bak"

CF_IPV4_URL="https://www.cloudflare.com/ips-v4"
CF_IPV6_URL="https://www.cloudflare.com/ips-v6"

# ------------------------------------------------------------
# Download Cloudflare IP ranges
# ------------------------------------------------------------

{
    echo "# Generated automatically - DO NOT EDIT"
    echo "# Generated at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo

    echo "# Cloudflare IPv4 ranges"
    curl -fsSL "$CF_IPV4_URL" |
        while read -r ip; do
            [[ -n "$ip" ]] && echo "set_real_ip_from $ip;"
        done

    echo
    echo "# Cloudflare IPv6 ranges"
    curl -fsSL "$CF_IPV6_URL" |
        while read -r ip; do
            [[ -n "$ip" ]] && echo "set_real_ip_from $ip;"
        done

    echo
    echo "real_ip_header CF-Connecting-IP;"
    echo "real_ip_recursive on;"
} > "$TMP_CONF"

# ------------------------------------------------------------
# Validate generated configuration
# ------------------------------------------------------------

cp -a "$CF_CONF" "$BACKUP_CONF" 2>/dev/null || true
mv "$TMP_CONF" "$CF_CONF"

if nginx -t >/dev/null 2>&1; then
    rm -f "$BACKUP_CONF"
    systemctl reload nginx
    echo "Cloudflare IP ranges updated successfully."
else
    echo "ERROR: Nginx configuration test failed."
    echo "Restoring previous configuration."

    if [[ -f "$BACKUP_CONF" ]]; then
        mv "$BACKUP_CONF" "$CF_CONF"
    else
        rm -f "$CF_CONF"
    fi

    rm -f "$TMP_CONF"
    exit 1
fi
EOF

chmod 755 "$SCRIPT"

# ============================================================
# systemd service
# ============================================================

echo "Creating $SERVICE ..."

cat > "$SERVICE" <<EOF
[Unit]
Description=Update Cloudflare IP ranges for Nginx

[Service]
Type=oneshot
ExecStart=$SCRIPT
EOF

chmod 644 "$SERVICE"

# ============================================================
# systemd timer
# ============================================================

echo "Creating $TIMER ..."

cat > "$TIMER" <<EOF
[Unit]
Description=Daily Cloudflare IP update

[Timer]
OnBootSec=10min
OnUnitActiveSec=24h
Persistent=true

[Install]
WantedBy=timers.target
EOF

chmod 644 "$TIMER"

# ============================================================
# Enable service/timer
# ============================================================

echo "Reloading systemd..."

systemctl daemon-reload

echo "Running Cloudflare update..."

systemctl start cloudflare-realip-update.service

echo "Enabling Cloudflare update timer..."

systemctl enable --now cloudflare-realip-update.timer

# ============================================================
# Final validation
# ============================================================

echo
echo "============================================================"
echo "Cloudflare Nginx Real IP setup completed"
echo "============================================================"
echo

echo "Files:"
echo "  $SCRIPT"
echo "  $SERVICE"
echo "  $TIMER"
echo "  $CF_CONF"

echo
echo "Timer:"
systemctl status cloudflare-realip-update.timer --no-pager

echo
echo "Nginx:"
nginx -t
