#!/usr/bin/env bash
# MCP Secure Setup Script for Linux/macOS
# Updated: June 2025
# Cross-platform (Linux, macOS, WSL)

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Script constants
SCRIPT_VERSION="1.2.0"
REQUIRED_DIRS=("data" "logs" "cache" "init-db" "secrets")
REQUIRED_VOLUMES=("mcp-data" "mcp-logs" "mcp-cache")
HEALTH_CHECK_URL="http://localhost:8811/health"
HEALTH_CHECK_TIMEOUT=30  # seconds

# Colors for output
BOLD="\033[1m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

# Start timer
START_TIME=$(date +%s)

# Helper functions
format_elapsed_time() {
  local elapsed=$1
  local hours=$((elapsed / 3600))
  local minutes=$(((elapsed % 3600) / 60))
  local seconds=$((elapsed % 60))
  printf "%02d:%02d:%02d" $hours $minutes $seconds
}

log_message() {
  local type=${2:-"INFO"}
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  case $type in
    "INFO")
      echo -e "[$timestamp] ${BLUE}${type}${NC}: $1"
      ;;
    "SUCCESS")
      echo -e "[$timestamp] ${GREEN}${type}${NC}: $1"
      ;;
    "WARNING")
      echo -e "[$timestamp] ${YELLOW}${type}${NC}: $1"
      ;;
    "ERROR")
      echo -e "[$timestamp] ${RED}${type}${NC}: $1" >&2
      ;;
    *)
      echo -e "[$timestamp] ${type}: $1"
      ;;
  esac
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

create_secure_directory() {
  local dir=$1
  
  if [[ ! -d "$dir" ]]; then
    log_message "Creating directory: $dir" "INFO"
    mkdir -p "$dir"
    
    # Set more restrictive permissions
    chmod 750 "$dir"
    log_message "Secured directory permissions: $dir" "SUCCESS"
  else
    log_message "Directory exists: $dir" "SUCCESS"
  fi
}

# Print header
echo -e "\n${CYAN}${BOLD}┌─────────────────────────────────────────┐${NC}"
echo -e "${CYAN}${BOLD}│ MCP Secure Setup v${SCRIPT_VERSION}             │${NC}"
echo -e "${CYAN}${BOLD}│ $(date "+%Y-%m-%d %H:%M:%S")                 │${NC}"
echo -e "${CYAN}${BOLD}└─────────────────────────────────────────┘${NC}\n"

# Check for Bash version
BASH_VERSION_MAJOR=${BASH_VERSION%%.*}
if [[ $BASH_VERSION_MAJOR -lt 4 ]]; then
  log_message "Your Bash version ($BASH_VERSION) is outdated. Some features may not work correctly." "WARNING"
fi

# Check Docker availability
if ! command_exists docker; then
  log_message "Docker is not installed or not in PATH!" "ERROR"
  log_message "Please install Docker and try again." "ERROR"
  exit 1
fi

if ! docker info > /dev/null 2>&1; then
  log_message "Docker is not running or not accessible!" "ERROR"
  log_message "Please start Docker and try again." "ERROR"
  exit 1
else
  DOCKER_VERSION=$(docker version --format "{{.Server.Version}}" 2>/dev/null || docker version | grep -E 'Server:.*version' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  log_message "Docker is available (v$DOCKER_VERSION)" "SUCCESS"
fi

# Load .env file if it exists
if [[ -f .env ]]; then
  log_message "Loading environment variables from .env" "INFO"
  ENV_COUNT=0
  
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue
    
    # Export variable if it contains =
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
      ENV_COUNT=$((ENV_COUNT + 1))
    fi
  done < .env
  
  log_message "Loaded $ENV_COUNT environment variables" "SUCCESS"
else
  log_message ".env file not found. Using default values." "WARNING"
  # Set defaults for required variables
  export MCP_NETWORK=${MCP_NETWORK:-mcp-network}
  export MCP_SUBNET=${MCP_SUBNET:-172.40.1.0/24}
fi

# Ensure directories exist with proper permissions
log_message "Setting up directories..." "INFO"
for dir in "${REQUIRED_DIRS[@]}"; do
  create_secure_directory "$dir"
done

# Create Docker volumes if missing
log_message "Setting up Docker volumes..." "INFO"
for volume in "${REQUIRED_VOLUMES[@]}"; do
  if docker volume inspect "$volume" > /dev/null 2>&1; then
    log_message "Volume exists: $volume" "SUCCESS"
  else
    if docker volume create "$volume" > /dev/null; then
      log_message "Created volume: $volume" "SUCCESS"
    else
      log_message "Failed to create volume: $volume" "ERROR"
      exit 1
    fi
  fi
done

# Create network if not exists
log_message "Setting up Docker network..." "INFO"
if docker network inspect "$MCP_NETWORK" > /dev/null 2>&1; then
  log_message "Network exists: $MCP_NETWORK" "SUCCESS"
else
  if docker network create --subnet="$MCP_SUBNET" "$MCP_NETWORK" > /dev/null; then
    log_message "Created network: $MCP_NETWORK ($MCP_SUBNET)" "SUCCESS"
  else
    log_message "Failed to create network: $MCP_NETWORK" "ERROR"
    exit 1
  fi
fi

# Set up secrets from environment variables
log_message "Setting up secrets..." "INFO"

# Create secrets directory if it doesn't exist
if [[ ! -d "secrets" ]]; then
  mkdir -p "secrets"
  chmod 700 "secrets"
  log_message "Created and secured secrets directory" "SUCCESS"
fi

# GitHub token
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  echo "$GITHUB_TOKEN" > "secrets/github_token"
  chmod 600 "secrets/github_token"
  log_message "Created GitHub token file" "SUCCESS"
fi

# GitHub Personal Access Token
if [[ -n "${GITHUB_PAT:-}" ]]; then
  echo "$GITHUB_PAT" > "secrets/github.personal_access_token"
  chmod 600 "secrets/github.personal_access_token"
  log_message "Created GitHub PAT file" "SUCCESS"
fi

# GitLab token
if [[ -n "${GITLAB_TOKEN:-}" ]]; then
  echo "$GITLAB_TOKEN" > "secrets/gitlab_token"
  chmod 600 "secrets/gitlab_token"
  log_message "Created GitLab token file" "SUCCESS"
fi

# Sentry token
if [[ -n "${SENTRY_TOKEN:-}" ]]; then
  echo "$SENTRY_TOKEN" > "secrets/sentry.auth_token"
  chmod 600 "secrets/sentry.auth_token"
  log_message "Created Sentry token file" "SUCCESS"
fi

# GitHub Chat API key
if [[ -n "${GITHUB_CHAT_API_KEY:-}" ]]; then
  echo "$GITHUB_CHAT_API_KEY" > "secrets/github-chat.api_key"
  chmod 600 "secrets/github-chat.api_key"
  log_message "Created GitHub Chat API key file" "SUCCESS"
fi

log_message "Secrets setup complete" "SUCCESS"

# Check for docker-compose availability
if command_exists docker-compose; then
  COMPOSE_CMD="docker-compose"
elif docker compose version > /dev/null 2>&1; then
  log_message "Using 'docker compose' plugin instead of docker-compose" "INFO"
  COMPOSE_CMD="docker compose"
else
  log_message "Neither docker-compose nor docker compose plugin is available" "ERROR"
  log_message "Please install Docker Compose and try again" "ERROR"
  exit 1
fi

# Start Docker Compose
log_message "Starting MCP stack with $COMPOSE_CMD..." "INFO"
if $COMPOSE_CMD up -d; then
  log_message "Services started successfully" "SUCCESS"
else
  log_message "Failed to start services" "ERROR"
  exit 1
fi

# Wait and run health check
log_message "Waiting for services to initialize (${HEALTH_CHECK_TIMEOUT}s timeout)..." "INFO"

HEALTH_START_TIME=$(date +%s)
HEALTHY=false

while (( $(date +%s) - HEALTH_START_TIME < HEALTH_CHECK_TIMEOUT )); do
  if curl -s -f "$HEALTH_CHECK_URL" > /dev/null 2>&1; then
    HEALTHY=true
    break
  fi
  
  # Progress indicator
  echo -n "." >&2
  sleep 2
done

echo "" # New line after progress dots

if $HEALTHY; then
  HEALTH_ELAPSED=$(($(date +%s) - HEALTH_START_TIME))
  log_message "MCP Server is healthy! (Time: ${HEALTH_ELAPSED}s)" "SUCCESS"
else
  log_message "MCP Server did not respond within timeout period (${HEALTH_CHECK_TIMEOUT} seconds)" "WARNING"
  log_message "Run './health-check.sh' to troubleshoot or check container logs with 'docker logs mcp-server'" "INFO"
fi

# Display service info
log_message "Checking service status..." "INFO"
CONTAINERS=$(docker ps --filter "name=mcp" --format "{{.Names}}: {{.Status}}" 2>/dev/null)

if [[ -n "$CONTAINERS" ]]; then
  echo -e "\nService Status:"
  echo "$CONTAINERS" | while IFS= read -r container; do
    if [[ "$container" =~ "Up " ]]; then
      echo -e "  ${GREEN}✅ $container${NC}"
    else
      echo -e "  ${RED}❌ $container${NC}"
    fi
  done
else
  log_message "Could not retrieve container status" "WARNING"
fi

# Script completion
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo -e "\n${GREEN}${BOLD}┌─────────────────────────────────────────┐${NC}"
echo -e "${GREEN}${BOLD}│ Setup completed in $(format_elapsed_time $ELAPSED)            │${NC}"
echo -e "${GREEN}${BOLD}└─────────────────────────────────────────┘${NC}"

echo -e "\n${CYAN}MCP Access Points:${NC}"
echo -e "  • MCP Server: http://localhost:8811"
echo -e "  • Traefik Dashboard: http://localhost:8080"

if ! $HEALTHY; then
  echo -e "\n${YELLOW}NOTE: MCP may still be initializing. Run './health-check.sh' to verify status.${NC}"
fi

echo -e "\n${CYAN}For troubleshooting, use: 'docker logs mcp-server'${NC}"
