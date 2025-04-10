#!/bin/bash
# n8n Cron Setup Script
# Sets up automated backups using cron

set -e

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"
ENV_FILE="$PROJECT_DIR/.env"
LOG_DIR="$PROJECT_DIR/logs"
CRON_LOG="$LOG_DIR/cron.log"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root to set up cron jobs"
    exit 1
fi

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    log_error ".env file not found at $ENV_FILE"
    exit 1
fi

log_info "Setting up automated backups for n8n..."

# Check if backup script exists and is executable
if [ ! -x "$BACKUP_SCRIPT" ]; then
    log_error "Backup script not found or not executable: $BACKUP_SCRIPT"
    log_info "Make sure the backup script exists and has execute permissions"
    log_info "Run: chmod +x $BACKUP_SCRIPT"
    exit 1
fi

# Create log directory if it doesn't exist
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    log_info "Created log directory at $LOG_DIR"
    chmod 700 "$LOG_DIR"  # Set proper permissions
fi

# Set up log rotation
log_info "Setting up log rotation..."
cat > /etc/logrotate.d/n8n << EOF
$PROJECT_DIR/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 root root
}
$PROJECT_DIR/backups/backup.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 root root
}
EOF
log_info "Log rotation configured"

# Set up cron job for daily backups
log_info "Setting up daily backup cron job..."

# Default to 2 AM if not specified
BACKUP_HOUR=2
BACKUP_MINUTE=0

# Create cron job
CRON_ENTRY="$BACKUP_MINUTE $BACKUP_HOUR * * * $BACKUP_SCRIPT >> $CRON_LOG 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "$BACKUP_SCRIPT"; then
    log_warning "Cron job for n8n backup already exists. Skipping."
else
    # Add cron job
    (crontab -l 2>/dev/null || echo "") | { cat; echo "$CRON_ENTRY"; } | crontab -
    log_info "Cron job added for daily backups at $BACKUP_HOUR:$BACKUP_MINUTE AM"
fi

# Check if it's a Mac system and configure launchd instead of cron
if [[ "$OSTYPE" == "darwin"* ]]; then
    log_info "macOS detected. Setting up launchd job instead of cron..."
    
    # Create launchd plist file
    PLIST_FILE="/Library/LaunchDaemons/com.n8n.backup.plist"
    
    cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.n8n.backup</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BACKUP_SCRIPT</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$BACKUP_HOUR</integer>
        <key>Minute</key>
        <integer>$BACKUP_MINUTE</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$CRON_LOG</string>
    <key>StandardErrorPath</key>
    <string>$CRON_LOG</string>
</dict>
</plist>
EOF
    
    # Set proper permissions on the plist file
    chmod 644 "$PLIST_FILE"
    
    # Load the launchd job
    launchctl load "$PLIST_FILE"
    
    log_info "launchd job set up for daily backups at $BACKUP_HOUR:$BACKUP_MINUTE AM"
    log_info "Check job status with: launchctl list | grep com.n8n.backup"
else
    log_info "Check cron job with: crontab -l"
fi

log_info "Automated backup setup complete!"
log_info "Backups will run daily at $BACKUP_HOUR:$BACKUP_MINUTE AM"
log_info "Logs will be stored in $CRON_LOG"
log_info "Backups will be stored in $PROJECT_DIR/backups"
