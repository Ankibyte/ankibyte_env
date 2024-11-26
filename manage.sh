#!/usr/bin/env bash

# Strict error handling
set -eo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to display usage
usage() {
    cat << EOF
${GREEN}tempbyte Environment Management Script${NC}

Usage: $0 [environment] [command] [options]

Environments:
  dev           : Development environment
  prod          : Production environment

Commands:
  up             : Start the environment
  down           : Stop the environment
  logs [service] : View logs of a specific service
  exec           : Execute a command in a running container
  migrate        : Run database migrations
  makemigrations : Create new migration files
  shell          : Open a shell in a service
  restart        : Restart services
  status         : Show status of services
  clean          : Clean up Docker resources
  reset          : Reset the environment (removes volumes)
  init-db        : Initialize database
  test           : Run tests
  nuke           : Complete Docker reset (removes everything)
  fix-migrations : Fix migration issues

Options:
  -b, --build    : Build images before starting containers
  -f, --force    : Force operation without confirmation
  -h, --help     : Show this help message
EOF
    exit 1
}

# Function to log messages
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

# Function to get confirmation
get_confirmation() {
    local prompt="$1"
    local default="${2:-N}"
    
    if [ "$FORCE_FLAG" = "true" ]; then
        return 0
    fi
    
    echo -e "${YELLOW}$prompt [y/N]${NC}"
    read -r response
    case "${response:-$default}" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

# Function to check if database exists and is initialized
check_db_state() {
    log "INFO" "Checking database state..."
    if ! $DOCKER_COMPOSE exec -T db psql -U ankibyte_user -d ankibyte_dev -lqt | cut -d \| -f 1 | grep -qw "${POSTGRES_DB:-ankibyte_dev}"; then
        log "INFO" "Database does not exist. Creating..."
        return 1
    else
        log "INFO" "Database exists"
        return 0
    fi
}

# Function to wait for database
wait_for_db() {
    local max_attempts=30
    local attempt=1

    log "INFO" "Waiting for database to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if $DOCKER_COMPOSE exec -T db pg_isready -U ankibyte_user -d ankibyte_dev >/dev/null 2>&1; then
            log "SUCCESS" "Database is ready!"
            return 0
        fi
        echo -n "."
        sleep 1
        attempt=$((attempt + 1))
    done
    
    log "ERROR" "Database failed to become ready"
    return 1
}

# Function to handle database initialization and migrations
handle_database() {
    wait_for_db || return 1
    
    if ! check_db_state; then
        log "INFO" "Initializing fresh database..."
        $DOCKER_COMPOSE exec -T backend python manage.py migrate --noinput
    else
        log "INFO" "Checking migrations..."
        # Try to run migrations, if they fail, attempt to fake the initial migrations
        if ! $DOCKER_COMPOSE exec -T backend python manage.py migrate --noinput; then
            log "WARN" "Migration failed. Attempting to fix with --fake-initial..."
            $DOCKER_COMPOSE exec -T backend python manage.py migrate --fake-initial
        fi
    fi
}

# Function to clean up Docker resources
docker_cleanup() {
    log "INFO" "Performing Docker cleanup..."
    
    # Use docker compose down instead of direct Docker commands
    $DOCKER_COMPOSE down --remove-orphans 2>/dev/null || true
    
    log "SUCCESS" "Cleanup completed"
}

# Default settings
BUILD_FLAG=""
FORCE_FLAG=""
ENVIRONMENT=""

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        dev|prod)
            ENVIRONMENT="$1"
            shift
            ;;
        -b|--build)
            BUILD_FLAG="--build"
            shift
            ;;
        -f|--force)
            FORCE_FLAG="true"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            break
            ;;
    esac
done

# Set environment file
if [ "$ENVIRONMENT" = "dev" ]; then
    ENV_FILE=".env.development"
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.dev.yml"
else
    ENV_FILE=".env.production"
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.prod.yml"
fi

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    log "ERROR" "Environment file $ENV_FILE not found"
    exit 1
fi

# Define Docker Compose command
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose --env-file $ENV_FILE $COMPOSE_FILES"
else
    DOCKER_COMPOSE="docker compose --env-file $ENV_FILE $COMPOSE_FILES"
fi

# Process commands
case "${1:-help}" in
    up)
        log "INFO" "Starting $ENVIRONMENT environment..."
        
        # Start services
        if [ "$BUILD_FLAG" = "--build" ]; then
            $DOCKER_COMPOSE up -d --build --remove-orphans
        else
            $DOCKER_COMPOSE up -d --remove-orphans
        fi

        # Handle database setup
        if ! handle_database; then
            log "ERROR" "Database initialization failed"
            exit 1
        fi

        log "SUCCESS" "Environment started!"
        echo "Frontend: http://localhost:${FRONTEND_PORT:-3000}"
        echo "Backend: http://localhost:${BACKEND_PORT:-8000}"
        ;;
        
    down)
        if get_confirmation "Are you sure you want to stop the $ENVIRONMENT environment?"; then
            log "INFO" "Stopping $ENVIRONMENT environment..."
            $DOCKER_COMPOSE down --remove-orphans
            log "SUCCESS" "Environment stopped"
        fi
        ;;
        
    logs)
        if [ -z "${2:-}" ]; then
            $DOCKER_COMPOSE logs -f
        else
            $DOCKER_COMPOSE logs -f "$2"
        fi
        ;;
        
    exec)
        if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
            log "ERROR" "Please specify a service name and command"
            echo "Example: $0 $ENVIRONMENT exec backend python manage.py shell"
            exit 1
        fi
        shift
        $DOCKER_COMPOSE exec "$@"
        ;;
        
    migrate)
        log "INFO" "Running migrations..."
        wait_for_db
        $DOCKER_COMPOSE exec backend python manage.py migrate
        log "SUCCESS" "Migrations completed"
        ;;
        
    makemigrations)
        log "INFO" "Creating migrations..."
        if [ -z "${2:-}" ]; then
            $DOCKER_COMPOSE exec backend python manage.py makemigrations
        else
            $DOCKER_COMPOSE exec backend python manage.py makemigrations "$2"
        fi
        log "SUCCESS" "Migrations created"
        ;;
        
    shell)
        if [ -z "${2:-}" ]; then
            log "ERROR" "Please specify a service"
            exit 1
        fi
        $DOCKER_COMPOSE exec "$2" bash || $DOCKER_COMPOSE exec "$2" sh
        ;;
        
    restart)
        if [ -z "${2:-}" ]; then
            log "INFO" "Restarting all services..."
            $DOCKER_COMPOSE restart
        else
            log "INFO" "Restarting service $2..."
            $DOCKER_COMPOSE restart "$2"
        fi
        log "SUCCESS" "Restart completed"
        ;;
        
    status)
        $DOCKER_COMPOSE ps
        ;;
        
    clean)
        if get_confirmation "This will remove unused Docker resources. Continue?"; then
            docker_cleanup
            log "INFO" "Cleaning up Docker resources..."
            docker system prune -f
            log "SUCCESS" "Cleanup completed"
        fi
        ;;
        
    reset)
        if get_confirmation "This will remove all data and volumes. Are you sure?"; then
            log "INFO" "Resetting environment..."
            $DOCKER_COMPOSE down -v --remove-orphans
            log "SUCCESS" "Environment reset completed"
        fi
        ;;
        
    init-db)
        wait_for_db
        handle_database
        ;;
        
    test)
        log "INFO" "Running tests..."
        $DOCKER_COMPOSE exec backend python manage.py test
        log "SUCCESS" "Tests completed"
        ;;

    fix-migrations)
        log "INFO" "Attempting to fix migrations..."
        wait_for_db
        $DOCKER_COMPOSE exec backend python manage.py migrate --fake-initial
        log "SUCCESS" "Migration fix attempted"
        ;;
        
    nuke)
        if get_confirmation "⚠️  WARNING: This will remove ALL Docker containers, images, and volumes on your system. Are you absolutely sure?"; then
            log "INFO" "Starting complete Docker cleanup..."
    
            log "INFO" "Stopping all containers..."
            docker stop $(docker ps -a -q) 2>/dev/null || true
            
            log "INFO" "Removing all containers..."
            docker rm $(docker ps -a -q) 2>/dev/null || true
            
            log "INFO" "Removing all volumes..."
            docker volume rm $(docker volume ls -q) 2>/dev/null || true
            
            log "INFO" "Removing all images..."
            docker rmi $(docker images -q) 2>/dev/null || true
            
            log "INFO" "Cleaning build cache..."
            docker builder prune -f
            
            log "INFO" "Removing unused networks..."
            docker network prune -f
            
            log "INFO" "Final system cleanup..."
            docker system prune -a --volumes -f
            
            log "SUCCESS" "Docker environment completely reset!"
        fi
        ;;
        
    *)
        usage
        ;;
esac