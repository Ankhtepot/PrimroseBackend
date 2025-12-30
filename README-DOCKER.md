Run & Deploy guide for PrimroseBackend with Docker Compose

This document explains how to run the project locally with Docker Compose and the recommended steps to deploy it to a Hetzner VM (or similar VPS).

Prerequisites
- Docker Engine and Docker Compose (v2) installed on your machine or server.
- At least 2GB RAM for SQL Server container (local dev may work with less but SQL Server has memory requirements).
- Sufficient disk space for the database volume.

Files provided
- docker-compose.yaml: Compose stack for the API and MSSQL.
- PrimroseBackend/.env.example: example environment file. Copy to PrimroseBackend/.env and edit.

Quick local run (development)
1) Copy the example env file and set secrets:
```powershell
cd "D:\C#\Projects\PrimroseBackend"
copy "PrimroseBackend\.env.example" "PrimroseBackend\.env"
# Edit PrimroseBackend\.env with a secure SA_PASSWORD and JwtSecret
notepad "PrimroseBackend\.env"
```
2) Start the stack:
```powershell
# from repository root
docker compose up --build
```
3) The API is available at http://localhost:8080 (unless you changed ports).

Security notes (local vs production)
- Do NOT commit `.env` with secrets. Keep it out of version control.
- For production use Docker secrets, environment variables from the orchestrator, or a secrets manager.
- The provided compose file intentionally does NOT expose SQL Server (port 1433) on the host. To connect from host tools, use an administrative container or temporary port mapping.

Preparing Hetzner (or other VPS) deployment
This guide assumes you deploy to a single VM running Docker. For production-grade deployments consider Kubernetes or managed services.

1) Provision a VM
- Create a small Ubuntu server (for MSSQL 2022 use at least 4GB RAM; Microsoft recommends >= 2 GB but 4 GB is safer).
- Configure firewall: allow only the application port (8080) and SSH (22). Close others.

2) Install Docker & Docker Compose
Follow Docker's official install instructions for your distro. Ensure docker-compose plugin is available.

3) Copy code & env
- Securely copy the repository to the server (git clone or rsync).
- Create `/var/lib/primrose/.env` or put `PrimroseBackend/.env` in the project root.

4) Use Docker secrets for production (recommended)
- Store SA_PASSWORD, JwtSecret, and SharedSecret as Docker secrets instead of plain env variables.
- Example using `docker stack` (requires swarm) or use files and `--env-file` carefully.

5) Persistent storage & backups
- The compose file uses a named volume for MSSQL data. Ensure backups by mounting a host path or scheduled database backup jobs.

6) Run the stack
```bash
# on the server
cd /path/to/repo
sudo docker compose up -d --build
```

7) Post-deploy checks
- Check logs: `docker compose logs -f primrosebackend`
- Confirm DB migration/initialization works (if your app runs migrations on startup).
- Monitor disk and memory usage.

Advanced: using systemd to manage the stack
Create a systemd service to ensure the stack restarts on boot using a small wrapper script. Or use a process manager like `watchtower` to manage image updates.

Final notes
- For production, prefer managed DB (e.g., Managed MSSQL or Azure SQL) or a hardened DB host.
- Consider adding TLS termination (NGINX or a load balancer) instead of exposing the app directly.
- If you want, I can add a `systemd` unit file, a script to create Docker secrets from env file, and a sample `nginx` reverse-proxy config with Let's Encrypt for Hetzner deployment.

