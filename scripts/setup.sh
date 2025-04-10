#!/bin/bash
# n8n Setup Script
# This script checks for dependencies, validates environment variables,
# and initializes the n8n installation.

set -e

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
DOCKER_COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

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

check_dependencies() {
    log_info "Checking dependencies..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker and try again."
        exit 1
    fi
    log_info "✅ Docker found."
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed or not in PATH. Please install Docker Compose and try again."
        exit 1
    fi
    log_info "✅ Docker Compose found."
}

validate_env_file() {
    log_info "Validating environment file..."
    
    if [ ! -f "$ENV_FILE" ]; then
        log_error ".env file not found at $ENV_FILE"
        exit 1
    fi
    
    # Source the environment file
    source "$ENV_FILE"
    
    # Check required variables
    local required_vars=(
        "N8N_HOST"
        "N8N_PROTOCOL"
        "POSTGRES_DB"
        "POSTGRES_USER"
        "POSTGRES_PASSWORD"
        "N8N_ENCRYPTION_KEY"
        "TIMEZONE"
    )
    
    local missing_vars=0
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "$var is not set in .env file"
            missing_vars=$((missing_vars + 1))
        fi
    done
    
    if [ $missing_vars -gt 0 ]; then
        log_error "$missing_vars required variables are missing in .env file"
        exit 1
    fi
    
    # Check for default passwords
    if [ "$POSTGRES_PASSWORD" == "change_me_in_production" ]; then
        log_warning "Default PostgreSQL password detected. Generating a secure password..."
        POSTGRES_PASSWORD=$(openssl rand -base64 24)
        # Use a temporary file for the substitution to avoid issues with special characters
        sed "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
        log_info "PostgreSQL password updated."
    fi
    
    if [ "$N8N_ENCRYPTION_KEY" == "change_me_in_production_with_32+_characters" ]; then
        log_warning "Default encryption key detected. Generating a secure key..."
        N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
        # Use a temporary file for the substitution to avoid issues with special characters
        sed "s|N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY|" "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
        log_info "Encryption key updated."
    fi
    
    log_info "✅ Environment file validated."
}

create_directories() {
    log_info "Creating required directories..."
    
    # Create backup directory if it doesn't exist
    if [ ! -d "$PROJECT_DIR/backups" ]; then
        mkdir -p "$PROJECT_DIR/backups"
        log_info "Created backups directory."
    fi
    
    # Create logs directory if it doesn't exist
    if [ ! -d "$PROJECT_DIR/logs" ]; then
        mkdir -p "$PROJECT_DIR/logs"
        log_info "Created logs directory."
    fi
    
    # Set proper permissions
    chmod 700 "$PROJECT_DIR/backups"
    chmod 700 "$PROJECT_DIR/logs"
    chmod 600 "$ENV_FILE"
    
    log_info "✅ Directories created and permissions set."
}

start_services() {
    log_info "Starting services..."
    
    cd "$PROJECT_DIR"
    
    # Pull latest images
    docker compose pull
    
    # Start the services
    docker compose up -d
    
    log_info "✅ Services started."
}

verify_startup() {
    log_info "Verifying startup..."
    
    cd "$PROJECT_DIR"
    
    # Wait for n8n to be ready
    log_info "Waiting for n8n to be ready..."
    local attempts=0
    local max_attempts=30
    
    while [ $attempts -lt $max_attempts ]; do
        if curl -s http://localhost:5678/healthz &>/dev/null; then
            log_info "✅ n8n is running and ready!"
            break
        fi
        
        attempts=$((attempts + 1))
        if [ $attempts -eq $max_attempts ]; then
            log_error "n8n did not start properly after $max_attempts attempts."
            log_info "Check the logs with: docker compose logs n8n"
            exit 1
        fi
        
        echo -n "."
        sleep 2
    done
    
    # Check if PostgreSQL is ready
    if ! docker compose exec postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" &>/dev/null; then
        log_error "PostgreSQL did not start properly."
        log_info "Check the logs with: docker compose logs postgres"
        exit 1
    fi
    
    log_info "✅ PostgreSQL is running and ready!"
    log_info "✅ Verification complete. All services are running."
}

# Main execution
log_info "Starting n8n setup..."

check_dependencies
validate_env_file
create_directories
start_services
verify_startup

log_info "n8n setup complete! You can access n8n at http://localhost:5678"
log_info "Remember to keep your .env file secure as it contains sensitive information."
