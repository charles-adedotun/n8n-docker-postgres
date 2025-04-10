#!/bin/bash
# n8n Restore Script
# Restores database and n8n data from a backup file

set -e

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/restore.log"

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

show_usage() {
    echo "Usage: $0 <backup_file.tar.gz>"
    echo "Restores n8n from a backup file created by backup.sh"
    exit 1
}

# Check arguments
if [ $# -ne 1 ]; then
    show_usage
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    log_error "Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Check if backup file is a tar.gz file
if [[ "$BACKUP_FILE" != *.tar.gz ]]; then
    log_error "Backup file must be a .tar.gz file"
    exit 1
fi

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    log_error ".env file not found at $ENV_FILE"
    exit 1
fi

# Create logs directory if it doesn't exist
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi

# Ensure log file exists
touch "$LOG_FILE"

log_info "Starting restore process from backup: $BACKUP_FILE"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
log_info "Created temporary directory at $TEMP_DIR"

# Extract backup archive
log_info "Extracting backup archive..."
if ! tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"; then
    log_error "Failed to extract backup archive"
    rm -rf "$TEMP_DIR"
    exit 1
fi
log_info "Backup archive extracted"

# Check if required backup files exist
if [ ! -f "$TEMP_DIR/database.dump" ]; then
    log_error "Database backup not found in archive"
    rm -rf "$TEMP_DIR"
    exit 1
fi

if [ ! -d "$TEMP_DIR/n8n_data" ]; then
    log_warning "n8n data directory not found in archive. Only database will be restored."
fi

# Stop services
log_info "Stopping services..."
cd "$PROJECT_DIR"
docker compose down
log_info "Services stopped"

# Restore PostgreSQL database
log_info "Restoring PostgreSQL database..."

# Start only PostgreSQL container
log_info "Starting PostgreSQL container..."
docker compose up -d postgres
sleep 10  # Wait for PostgreSQL to start

# Check if PostgreSQL is ready
attempts=0
max_attempts=30
while [ $attempts -lt $max_attempts ]; do
    if docker compose exec postgres pg_isready -U "$POSTGRES_USER" &>/dev/null; then
        log_info "PostgreSQL is ready"
        break
    fi
    
    attempts=$((attempts + 1))
    if [ $attempts -eq $max_attempts ]; then
        log_error "PostgreSQL did not start properly after $max_attempts attempts"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    echo -n "."
    sleep 2
done

# Drop existing database
log_info "Dropping existing database..."
docker compose exec -T postgres dropdb -U "$POSTGRES_USER" --if-exists "$POSTGRES_DB"
docker compose exec -T postgres createdb -U "$POSTGRES_USER" "$POSTGRES_DB"

# Restore database
log_info "Restoring database from backup..."
cat "$TEMP_DIR/database.dump" | docker compose exec -T postgres pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges
log_info "Database restored"

# Stop PostgreSQL container
log_info "Stopping PostgreSQL container..."
docker compose down
log_info "PostgreSQL container stopped"

# Restore n8n data directory
if [ -d "$TEMP_DIR/n8n_data" ]; then
    log_info "Restoring n8n data directory..."
    
    # Start n8n container with a temporary command to copy files
    log_info "Starting n8n container temporarily..."
    docker compose up -d n8n
    sleep 5
    
    # Copy n8n data
    log_info "Copying n8n data from backup..."
    docker compose cp "$TEMP_DIR/n8n_data/." n8n:/home/node/.n8n/
    
    # Stop n8n container
    log_info "Stopping n8n container..."
    docker compose down
    log_info "n8n data directory restored"
else
    log_warning "Skipping n8n data directory restoration as it was not found in the backup"
fi

# Start all services
log_info "Starting all services..."
docker compose up -d
log_info "Services started"

# Wait for n8n to be ready
log_info "Waiting for n8n to be ready..."
attempts=0
max_attempts=30
while [ $attempts -lt $max_attempts ]; do
    if curl -s http://localhost:5678/healthz &>/dev/null; then
        log_info "n8n is ready"
        break
    fi
    
    attempts=$((attempts + 1))
    if [ $attempts -eq $max_attempts ]; then
        log_error "n8n did not start properly after $max_attempts attempts"
        log_info "Check the logs with: docker compose logs n8n"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    echo -n "."
    sleep 2
done

# Cleanup temporary directory
rm -rf "$TEMP_DIR"
log_info "Temporary directory removed"

log_info "Restore completed successfully. n8n is now running with restored data."
log_info "You can access n8n at http://localhost:5678"
