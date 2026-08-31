Dynamic WP Site configuration

Update System

apt update && apt upgrade -y

apt install curl wget gnupg2 apt-transport-https lsb-release ca-certificates -y

Install nginx

apt install nginx -y

systemctl enable nginx

systemctl start nginx

rm /etc/nginx/sites-enabled/default
rm /etc/nginx/sites-available/default
rm /var/www/html/index.nginx-debian.html

 Install PHP 8.3

wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list


apt update

Install PHP and Extensions


apt install php8.3-fpm php8.3-mysql php8.3-xml php8.3-xmlrpc php8.3-curl php8.3-gd php8.3-imagick php8.3-cli php8.3-dev php8.3-imap php8.3-mbstring php8.3-opcache php8.3-soap php8.3-zip php8.3-intl php8.3-bcmath -y



Install MariaDB

apt install mariadb-server -y
systemctl enable mariadb
systemctl start mariadb

mariadb-secure-installation



Create WordPress Database

CREATE DATABASE abc_wordpress;
CREATE USER 'abc_user'@'localhost' IDENTIFIED BY 'SecurePassword123!';
GRANT ALL PRIVILEGES ON abc_wordpress.* TO 'abc_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;

Main NGINX Configuration


vim /etc/nginx/nginx.conf


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









Create Site Configuration


vim /etc/nginx/sites-available/abc.com

server {
    listen 80;
    server_name abc.com www.abc.com;
    root /var/www/abc.com;
    index index.php index.html index.htm;
    
    # Enhanced Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Security - block sensitive files
    location ~* \.(htaccess|env|log|ini|sh|bak|sql|conf|git|svn|project|zip|tar|gz)$ {
        deny all;
        return 444;
    }
    
    # Block WordPress sensitive areas
    location ~* /(?:uploads|files)/.*\.php$ {
        deny all;
        return 444;
    }
    
    location ~ /wp-config\.php {
        deny all;
        return 444;
    }
    
    # Disable xmlrpc.php
    location = /xmlrpc.php {
        deny all;
        return 444;
    }
    
    # Block access to hidden files
    location ~ /\. {
        deny all;
        return 444;
    }
    
    # Enhanced static files handling
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|webp|avif|woff|woff2|ttf|eot|otf|mp4|mp3|pdf|zip|wasm)$ {
        expires 30d;
        add_header Cache-Control "public, immutable, stale-while-revalidate=86400";
        add_header Vary "Accept-Encoding";
        access_log off;
        log_not_found off;
        
        # Performance optimizations
        tcp_nopush on;
        tcp_nodelay on;
        sendfile on;
        gzip_static on;
    }
    
    # Let's Encrypt verification
    location ^~ /.well-known/acme-challenge/ {
        default_type "text/plain";
        root /var/www/abc.com;
        allow all;
    }
    
    # Favicon optimization
    location = /favicon.ico {
        expires max;
        access_log off;
        log_not_found off;
        add_header Cache-Control "public, immutable";
    }
    
    # Robots.txt optimization
    location = /robots.txt {
        expires 1d;
        access_log off;
        log_not_found off;
        add_header Cache-Control "public";
    }
    
    # WordPress login - rate limited
    location = /wp-login.php {
        limit_req zone=login burst=3 nodelay;
        
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        
        # No caching for login
        fastcgi_cache_bypass 1;
        fastcgi_no_cache 1;
        
        # Prevent caching
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header Expires "0" always;
    }
    
    # WordPress admin area
    location ~* /wp-admin/.*\.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        
        # Skip cache completely
        fastcgi_cache_bypass 1;
        fastcgi_no_cache 1;
        
        # Optimized buffering
        fastcgi_buffering on;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout 300;
    }
    
    # WordPress permalinks
    location / {
        try_files $uri $uri/ /index.php?$args;
    }
    
    # Enhanced PHP handling
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        
        # Enhanced FastCGI buffering
        fastcgi_buffering on;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 8 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_temp_file_write_size 256k;
        fastcgi_read_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_connect_timeout 60;
        
        # Cache logic
        set $skip_cache 0;
        
        if ($skip_cache_method) {
            set $skip_cache 1;
        }
        if ($skip_cache_uri) {
            set $skip_cache 1;
        }
        if ($skip_cache_cookie) {
            set $skip_cache 1;
        }
        
        # Cache configuration
        fastcgi_cache_bypass $skip_cache;
        fastcgi_no_cache $skip_cache;
        fastcgi_cache WORDPRESS;
        fastcgi_cache_valid 200 301 302 60m;
        fastcgi_cache_valid 404 1m;
        fastcgi_cache_min_uses 1;
        fastcgi_cache_lock on;
        fastcgi_cache_lock_timeout 5s;
        fastcgi_cache_use_stale error timeout invalid_header http_500 http_503;
        add_header X-FastCGI-Cache $upstream_cache_status;
    }
}




Alternative: WWW as Primary Domain (with non-WWW redirect)

If you prefer www.abc.com as your primary domain with automatic redirect from non-www:
 #may me there should need www.abc.com server redirection 

nano /etc/nginx/sites-available/abc.com

# Redirect non-www to www
server {
    listen 80;
    server_name abc.com;
    return 301 $scheme://www.abc.com$request_uri;
}

# Main server block with www
server {
    listen 80;
    server_name www.abc.com;
    root /var/www/abc.com;
    index index.php index.html index.htm;
    
    # Enhanced Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Security - block sensitive files
    location ~* \.(htaccess|env|log|ini|sh|bak|sql|conf|git|svn|project|zip|tar|gz)$ {
        deny all;
        return 444;
    }
    
    # Block WordPress sensitive areas
    location ~* /(?:uploads|files)/.*\.php$ {
        deny all;
        return 444;
    }
    
    location ~ /wp-config\.php {
        deny all;
        return 444;
    }
    
    # Disable xmlrpc.php
    location = /xmlrpc.php {
        deny all;
        return 444;
    }
    
    # Block access to hidden files
    location ~ /\. {
        deny all;
        return 444;
    }
    
    # Enhanced static files handling
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|webp|avif|woff|woff2|ttf|eot|otf|mp4|mp3|pdf|zip|wasm)$ {
        expires 30d;
        add_header Cache-Control "public, immutable, stale-while-revalidate=86400";
        add_header Vary "Accept-Encoding";
        access_log off;
        log_not_found off;
        
        # Performance optimizations
        tcp_nopush on;
        tcp_nodelay on;
        sendfile on;
        gzip_static on;
    }
    
    # Let's Encrypt verification
    location ^~ /.well-known/acme-challenge/ {
        default_type "text/plain";
        root /var/www/abc.com;
        allow all;
    }
    
    # Favicon optimization
    location = /favicon.ico {
        expires max;
        access_log off;
        log_not_found off;
        add_header Cache-Control "public, immutable";
    }
    
    # Robots.txt optimization
    location = /robots.txt {
        expires 1d;
        access_log off;
        log_not_found off;
        add_header Cache-Control "public";
    }
    
    # WordPress login - rate limited
    location = /wp-login.php {
        limit_req zone=login burst=3 nodelay;
        
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        
        # No caching for login
        fastcgi_cache_bypass 1;
        fastcgi_no_cache 1;
        
        # Prevent caching
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header Expires "0" always;
    }
    
    # WordPress admin area
    location ~* /wp-admin/.*\.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        
        # Skip cache completely
        fastcgi_cache_bypass 1;
        fastcgi_no_cache 1;
        
        # Optimized buffering
        fastcgi_buffering on;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout 300;
    }
    
    # WordPress permalinks
    location / {
        try_files $uri $uri/ /index.php?$args;
    }
    
    # Enhanced PHP handling
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        
        # Enhanced FastCGI buffering
        fastcgi_buffering on;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 8 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_temp_file_write_size 256k;
        fastcgi_read_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_connect_timeout 60;
        
        # Cache logic
        set $skip_cache 0;
        
        if ($skip_cache_method) {
            set $skip_cache 1;
        }
        if ($skip_cache_uri) {
            set $skip_cache 1;
        }
        if ($skip_cache_cookie) {
            set $skip_cache 1;
        }
        
        # Cache configuration
        fastcgi_cache_bypass $skip_cache;
        fastcgi_no_cache $skip_cache;
        fastcgi_cache WORDPRESS;
        fastcgi_cache_valid 200 301 302 60m;
        fastcgi_cache_valid 404 1m;
        fastcgi_cache_min_uses 1;
        fastcgi_cache_lock on;
        fastcgi_cache_lock_timeout 5s;
        fastcgi_cache_use_stale error timeout invalid_header http_500 http_503;
        add_header X-FastCGI-Cache $upstream_cache_status;
    }
}


sudo ln -s /etc/nginx/sites-available/abc.com /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx



mkdir -p /var/cache/nginx
chown -R www-data:www-data /var/cache/nginx
chmod -R 755 /var/cache/nginx


Create Web Directory

mkdir -p /var/www/abc.com
cd /var/www/abc.com

Download and Install WordPress

wget https://wordpress.org/latest.tar.gz          //Don’t use this now for a reason https://wordpress.org/wordpress-7.0.4.tar.gz


tar xzf latest.tar.gz --strip-components=1
rm latest.tar.gz




Set Proper Permissions

chown -R www-data:www-data /var/www/abc.com
chmod -R 755 /var/www/abc.com

Set Proper Permissions
find /path/to/directory -type d -exec chmod 755 {} \;
find /path/to/directory -type f -exec chmod 644 {} \;




Install WP-CLI

curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

sudo -u www-data wp config create --prompt
sudo -u www-data wp core install --prompt 


WP CONFIG CREATION mannually
wp config create \
 --dbname=my_database \
 --dbuser=my_user \
 --dbpass=my_password \
 --dbhost=localhost



Install Certbot

apt install certbot python3-certbot-nginx -y

Get SSL Certificate

certbot --nginx -d abc.com -d www.abc.com

sudo systemctl status certbot.timer

sudo systemctl enable certbot.timer




PHP OPTIMIZATION
vim /etc/php/8.3/fpm/php.ini	
memory_limit = 256M

max_execution_time = 300

upload_max_filesize = 64M
post_max_size = 64M

;to store the file path in cache
realpath_cache_size = 8M
realpath_cache_ttl = 600


;to enable opcache	
opcache.enable = 1
opcache.memory_consumption = 64
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = 10000
opcache.validate_timestamps = 1
opcache.revalidate_freq = 60
opcache.save_comments = 1

vim /etc/php/8.3/fpm/pool.d/www.conf
pm = dynamic
	
pm.max_children = 8
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3

pm.max_requests = 500


;optional to add
request_terminate_timeout = 60s




systemctl reload php




Service checking script

vim /usr/local/sbin/service-monitor.sh 
#!/bin/bash

LOG_FILE="/var/log/service-monitor.log"
SERVICES=("nginx" "mariadb" "php8.3-fpm")

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE"
}

log "===== Service monitor execution started ====="

for SERVICE in "${SERVICES[@]}"; do

    if systemctl is-active --quiet "$SERVICE"; then
        log "OK      | $SERVICE is running."
    else
        log "WARNING | $SERVICE is stopped/failed. Attempting restart."

        if systemctl restart "$SERVICE"; then
            log "SUCCESS | $SERVICE restarted successfully."
        else
            log "ERROR   | Failed to restart $SERVICE."
        fi
    fi

done

log "===== Service monitor execution completed ====="




vim /etc/systemd/system/service-monitor.service

[Unit]
Description=Service Monitor for Nginx and MariaDB
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/service-monitor.sh



vim /etc/systemd/system/service-monitor.timer

[Unit]
Description=Run Nginx and MariaDB Service Monitor every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target


Create log files
 touch /var/log/service-monitor.log
 chown root:root /var/log/service-monitor.log
 chmod 640 /var/log/service-monitor.log



vim /etc/logrotate.d/service-monitor


/var/log/service-monitor.log {
    weekly
    rotate 14
    size 10M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}


Dont forget
Add redis

Clear nginx cache

Clear cloudflare cache 

Add cloudflare ip on trustable list of nginx

Add systemfailure script and make it executable

Upload backup files from the dev site

Enable site indexing





Adding cloud flare on trust list of nginx


vim /usr/local/sbin/update-cloudflare-nginx-realip.sh

#!/bin/bash

set -euo pipefail

CF_CONF="/etc/nginx/conf.d/cloudflare-realip.conf"
TMP_CONF="/etc/nginx/conf.d/cloudflare-realip.conf.tmp"

CF_IPV4_URL="https://www.cloudflare.com/ips-v4"
CF_IPV6_URL="https://www.cloudflare.com/ips-v6"


echo "# Generated automatically - DO NOT EDIT" > "$TMP_CONF"
echo "# Generated at $(date -u)" >> "$TMP_CONF"
echo "" >> "$TMP_CONF"


echo "# Cloudflare IPv4 ranges" >> "$TMP_CONF"

curl -fsSL "$CF_IPV4_URL" | while read -r ip
do
    echo "set_real_ip_from $ip;" >> "$TMP_CONF"
done


echo "" >> "$TMP_CONF"
echo "# Cloudflare IPv6 ranges" >> "$TMP_CONF"

curl -fsSL "$CF_IPV6_URL" | while read -r ip
do
    echo "set_real_ip_from $ip;" >> "$TMP_CONF"
done


echo "" >> "$TMP_CONF"

# Keep real IP settings
cat <<EOF >> "$TMP_CONF"

real_ip_header CF-Connecting-IP;
real_ip_recursive on;

EOF


# Validate generated nginx config before replacing
cp "$TMP_CONF" "$CF_CONF"

if nginx -t >/dev/null 2>&1
then
    echo "$(date): Cloudflare IP list updated successfully"
    rm -f "$TMP_CONF"
else
    echo "$(date): nginx validation failed, keeping old configuration"
    rm -f "$TMP_CONF"
    exit 1
fi


chmod 750 /usr/local/sbin/update-cloudflare-nginx-realip.sh

vim /etc/systemd/system/cloudflare-realip-update.service

[Unit]
Description=Update Cloudflare IP ranges for Nginx real IP
After=network-online.target nginx.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/update-cloudflare-nginx-realip.sh

vim /etc/systemd/system/cloudflare-realip-update.timer
 		
[Unit]
Description=Daily Cloudflare IP update

[Timer]
OnBootSec=10min
OnUnitActiveSec=24h
Persistent=true

[Install]
WantedBy=timers.target


systemctl daemon-reload

systemctl start cloudflare-realip-update.service
systemctl enable –now cloudflare-realip-update.timer

