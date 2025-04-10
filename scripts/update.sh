#!/bin/bash
# n8n Update Script
# Safely updates n8n and PostgreSQL to new versions

set -e

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
DOCKER_COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/update.log"

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
    echo "Usage: $0 [-n <n8n_version>] [-p <postgres_version>]"
    echo "Updates n8n and/or PostgreSQL to new versions"
    echo ""
    echo "  -n, --n8n VERSION       Update n8n to VERSION (e.g., 'latest', '1.0.0')"
    echo "  -p, --postgres VERSION  Update PostgreSQL to VERSION (e.g., '14.17-alpine')"
    echo "  -h, --help              Show this help message"
    exit 1
}

# Parse command line arguments
n8n_version=""
postgres_version=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--n8n)
            n8n_version="$2"
            shift 2
            ;;
        -p|--postgres)
            postgres_version="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Check if at least one version parameter is provided
if [ -z "$n8n_version" ] && [ -z "$postgres_version" ]; then
    log_error "No version parameters provided"
    show_usage
fi

# Create logs directory if it doesn't exist
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi

# Ensure log file exists
touch "$LOG_FILE"

log_info "Starting update process..."

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    log_error ".env file not found at $ENV_FILE"
    exit 1
fi

# Get current versions
current_n8n_version=$(docker compose -f "$DOCKER_COMPOSE_FILE" exec -T n8n node -e "console.log(require('@/package.json').version)" 2>/dev/null || echo "unknown")
current_postgres_version=$(docker compose -f "$DOCKER_COMPOSE_FILE" exec -T postgres postgres --version 2>/dev/null | awk '{print $3}' || echo "unknown")

# Get version from .env if not specified in command line
if [ -z "$n8n_version" ]; then
    n8n_version=${N8N_VERSION:-latest}
    log_info "Using n8n version from .env: $n8n_version"
fi

if [ -z "$postgres_version" ]; then
    postgres_version=${POSTGRES_VERSION:-14.17-alpine}
    log_info "Using PostgreSQL version from .env: $postgres_version"
fi

log_info "Current versions:"
log_info "  n8n: $current_n8n_version"
log_info "  PostgreSQL: $current_postgres_version"

log_info "Target versions:"
[ -n "$n8n_version" ] && log_info "  n8n: $n8n_version" || log_info "  n8n: unchanged"
[ -n "$postgres_version" ] && log_info "  PostgreSQL: $postgres_version" || log_info "  PostgreSQL: unchanged"

# Create backup before updating
log_info "Creating backup before updating..."
if [ -x "$BACKUP_SCRIPT" ]; then
    if ! "$BACKUP_SCRIPT"; then
        log_error "Failed to create backup. Update aborted."
        exit 1
    fi
    log_info "Backup created successfully"
else
    log_error "Backup script not found or not executable: $BACKUP_SCRIPT"
    exit 1
fi

# Update docker-compose.yml file
log_info "Updating docker-compose.yml file..."
TEMP_FILE=$(mktemp)

# Update n8n version if provided
if [ -n "$n8n_version" ]; then
    log_info "Updating n8n version to $n8n_version..."
    sed -E "s|(image: docker.n8n.io/n8nio/n8n:)[^[:space:]]+|\1$n8n_version|" "$DOCKER_COMPOSE_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$DOCKER_COMPOSE_FILE"
    log_info "n8n version updated in docker-compose.yml"
fi

# Update PostgreSQL version if provided
if [ -n "$postgres_version" ]; then
    log_info "Updating PostgreSQL version to $postgres_version..."
    
    # Major version upgrade check for PostgreSQL
    current_major=$(echo "$current_postgres_version" | cut -d. -f1)
    new_major=$(echo "$postgres_version" | cut -d. -f1)
    
    if [ "$current_major" != "$new_major" ] && [ "$current_major" != "unknown" ]; then
        log_warning "Major PostgreSQL version upgrade detected ($current_major -> $new_major)"
        log_warning "This requires additional steps and may not be compatible with your data"
        log_warning "It is recommended to create a full backup and perform a manual upgrade"
        
        read -p "Continue with the update? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Update aborted by user"
            exit 0
        fi
    fi
    
    sed -E "s|(image: postgres:)[^[:space:]]+|\1$postgres_version|" "$DOCKER_COMPOSE_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$DOCKER_COMPOSE_FILE"
    log_info "PostgreSQL version updated in docker-compose.yml"
fi

# Pull new Docker images
log_info "Pulling new Docker images..."
cd "$PROJECT_DIR"
docker compose pull
log_info "New Docker images pulled"

# Restart services
log_info "Restarting services..."
docker compose down
docker compose up -d
log_info "Services restarted"

# Verify successful update
log_info "Verifying update..."

# Wait for services to be ready
log_info "Waiting for services to be ready..."
sleep 10

# Check if n8n is running
if ! curl -s http://localhost:5678/healthz &>/dev/null; then
    log_error "n8n did not start properly after update"
    log_error "Check the logs with: docker compose logs n8n"
    log_error "Consider reverting to the previous version or restoring from backup"
    exit 1
fi

# Check if PostgreSQL is running
if ! docker compose exec postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" &>/dev/null; then
    log_error "PostgreSQL did not start properly after update"
    log_error "Check the logs with: docker compose logs postgres"
    log_error "Consider reverting to the previous version or restoring from backup"
    exit 1
fi

# Get new versions
new_n8n_version=$(docker compose exec -T n8n node -e "console.log(require('@/package.json').version)" 2>/dev/null || echo "unknown")
new_postgres_version=$(docker compose exec -T postgres postgres --version 2>/dev/null | awk '{print $3}' || echo "unknown")

log_info "Update completed successfully!"
log_info "New versions:"
log_info "  n8n: $new_n8n_version"
log_info "  PostgreSQL: $new_postgres_version"
log_info "You can access n8n at http://localhost:5678"
