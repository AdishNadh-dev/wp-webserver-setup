#!/bin/bash

set -e

PHP_INI="/etc/php/8.3/fpm/php.ini"
WWW_CONF="/etc/php/8.3/fpm/pool.d/www.conf"
BACKUP_DIR="/root/backup"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "Creating backup directory..."
mkdir -p "$BACKUP_DIR"

echo "Backing up configuration files..."

cp "$PHP_INI" "$BACKUP_DIR/php.ini.$TIMESTAMP"
cp "$WWW_CONF" "$BACKUP_DIR/www.conf.$TIMESTAMP"

echo "Backups created:"
echo "  $BACKUP_DIR/php.ini.$TIMESTAMP"
echo "  $BACKUP_DIR/www.conf.$TIMESTAMP"

echo "Updating php.ini..."

sed -i -E 's/^[;[:space:]]*memory_limit[[:space:]]*=.*/memory_limit = 256M/' "$PHP_INI"
sed -i -E 's/^[;[:space:]]*max_execution_time[[:space:]]*=.*/max_execution_time = 300/' "$PHP_INI"
sed -i -E 's/^[;[:space:]]*upload_max_filesize[[:space:]]*=.*/upload_max_filesize = 64M/' "$PHP_INI"
sed -i -E 's/^[;[:space:]]*post_max_size[[:space:]]*=.*/post_max_size = 64M/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*realpath_cache_size[[:space:]]*=.*/realpath_cache_size = 8M/' "$PHP_INI"
sed -i -E 's/^[;[:space:]]*realpath_cache_ttl[[:space:]]*=.*/realpath_cache_ttl = 600/' "$PHP_INI"

# Uncomment and enable OPcache
sed -i -E 's/^[;[:space:]]*opcache\.enable[[:space:]]*=.*/opcache.enable = 1/' "$PHP_INI"

sed -i -E 's/^[;[:space:]]*opcache\.memory_consumption[[:space:]]*=.*/opcache.memory_consumption = 64/' "$PHP_INI"
sed -i -E 's/^[;[:space:]]*opcache\.interned_strings_buffer[[:space:]]*=.*/opcache.interned_strings_buffer = 8/' "$PHP_INI"
sed -i -E 's/^[;[:space:]]*opcache\.max_accelerated_files[[:space:]]*=.*/opcache.max_accelerated_files = 10000/' "$PHP_INI"
sed -i -E 's/^[;[:space:]]*opcache\.validate_timestamps[[:space:]]*=.*/opcache.validate_timestamps = 1/' "$PHP_INI"
sed -i -E 's/^[;[:space:]]*opcache\.revalidate_freq[[:space:]]*=.*/opcache.revalidate_freq = 60/' "$PHP_INI"
sed -i -E 's/^[;[:space:]]*opcache\.save_comments[[:space:]]*=.*/opcache.save_comments = 1/' "$PHP_INI"

echo "Updating www.conf..."

sed -i -E 's/^[;[:space:]]*pm[[:space:]]*=.*/pm = dynamic/' "$WWW_CONF"
sed -i -E 's/^[;[:space:]]*pm\.max_children[[:space:]]*=.*/pm.max_children = 8/' "$WWW_CONF"
sed -i -E 's/^[;[:space:]]*pm\.start_servers[[:space:]]*=.*/pm.start_servers = 2/' "$WWW_CONF"
sed -i -E 's/^[;[:space:]]*pm\.min_spare_servers[[:space:]]*=.*/pm.min_spare_servers = 1/' "$WWW_CONF"
sed -i -E 's/^[;[:space:]]*pm\.max_spare_servers[[:space:]]*=.*/pm.max_spare_servers = 3/' "$WWW_CONF"
sed -i -E 's/^[;[:space:]]*pm\.max_requests[[:space:]]*=.*/pm.max_requests = 500/' "$WWW_CONF"

echo
echo "Configuration updated successfully."
echo
echo "Backup files:"
echo "  $BACKUP_DIR/php.ini.$TIMESTAMP"
echo "  $BACKUP_DIR/www.conf.$TIMESTAMP"
