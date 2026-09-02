#!/bin/bash

set -e

PHP_INI="/etc/php/8.3/fpm/php.ini"
WWW_CONF="/etc/php/8.3/fpm/pool.d/www.conf"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "========================================="
echo " PHP 8.3 FPM Configuration Update"
echo "========================================="

# Check that files exist
if [ ! -f "$PHP_INI" ]; then
    echo "ERROR: $PHP_INI not found"
    exit 1
fi

if [ ! -f "$WWW_CONF" ]; then
    echo "ERROR: $WWW_CONF not found"
    exit 1
fi

# --------------------------------------------------
# 1. BACKUP
# --------------------------------------------------

echo
echo "[1/4] Creating backups..."

cp "$PHP_INI" "${PHP_INI}.backup_${TIMESTAMP}"
cp "$WWW_CONF" "${WWW_CONF}.backup_${TIMESTAMP}"

echo "Backup created:"
echo "  $PHP_INI.backup_$TIMESTAMP"
echo "  $WWW_CONF.backup_$TIMESTAMP"

# --------------------------------------------------
# 2. UPDATE php.ini
# --------------------------------------------------

echo
echo "[2/4] Updating php.ini..."

sed -i -E 's/^[;[:space:]]*memory_limit[[:space:]]*=.*/memory_limit = 512M/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*max_execution_time[[:space:]]*=.*/max_execution_time = 600/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*upload_max_filesize[[:space:]]*=.*/upload_max_filesize = 128M/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*post_max_size[[:space:]]*=.*/post_max_size = 128M/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*realpath_cache_size[[:space:]]*=.*/realpath_cache_size = 16M/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*realpath_cache_ttl[[:space:]]*=.*/realpath_cache_ttl = 1200/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*opcache\.enable[[:space:]]*=.*/opcache.enable = 1/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*opcache\.memory_consumption[[:space:]]*=.*/opcache.memory_consumption = 128/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*opcache\.interned_strings_buffer[[:space:]]*=.*/opcache.interned_strings_buffer = 16/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*opcache\.max_accelerated_files[[:space:]]*=.*/opcache.max_accelerated_files = 20000/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*opcache\.validate_timestamps[[:space:]]*=.*/opcache.validate_timestamps = 1/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*opcache\.revalidate_freq[[:space:]]*=.*/opcache.revalidate_freq = 60/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*opcache\.save_comments[[:space:]]*=.*/opcache.save_comments = 1/' "$PHP_INI"

# --------------------------------------------------
# 3. UPDATE www.conf
# --------------------------------------------------

echo
echo "[3/4] Updating www.conf..."

sed -i -E 's/^[;[:space:]]*pm[[:space:]]*=.*/pm = dynamic/' "$WWW_CONF"

sed -i -E 's/^[;[:space:]]*pm\.max_children[[:space:]]*=.*/pm.max_children = 16/' "$WWW_CONF"

sed -i -E 's/^[;[:space:]]*pm\.start_servers[[:space:]]*=.*/pm.start_servers = 4/' "$WWW_CONF"

sed -i -E 's/^[;[:space:]]*pm\.min_spare_servers[[:space:]]*=.*/pm.min_spare_servers = 2/' "$WWW_CONF"

sed -i -E 's/^[;[:space:]]*pm\.max_spare_servers[[:space:]]*=.*/pm.max_spare_servers = 6/' "$WWW_CONF"

sed -i -E 's/^[;[:space:]]*pm\.max_requests[[:space:]]*=.*/pm.max_requests = 1000/' "$WWW_CONF"

# --------------------------------------------------
# 4. TEST CONFIGURATION
# --------------------------------------------------

echo
echo "[4/4] Testing PHP-FPM configuration..."

php-fpm8.3 -t

echo
echo "PHP-FPM configuration test successful."

echo
echo "Restarting PHP-FPM..."

systemctl restart php8.3-fpm

echo
echo "========================================="
echo " Configuration updated successfully"
echo "========================================="
