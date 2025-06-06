#!/usr/bin/env bash
# MCP Unified Setup Script for Linux/macOS
# Updated: June 2025
# Combines functionality of setup.sh and mcpconfig.sh
# Cross-platform (Linux, macOS, WSL)

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Parse command line arguments
QUICK_MODE=false
SKIP_CHECKS=false

function show_help {
  echo ""
  echo "MCP Setup Script - Usage:"
  echo "setup.sh [options]"
  echo ""
  echo "Options:"
  echo "  -q, --quick    Quick setup mode (skips some confirmations)"
  echo "  -y, --yes      Skip all confirmations and checks"
  echo "  -h, --help     Show this help message"
  echo ""
  exit 0
}

# Process command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -q|--quick)
      QUICK_MODE=true
      shift
      ;;
    -y|--yes)
      SKIP_CHECKS=true
      shift
      ;;
    -h|--help)
      show_help
      ;;
    *)
      echo "Unknown parameter: $1"
      show_help
      ;;
  esac
done

# Script constants
SCRIPT_VERSION="1.2.0"
MIN_DOCKER_VERSION="20.10.0"
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

compare_versions() {
  local version1=$1
  local version2=$2
  
  # Use sort -V for version comparison
  # Sort both versions and check if the minimum version comes first
  if [ "$(printf '%s\n' "$version1" "$version2" | sort -V | head -n1)" = "$version2" ]; then
    # version1 >= version2
    return 1
  elif [ "$version1" = "$version2" ]; then
    # version1 = version2
    return 0
  else
    # version1 < version2
    return 2
  fi
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

check_env_vars() {
  log_message "🔍 Checking required environment variables..." "INFO"
  required=(
    "COMPOSE_PROJECT_NAME"
    "COMPOSE_FILE"
    "MCP_HOST"
    "MCP_PORT"
    "MCP_NETWORK"
    "MCP_SUBNET"
    "MCP_DATA_DIR"
    "MCP_CACHE_DIR"
    "MCP_CONFIG_PATH"
    "MCP_SECRETS_PATH"
    "MCP_REGISTRY_PATH"
    "POSTGRES_DB"
    "POSTGRES_USER"
    "POSTGRES_PASSWORD"
    "REDIS_PASSWORD"
  )
  
  missing=()
  for var in "${required[@]}"; do
    if [[ -z "${!var-}" ]]; then
      missing+=("$var")
    fi
  done
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_message "❌ Missing required environment variables:" "ERROR"
    for var in "${missing[@]}"; do
      log_message "   - $var" "ERROR"
    done
    
    if [[ "$SKIP_CHECKS" == "false" ]]; then
      echo "Missing required environment variables. Please check your .env file."
      return 1
    else
      log_message "Continuing despite missing variables because --yes was specified." "WARNING"
    fi
  else
    log_message "✅ All required environment variables present." "SUCCESS"
  fi
  
  return 0
}

# Print header
if [[ "$QUICK_MODE" == "true" ]]; then
  echo -e "\n${CYAN}${BOLD}┌─────────────────────────────────────────┐${NC}"
  echo -e "${CYAN}${BOLD}│ MCP Quick Setup v${SCRIPT_VERSION}              │${NC}"
  echo -e "${CYAN}${BOLD}│ $(date "+%Y-%m-%d %H:%M:%S")                 │${NC}"
  echo -e "${CYAN}${BOLD}└─────────────────────────────────────────┘${NC}\n"
else
  echo -e "\n${CYAN}${BOLD}┌─────────────────────────────────────────┐${NC}"
  echo -e "${CYAN}${BOLD}│ MCP Secure Setup v${SCRIPT_VERSION}             │${NC}"
  echo -e "${CYAN}${BOLD}│ $(date "+%Y-%m-%d %H:%M:%S")                 │${NC}"
  echo -e "${CYAN}${BOLD}└─────────────────────────────────────────┘${NC}\n"
fi

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

# Prompt for confirmation in full mode
if [[ "$QUICK_MODE" == "false" && "$SKIP_CHECKS" == "false" ]]; then
  echo ""
  echo "This script will:"
  echo " • Set up Docker volumes and networks"
  echo " • Create required directories with secure permissions"
  echo " • Configure environment variables"
  echo " • Start MCP containers"
  echo ""
  read -p "Continue with setup? [Y/n]: " CONFIRM
  if [[ "$CONFIRM" == "n" || "$CONFIRM" == "N" ]]; then
    echo "Setup cancelled by user."
    exit 0
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
      # Extract name and value, trim whitespace
      name="${BASH_REMATCH[1]}"
      name="$(echo "$name" | xargs)"
      
      value="${BASH_REMATCH[2]}"
      # Remove trailing comments if any
      if [[ "$value" =~ ^([^#]+)# ]]; then
        value="${BASH_REMATCH[1]}"
      fi
      value="$(echo "$value" | xargs)"
      
      export "$name=$value"
      ENV_COUNT=$((ENV_COUNT + 1))
    fi
  done < .env
  
  log_message "Loaded $ENV_COUNT environment variables" "SUCCESS"
  
  # Validate required environment variables
  check_env_vars || exit 1
else
  log_message ".env file not found. Using default values." "WARNING"
  
  # Set default values for required variables
  declare -A defaults
  defaults=(
    ["COMPOSE_PROJECT_NAME"]="mcp"
    ["COMPOSE_FILE"]="docker-compose.yml"
    ["MCP_HOST"]="0.0.0.0"
    ["MCP_PORT"]="8811"
    ["MCP_NETWORK"]="mcp-network"
    ["MCP_SUBNET"]="172.40.1.0/24"
    ["MCP_DATA_DIR"]="./data"
    ["MCP_CACHE_DIR"]="./cache"
    ["MCP_CONFIG_PATH"]="$(pwd)/config.yaml"
    ["MCP_SECRETS_PATH"]="$(pwd)/secrets"
    ["MCP_REGISTRY_PATH"]="$(pwd)/registry.yaml"
    ["POSTGRES_DB"]="mcp"
    ["POSTGRES_USER"]="mcp"
    ["POSTGRES_PASSWORD"]="mcp_password"
    ["REDIS_PASSWORD"]="mcp"
  )
  
  for key in "${!defaults[@]}"; do
    if [[ -z "${!key-}" ]]; then
      export "$key=${defaults[$key]}"
      log_message "Set default for $key = ${defaults[$key]}" "INFO"
    fi
  done
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
if [[ -n "${GITHUB_TOKEN-}" ]]; then
  echo "$GITHUB_TOKEN" > "secrets/github.personal_access_token"
  chmod 600 "secrets/github.personal_access_token"
  log_message "Created GitHub token file" "SUCCESS"
fi

# GitHub Personal Access Token
if [[ -n "${GITHUB_PAT-}" ]]; then
  echo "$GITHUB_PAT" > "secrets/github.personal_access_token"
  chmod 600 "secrets/github.personal_access_token"
  log_message "Created GitHub PAT file" "SUCCESS"
fi

# GitLab token
if [[ -n "${GITLAB_TOKEN-}" ]]; then
  echo "$GITLAB_TOKEN" > "secrets/gitlab.personal_access_token"
  chmod 600 "secrets/gitlab.personal_access_token"
  log_message "Created GitLab token file" "SUCCESS"
fi

# Sentry token
if [[ -n "${SENTRY_TOKEN-}" ]]; then
  echo "$SENTRY_TOKEN" > "secrets/sentry.auth_token"
  chmod 600 "secrets/sentry.auth_token"
  log_message "Created Sentry token file" "SUCCESS"
fi

# GitHub Chat API key
if [[ -n "${GITHUB_CHAT_API_KEY-}" ]]; then
  echo "$GITHUB_CHAT_API_KEY" > "secrets/github-chat.api_key"
  chmod 600 "secrets/github-chat.api_key"
  log_message "Created GitHub Chat API key file" "SUCCESS"
fi

# PostgreSQL password
if [[ -n "${POSTGRES_PASSWORD-}" ]]; then
  echo "$POSTGRES_PASSWORD" > "secrets/postgres_password.txt"
  chmod 600 "secrets/postgres_password.txt"
  log_message "Created PostgreSQL password file" "SUCCESS"
fi

log_message "Secrets setup complete" "SUCCESS"

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

# Run detailed health check
log_message "Running detailed health check..." "INFO"
if [[ -f "./health-check.sh" ]]; then
  bash ./health-check.sh
else
  log_message "health-check.sh not found. Skipping detailed health check." "WARNING"
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
