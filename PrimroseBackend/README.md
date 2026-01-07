Pull latest:
```shell
git pull origin master
```

List docker secrets:
```shell
docker secret ls
```

Remove docker secret:
```shell
docker secret rm <secret_name>
```

Stop docker compose and remove volumes (Local Development):
```shell
docker compose down -v
```

Remove stack and cleanup (Production Swarm):
```shell
sudo docker stack rm primrose
# To remove persistent volumes as well:
sudo docker volume rm primrose_mssql_data primrose_primrose_dataprotection
```

Running backend only – restart (Local Development):
```shell
docker compose up -d --no-deps --force-recreate --build primrose-backend
```

Confirm active swarm mode:
```shell
docker info --format '{{.Swarm.LocalNodeState}}'
```

### Database Migrations (Local Development)
If you change the models, you need to create and apply migrations locally:
```shell
# 1. Create a new migration
dotnet ef migrations add <MigrationName> --project PrimroseBackend --startup-project PrimroseBackend

# 2. Apply migrations to the local database
dotnet ef database update --project PrimroseBackend --startup-project PrimroseBackend
```
*Note: In production (Hetzner), migrations are applied automatically on startup.*

## Scripts

### Deploy stack (Swarm) using the convenience script (recommended):
```shell
# run from repo root on the server
sudo bash /srv/primrose/deploy.sh
```

**Supported Flags:**
- `--force` or `-f`: Force rebuild and redeploy even if no git changes are detected.
- `--fresh`: Remove the existing stack, secrets, and networks before redeploying.
- `--purge-volumes`: Use with `--fresh` to also remove persistent database and data protection volumes.

### Check Stack
```shell
sudo bash /srv/primrose/scripts/check_stack.sh
```

## API Testing (Postman)
A Postman collection is provided in the root directory: `postman_collection.json`.
- **JWT Auth**: Automatically handled for admin endpoints after a successful login.
- **TOTP Auth**: Required for public `/api/pages`. Provide a 6-digit code in the `X-App-Auth` header.
- **Expiration**: If a token expires, the backend returns `X-Token-Expired: true` header. The Postman collection will automatically clear the token variable in this case.

## Summary For Hetzner Cloud

### Commands you’ll use frequently (copy/paste)

Create or re-create secrets from the server's PrimroseBackend/.env (the deploy script will try to auto-create missing secrets):
```shell
# interactive creation example
read -s -p "Enter JwtSecret: " JWT && echo
printf '%s' "$JWT" | docker secret create primrose_jwt -

read -s -p "Enter SharedSecret: " SH && echo
printf '%s' "$SH" | docker secret create primrose_shared -

read -s -p "Enter admin username (e.g. admin): " ADMINUSER && echo
printf '%s' "$ADMINUSER" | docker secret create primrose_admin_username -

read -s -p "Enter admin password (will be hidden): " ADMINPASS && echo
printf '%s' "$ADMINPASS" | docker secret create primrose_admin_password -

read -s -p "Enter health token: " HT && echo
printf '%s' "$HT" | docker secret create primrose_health_token -
```

Redeploy (pull latest, build image and deploy stack)
```shell
cd /srv/primrose
sudo chmod +x ./deploy.sh
sudo ./deploy.sh
Quick one-off rebuild of backend only (Local Dev or troubleshooting only)
cd /srv/primrose
sudo docker compose up -d --no-deps --build primrose-backend
```
Run the health/readiness checker and view its log
```shell
cd /srv/primrose
sudo chmod +x ./scripts/check_stack.sh
sudo ./scripts/check_stack.sh
# view the log
tail -n 200 primrose-check.log
```
Inspect stack & logs manually
```shell
# list services in the stack
sudo docker stack services primrose

# view service tasks
sudo docker service ps primrose_primrose-backend

# stream backend logs (service logs via swarm)
sudo docker service logs -f primrose_primrose-backend
```
View secrets & DataProtection volume contents (no secret values)
```shell
# list secrets
docker secret ls
```
```shell
# inside a backend task/container (replace CID if needed)
CID=$(docker ps --filter "name=primrose_primrose-backend" -q | head -n1)
sudo docker exec -it $CID ls -l /run/secrets
sudo docker exec -it $CID ls -l /home/ubuntu/.aspnet/DataProtection-Keys || true
```

Optional: run checks from remote (PowerShell example)
```shell
# TCP check
Test-NetConnection -ComputerName <VM_IP> -Port 443

# HTTPS /health (self-signed may require --insecure)
curl -v https://<VM_IP>/health --insecure

# If HEALTH_TOKEN required:
curl -v https://<VM_IP>/health -H "X-Health-Token: <token>" --insecure
```
