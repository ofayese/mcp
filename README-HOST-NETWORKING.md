# MCP Host Networking Architecture

*Updated: June 2025*

## Overview

This MCP deployment has been completely restructured to use **Docker Host Networking** for maximum performance and simplified connectivity. All services now bind directly to localhost, eliminating Docker networking overhead and port mapping complexity.

## Architecture Changes

### Network Configuration

- **Previous**: Bridge networking with `172.40.1.0/24` subnet
- **Current**: Host networking with direct localhost binding
- **Benefits**: No NAT overhead, direct localhost access, simplified connectivity

### Service Names

All services have been renamed with the `dhv01mcp` prefix:

- `mcp-server` → `dhv01mcp`
- `mcp-postgres` → `dhv01mcp-postgres`
- `mcp-redis` → `dhv01mcp-redis`
- `mcp-traefik` → `dhv01mcp-traefik`

### Port Allocation

| Service | Port | Access URL |
|---------|------|------------|
| MCP Server | 8811 | <http://localhost:8811> |
| MCP Secondary | 8812 | <http://localhost:8812> |
| PostgreSQL | 5432 | localhost:5432 |
| Redis | 6379 | localhost:6379 |
| Traefik HTTP | 80 | <http://localhost:80> |
| Traefik Dashboard | 8080 | <http://localhost:8080> |
| SSH Gateway | 2222 | ssh://localhost:2222 |

## Security Features

### Dynamic Port Management

- **Automatic port conflict detection**
- **Dynamic port reassignment** if conflicts found
- **Environment file updates** with discovered ports

### Firewall Automation

- **Windows Defender integration**
- **Localhost-only rules** (127.0.0.1 binding)
- **Automatic rule lifecycle management**
- **Admin privilege detection**

### Security Scripts

- `port-scanner.ps1` - Port availability checking
- `firewall-manager.ps1` - Firewall rule management
- `cleanup.bat` - Complete service and security cleanup

## Quick Start

### Setup

```batch
# Basic setup with automatic port detection
setup.bat

# Quick mode (minimal prompts)
setup.bat -q

# Automatic mode (no confirmations)
setup.bat -y
```

### Health Check

```batch
# Check all services
health-check.bat
```

### Cleanup

```batch
# Complete cleanup including firewall rules
cleanup.bat
```

## Advanced Usage

### Manual Port Scanning

```powershell
# Check port availability
pwsh -File port-scanner.ps1

# Verbose output
pwsh -File port-scanner.ps1 -Verbose
```

### Firewall Management

```powershell
# Create firewall rules (requires admin)
pwsh -File firewall-manager.ps1 -Action enable

# Check existing rules
pwsh -File firewall-manager.ps1 -Action check

# Remove all MCP rules
pwsh -File firewall-manager.ps1 -Action disable
```

### Manual Service Management

```batch
# Start services
docker compose up -d

# View logs
docker logs dhv01mcp
docker logs dhv01mcp-postgres
docker logs dhv01mcp-redis

# Stop services
docker compose down
```

## Configuration Files

### Environment Variables (.env)

Key variables for host networking:

```bash
MCP_HOST=localhost
MCP_PORT=8811
POSTGRES_PORT=5432
REDIS_PORT=6379
TRAEFIK_PORT=80
TRAEFIK_DASHBOARD_PORT=8080
```

### Service Configuration (config.yaml)

```yaml
server:
  host: "localhost"
  port: 8811
```

## Troubleshooting

### Port Conflicts

If you encounter port conflicts:

1. Run `port-scanner.ps1` to detect conflicts
2. Check `.env` file for updated port assignments
3. Restart services: `docker compose down && docker compose up -d`

### Firewall Issues

If services are not accessible:

1. Run PowerShell as Administrator
2. Execute: `pwsh -File firewall-manager.ps1 -Action enable`
3. Check Windows Defender Firewall settings

### Container Issues

If containers fail to start:

```batch
# Check Docker status
docker info

# View container logs
docker logs dhv01mcp

# Check port usage
netstat -ano | findstr :8811
```

### Performance Optimization

Host networking provides:

- **Zero NAT overhead** - Direct localhost binding
- **Native port access** - Standard database ports
- **Simplified networking** - No Docker network complexity
- **Better debugging** - Direct service access

## Security Considerations

### Localhost Binding

All services bind to `127.0.0.1` (localhost only):

- ✅ **Secure**: No external network exposure
- ✅ **Fast**: No network translation overhead
- ✅ **Simple**: Standard localhost connectivity

### Firewall Rules

Automatic firewall rules:

- Scope: Local computer only
- Address: 127.0.0.1 (localhost)
- Action: Allow inbound
- Profile: All profiles

### Access Control

- Services only accessible from the host machine
- No external network exposure by default
- Firewall rules automatically managed

## Migration Notes

### From Bridge Networking

If migrating from bridge networking:

1. Run `cleanup.bat` to remove old infrastructure
2. Run `setup.bat` to create new host networking setup
3. Update any hardcoded service references to new names

### Service Discovery

Update any external applications to use:

- `localhost:8811` instead of `mcp-server:8811`
- `localhost:5432` instead of `mcp-postgres:5432`
- `localhost:6379` instead of `mcp-redis:6379`

## Support

### Logs Location

- Container logs: `docker logs <container-name>`
- System logs: Windows Event Viewer
- Application logs: `./logs` directory

### Common Commands

```batch
# Quick health check
health-check.bat

# View all containers
docker ps --filter "name=dhv01mcp"

# Check port usage
netstat -ano | findstr :8811

# View firewall rules
netsh advfirewall firewall show rule name=all | findstr MCP
```

This architecture provides maximum performance while maintaining security through localhost-only binding and automated firewall management.
