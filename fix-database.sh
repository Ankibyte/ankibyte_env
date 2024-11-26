#!/usr/bin/env bash

# Set strict error handling
set -eo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local color=""
    case "$level" in
        "INFO")    color="$BLUE";;
        "SUCCESS") color="$GREEN";;
        "WARN")    color="$YELLOW";;
        "ERROR")   color="$RED";;
    esac
    echo -e "${color}[$level] $message${NC}"
}

# Main fix function
fix_database() {
    log "INFO" "Starting database fix..."

    # Stop all containers
    log "INFO" "Stopping all containers..."
    docker compose down -v

    # Start containers
    log "INFO" "Starting containers..."
    docker compose up -d

    # Wait for services to be ready
    log "INFO" "Waiting for services to be ready..."
    sleep 15

    # Check if backend is running
    if ! docker ps | grep -q "ankibyte_env-backend-1"; then
        log "ERROR" "Backend container failed to start"
        docker logs ankibyte_env-backend-1
        return 1
    fi

    # Run migrations
    log "INFO" "Running migrations..."
    docker exec ankibyte_env-backend-1 python manage.py migrate --noinput || {
        log "WARN" "Standard migration failed, attempting with --fake-initial..."
        docker exec ankibyte_env-backend-1 python manage.py migrate --fake-initial
    }

    log "SUCCESS" "Database fix completed"
}

# Main execution
log "INFO" "Starting database fix process..."

if ! fix_database; then
    log "ERROR" "Database fix failed"
    exit 1
fi

log "SUCCESS" "Process completed successfully"
log "INFO" "You can now access:"
echo "Frontend: http://localhost:3000"
echo "Backend: http://localhost:8000"