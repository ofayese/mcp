#!/usr/bin/env bash
# MCP Environment Setup - Bash
# Updated: June 2025
# Compatible with Linux, macOS and WSL environments

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Script constants
SCRIPT_VERSION="1.2.0"
MIN_DOCKER_VERSION="20.10.0"
REQUIRED_DIRS=("data" "logs" "cache" "init-db" "secrets")
REQUIRED_VOLUMES=("mcp-data" "mcp-logs" "mcp-cache")
MCP_NETWORK="mcp-network"
MCP_SUBNET="172.40.1.0/24"
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

compare_versions() {
  local version1=$1
  local version2=$2
  
  # Remove any non-numeric prefix/suffix
  version1=$(echo "$version1" | sed -E 's/[^0-9.].*$//')
  version2=$(echo "$version2" | sed -E 's/[^0-9.].*$//')
  
  if [[ "$version1" == "$version2" ]]; then
    return 0
  fi
  
  local IFS=.
  local i ver1=($version1) ver2=($version2)
  
  # Fill empty fields with zeros
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
    ver1[i]=0
  done
  for ((i=${#ver2[@]}; i<${#ver1[@]}; i++)); do
    ver2[i]=0
  done
  
  # Compare version numbers
  for ((i=0; i<${#ver1[@]}; i++)); do
    if [[ -z ${ver2[i]} ]]; then
      # If ver2 is shorter, and ver1 still has elements, ver1 is greater
      return 1
    fi
    
    if ((10#${ver1[i]} > 10#${ver2[i]})); then
      return 1
    fi
    
    if ((10#${ver1[i]} < 10#${ver2[i]})); then
      return 2
    fi
  done
  
  return 0
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
echo -e "${CYAN}${BOLD}│ MCP Environment Setup v${SCRIPT_VERSION}        │${NC}"
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
  
  # Check minimum Docker version
  compare_versions "$DOCKER_VERSION" "$MIN_DOCKER_VERSION"
  VERSION_COMPARE=$?
  
  if [[ $VERSION_COMPARE -eq 2 ]]; then
    log_message "Docker version $DOCKER_VERSION is below minimum required version $MIN_DOCKER_VERSION" "WARNING"
    log_message "Some features may not work correctly. Consider upgrading Docker." "WARNING"
  fi
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

# Pull images before starting
log_message "Pulling Docker images (this may take a few minutes)..." "INFO"
if ! $COMPOSE_CMD pull > /dev/null 2>&1; then
  log_message "Warning: Some images could not be pulled. Continuing with local images if available." "WARNING"
else
  log_message "Images pulled successfully" "SUCCESS"
fi

# Start Docker Compose
log_message "Starting services with Docker Compose..." "INFO"
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
