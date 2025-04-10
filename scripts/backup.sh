#!/bin/bash
# n8n Backup Script
# Creates database dumps and backs up n8n data directory

set -e

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
BACKUP_DIR="$PROJECT_DIR/backups"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/backup.log"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Functions
log() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "$timestamp - $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    log_error ".env file not found at $ENV_FILE"
    exit 1
fi

# Create timestamp for backup files
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILENAME="n8n_backup_$TIMESTAMP"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}

# Create backup directory if it doesn't exist
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    log_info "Created backup directory at $BACKUP_DIR"
fi

# Create logs directory if it doesn't exist
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi

# Ensure log file exists
touch "$LOG_FILE"

log_info "Starting backup process..."

# Check if containers are running
if ! docker compose -f "$PROJECT_DIR/docker-compose.yml" ps | grep -q "postgres.*Up"; then
    log_error "PostgreSQL container is not running. Backup cannot proceed."
    exit 1
fi

if ! docker compose -f "$PROJECT_DIR/docker-compose.yml" ps | grep -q "n8n.*Up"; then
    log_warning "n8n container is not running. Only database will be backed up."
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
log_info "Created temporary directory at $TEMP_DIR"

# Backup PostgreSQL database
log_info "Backing up PostgreSQL database..."
if ! docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F c > "$TEMP_DIR/database.dump"; then
    log_error "Failed to backup PostgreSQL database"
    rm -rf "$TEMP_DIR"
    exit 1
fi
log_info "PostgreSQL database backup completed"

# Backup n8n data directory
log_info "Backing up n8n data directory..."
mkdir -p "$TEMP_DIR/n8n_data"
if ! docker compose -f "$PROJECT_DIR/docker-compose.yml" cp n8n:/home/node/.n8n/. "$TEMP_DIR/n8n_data/"; then
    log_warning "Failed to backup n8n data directory. This may be due to container not running."
else
    log_info "n8n data directory backup completed"
fi

# Create compressed archive
log_info "Creating compressed backup archive..."
cd "$TEMP_DIR"
if ! tar -czf "$BACKUP_DIR/$BACKUP_FILENAME.tar.gz" .; then
    log_error "Failed to create compressed backup archive"
    rm -rf "$TEMP_DIR"
    exit 1
fi
log_info "Compressed backup archive created at $BACKUP_DIR/$BACKUP_FILENAME.tar.gz"

# Cleanup temporary directory
rm -rf "$TEMP_DIR"
log_info "Temporary directory removed"

# Implement retention policy
log_info "Implementing retention policy (keeping backups for $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -name "n8n_backup_*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete
log_info "Old backups removed according to retention policy"

# Calculate size of the backup
BACKUP_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILENAME.tar.gz" | cut -f1)
log_info "Backup completed successfully. Size: $BACKUP_SIZE"
log_info "Backup location: $BACKUP_DIR/$BACKUP_FILENAME.tar.gz"
