#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================="
echo " WordPress Server Setup"
echo "=============================================="
echo
echo "This script will let you choose which setup"
echo "components you want to install/configure."
echo

run_script() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"

    echo
    echo "----------------------------------------------"
    echo " $script_name"
    echo "----------------------------------------------"

    if [[ ! -f "$script_path" ]]; then
        echo "ERROR: $script_name was not found."
        echo "Expected location:"
        echo "  $script_path"
        return 1
    fi

    if [[ ! -x "$script_path" ]]; then
        echo "Making $script_name executable..."
        chmod +x "$script_path"
    fi

    echo "Running $script_name..."
    echo

    if "$script_path"; then
        echo
        echo "SUCCESS: $script_name completed."
    else
        local exit_code=$?
        echo
        echo "ERROR: $script_name failed with exit code $exit_code."
        return "$exit_code"
    fi
}

ask_to_run() {
    local script_name="$1"
    local description="$2"
    local answer

    echo
    echo "----------------------------------------------"
    echo "$description"
    echo "----------------------------------------------"

    while true; do
        read -r -p "Run $script_name? [y/n]: " answer

        case "$answer" in
            y|Y)
                run_script "$script_name"
                return $?
                ;;

            n|N)
                echo "Skipping $script_name."
                return 0
                ;;

            *)
                echo "Please enter y or n."
                ;;
        esac
    done
}

# ------------------------------------------------
# Scripts
# ------------------------------------------------

ask_to_run \
    "wp-installer.sh" \
    "WordPress installation and configuration"

ask_to_run \
    "php-config.sh" \
    "PHP 8.3 / php.ini / www.conf configuration"

ask_to_run \
    "brotli-installer.sh" \
    "Brotli installation and configuration"

ask_to_run \
    "cloudflare-trustlist.sh" \
    "Cloudflare trusted IP configuration"

ask_to_run \
    "service-monitoring-installer.sh" \
    "Service monitoring setup"

echo
echo "=============================================="
echo " Setup process completed"
echo "=============================================="
echo
