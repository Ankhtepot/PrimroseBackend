# Quick Fix for 503 Error on api.primrose.work

## The 503 Error Means
Your Cloudflare tunnel cannot reach your backend service. Here's how to fix it:

---

## SSH to Your Server and Run These Commands

### 1️⃣ Run the Diagnostic Script
```bash
cd /srv/primrose
bash scripts/diagnose-cloudflare-tunnel.sh
```

This will check everything and tell you exactly what's wrong.

---

## Most Common Issues and Fixes

### Issue A: Service Not Running
**Check if service is running:**
```bash
sudo docker stack services primrose
```

**If you see 0/1 replicas, restart the service:**
```bash
cd /srv/primrose
sudo ./deploy.sh --force
```

---

### Issue B: Wrong Cloudflare Config
**Check your Cloudflare tunnel config:**
```bash
sudo cat /root/.cloudflared/config.yml
```

**It should look like this:**
```yaml
tunnel: <your-tunnel-id>
credentials-file: /root/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: api.primrose.work
    service: http://localhost:8080    # ← Must be HTTP, not HTTPS
  - service: http_status:404
```

**If it's wrong, edit it:**
```bash
sudo nano /root/.cloudflared/config.yml
```

**Then restart the tunnel:**
```bash
sudo systemctl restart cloudflared
```

---

### Issue C: Cloudflare Tunnel Not Running
**Check tunnel status:**
```bash
sudo systemctl status cloudflared
```

**If not running, start it:**
```bash
sudo systemctl start cloudflared
```

**Check logs for errors:**
```bash
sudo journalctl -u cloudflared -f
```

---

## Test the Fix

### From Server (Local Test)
```bash
# Get your health token
HEALTH_TOKEN=$(cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN | cut -d= -f2)

# Test locally
curl -v http://localhost:8080/health -H "X-Health-Token: $HEALTH_TOKEN"
```

**Expected result:** `{"status":"ok"}`

### From Your Computer (Postman or Browser)
```
URL: https://api.primrose.work/health
Method: GET
Headers:
  X-Health-Token: <your_token_from_env_file>
```

---

## Complete Solution (If Nothing Works)

Run these commands in order:

```bash
# 1. Go to project directory
cd /srv/primrose

# 2. Check what's wrong
bash scripts/diagnose-cloudflare-tunnel.sh

# 3. Stop everything
sudo docker stack rm primrose
sleep 10

# 4. Restart everything
sudo ./deploy.sh --force

# 5. Wait for services to start (30-60 seconds)
sleep 30

# 6. Check status
sudo docker stack services primrose

# 7. View backend logs
sudo docker service logs primrose_primrose-backend --tail 50

# 8. Test locally
HEALTH_TOKEN=$(cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN | cut -d= -f2)
curl http://localhost:8080/health -H "X-Health-Token: $HEALTH_TOKEN"

# 9. Restart Cloudflare tunnel
sudo systemctl restart cloudflared

# 10. Test from external
curl https://api.primrose.work/health -H "X-Health-Token: $HEALTH_TOKEN"
```

---

## Get Your Health Token

**From server:**
```bash
sudo cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN
```

**Use this token in Postman:**
- Header name: `X-Health-Token`
- Header value: `<the_value_from_above>`

---

## Still Not Working?

### Check These:

1. **Is Docker Swarm active?**
   ```bash
   sudo docker info | grep "Swarm:"
   # Should show: Swarm: active
   ```

2. **Are services actually running?**
   ```bash
   sudo docker stack ps primrose --no-trunc
   ```

3. **What do the logs say?**
   ```bash
   sudo docker service logs primrose_primrose-backend --tail 100
   ```

4. **Is port 8080 listening?**
   ```bash
   sudo ss -tlnp | grep 8080
   # Should show: LISTEN on :8080
   ```

5. **Can you reach the service locally?**
   ```bash
   curl -v http://localhost:8080/health
   # Should get 403 or 200, NOT connection refused
   ```

6. **Is Cloudflare tunnel connected?**
   ```bash
   sudo journalctl -u cloudflared --since "5 minutes ago"
   # Look for "Connection established" or errors
   ```

---

## Common Mistakes

❌ **Using HTTPS in config** - Should be `http://localhost:8080`, not `https://`

❌ **Wrong hostname** - Must be exactly `api.primrose.work`

❌ **Missing health token** - Add `X-Health-Token` header to Postman

❌ **Service not started** - Run `sudo ./deploy.sh --force`

❌ **Tunnel not restarted** - After config changes, run `sudo systemctl restart cloudflared`

---

## Contact Info

If still stuck, provide:
1. Output of: `sudo docker stack services primrose`
2. Output of: `sudo docker service logs primrose_primrose-backend --tail 30`
3. Output of: `sudo journalctl -u cloudflared --since "5 minutes ago"`
4. Content of: `sudo cat /root/.cloudflared/config.yml`

