#!/bin/bash
# A simple test script to check if n8n is working

set -e

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
TEST_LOG="$LOG_DIR/test.log"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create logs directory if it doesn't exist
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi

# Ensure log file exists
touch "$TEST_LOG"

# Logging function
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$TEST_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$TEST_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$TEST_LOG"
}

# Main test function
run_tests() {
    log_info "Starting n8n tests..."
    
    # Test 1: Check if containers are running
    log_info "Test 1: Checking if containers are running..."
    if [ "$(docker ps -q -f name=n8n-project-n8n-1)" ] && [ "$(docker ps -q -f name=n8n-project-postgres-1)" ]; then
        log_info "✅ Both containers are running."
    else
        log_error "❌ One or both containers are not running."
        exit 1
    fi
    
    # Test 2: Check if PostgreSQL is responding
    log_info "Test 2: Checking PostgreSQL connection..."
    if docker exec n8n-project-postgres-1 pg_isready -U n8n_user -d n8n; then
        log_info "✅ PostgreSQL is running and responsive."
    else
        log_error "❌ PostgreSQL is not responding."
        exit 1
    fi
    
    # Test 3: Check if n8n is responding
    log_info "Test 3: Checking n8n health endpoint..."
    if curl -s http://localhost:5678/healthz > /dev/null; then
        log_info "✅ n8n is running and responsive."
    else
        log_error "❌ n8n health endpoint is not responding."
        exit 1
    fi
    
    # Test 4: Verify the n8n web UI is accessible
    log_info "Test 4: Checking n8n web UI..."
    if curl -s http://localhost:5678 | grep -q "n8n"; then
        log_info "✅ n8n web UI is accessible."
    else
        log_error "❌ n8n web UI is not accessible."
        exit 1
    fi
    
    # Test 5: Test backup script
    log_info "Test 5: Testing backup script..."
    if "$PROJECT_DIR/scripts/backup.sh"; then
        log_info "✅ Backup script executed successfully."
        
        # Check if backup file was created
        LATEST_BACKUP=$(ls -t "$PROJECT_DIR/backups/n8n_backup_"*.tar.gz 2>/dev/null | head -1)
        if [ -n "$LATEST_BACKUP" ]; then
            log_info "✅ Backup file created: $(basename "$LATEST_BACKUP")"
        else
            log_error "❌ No backup file was created."
            exit 1
        fi
    else
        log_error "❌ Backup script failed."
        exit 1
    fi
    
    log_info "All tests completed successfully! n8n setup is verified and working."
}

# Run the tests
run_tests
