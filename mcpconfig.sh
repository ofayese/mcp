#!/bin/bash
# MCP Environment Setup - Bash
# Compatible with Linux, macOS and WSL environments
set -e

echo "🔧 Preparing MCP environment..."

# Check Docker availability
if ! docker info > /dev/null 2>&1; then
  echo "❌ Docker is not running or not accessible!"
  echo "   Please start Docker and try again."
  exit 1
else
  DOCKER_VERSION=$(docker version --format "{{.Server.Version}}" 2>/dev/null || docker version | grep 'Server version' | cut -d':' -f2 | tr -d ' ')
  echo "✅ Docker is available (v$DOCKER_VERSION)"
fi

# Load .env file if it exists
if [ -f .env ]; then
  echo "🔑 Loading environment variables from .env"
  export $(grep -v '^#' .env | xargs)
fi
mkdir -p data logs cache init-db
for vol in mcp-data mcp-logs mcp-cache mcp-postgres-data; do
  if ! docker volume inspect "$vol" > /dev/null 2>&1; then
    echo "📦 Creating volume: $vol"
    docker volume create "$vol"
  else
    echo "✅ Volume exists: $vol"
  fi
done
if ! docker network inspect mcp-network > /dev/null 2>&1; then
  echo "🌐 Creating Docker network: mcp-network"
  docker network create --subnet=172.40.1.0/24 mcp-network
else
  echo "✅ Network exists: mcp-network"
fi

# Start Docker Compose
echo "🚀 Starting services with Docker Compose..."
docker-compose up -d

# Wait and check health
echo "⏳ Waiting for services to start..."
sleep 10

# Check health endpoint
if curl -s -f http://localhost:8811/health > /dev/null 2>&1; then
  echo "✅ MCP Server is healthy!"
else
  echo "❌ MCP Server is not responding!"
fi

echo "🎉 MCP environment setup complete."
