#!/bin/bash
# Secure MCP Setup Bootstrap Script
# Cross-platform (Linux, macOS, WSL)

set -e

echo "🔐 Secure MCP Setup Initializing..."

# Ensure Docker is available
if ! docker info > /dev/null 2>&1; then
  echo "❌ Docker is not running. Please start Docker and retry."
  exit 1
fi

# Export .env variables
if [ -f ".env" ]; then
  echo "📄 Loading .env..."
  export $(grep -v '^#' .env | xargs)
else
  echo "⚠️ .env file not found!"
  exit 1
fi

# Create required directories
for dir in data logs cache init-db; do
  [ ! -d "$dir" ] && mkdir -p "$dir" && echo "📁 Created $dir"
done

# Create Docker volumes if missing
for vol in mcp-data mcp-logs mcp-cache mcp-postgres-data; do
  if ! docker volume inspect "$vol" >/dev/null 2>&1; then
    docker volume create "$vol" >/dev/null
    echo "📦 Volume created: $vol"
  fi
done

# Create Docker network if missing
if ! docker network inspect "$MCP_NETWORK" >/dev/null 2>&1; then
  docker network create --subnet=$MCP_SUBNET $MCP_NETWORK
  echo "🌐 Docker network created: $MCP_NETWORK"
fi

# Generate secrets.yaml from environment vars
echo "🔑 Generating secrets.yaml..."
mkdir -p ${HOME}/.docker/mcp
cat > ${HOME}/.docker/mcp/secrets.yaml << EOF
# MCP Secrets Configuration - Generated $(date)
github:
  personal_access_token: "${GITHUB_TOKEN}"

gitlab:
  personal_access_token: "${GITLAB_TOKEN}"

sentry:
  auth_token: "${SENTRY_TOKEN}"
EOF

# Start Docker Compose stack
echo "🚀 Starting MCP stack..."
docker-compose up -d

# Wait and check health
sleep 8
curl -fs http://localhost:8811/health && echo "✅ MCP is healthy!" || echo "❌ MCP health check failed."
