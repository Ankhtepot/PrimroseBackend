# Cloudflare Tunnel Troubleshooting Guide

## Issue: 503 Error when accessing https://api.primrose.work/health

### Possible Causes and Solutions

## 1. **Check if the service is running**

On your server, check if the stack is deployed and running:

```bash
# Check if stack is deployed
sudo docker stack ls

# Check service status
sudo docker stack services primrose

# Check if backend container is running
sudo docker service ps primrose_primrose-backend

# View backend logs
sudo docker service logs -f primrose_primrose-backend --tail 100
```

## 2. **Check Cloudflare Tunnel Configuration**

Your Cloudflare Tunnel needs to point to the correct internal service endpoint:

- **Service URL should be**: `http://primrose-backend:8080` OR `http://localhost:8080`
- **NOT**: `https://...` (the tunnel itself handles HTTPS termination)

Example tunnel config (`config.yml`):
```yaml
tunnel: <your-tunnel-id>
credentials-file: /path/to/credentials.json

ingress:
  - hostname: api.primrose.work
    service: http://localhost:8080
  - service: http_status:404
```

## 3. **Health Endpoint Requires Token**

Your `/health` endpoint requires the `X-Health-Token` header. Test with:

```bash
# From the server (replace <token> with your actual health token)
curl -v http://localhost:8080/health -H "X-Health-Token: <token>"

# From Postman, add header:
# X-Health-Token: <your_health_token_value>
```

To get your health token from the server:
```bash
# View the health token secret (won't show the value)
docker secret ls | grep health

# Check the environment file
cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN
```

## 4. **Port Binding Issue**

Verify the service is actually listening on port 8080:

```bash
# From the server
sudo netstat -tlnp | grep 8080
# OR
sudo ss -tlnp | grep 8080
```

## 5. **Docker Swarm Mode**

Ensure Docker Swarm is active:
```bash
docker info --format '{{.Swarm.LocalNodeState}}'
# Should output: active
```

## 6. **Network Connectivity**

Test if the service responds locally on the server:

```bash
# Basic health check (might fail without token)
curl -v http://localhost:8080/health

# With health token
curl -v http://localhost:8080/health -H "X-Health-Token: YOUR_TOKEN_HERE"

# Test with Cloudflare tunnel's internal IP
curl -v http://127.0.0.1:8080/health -H "X-Health-Token: YOUR_TOKEN_HERE"
```

## 7. **Check Cloudflare Tunnel Status**

On your server where the tunnel is running:

```bash
# If running as a service
sudo systemctl status cloudflared

# Check tunnel logs
sudo journalctl -u cloudflared -f

# Or if running in Docker
docker logs cloudflared
```

## Quick Fix Steps

### Step 1: Verify Service is Running
```bash
sudo docker stack services primrose
# Look for 1/1 replicas for primrose-backend
```

### Step 2: Check Service Logs for Errors
```bash
sudo docker service logs primrose_primrose-backend --tail 50
```

### Step 3: Test Local Connectivity
```bash
# Get your health token
HEALTH_TOKEN=$(cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN | cut -d= -f2)

# Test the health endpoint
curl -v http://localhost:8080/health -H "X-Health-Token: $HEALTH_TOKEN"
```

### Step 4: Verify Cloudflare Tunnel Config
Check your tunnel configuration file at `/root/.cloudflared/config.yml`:
- Ensure hostname matches: `api.primrose.work`
- Ensure service points to: `http://localhost:8080`

```bash
# View the config
sudo cat /root/.cloudflared/config.yml
```

Expected configuration:
```yaml
tunnel: <your-tunnel-id>
credentials-file: /root/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: api.primrose.work
    service: http://localhost:8080
  - service: http_status:404
```

### Step 5: Restart Cloudflare Tunnel
```bash
sudo systemctl restart cloudflared
# OR
cloudflared tunnel run <tunnel-name>
```

### Step 6: Test from Postman
Add the header in Postman:
- Header name: `X-Health-Token`
- Header value: `<your_health_token_from_env>`

## Common Issues

### Issue: "Connection refused"
- Service isn't running or not listening on 8080
- Solution: Restart stack with `sudo ./deploy.sh`

### Issue: "403 Forbidden"
- Missing or incorrect health token
- Solution: Add `X-Health-Token` header with correct value

### Issue: "503 Service Unavailable"
- Backend service not ready or crashed
- Cloudflare tunnel can't reach the backend
- Solution: Check service logs and tunnel configuration

### Issue: "429 Too Many Requests"
- Rate limit exceeded (10 requests per minute per IP)
- Solution: Wait 60 seconds or use the health token correctly

## Disable Health Token (For Testing Only)

If you want to temporarily disable the health token requirement for testing:

1. On the server, edit the `.env` file:
```bash
sudo nano /srv/primrose/PrimroseBackend/.env
```

2. Comment out or remove the `HEALTH_TOKEN` line:
```bash
# HEALTH_TOKEN=your_token_here
```

3. Remove the secret:
```bash
docker secret rm primrose_health_token
```

4. Redeploy:
```bash
sudo ./deploy.sh --force
```

**Remember to re-enable it for production!**

## Alternative: Use /health/internal

The `/health/internal` endpoint doesn't require a token but only accepts requests from loopback IPs. If Cloudflare tunnel runs on the same machine, you can configure it to use this endpoint:

```yaml
ingress:
  - hostname: api.primrose.work
    service: http://127.0.0.1:8080
```

However, for the public health endpoint, keep using `/health` with the token.

