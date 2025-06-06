#!/usr/bin/env bash
# MCP Health Check Script
# Updated: June 2025

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Required environment variables
REQUIRED_VARS=("MCP_HOST" "MCP_PORT")

# Load .env file if it exists
if [[ -f .env ]]; then
  echo "[INFO] Loading environment variables from .env"
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
  
  echo "[INFO] Loaded $ENV_COUNT environment variables"
fi

# Configuration with defaults
MCP_HOST="${MCP_HOST:-localhost}"
MCP_PORT="${MCP_PORT:-8811}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-/health}"
METRICS_ENDPOINT="${METRICS_ENDPOINT:-/metrics}"
TOOLS_ENDPOINT="${TOOLS_ENDPOINT:-/tools}"
TIMEOUT="${TIMEOUT:-10}"
CURL_OPTS="-fsSL --max-time ${TIMEOUT}"

# Colors for output
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Timestamp function
timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

# Log functions
log_info() {
  echo -e "$(timestamp) ${BLUE}INFO${NC}: $*"
}

log_success() {
  echo -e "$(timestamp) ${GREEN}SUCCESS${NC}: $*"
}

log_warn() {
  echo -e "$(timestamp) ${YELLOW}WARNING${NC}: $*"
}

log_error() {
  echo -e "$(timestamp) ${RED}ERROR${NC}: $*" >&2
}

# Print header
print_header() {
  echo -e "\n${BOLD}======================================${NC}"
  echo -e "${BOLD}🔍 MCP HEALTH CHECK - $(timestamp)${NC}"
  echo -e "${BOLD}======================================${NC}\n"
  log_info "Environment: MCP_HOST=$MCP_HOST, MCP_PORT=$MCP_PORT"
}

# Verify prerequisites
check_prerequisites() {
  log_info "Verifying prerequisites..."
  
  # Check if curl is installed
  if ! command -v curl &> /dev/null; then
    log_error "curl is required but not installed."
    return 1
  fi
  
  # Check if docker is installed
  if ! command -v docker &> /dev/null; then
    log_warn "docker command not found. Docker checks will be skipped."
  fi
  
  return 0
}

# Check if MCP server is responding
check_health() {
  local url="http://${MCP_HOST}:${MCP_PORT}${HEALTH_ENDPOINT}"
  log_info "Checking MCP server health at: $url"
  
  local response
  if response=$(curl $CURL_OPTS "$url" 2>&1); then
    log_success "MCP server is healthy"
    echo -e "  Response: ${response:-OK}"
    return 0
  else
    log_error "MCP server is not responding"
    echo -e "  Error: ${response:-Connection failed}"
    return 1
  fi
}

# Check MCP metrics
check_metrics() {
  local url="http://${MCP_HOST}:${MCP_PORT}${METRICS_ENDPOINT}"
  log_info "Checking MCP metrics at: $url"
  
  if curl $CURL_OPTS --head "$url" &> /dev/null; then
    log_success "MCP metrics endpoint is accessible"
    return 0
  else
    log_warn "MCP metrics endpoint not available"
    return 1
  fi
}

# Check Docker connectivity
check_docker() {
  log_info "Checking Docker connectivity..."
  
  if ! command -v docker &> /dev/null; then
    log_warn "Docker command not found, skipping check"
    return 0
  fi
  
  # First check current Docker context
  local docker_context=""
  if docker context ls &>/dev/null; then
    docker_context=$(docker context ls --format "{{.Name}} {{.Current}}" | grep "true" | awk '{print $1}')
    if [ -n "$docker_context" ]; then
      log_info "Current Docker context: $docker_context"
    fi
  fi
  
  # Try standard docker info check first
  if docker info &> /dev/null; then
    log_success "Docker is accessible"
  else
    # If that fails, try with desktop-linux context
    if [ "$docker_context" != "desktop-linux" ] && docker context use desktop-linux &>/dev/null; then
      if docker info &> /dev/null; then
        log_success "Docker is accessible in desktop-linux context"
      else
        # Try docker ps as a fallback check
        if docker ps &> /dev/null; then
          log_success "Docker is accessible (limited info)"
        else
          log_error "Docker is not accessible"
          return 1
        fi
      fi
    else
      # Try docker ps as a fallback check
      if docker ps &> /dev/null; then
        log_success "Docker is accessible (limited info)"
      else
        log_error "Docker is not accessible"
        return 1
      fi
    fi
  fi
  
  # Check if MCP containers are running
  local mcp_containers
  mcp_containers=$(docker ps --filter "name=mcp" --format "{{.Names}}" 2>/dev/null || echo "")
  if [ -n "$mcp_containers" ]; then
    log_success "MCP containers running:"
    echo "$mcp_containers" | while read -r container; do
      echo "  - $container"
    done
  else
    log_warn "No MCP containers found running"
  fi
  return 0
}

# Check MCP tools
check_tools() {
  local url="http://${MCP_HOST}:${MCP_PORT}${TOOLS_ENDPOINT}"
  log_info "Checking MCP tools at: $url"
  
  local response
  if response=$(curl $CURL_OPTS "$url" 2>/dev/null); then
    log_success "MCP tools are accessible"
    local tool_count
    tool_count=$(echo "$response" | grep -o "\"name\"" | wc -l)
    echo -e "  $tool_count tools available"
    return 0
  else
    log_warn "MCP tools endpoint not available"
    return 1
  fi
}

# Check Redis connection (if exposed)
check_redis() {
  log_info "Checking Redis connection..."
  
  if docker exec mcp-redis redis-cli -a "${REDIS_PASSWORD:-mcp}" ping &> /dev/null; then
    log_success "Redis is responsive"
    return 0
  else
    log_warn "Redis check failed (may not be directly accessible)"
    return 0  # Non-fatal error
  fi
}

# Check PostgreSQL connection (if exposed)
check_postgres() {
  log_info "Checking PostgreSQL connection..."
  
  if docker exec mcp-postgres pg_isready -U "${POSTGRES_USER:-mcp}" &> /dev/null; then
    log_success "PostgreSQL is responsive"
    return 0
  else
    log_warn "PostgreSQL check failed (may not be directly accessible)"
    return 0  # Non-fatal error
  fi
}

# Print summary
print_summary() {
  local exit_code=$1
  echo -e "\n${BOLD}======================================${NC}"
  if [ $exit_code -eq 0 ]; then
    echo -e "${GREEN}${BOLD}🎉 All critical health checks passed!${NC}"
  else
    echo -e "${RED}${BOLD}💥 Some health checks failed!${NC}"
    echo -e "${YELLOW}See details above for troubleshooting.${NC}"
  fi
  echo -e "${BOLD}======================================${NC}\n"
}

# Main health check function
main() {
  print_header
  
  local critical_error=0
  
  # Run checks
  check_prerequisites || critical_error=1
  
  # Only continue if prerequisites are met
  if [ $critical_error -eq 0 ]; then
    check_health || critical_error=1
    check_docker || critical_error=1
    check_tools || :  # Non-critical check
    check_metrics || :  # Non-critical check
    check_redis || :  # Non-critical check
    check_postgres || :  # Non-critical check
  fi
  
  # Print summary
  print_summary $critical_error
  
  return $critical_error
}

# Execute main function with arguments
main "$@"
