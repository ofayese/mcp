# MCP Docker Setup

This repository contains a fully working Dockerized setup for MCP (Model Context Protocol) with optional services like Redis, PostgreSQL, and Traefik.

---

## 📦 Included

- `docker-compose.yml` – MCP server + dependencies
- `.env` – environment variables
- `mcpconfig.ps1` – PowerShell setup script for Windows
- `mcpconfig.sh` – Shell setup script for Linux/macOS
- `health-check.bat` – Quick MCP HTTP check
- `quick-setup.bat` – One-click setup for Windows
- `traefik.yml` – Optional Traefik config
- Volumes: `mcp-data`, `mcp-logs`, `mcp-cache`, `mcp-postgres-data`

---

## 🚀 Quick Start (Windows)

```powershell
.\mcpconfig.ps1
```

Or:

```cmd
quick-setup.bat
```

---

## 🐧 Quick Start (Linux/macOS)

```bash
chmod +x mcpconfig.sh
./mcpconfig.sh
docker-compose up -d
```

---

## ✅ Health Check

```bash
curl http://localhost:8811/health
```

---

## 🛠️ Setup Details

- Docker volumes and network are auto-created
- MCP port: `http://localhost:8811`
- Traefik dashboard (optional): `http://localhost:8080`

---

## 🔁 Autostart (Linux)

To enable auto-start using `systemd`:

```ini
# /etc/systemd/system/mcp.service
[Unit]
Description=MCP Docker Compose Service
After=network.target docker.service
Requires=docker.service

[Service]
WorkingDirectory=/home/YOURUSER/.docker/mcp
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
Restart=always

[Install]
WantedBy=multi-user.target
```

Then run:
```bash
sudo systemctl daemon-reexec
sudo systemctl enable mcp
sudo systemctl start mcp
```

---

## 🧪 Test MCP

```bash
docker-compose logs mcp-server
docker ps
```

---

## 🧹 Cleanup

```bash
docker-compose down -v
docker volume rm mcp-data mcp-logs mcp-cache mcp-postgres-data
```

