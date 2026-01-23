# Cloudflare Tunnel Troubleshooting - File Index

## 🚀 Quick Start

**Getting a 503 error on api.primrose.work?**

👉 **SSH to your server and run:**
```bash
cd /srv/primrose
git pull  # Get latest scripts
bash scripts/check-tunnel.sh
```

This will show you exactly what's wrong!

---

## 📂 Files in This Repository

### 🎯 Start Here
- **[FIX-NOW.md](FIX-NOW.md)** ⭐ - Copy-paste auto-fix script
  - Complete automated diagnostic and repair
  - Shows your health token
  - Tests everything

### 🔧 Quick Fixes  
- **[QUICK-FIX-503.md](QUICK-FIX-503.md)** - Manual step-by-step fixes
- **[scripts/check-tunnel.sh](scripts/check-tunnel.sh)** - One-command health check

### 📊 Diagnostics
- **[scripts/diagnose-cloudflare-tunnel.sh](scripts/diagnose-cloudflare-tunnel.sh)** - Full server-side diagnostic
- **[scripts/test-cloudflare-tunnel.ps1](scripts/test-cloudflare-tunnel.ps1)** - Windows client-side test

### 📚 Documentation
- **[CLOUDFLARE-SETUP.md](CLOUDFLARE-SETUP.md)** - Complete reference guide
- **[CLOUDFLARE_TUNNEL_TROUBLESHOOTING.md](CLOUDFLARE_TUNNEL_TROUBLESHOOTING.md)** - Detailed troubleshooting
- **[PrimroseBackend/README.md](PrimroseBackend/README.md)** - Updated with Cloudflare section

---

## 🎯 Your Problem: 503 Error

### Most Common Causes:

1. **Cloudflare config points to wrong URL** (90% of issues)
   - Location: `/root/.cloudflared/config.yml`
   - Must be: `service: http://localhost:8080`
   - NOT: https, NOT docker service name

2. **Backend service not running**
   - Check: `sudo docker stack services primrose`
   - Fix: `cd /srv/primrose && sudo ./deploy.sh --force`

3. **Cloudflare tunnel not running**
   - Check: `sudo systemctl status cloudflared`
   - Fix: `sudo systemctl restart cloudflared`

---

## 🛠️ Command Quick Reference

### On Server (Linux)

**Quick health check:**
```bash
cd /srv/primrose
bash scripts/check-tunnel.sh
```

**Full diagnostic:**
```bash
cd /srv/primrose
bash scripts/diagnose-cloudflare-tunnel.sh
```

**Get health token:**
```bash
cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN
```

**View Cloudflare config:**
```bash
sudo cat /root/.cloudflared/config.yml
```

**Edit Cloudflare config:**
```bash
sudo nano /root/.cloudflared/config.yml
```

**Restart services:**
```bash
# Backend
cd /srv/primrose && sudo ./deploy.sh --force

# Cloudflare tunnel
sudo systemctl restart cloudflared
```

**View logs:**
```bash
# Backend logs
sudo docker service logs primrose_primrose-backend --tail 50

# Tunnel logs
sudo journalctl -u cloudflared -f
```

### On Your Computer (Windows)

**Test connectivity:**
```powershell
cd D:\C#\Projects\PrimroseBackend
.\scripts\test-cloudflare-tunnel.ps1
```

**Test with health token:**
```powershell
.\scripts\test-cloudflare-tunnel.ps1 -HealthToken "your_token_here"
```

---

## ✅ Correct Configuration

**File: `/root/.cloudflared/config.yml`**

```yaml
tunnel: <your-tunnel-id>
credentials-file: /root/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: api.primrose.work
    service: http://localhost:8080    # ← HTTP not HTTPS!
  - service: http_status:404
```

**Key points:**
- ✅ `http://` not `https://`
- ✅ `localhost:8080` or `127.0.0.1:8080`
- ✅ Port `8080`
- ❌ NOT Docker service name
- ❌ NOT HTTPS

---

## 🧪 Testing in Postman

1. **URL:** `https://api.primrose.work/health`
2. **Method:** GET
3. **Headers:**
   - Name: `X-Health-Token`
   - Value: `<get_from_server_env_file>`
4. **Expected Response:** `{"status":"ok"}`
5. **Expected Status:** 200 OK

**Get your health token from server:**
```bash
cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN
```

---

## 📖 Which File to Use?

| Situation | Use This File |
|-----------|---------------|
| Just want it fixed NOW | **FIX-NOW.md** |
| Need step-by-step manual fix | **QUICK-FIX-503.md** |
| Want to check status quickly | `scripts/check-tunnel.sh` |
| Need detailed diagnostic | `scripts/diagnose-cloudflare-tunnel.sh` |
| Want complete reference | **CLOUDFLARE-SETUP.md** |
| Advanced troubleshooting | **CLOUDFLARE_TUNNEL_TROUBLESHOOTING.md** |
| Test from Windows | `scripts/test-cloudflare-tunnel.ps1` |

---

## 🔄 Typical Workflow

1. **Problem occurs** (503 error in Postman)
   
2. **Quick check:**
   ```bash
   cd /srv/primrose
   bash scripts/check-tunnel.sh
   ```

3. **If issue found:**
   - Backend down? → Run `sudo ./deploy.sh --force`
   - Config wrong? → Edit `/root/.cloudflared/config.yml`
   - Tunnel down? → Run `sudo systemctl restart cloudflared`

4. **Test again** in Postman with health token

5. **Still broken?** Run full diagnostic:
   ```bash
   bash scripts/diagnose-cloudflare-tunnel.sh
   ```

6. **Still stuck?** Copy the complete auto-fix script from `FIX-NOW.md`

---

## 🎓 Understanding the Setup

```
Postman (your PC)
    ↓ HTTPS
api.primrose.work (Cloudflare DNS)
    ↓ HTTPS
Cloudflare Edge Servers
    ↓ Cloudflare Tunnel (encrypted)
Your Server (Hetzner)
    ↓ HTTP on localhost:8080
primrose-backend (Docker container)
    ↓
Your ASP.NET Core API
```

**The 503 happens when:**
- Cloudflare tunnel can't reach `localhost:8080`
- Backend container isn't running
- Cloudflare config points to wrong place

---

## 📞 Support Resources

All scripts provide:
- ✅ Clear error messages
- ✅ Exact fix commands
- ✅ Your health token
- ✅ Service status
- ✅ Log excerpts
- ✅ Configuration validation

Just run them and follow the output!

---

## 🔥 Emergency Fix

If everything is broken and you just want it working:

```bash
cd /srv/primrose
sudo docker stack rm primrose
sleep 15
sudo ./deploy.sh --force
sleep 30
sudo systemctl restart cloudflared
sleep 5

# Test it
HEALTH_TOKEN=$(cat PrimroseBackend/.env | grep HEALTH_TOKEN | cut -d= -f2)
curl https://api.primrose.work/health -H "X-Health-Token: $HEALTH_TOKEN"
```

Should return: `{"status":"ok"}`

---

**Last Updated:** 2026-01-23  
**Location:** /srv/primrose on your Hetzner server  
**Config:** /root/.cloudflared/config.yml

