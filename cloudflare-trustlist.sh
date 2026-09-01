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
    echo "ERROR: This script must be run as root."
    echo "Run:"
    echo "  sudo $0"
    exit 1
fi

# ------------------------------------------------------------
# Dependency checks
# ------------------------------------------------------------

if ! command -v nginx >/dev/null 2>&1; then
    echo "ERROR: nginx is not installed."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl is not installed."
    echo "Install it with your package manager first."
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    echo "ERROR: systemd/systemctl is required."
    exit 1
fi

# ------------------------------------------------------------
# Create Nginx config directory if necessary
# ------------------------------------------------------------

mkdir -p /etc/nginx/conf.d

# ------------------------------------------------------------
# Create Cloudflare update script
# ------------------------------------------------------------

echo "Creating $SCRIPT ..."

cat > "$SCRIPT" <<'SCRIPT_EOF'
#!/bin/bash

set -euo pipefail

CF_CONF="/etc/nginx/conf.d/cloudflare-realip.conf"
TMP_CONF="/etc/nginx/conf.d/cloudflare-realip.conf.tmp"

CF_IPV4_URL="https://www.cloudflare.com/ips-v4"
CF_IPV6_URL="https://www.cloudflare.com/ips-v6"

# ------------------------------------------------------------
# Temporary configuration
# ------------------------------------------------------------

echo "# Generated automatically - DO NOT EDIT" > "$TMP_CONF"
echo "# Generated at $(date -u)" >> "$TMP_CONF"
echo "" >> "$TMP_CONF"

# ------------------------------------------------------------
# Cloudflare IPv4 ranges
# ------------------------------------------------------------

echo "# Cloudflare IPv4 ranges" >> "$TMP_CONF"

curl -fsSL "$CF_IPV4_URL" | while read -r ip
do
    [[ -z "$ip" ]] && continue
    echo "set_real_ip_from $ip;" >> "$TMP_CONF"
done

# ------------------------------------------------------------
# Cloudflare IPv6 ranges
# ------------------------------------------------------------

echo "" >> "$TMP_CONF"
echo "# Cloudflare IPv6 ranges" >> "$TMP_CONF"

curl -fsSL "$CF_IPV6_URL" | while read -r ip
do
    [[ -z "$ip" ]] && continue
    echo "set_real_ip_from $ip;" >> "$TMP_CONF"
done

# ------------------------------------------------------------
# Nginx Real IP configuration
# ------------------------------------------------------------

cat >> "$TMP_CONF" <<EOF

# Trust Cloudflare's CF-Connecting-IP header
real_ip_header CF-Connecting-IP;
real_ip_recursive on;

EOF

# ------------------------------------------------------------
# Validate before replacing active configuration
# ------------------------------------------------------------

echo "Validating Nginx configuration..."

if nginx -t >/dev/null 2>&1
then
    mv "$TMP_CONF" "$CF_CONF"

    echo "Cloudflare IP list updated successfully."
    echo "Reloading Nginx..."

    nginx -t
    systemctl reload nginx

    echo "Nginx reloaded successfully."
else
    echo "ERROR: nginx validation failed."
    echo "The existing Cloudflare configuration was NOT replaced."

    rm -f "$TMP_CONF"

    exit 1
fi
SCRIPT_EOF

chmod 755 "$SCRIPT"

# ------------------------------------------------------------
# Create systemd service
# ------------------------------------------------------------

echo "Creating $SERVICE ..."

cat > "$SERVICE" <<EOF
[Unit]
Description=Update Cloudflare IP ranges for Nginx Real IP
Wants=network-online.target
After=network-online.target
Before=nginx.service

[Service]
Type=oneshot
ExecStart=$SCRIPT
EOF

chmod 644 "$SERVICE"

# ------------------------------------------------------------
# Create systemd timer
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Reload systemd
# ------------------------------------------------------------

echo "Reloading systemd..."

systemctl daemon-reload

# ------------------------------------------------------------
# Run update immediately
# ------------------------------------------------------------

echo "Updating Cloudflare IP ranges now..."

if ! systemctl start cloudflare-realip-update.service; then
    echo
    echo "ERROR: Cloudflare IP update failed."
    echo "Check:"
    echo "  journalctl -u cloudflare-realip-update.service"
    exit 1
fi

# ------------------------------------------------------------
# Enable and start timer
# ------------------------------------------------------------

echo "Enabling Cloudflare update timer..."

systemctl enable --now cloudflare-realip-update.timer

# ------------------------------------------------------------
# Final validation
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Cloudflare Nginx Real IP setup completed successfully"
echo "============================================================"
echo

echo "Generated files:"
echo "  $SCRIPT"
echo "  $SERVICE"
echo "  $TIMER"
echo "  $CF_CONF"

echo
echo "Timer status:"
systemctl status cloudflare-realip-update.timer --no-pager

echo
echo "Next scheduled run:"
systemctl list-timers cloudflare-realip-update.timer --no-pager

echo
echo "Cloudflare configuration:"
cat "$CF_CONF"

echo
echo "Nginx configuration test:"
nginx -t

echo
echo "Done."

