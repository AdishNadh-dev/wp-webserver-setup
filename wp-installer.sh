#!/bin/bash

set -e

# ============================================================
# WordPress Full Site Installer
#
# Installs:
#   - Nginx
#   - PHP 8.3
#   - MariaDB
#   - WordPress
#   - WP-CLI
#   - Nginx FastCGI cache
#   - Optional SSL with Certbot
#
# Usage:
#   sudo bash install-wordpress.sh
# ============================================================


# ============================================================
# ROOT CHECK
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root or with sudo."
    exit 1
fi


# ============================================================
# DOMAIN
# ============================================================

read -rp "Enter domain (example.com): " DOMAIN

# Remove protocol
DOMAIN="${DOMAIN#http://}"
DOMAIN="${DOMAIN#https://}"

# Remove www
DOMAIN="${DOMAIN#www.}"

# Remove trailing path
DOMAIN="${DOMAIN%%/*}"

# Remove trailing dot
DOMAIN="${DOMAIN%.}"

if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "Invalid domain: $DOMAIN"
    exit 1
fi

WWW_DOMAIN="www.${DOMAIN}"


# ============================================================
# WWW REDIRECT
# ============================================================

echo
echo "How should www/non-www work?"
echo

echo "1) No redirect"
echo "   example.com and www.example.com both work"
echo

echo "2) Redirect to www"
echo "   example.com -> www.example.com"
echo

echo "3) Redirect to non-www"
echo "   www.example.com -> example.com"
echo

while true; do

    read -rp "Choose [1-3]: " WWW_CHOICE

    case "$WWW_CHOICE" in

        1)
            WWW_MODE="none"
            break
            ;;

        2)
            WWW_MODE="www"
            break
            ;;

        3)
            WWW_MODE="non-www"
            break
            ;;

        *)
            echo "Please choose 1, 2, or 3."
            ;;

    esac

done


# ============================================================
# SITE INFORMATION
# ============================================================

WEB_ROOT="/var/www/${DOMAIN}"

NGINX_AVAILABLE="/etc/nginx/sites-available/${DOMAIN}"
NGINX_ENABLED="/etc/nginx/sites-enabled/${DOMAIN}"

PHP_VERSION="8.3"
PHP_SOCKET="/run/php/php${PHP_VERSION}-fpm.sock"

# Database names cannot contain dots
DB_PREFIX=$(echo "$DOMAIN" | cut -d'.' -f1 | tr '-' '_')

DB_NAME="${DB_PREFIX}_wordpress"
DB_USER="${DB_PREFIX}_user"

# Random database password
DB_PASS=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)

# WordPress admin information
echo
read -rp "WordPress admin username [admin]: " WP_ADMIN_USER

if [ -z "$WP_ADMIN_USER" ]; then
    WP_ADMIN_USER="admin"
fi

while true; do

    read -rsp "WordPress admin password: " WP_ADMIN_PASS
    echo

    if [ -z "$WP_ADMIN_PASS" ]; then
        echo "Password cannot be empty."
        continue
    fi

    read -rsp "Confirm WordPress admin password: " WP_ADMIN_PASS_CONFIRM
    echo

    if [ "$WP_ADMIN_PASS" != "$WP_ADMIN_PASS_CONFIRM" ]; then
        echo "Passwords do not match."
        continue
    fi

    break

done


read -rp "WordPress admin email: " WP_ADMIN_EMAIL

if [[ ! "$WP_ADMIN_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
    echo "Invalid email address."
    exit 1
fi


# ============================================================
# SUMMARY
# ============================================================

echo
echo "================================================"
echo "WordPress installation summary"
echo "================================================"
echo "Domain          : $DOMAIN"
echo "WWW domain      : $WWW_DOMAIN"
echo "WWW mode        : $WWW_MODE"
echo "Web root        : $WEB_ROOT"
echo "Database        : $DB_NAME"
echo "Database user   : $DB_USER"
echo "PHP version     : $PHP_VERSION"
echo "Admin username  : $WP_ADMIN_USER"
echo "Admin email     : $WP_ADMIN_EMAIL"
echo "================================================"
echo

read -rp "Continue with installation? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi


# ============================================================
# UPDATE SYSTEM
# ============================================================

echo
echo "[1/12] Updating system..."

apt update
apt upgrade -y


# ============================================================
# INSTALL REQUIRED PACKAGES
# ============================================================

echo
echo "[2/12] Installing required packages..."

apt install -y \
    curl \
    wget \
    gnupg2 \
    apt-transport-https \
    lsb-release \
    ca-certificates \
    openssl \
    nginx \
    mariadb-server \
    certbot \
    python3-certbot-nginx


# ============================================================
# PHP REPOSITORY
# ============================================================

echo
echo "[3/12] Configuring PHP repository..."

wget -q -O /etc/apt/trusted.gpg.d/php.gpg \
    https://packages.sury.org/php/apt.gpg

echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" \
    > /etc/apt/sources.list.d/php.list

apt update


# ============================================================
# PHP 8.3
# ============================================================

echo
echo "[4/12] Installing PHP ${PHP_VERSION}..."

apt install -y \
    php${PHP_VERSION}-fpm \
    php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-xmlrpc \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-imagick \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-opcache \
    php${PHP_VERSION}-soap \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-intl \
    php${PHP_VERSION}-bcmath


systemctl enable nginx
systemctl enable mariadb
systemctl enable "php${PHP_VERSION}-fpm"

systemctl start nginx
systemctl start mariadb
systemctl start "php${PHP_VERSION}-fpm"


# ============================================================
# DATABASE
# ============================================================

echo
echo "[5/12] Creating WordPress database..."

mariadb <<MYSQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost'
    IDENTIFIED BY '${DB_PASS}';

ALTER USER '${DB_USER}'@'localhost'
    IDENTIFIED BY '${DB_PASS}';

GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.*
    TO '${DB_USER}'@'localhost';

FLUSH PRIVILEGES;
MYSQL


# ============================================================
# WEB DIRECTORY
# ============================================================

echo
echo "[6/12] Creating WordPress directory..."

mkdir -p "$WEB_ROOT"

# Remove existing content only if directory is not empty
if [ -n "$(find "$WEB_ROOT" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then

    echo
    echo "WARNING:"
    echo "$WEB_ROOT is not empty."

    read -rp "Delete existing contents and continue? [y/N]: " DELETE_EXISTING

    if [[ "$DELETE_EXISTING" =~ ^[Yy]$ ]]; then

        rm -rf "${WEB_ROOT:?}/"*
        rm -rf "${WEB_ROOT:?}/".[!.]*
        rm -rf "${WEB_ROOT:?}/"..?*

    else

        echo "Installation cancelled."
        exit 1

    fi

fi


# ============================================================
# DOWNLOAD WORDPRESS
# ============================================================

echo
echo "[7/12] Downloading WordPress..."

cd "$WEB_ROOT"

wget -q https://wordpress.org/latest.tar.gz

tar xzf latest.tar.gz --strip-components=1

rm -f latest.tar.gz


# ============================================================
# WORDPRESS OWNERSHIP
#
# IMPORTANT:
# This must happen BEFORE WP-CLI creates wp-config.php.
# ============================================================

echo
echo "Setting WordPress ownership..."

chown -R www-data:www-data "$WEB_ROOT"


# ============================================================
# WP-CLI
# ============================================================

echo
echo "[8/12] Installing WP-CLI..."

if ! command -v wp >/dev/null 2>&1; then

    curl -fsSL \
        -o /tmp/wp-cli.phar \
        https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar

    chmod +x /tmp/wp-cli.phar

    mv /tmp/wp-cli.phar /usr/local/bin/wp

fi


# ============================================================
# WORDPRESS CONFIGURATION
# ============================================================

echo
echo "[9/12] Creating wp-config.php..."

cd "$WEB_ROOT"

sudo -u www-data wp config create \
    --dbname="$DB_NAME" \
    --dbuser="$DB_USER" \
    --dbpass="$DB_PASS" \
    --dbhost="localhost" \
    --dbcharset="utf8mb4" \
    --skip-check


# ============================================================
# NGINX CACHE
# ============================================================

echo
echo "[10/12] Configuring Nginx cache..."

mkdir -p /var/cache/nginx

chown -R www-data:www-data /var/cache/nginx
chmod -R 755 /var/cache/nginx


cat > /etc/nginx/nginx.conf <<'EOF'

user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Performance optimizations
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    types_hash_max_size 2048;
    
    # Connection optimizations
    keepalive_timeout 75s;
    keepalive_requests 1000;
    reset_timedout_connection on;
    
    # Buffer optimizations for 1GB RAM
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    client_max_body_size 64M;
    client_body_timeout 30s;
    client_header_timeout 30s;
    send_timeout 60s;
    
    # File cache optimization
    open_file_cache max=5000 inactive=30s;
    open_file_cache_valid 60s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;
    
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    # FastCGI cache config for 1GB RAM
    fastcgi_cache_path /var/cache/nginx levels=1:2 keys_zone=WORDPRESS:50m inactive=60m max_size=500m;
    fastcgi_cache_key "$scheme$request_method$host$request_uri";
    fastcgi_cache_use_stale error timeout invalid_header http_500 http_503;
    fastcgi_cache_methods GET HEAD;
    
    # For 2GB RAM, use:
    # fastcgi_cache_path /var/cache/nginx levels=1:2 keys_zone=WORDPRESS:100m inactive=60m max_size=1g;
    
    # For 4GB RAM, use:
    # fastcgi_cache_path /var/cache/nginx levels=1:2 keys_zone=WORDPRESS:200m inactive=60m max_size=2g;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=login:10m rate=2r/s;
    limit_req_zone $binary_remote_addr zone=general:10m rate=15r/s;
    
    # Enhanced Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 256;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types
        text/plain
        text/css
        application/json
        application/javascript
        text/xml
        application/xml
        application/xml+rss
        text/javascript
        application/atom+xml
        image/svg+xml
        application/x-font-ttf
        application/vnd.ms-fontobject
        font/opentype;
    
    # Cache bypass rules - Method
    map $request_method $skip_cache_method {
        default 0;
        POST 1;
    }
    
    # Cache bypass rules - URI
    map $request_uri $skip_cache_uri {
        default 0;
        "~*/wp-admin/" 1;
        "~*/wp-login.php" 1;
        "~*/wp-cron.php" 1;
        "~*preview=true" 1;
        "~*\?s=" 1;
    }
    
    # Cache bypass rules - Cookies
    map $http_cookie $skip_cache_cookie {
        default 0;
        "~*wordpress_logged_in" 1;
        "~*comment_author" 1;
        "~*woocommerce_items_in_cart" 1;
        "~*woocommerce_cart_hash" 1;
        "~*wp-postpass" 1;
        "~*PHPSESSID" 1;
    }
    
    # SSL optimization
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}

EOF


# ============================================================
# NGINX SITE CONFIGURATION
# ============================================================

echo
echo "[11/12] Creating Nginx configuration..."


# ------------------------------------------------------------
# FUNCTION: COMMON SITE CONFIG
# ------------------------------------------------------------

create_main_server()
{

cat <<EOF

server {
    listen 80;
    listen [::]:80;

    server_name \$SERVER_NAMES;

    root ${WEB_ROOT};
    index index.php index.html index.htm;


    # ========================================================
    # Security Headers
    # ========================================================

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;


    # ========================================================
    # Block Sensitive Files
    # ========================================================

    location ~* \.(htaccess|env|log|ini|sh|bak|sql|conf|git|svn|project|zip|tar|gz)$ {
        deny all;
        return 444;
    }


    # ========================================================
    # Block PHP in Uploads
    # ========================================================

    location ~* /(?:uploads|files)/.*\.php$ {
        deny all;
        return 444;
    }


    # ========================================================
    # Protect wp-config.php
    # ========================================================

    location ~ /wp-config\.php {
        deny all;
        return 444;
    }


    # ========================================================
    # Disable XML-RPC
    # ========================================================

    location = /xmlrpc.php {
        deny all;
        return 444;
    }


    # ========================================================
    # Block Hidden Files
    # ========================================================

    location ~ /\. {
        deny all;
        return 444;
    }


    # ========================================================
    # Static Files
    # ========================================================

    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|webp|avif|woff|woff2|ttf|eot|otf|mp4|mp3|pdf|wasm)$ {

        expires 30d;

        add_header Cache-Control "public, immutable, stale-while-revalidate=86400";
        add_header Vary "Accept-Encoding";

        access_log off;
        log_not_found off;

        tcp_nopush on;
        tcp_nodelay on;
        sendfile on;
    }


    # ========================================================
    # Let's Encrypt
    # ========================================================

    location ^~ /.well-known/acme-challenge/ {

        default_type "text/plain";

        root ${WEB_ROOT};

        allow all;
    }


    # ========================================================
    # Favicon
    # ========================================================

    location = /favicon.ico {

        expires max;

        access_log off;
        log_not_found off;

        add_header Cache-Control "public, immutable";
    }


    # ========================================================
    # Robots
    # ========================================================

    location = /robots.txt {

        expires 1d;

        access_log off;
        log_not_found off;

        add_header Cache-Control "public";
    }


    # ========================================================
    # WordPress Login
    # ========================================================

    location = /wp-login.php {

        limit_req zone=login burst=3 nodelay;

        include snippets/fastcgi-php.conf;

        fastcgi_pass unix:${PHP_SOCKET};

        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;

        include fastcgi_params;

        fastcgi_cache_bypass 1;
        fastcgi_no_cache 1;

        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header Expires "0" always;
    }


    # ========================================================
    # WordPress Admin
    # ========================================================

    location ~* /wp-admin/.*\.php$ {

        include snippets/fastcgi-php.conf;

        fastcgi_pass unix:${PHP_SOCKET};

        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;

        include fastcgi_params;

        fastcgi_cache_bypass 1;
        fastcgi_no_cache 1;

        fastcgi_buffering on;

        fastcgi_buffer_size 128k;

        fastcgi_buffers 4 256k;

        fastcgi_busy_buffers_size 256k;

        fastcgi_read_timeout 300;
    }


    # ========================================================
    # WordPress Permalinks
    # ========================================================

    location / {

        try_files \$uri \$uri/ /index.php?\$args;
    }


    # ========================================================
    # PHP
    # ========================================================

    location ~ \.php$ {

        include snippets/fastcgi-php.conf;

        fastcgi_pass unix:${PHP_SOCKET};

        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;

        include fastcgi_params;


        # ----------------------------------------------------
        # PHP Buffering
        # ----------------------------------------------------

        fastcgi_buffering on;

        fastcgi_buffer_size 128k;

        fastcgi_buffers 8 256k;

        fastcgi_busy_buffers_size 256k;

        fastcgi_temp_file_write_size 256k;

        fastcgi_read_timeout 300;

        fastcgi_send_timeout 300;

        fastcgi_connect_timeout 60;


        # ----------------------------------------------------
        # Cache Logic
        # ----------------------------------------------------

        set \$skip_cache 0;


        # POST requests
        if (\$request_method = POST) {
            set \$skip_cache 1;
        }


        # WordPress admin
        if (\$request_uri ~* "/wp-admin/") {
            set \$skip_cache 1;
        }


        # WordPress login
        if (\$request_uri ~* "/wp-login.php") {
            set \$skip_cache 1;
        }


        # WordPress cron
        if (\$request_uri ~* "/wp-cron.php") {
            set \$skip_cache 1;
        }


        # Preview
        if (\$request_uri ~* "preview=true") {
            set \$skip_cache 1;
        }


        # Search
        if (\$request_uri ~* "\?s=") {
            set \$skip_cache 1;
        }


        # Logged-in users
        if (\$http_cookie ~* "wordpress_logged_in") {
            set \$skip_cache 1;
        }


        # Comment author
        if (\$http_cookie ~* "comment_author") {
            set \$skip_cache 1;
        }


        # WooCommerce cart
        if (\$http_cookie ~* "woocommerce_items_in_cart") {
            set \$skip_cache 1;
        }


        if (\$http_cookie ~* "woocommerce_cart_hash") {
            set \$skip_cache 1;
        }


        # Password protected posts
        if (\$http_cookie ~* "wp-postpass") {
            set \$skip_cache 1;
        }


        # PHP sessions
        if (\$http_cookie ~* "PHPSESSID") {
            set \$skip_cache 1;
        }


        # ----------------------------------------------------
        # FastCGI Cache
        # ----------------------------------------------------

        fastcgi_cache_bypass \$skip_cache;

        fastcgi_no_cache \$skip_cache;

        fastcgi_cache WORDPRESS;

        fastcgi_cache_valid 200 301 302 60m;

        fastcgi_cache_valid 404 1m;

        fastcgi_cache_min_uses 1;

        fastcgi_cache_lock on;

        fastcgi_cache_lock_timeout 5s;

        fastcgi_cache_use_stale error timeout invalid_header http_500 http_503;

        add_header X-FastCGI-Cache \$upstream_cache_status;
    }
}

EOF

}


# ------------------------------------------------------------
# CREATE CONFIG BASED ON WWW MODE
# ------------------------------------------------------------

if [ "$WWW_MODE" = "www" ]; then

    SERVER_NAMES="$WWW_DOMAIN"

    cat > "$NGINX_AVAILABLE" <<EOF

# ============================================================
# Redirect non-WWW -> WWW
# ============================================================

server {

    listen 80;
    listen [::]:80;

    server_name ${DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root ${WEB_ROOT};
        allow all;
    }

    return 301  $scheme://${WWW_DOMAIN}\$request_uri;
}


# ============================================================
# Main WWW site
# ============================================================

EOF

    create_main_server >> "$NGINX_AVAILABLE"


elif [ "$WWW_MODE" = "non-www" ]; then

    SERVER_NAMES="$DOMAIN"

    cat > "$NGINX_AVAILABLE" <<EOF

# ============================================================
# Redirect WWW -> non-WWW
# ============================================================

server {

    listen 80;
    listen [::]:80;

    server_name ${WWW_DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root ${WEB_ROOT};
        allow all;
    }

    return 301 http://${DOMAIN}\$request_uri;
}


# ============================================================
# Main non-WWW site
# ============================================================

EOF

    create_main_server >> "$NGINX_AVAILABLE"


else

    SERVER_NAMES="${DOMAIN} ${WWW_DOMAIN}"

    cat > "$NGINX_AVAILABLE" <<EOF

# ============================================================
# Main WordPress site
#
# Both:
#   ${DOMAIN}
#   ${WWW_DOMAIN}
#
# are accepted.
# ============================================================

EOF

    create_main_server >> "$NGINX_AVAILABLE"

fi


# Replace placeholder with actual server names
sed -i "s/\\\$SERVER_NAMES/${SERVER_NAMES}/g" "$NGINX_AVAILABLE"


# ============================================================
# ENABLE SITE
# ============================================================

rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default

ln -sf "$NGINX_AVAILABLE" "$NGINX_ENABLED"


# ============================================================
# FINAL WORDPRESS PERMISSIONS
# ============================================================

echo
echo "[12/12] Setting final WordPress permissions..."

# www-data owns the complete WordPress installation
chown -R www-data:www-data "$WEB_ROOT"

# Directories
find "$WEB_ROOT" -type d -exec chmod 755 {} \;

# Files
find "$WEB_ROOT" -type f -exec chmod 644 {} \;

# Protect database credentials
chmod 640 "$WEB_ROOT/wp-config.php"


# ============================================================
# WORDPRESS CORE INSTALL
# ============================================================

echo
echo "Installing WordPress..."

cd "$WEB_ROOT"

if [ "$WWW_MODE" = "www" ]; then
    SITE_URL="https://${WWW_DOMAIN}"
else
    SITE_URL="https://${DOMAIN}"
fi

sudo -u www-data wp core install \
    --url="$SITE_URL" \
    --title="$DOMAIN" \
    --admin_user="$WP_ADMIN_USER" \
    --admin_password="$WP_ADMIN_PASS" \
    --admin_email="$WP_ADMIN_EMAIL" \
    --skip-email


# ============================================================
# NGINX TEST
# ============================================================

echo
echo "Testing Nginx configuration..."

nginx -t

systemctl reload nginx


# ============================================================
# SAVE CREDENTIALS
# ============================================================

CREDENTIAL_FILE="/root/${DOMAIN}-credentials.txt"

cat > "$CREDENTIAL_FILE" <<EOF
========================================
WordPress Site Information
========================================

Domain:
${DOMAIN}

WWW Domain:
${WWW_DOMAIN}

WWW Mode:
${WWW_MODE}

Site URL:
${SITE_URL}

Web Root:
${WEB_ROOT}

Nginx Configuration:
${NGINX_AVAILABLE}

Database:
${DB_NAME}

Database User:
${DB_USER}

Database Password:
${DB_PASS}

Database Host:
localhost

WordPress Admin:
${WP_ADMIN_USER}

WordPress Admin Email:
${WP_ADMIN_EMAIL}

WordPress Admin Password:
${WP_ADMIN_PASS}

PHP Version:
${PHP_VERSION}

PHP-FPM Socket:
${PHP_SOCKET}

========================================
EOF

chmod 600 "$CREDENTIAL_FILE"


# ============================================================
# SSL
# ============================================================

echo
echo "Do you want to install SSL with Let's Encrypt now?"
echo

echo "This requires DNS for the domain to already point to this server."
echo

read -rp "Install SSL? [y/N]: " INSTALL_SSL

if [[ "$INSTALL_SSL" =~ ^[Yy]$ ]]; then

    echo
    echo "Installing SSL..."

        certbot --nginx \
            -d "$DOMAIN" \
            -d "$WWW_DOMAIN"

    systemctl reload nginx

fi


# ============================================================
# FINAL INFORMATION
# ============================================================

echo
echo "================================================"
echo "WordPress installation completed"
echo "================================================"
echo

echo "Site:"
echo "  $SITE_URL"
echo

echo "Web root:"
echo "  $WEB_ROOT"
echo

echo "Nginx config:"
echo "  $NGINX_AVAILABLE"
echo

echo "Database:"
echo "  $DB_NAME"
echo

echo "Database user:"
echo "  $DB_USER"
echo

echo "Credentials:"
echo "  $CREDENTIAL_FILE"
echo

if [ "$INSTALL_SSL" = "y" ] || [ "$INSTALL_SSL" = "Y" ]; then

    echo "SSL:"
    echo "  Installed"

else

    echo "SSL:"
    echo "  Not installed"
    echo

    echo "When DNS is ready, run:"
    echo

    echo "  certbot --nginx -d $DOMAIN -d $WWW_DOMAIN"

fi

echo
echo "================================================"
