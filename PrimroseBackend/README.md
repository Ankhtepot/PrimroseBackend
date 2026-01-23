## 🚨 Cloudflare Tunnel Troubleshooting

If you're getting **503 errors** when accessing `https://api.primrose.work`:

### Quick Fix (Copy-paste this on server):
```bash
cd /srv/primrose
bash scripts/check-tunnel.sh
```

### Complete Auto-Fix Script:
See `../FIX-NOW.md` - contains a complete copy-paste script that will:
- Diagnose the issue
- Show your health token
- Test everything
- Auto-fix common problems

### Troubleshooting Guides:
- 📄 **`../FIX-NOW.md`** - Automated fix script (recommended)
- 📄 **`../QUICK-FIX-503.md`** - Step-by-step manual fixes
- 📄 **`../CLOUDFLARE-SETUP.md`** - Complete reference guide
- 📄 **`../CLOUDFLARE_TUNNEL_TROUBLESHOOTING.md`** - Detailed troubleshooting

### Common Issue: Config Location
Your Cloudflare tunnel config is at: **`/root/.cloudflared/config.yml`**

Must point to: `http://localhost:8080` (not https!)

---

## Summary For Hetzner Cloud

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
A Postman collection is provided in the root directory: `postman_collection.json` (HTTP) and `postman_https_collection.json` (HTTPS).

- `postman_collection.json`: uses `{{baseUrl}}` variable and is convenient for local HTTP testing.
- `postman_https_collection.json`: uses `{{host}}` collection variable and targets `https://{{host}}/...` endpoints. This is useful for testing the production HTTPS endpoints.

How to import and use the HTTPS collection
1. Open Postman (native app recommended).
2. Import `postman_https_collection.json` (File > Import > Choose Files).
3. Edit the collection variables or create an environment: set `host` to your server host (include port if not 443), `admin_username`, `admin_password`, and `health_token` as needed.
4. For quick testing of self-signed certs you can temporarily disable SSL verification in Postman Settings > General > `SSL certificate verification` = OFF, but the recommended approach is to trust the server certificate on your OS (instructions below).

Trusting the provided certificate (recommended)
- Certificate file: `PrimroseBackend/primrose.crt` (included in repo).
- Windows: run as Administrator and import into Trusted Root Certification Authorities (double-click the .crt and use the Certificate Import Wizard) or use `certutil -addstore -f "Root" "PrimroseBackend\\primrose.crt"`.
- Debian/Ubuntu: `sudo cp PrimroseBackend/primrose.crt /usr/local/share/ca-certificates/primrose.crt && sudo update-ca-certificates`.
- macOS: `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain PrimroseBackend/primrose.crt`.

Important: the certificate CN/SAN must match the host you use in Postman (use the domain that matches the cert or add a hosts file entry mapping the domain to the VM IP).

## Cloudflare Tunnel Setup

If you're using Cloudflare Tunnel to expose your API:

1. **Tunnel Configuration**: Point your tunnel to `http://localhost:8080` (NOT https)
2. **Health Endpoint**: The `/health` endpoint requires the `X-Health-Token` header
3. **Token**: Get your health token from `/srv/primrose/PrimroseBackend/.env`

Example Cloudflare Tunnel config (`/etc/cloudflared/config.yml`):
```yaml
tunnel: <your-tunnel-id>
credentials-file: /path/to/credentials.json

ingress:
  - hostname: api.primrose.work
    service: http://localhost:8080
  - service: http_status:404
```

Test health endpoint with token:
```bash
curl https://api.primrose.work/health -H "X-Health-Token: YOUR_TOKEN"
```

For detailed troubleshooting, see `CLOUDFLARE_TUNNEL_TROUBLESHOOTING.md` in the repo root.

## Summary For Hetzner Cloud

### Commands you'll use frequently (copy/paste)

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

### Frontend (React / Vite) — running against HTTPS backend

Goal: let your admin frontend (React + Vite) talk to the HTTPS backend during development.

Options:

1) Preferable: run the frontend locally (Vite dev server) and call the backend HTTPS domain (same domain used by cert)
   - Make sure the cert is trusted in your development machine (import `PrimroseBackend/primrose.crt` into OS trust store as described above).
   - In the React app, set the API base URL to the HTTPS host (e.g., https://primrose.example.com) so fetch requests go directly to HTTPS production-like endpoint.
   - If using different host/port for frontend, enable CORS in the backend (the project already has CORS policies). Ensure the backend CORS policy allows the frontend origin.

2) If you prefer local HTTPS for the dev server (serve the React app over HTTPS):
   - Vite supports HTTPS in dev by passing `--https` and certificate files.
   - Example (project root for frontend):
     - Generate or reuse the same certificate/key pair (or use mkcert to create a local trusted cert for your chosen dev hostname).
     - Start Vite with HTTPS: `vite --host --https --cert path/to/primrose.crt --key path/to/primrose.key` (or configure vite.config.js dev server https option).
   - Browser treats front-end and backend as secure contexts; you still need to ensure the cert names match hostnames used.

3) Quick workaround (less secure): disable browser SSL validation for testing or use the browser's ignore-certificate-error flag (not recommended).

4) Using IDE / proxy:
   - If you run the frontend from an IDE (VSCode/JetBrains), you can create a run configuration that starts Vite with the `--https` flags and points to cert/key files, or use an HTTP proxy that terminates TLS and forwards to local Vite.

Practical checklist to run frontend dev against HTTPS backend
- Import `PrimroseBackend/primrose.crt` into OS trust store.
- Configure frontend API base URL to the HTTPS host used by the certificate (matching CN/SAN).
- Ensure CORS policy on backend allows your frontend origin (edit AllowedOrigins / ALLOWED_ORIGINS env as needed).
- If you need Vite served over HTTPS too, provide cert/key to Vite or use mkcert to generate a trusted local cert.
