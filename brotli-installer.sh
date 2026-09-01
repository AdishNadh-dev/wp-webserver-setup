#!/bin/bash

set -e

# ============================================================
# NGINX BROTLI CONFIGURATION
# ============================================================

echo "================================================"
echo "Installing and configuring Brotli for Nginx"
echo "================================================"

# ------------------------------------------------------------
# ROOT CHECK
# ------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root or with sudo."
    exit 1
fi

# ------------------------------------------------------------
# INSTALL BROTLI MODULES
# ------------------------------------------------------------

echo
echo "[1/3] Installing Nginx Brotli modules..."

apt update

apt install -y \
    libnginx-mod-http-brotli-filter \
    libnginx-mod-http-brotli-static

# ------------------------------------------------------------
# CREATE BROTLI CONFIGURATION
# ------------------------------------------------------------

echo
echo "[2/3] Creating Brotli configuration..."

cat > /etc/nginx/conf.d/brotli.conf <<'EOF'
# --------------------------------------------------------
# Brotli compression
# --------------------------------------------------------

brotli on;
brotli_comp_level 5;
brotli_static on;

brotli_types
    text/plain
    text/css
    text/xml
    text/javascript
    application/javascript
    application/x-javascript
    application/json
    application/xml
    application/rss+xml
    application/atom+xml
    application/xhtml+xml
    application/wasm
    image/svg+xml;
EOF

# ------------------------------------------------------------
# TEST NGINX CONFIGURATION
# ------------------------------------------------------------

echo
echo "[3/3] Testing Nginx configuration..."

nginx -t

# ------------------------------------------------------------
# RELOAD NGINX
# ------------------------------------------------------------

echo
echo "Reloading Nginx..."

systemctl reload nginx

echo
echo "================================================"
echo "Brotli configuration completed successfully"
echo "================================================"
echo
echo "Configuration file:"
echo "  /etc/nginx/conf.d/brotli.conf"
echo

