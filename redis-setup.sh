#!/bin/bash

set -e

DOMAIN="$1"
WP_PATH="/var/www/$DOMAIN"
WP_CONFIG="$WP_PATH/wp-config.php"
PREFIX="${DOMAIN//./_}:"

if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 domain.com"
    exit 1
fi

if [ ! -f "$WP_CONFIG" ]; then
    echo "Error: $WP_CONFIG not found"
    exit 1
fi

echo "Installing Redis..."
apt-get update
apt-get install -y redis-server

systemctl enable --now redis-server

echo "Installing Redis Object Cache plugin..."

cd "$WP_PATH"

if command -v wp >/dev/null 2>&1; then
    wp plugin install redis-cache --activate --allow-root
else
    echo "Error: WP-CLI is not installed."
    exit 1
fi

echo "Adding Redis configuration..."

if ! grep -q "WP_REDIS_HOST" "$WP_CONFIG"; then
cat >> "$WP_CONFIG" <<EOF

/*--------------------------------------------
 * redis config
 * -------------------------------------------*/

define('WP_REDIS_HOST', '127.0.0.1');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_DATABASE', 0);
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);
define('WP_REDIS_RETRY_INTERVAL', 100);

/* for multiple sites */
define('WP_REDIS_PREFIX', '$PREFIX');
EOF
else
    echo "Redis configuration already exists. Skipping wp-config.php changes."
fi

echo "Enabling Redis object cache..."

wp redis enable --allow-root

echo "Done."
