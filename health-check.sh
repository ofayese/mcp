# MCP Health Check Script
#!/bin/bash

# Configuration
MCP_HOST="${MCP_HOST:-localhost}"
MCP_PORT="${MCP_PORT:-8811}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-/health}"
TIMEOUT="${TIMEOUT:-10}"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 MCP Health Check Starting..."

# Check if MCP server is responding
check_health() {
    local url="http://${MCP_HOST}:${MCP_PORT}${HEALTH_ENDPOINT}"
    echo "📡 Checking MCP server at: $url"
    
    if curl -f -s --max-time "$TIMEOUT" "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ MCP server is healthy${NC}"
        return 0
    else
        echo -e "${RED}❌ MCP server is not responding${NC}"
        return 1
    fi
}

# Check Docker connectivity
check_docker() {
    echo "🐳 Checking Docker connectivity..."
    if docker ps > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Docker is accessible${NC}"
        return 0
    else
        echo -e "${RED}❌ Docker is not accessible${NC}"
        return 1
    fi
}

# Check MCP tools
check_tools() {
    echo "🛠️ Checking MCP tools..."
    local url="http://${MCP_HOST}:${MCP_PORT}/tools"
    
    if curl -f -s --max-time "$TIMEOUT" "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ MCP tools are accessible${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️ MCP tools endpoint not available${NC}"
        return 1
    fi
}

# Main health check
main() {
    local exit_code=0
    
    check_health || exit_code=1
    check_docker || exit_code=1
    check_tools || exit_code=1
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}🎉 All health checks passed!${NC}"
    else
        echo -e "${RED}💥 Some health checks failed!${NC}"
    fi
    
    return $exit_code
}

main "$@"