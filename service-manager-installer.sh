#!/bin/bash

# ============================================================
# Service Monitor Installer
# Creates:
#   /usr/local/sbin/service-monitor.sh
#   /etc/systemd/system/service-monitor.service
#   /etc/systemd/system/service-monitor.timer
#   /etc/logrotate.d/service-monitor
#   /var/log/service-monitor.log
#
# Monitors:
#   nginx
#   mariadb
#   php8.3-fpm
# ============================================================

set -u

# -----------------------------
# Configuration
# -----------------------------

MONITOR_SCRIPT="/usr/local/sbin/service-monitor.sh"
SERVICE_UNIT="/etc/systemd/system/service-monitor.service"
TIMER_UNIT="/etc/systemd/system/service-monitor.timer"
LOG_FILE="/var/log/service-monitor.log"
LOGROTATE_FILE="/etc/logrotate.d/service-monitor"

SERVICES=("nginx" "mariadb" "php8.3-fpm")

BACKUP_DIR="/root/service-monitor-backup-$(date +%Y%m%d-%H%M%S)"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# -----------------------------
# Output functions
# -----------------------------


print_info() {
    echo "[INFO] $1"
}

print_pass() {
    echo "[PASS] $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

print_fail() {
    echo "[FAIL] $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

print_warn() {
    echo "[WARN] $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

print_section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

# -----------------------------
# Root check
# -----------------------------

if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] This script must be run as root."
    echo "        Run: sudo $0"
    exit 1
fi

# -----------------------------
# Dependency check
# -----------------------------

print_section "Checking required commands"

REQUIRED_COMMANDS=(
    bash
    systemctl
    systemd-analyze
    install
    chmod
    chown
    touch
)

for CMD in "${REQUIRED_COMMANDS[@]}"; do
    if command -v "$CMD" >/dev/null 2>&1; then
        print_pass "$CMD is available"
    else
        print_fail "$CMD is not available"
    fi
done

if command -v logrotate >/dev/null 2>&1; then
    print_pass "logrotate is available"
else
    print_warn "logrotate is not installed; logrotate validation will be skipped"
fi

if (( FAIL_COUNT > 0 )); then
    echo
    echo "[ERROR] Required dependencies are missing."
    exit 1
fi

# -----------------------------
# Create backup directory
# -----------------------------

print_section "Preparing backup"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

print_pass "Backup directory created: $BACKUP_DIR"

# -----------------------------
# Backup existing files
# -----------------------------

backup_file() {
    local FILE="$1"

    if [[ -e "$FILE" ]]; then
        cp -a "$FILE" "$BACKUP_DIR/"
        print_info "Backed up existing file: $FILE"
    fi
}

backup_file "$MONITOR_SCRIPT"
backup_file "$SERVICE_UNIT"
backup_file "$TIMER_UNIT"
backup_file "$LOGROTATE_FILE"

# -----------------------------
# Create service monitor script
# -----------------------------

print_section "Creating service-monitor.sh"

cat > "$MONITOR_SCRIPT" <<'EOF'
#!/bin/bash

# ============================================================
# Service Monitor
# ============================================================

set -u

LOG_FILE="/var/log/service-monitor.log"

SERVICES=(
    "nginx"
    "mariadb"
    "php8.3-fpm"
)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE"
}

log "===== Service monitor execution started ====="

for SERVICE in "${SERVICES[@]}"; do

    # Check whether the unit exists.
    if ! systemctl cat "$SERVICE" >/dev/null 2>&1; then
        log "WARNING | $SERVICE service/unit does not exist. Skipping."
        continue
    fi

    if systemctl is-active --quiet "$SERVICE"; then

        log "OK      | $SERVICE is running."

    else

        log "WARNING | $SERVICE is stopped/failed. Attempting restart."

        if systemctl restart "$SERVICE"; then

            # Give the service a moment to settle.
            sleep 2

            if systemctl is-active --quiet "$SERVICE"; then
                log "SUCCESS | $SERVICE restarted successfully."
            else
                log "ERROR   | $SERVICE restart command succeeded, but service is not active."
            fi

        else

            log "ERROR   | Failed to restart $SERVICE."

        fi
    fi

done

log "===== Service monitor execution completed ====="
EOF

# Permissions
chown root:root "$MONITOR_SCRIPT"
chmod 750 "$MONITOR_SCRIPT"

print_pass "Created $MONITOR_SCRIPT"
print_pass "Permissions set to 750 root:root"

# -----------------------------
# Create systemd service
# -----------------------------

print_section "Creating service-monitor.service"

cat > "$SERVICE_UNIT" <<EOF
[Unit]
Description=Service Monitor for Nginx, MariaDB and PHP-FPM
After=network.target

[Service]
Type=oneshot
ExecStart=$MONITOR_SCRIPT
User=root
Group=root
EOF

chown root:root "$SERVICE_UNIT"
chmod 644 "$SERVICE_UNIT"

print_pass "Created $SERVICE_UNIT"
print_pass "Permissions set to 644 root:root"

# -----------------------------
# Create systemd timer
# -----------------------------

print_section "Creating service-monitor.timer"

cat > "$TIMER_UNIT" <<'EOF'
[Unit]
Description=Run Service Monitor every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s
Persistent=true
Unit=service-monitor.service

[Install]
WantedBy=timers.target
EOF

chown root:root "$TIMER_UNIT"
chmod 644 "$TIMER_UNIT"

print_pass "Created $TIMER_UNIT"
print_pass "Permissions set to 644 root:root"

# -----------------------------
# Create log file
# -----------------------------

print_section "Creating log file"

touch "$LOG_FILE"
chown root:root "$LOG_FILE"
chmod 640 "$LOG_FILE"

print_pass "Created $LOG_FILE"
print_pass "Permissions set to 640 root:root"

# -----------------------------
# Create logrotate configuration
# -----------------------------

print_section "Creating logrotate configuration"

cat > "$LOGROTATE_FILE" <<EOF
$LOG_FILE {
    weekly
    rotate 14
    size 10M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF

chown root:root "$LOGROTATE_FILE"
chmod 644 "$LOGROTATE_FILE"

print_pass "Created $LOGROTATE_FILE"
print_pass "Permissions set to 644 root:root"

# -----------------------------
# Validate shell script
# -----------------------------

print_section "Testing shell script syntax"

if bash -n "$MONITOR_SCRIPT"; then
    print_pass "Shell syntax check passed"
else
    print_fail "Shell syntax check failed"
fi

# -----------------------------
# Reload systemd
# -----------------------------

print_section "Reloading systemd"

if systemctl daemon-reload; then
    print_pass "systemctl daemon-reload completed"
else
    print_fail "systemctl daemon-reload failed"
fi

# -----------------------------
# Validate systemd service
# -----------------------------

print_section "Validating systemd service"

if systemd-analyze verify "$SERVICE_UNIT"; then
    print_pass "service-monitor.service validation passed"
else
    print_fail "service-monitor.service validation failed"
fi

# -----------------------------
# Validate systemd timer
# -----------------------------

print_section "Validating systemd timer"

if systemd-analyze verify "$TIMER_UNIT"; then
    print_pass "service-monitor.timer validation passed"
else
    print_fail "service-monitor.timer validation failed"
fi

# -----------------------------
# Validate logrotate
# -----------------------------

print_section "Validating logrotate configuration"

if command -v logrotate >/dev/null 2>&1; then

    if logrotate -d "$LOGROTATE_FILE" >/dev/null 2>&1; then
        print_pass "logrotate configuration validation passed"
    else
        print_fail "logrotate configuration validation failed"
    fi

else
    print_warn "logrotate not installed; skipped logrotate test"
fi

# -----------------------------
# Check monitored services
# -----------------------------

print_section "Checking monitored services"

for SERVICE in "${SERVICES[@]}"; do

    if systemctl cat "$SERVICE" >/dev/null 2>&1; then
        print_pass "$SERVICE unit exists"
    else
        print_warn "$SERVICE unit does not exist"
    fi

done

# -----------------------------
# Enable timer
# -----------------------------

print_section "Enabling service monitor timer"

if systemctl enable service-monitor.timer; then
    print_pass "service-monitor.timer enabled"
else
    print_fail "Failed to enable service-monitor.timer"
fi

# -----------------------------
# Start timer
# -----------------------------

if systemctl start service-monitor.timer; then
    print_pass "service-monitor.timer started"
else
    print_fail "Failed to start service-monitor.timer"
fi

# -----------------------------
# Test monitor immediately
# -----------------------------

print_section "Running service monitor test"

if systemctl start service-monitor.service; then
    print_pass "service-monitor.service executed successfully"
else
    print_fail "service-monitor.service execution failed"
fi

# -----------------------------
# Check timer status
# -----------------------------

print_section "Checking timer status"

if systemctl is-active --quiet service-monitor.timer; then
    print_pass "service-monitor.timer is ACTIVE"
else
    print_fail "service-monitor.timer is NOT active"
fi

# -----------------------------
# Display timer information
# -----------------------------

echo
echo "Timer status:"
systemctl status service-monitor.timer --no-pager --full || true

# -----------------------------
# Display monitor log
# -----------------------------

print_section "Latest service monitor log"

if [[ -f "$LOG_FILE" ]]; then
    tail -n 30 "$LOG_FILE"
else
    print_fail "Log file does not exist"
fi

# -----------------------------
# Final summary
# -----------------------------

print_section "Installation Summary"

echo "PASS : $PASS_COUNT"
echo "WARN : $WARN_COUNT"
echo "FAIL : $FAIL_COUNT"
echo
echo "Configuration files:"
echo "  Monitor script : $MONITOR_SCRIPT"
echo "  Service unit   : $SERVICE_UNIT"
echo "  Timer unit     : $TIMER_UNIT"
echo "  Log file       : $LOG_FILE"
echo "  Logrotate      : $LOGROTATE_FILE"
echo
echo "Backup directory:"
echo "  $BACKUP_DIR"
echo

if (( FAIL_COUNT == 0 )); then
    echo "============================================================"
    echo "RESULT: SERVICE MONITOR INSTALLATION SUCCESSFUL"
    echo "============================================================"
    echo
    echo "The monitor will run:"
    echo "  - 2 minutes after boot"
    echo "  - Every 5 minutes thereafter"
    echo
    echo "Check timer:"
    echo "  systemctl list-timers service-monitor.timer"
    echo
    echo "Check logs:"
    echo "  tail -f /var/log/service-monitor.log"
    echo
    echo "Check service monitor:"
    echo "  systemctl status service-monitor.service"
    echo
    echo "Check timer:"
    echo "  systemctl status service-monitor.timer"
    echo
    exit 0
else
    echo "============================================================"
    echo "RESULT: INSTALLATION COMPLETED WITH ERRORS"
    echo "============================================================"
    echo
    echo "Review the [FAIL] messages above."
    echo
    exit 1
fi



