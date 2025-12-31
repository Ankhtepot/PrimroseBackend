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

Stop docker compose and remove volumes:
```shell
sudo docker compose down -v
```

Running backend only – restart:
```shell
sudo docker compose up -d --no-deps --force-recreate --build primrose-backend
```

Confirm active swarm mode:
```shell
docker info --format '{{.Swarm.LocalNodeState}}'
```

## Scripts

### Deploy stack (Swarm) using the convenience script (recommended):
```shell
# run from repo root on the server
sudo bash /srv/primrose/deploy.sh
```

### Check Stack
```shell
sudo bash /srv/primrose/scripts/check_stack.sh
```

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
```

Redeploy (pull latest, build image and deploy stack)
```shell
cd /srv/primrose
sudo chmod +x ./deploy.sh
sudo ./deploy.sh
Quick one-off rebuild of backend only (no DB downtime)
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
