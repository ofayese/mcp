# MCP Docker Setup

A production-ready, secure Dockerized setup for MCP (Model Context Protocol) with Redis, PostgreSQL, and Traefik reverse proxy.

[![Docker Version](https://img.shields.io/badge/docker-%3E%3D20.10.0-blue)](https://www.docker.com/)
[![Docker Compose](https://img.shields.io/badge/docker--compose-v2-green)](https://docs.docker.com/compose/)
[![License](https://img.shields.io/badge/license-MIT-brightgreen)](LICENSE)

## 📦 Features

- **Security Hardening**: Enhanced security with rate limiting, TLS configuration, and no-new-privileges constraints
- **Health Monitoring**: Comprehensive health checks for all services
- **Auto Recovery**: Automatic restart policies and dependency handling
- **Multi-Platform**: Support for Windows, Linux, and macOS
- **Resource Management**: Configurable resource constraints
- **Secret Management**: Secure handling of API tokens and credentials

## 🔧 Components

| Component | Description | Version |
|-----------|-------------|---------|
| MCP Server | Core Model Context Protocol service | latest |
| PostgreSQL | Database for persistent storage | 16-alpine |
| Redis | In-memory cache and message broker | 7.2-alpine |
| Traefik | Modern reverse proxy and load balancer | v3.0 |

## 📋 Requirements

- Docker Engine 20.10.0 or later
- Docker Compose v2 or later (or docker-compose 1.29+)
- 2GB RAM minimum (4GB recommended)
- 10GB disk space

## 🚀 Quick Start

### Windows

```powershell
# One-click setup
.\quick-setup.bat

# Or run PowerShell setup directly
.\mcpconfig.ps1
```

### Linux/macOS

```bash
# Make scripts executable
chmod +x mcpconfig.sh health-check.sh

# Run setup
./mcpconfig.sh
```

## 🩺 Health Checks

Run the included health check scripts to verify your setup:

**Windows:**
```cmd
health-check.bat
```

**Linux/macOS:**
```bash
./health-check.sh
```

## 🛠️ Configuration

The setup is preconfigured for immediate use, but can be customized through:

- `.env` - Environment variables
- `config.yaml` - MCP Server configuration
- `registry.yaml` - MCP tools registry
- `traefik.yml` & `traefik_dynamic.yml` - Traefik configuration

## 🔐 Secrets Management

Secrets are stored in the `secrets/` directory and mounted securely into containers:

```
secrets/
├── github_token
├── github.personal_access_token
├── gitlab_token
├── sentry.auth_token
└── ...
```

Each file should contain only the token value with no formatting or additional text.

## 🔄 Autostart (Linux/systemd)

To enable auto-start using `systemd`:

1. Copy the provided `mcp.service` file to systemd:
```bash
sudo cp mcp.service /etc/systemd/system/
```

2. Edit the file to set your correct user path:
```bash
sudo nano /etc/systemd/system/mcp.service
```

3. Enable and start the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable mcp
sudo systemctl start mcp
```

## 🧪 Troubleshooting

### Checking Logs

```bash
# MCP server logs
docker logs mcp-server

# All MCP-related container logs
docker logs mcp-postgres
docker logs mcp-redis
docker logs mcp-traefik
```

### Common Issues

| Problem | Solution |
|---------|----------|
| Cannot connect to MCP | Check Docker is running and ports are not in use |
| PostgreSQL errors | Check volume permissions and database credentials |
| Network issues | Verify the mcp-network exists and subnet is available |
| Missing secrets | Create the required token files in the secrets directory |

## 🧹 Cleanup

Remove containers and volumes:

```bash
# Stop and remove containers
docker-compose down

# Remove volumes (WARNING: this deletes all data)
docker-compose down -v

# For complete cleanup
docker volume rm mcp-data mcp-logs mcp-cache
```

## 📊 Access Points

- MCP Server: http://localhost:8811
- Traefik Dashboard: http://localhost:8080
- MCP API Documentation: http://localhost:8811/docs
