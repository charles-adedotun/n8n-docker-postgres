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

# User-level log rotation using logrotate if available, otherwise just log a note
if command -v logrotate &> /dev/null; then
    log_info "Setting up log rotation..."
    mkdir -p "$HOME/.config/logrotate"
    cat > "$HOME/.config/logrotate/n8n" << EOF
$PROJECT_DIR/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 $(id -un) $(id -gn)
}
$PROJECT_DIR/backups/backup.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 $(id -un) $(id -gn)
}
EOF
    log_info "Log rotation configured. You may need to set up a personal cron job to run logrotate."
else
    log_info "Logrotate not found. Log files will need to be managed manually."
fi

# Default to 2 AM if not specified
BACKUP_HOUR=2
BACKUP_MINUTE=0

# On non-macOS systems, we'd set up a cron job here
# But we'll skip this for macOS and use launchd instead

# Check if it's a Mac system and configure launchd instead of cron
if [[ "$OSTYPE" == "darwin"* ]]; then
    log_info "macOS detected. Setting up user-level launchd job..."
    
    # Create user-level LaunchAgents directory if it doesn't exist
    LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
    mkdir -p "$LAUNCH_AGENTS_DIR"
    
    # Create launchd plist file at user level
    PLIST_FILE="$LAUNCH_AGENTS_DIR/com.n8n.backup.plist"
    
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
    <array>
        <dict>
            <key>Hour</key>
            <integer>0</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>6</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>12</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>18</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
    </array>
    <key>StandardOutPath</key>
    <string>$CRON_LOG</string>
    <key>StandardErrorPath</key>
    <string>$CRON_LOG</string>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
    
    # Set proper permissions on the plist file
    chmod 644 "$PLIST_FILE"
    
    # Unload the job first if it exists (to prevent errors)
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    
    # Load the launchd job
    launchctl load "$PLIST_FILE"
    
    log_info "User-level launchd job set up for backups every 6 hours (at 00:00, 06:00, 12:00, and 18:00)"
    log_info "Check job status with: launchctl list | grep com.n8n.backup"
fi

log_info "Automated backup setup complete!"
log_info "Backups will run every 6 hours (at 00:00, 06:00, 12:00, and 18:00)"
log_info "Logs will be stored in $CRON_LOG"
log_info "Backups will be stored in $PROJECT_DIR/backups"
