# Cloudflare Tunnel Files Reference

This directory contains scripts and guides for troubleshooting your Cloudflare tunnel setup.

## Quick Reference

### Your Setup
- **Domain**: `api.primrose.work`
- **Backend Port**: `8080`
- **Cloudflare Config**: `/root/.cloudflared/config.yml`
- **Backend Location**: `/srv/primrose`

---

## Files in This Repo

### 🚀 Quick Start
- **`QUICK-FIX-503.md`** - Step-by-step guide to fix 503 errors
- **`scripts/check-tunnel.sh`** - Quick one-command health check

### 📊 Diagnostics
- **`scripts/diagnose-cloudflare-tunnel.sh`** - Full server-side diagnostic script
- **`scripts/test-cloudflare-tunnel.ps1`** - Client-side testing from Windows

### 📖 Documentation
- **`CLOUDFLARE_TUNNEL_TROUBLESHOOTING.md`** - Comprehensive troubleshooting guide

---

## Commands to Run on Server

### Quick Check
```bash
cd /srv/primrose
bash scripts/check-tunnel.sh
```

### Full Diagnostics
```bash
cd /srv/primrose
bash scripts/diagnose-cloudflare-tunnel.sh
```

### Fix Commands
```bash
# Restart backend
cd /srv/primrose && sudo ./deploy.sh --force

# Restart tunnel
sudo systemctl restart cloudflared

# Edit tunnel config
sudo nano /root/.cloudflared/config.yml

# View logs
sudo docker service logs primrose_primrose-backend --tail 50
sudo journalctl -u cloudflared -f
```

---

## Commands to Run Locally (Windows)

### Test from your computer
```powershell
cd D:\C#\Projects\PrimroseBackend
.\scripts\test-cloudflare-tunnel.ps1

# With health token
.\scripts\test-cloudflare-tunnel.ps1 -HealthToken "your_token_here"
```

---

## Correct Cloudflare Tunnel Config

Location: `/root/.cloudflared/config.yml`

```yaml
tunnel: <your-tunnel-id>
credentials-file: /root/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: api.primrose.work
    service: http://localhost:8080    # Must be HTTP, not HTTPS!
  - service: http_status:404
```

**Key Points:**
- ✅ Use `http://` not `https://`
- ✅ Use `localhost:8080` or `127.0.0.1:8080`
- ✅ Port must be `8080` (where your backend listens)
- ❌ Don't use Docker service name (`primrose-backend`)
- ❌ Don't use HTTPS

---

## Health Endpoint

### URL
```
https://api.primrose.work/health
```

### Required Header
```
X-Health-Token: <your_token_value>
```

### Get Your Token
On server:
```bash
cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN
```

### Expected Response
```json
{"status":"ok"}
```

---

## Common Issues and Solutions

### Issue: 503 Service Unavailable
**Cause**: Backend not running or tunnel can't reach it

**Fix**:
```bash
# Check backend
sudo docker stack services primrose

# Restart if needed
cd /srv/primrose && sudo ./deploy.sh --force
```

### Issue: 403 Forbidden
**Cause**: Missing or wrong health token

**Fix**: Add `X-Health-Token` header in Postman with correct value

### Issue: Connection Timeout
**Cause**: Cloudflare tunnel not running

**Fix**:
```bash
sudo systemctl status cloudflared
sudo systemctl restart cloudflared
```

### Issue: Tunnel Can't Connect
**Cause**: Wrong service URL in config

**Fix**: Edit `/root/.cloudflared/config.yml` to use `http://localhost:8080`

---

## Testing Workflow

1. **Test locally on server first:**
   ```bash
   HEALTH_TOKEN=$(cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN | cut -d= -f2)
   curl http://localhost:8080/health -H "X-Health-Token: $HEALTH_TOKEN"
   ```
   Should return: `{"status":"ok"}`

2. **If local test works, test via tunnel:**
   ```bash
   curl https://api.primrose.work/health -H "X-Health-Token: $HEALTH_TOKEN"
   ```
   Should return: `{"status":"ok"}`

3. **If tunnel test fails but local works:**
   - Problem is with Cloudflare tunnel config or service
   - Check `/root/.cloudflared/config.yml`
   - Restart tunnel: `sudo systemctl restart cloudflared`

4. **If local test fails:**
   - Problem is with backend service
   - Check logs: `sudo docker service logs primrose_primrose-backend --tail 50`
   - Restart: `cd /srv/primrose && sudo ./deploy.sh --force`

---

## Support

For detailed help, see:
- `QUICK-FIX-503.md` - Fast solutions
- `CLOUDFLARE_TUNNEL_TROUBLESHOOTING.md` - Detailed guide
- Run diagnostics: `bash scripts/diagnose-cloudflare-tunnel.sh`

