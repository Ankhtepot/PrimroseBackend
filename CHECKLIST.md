# 503 Error Fix Checklist

## ✅ Pre-Deployment (On Your Windows PC)

- [ ] Review all new files created
- [ ] Commit changes to Git:
  ```powershell
  cd D:\C#\Projects\PrimroseBackend
  git add .
  git commit -m "Add Cloudflare tunnel troubleshooting tools"
  ```
- [ ] Push to master:
  ```powershell
  git push origin master
  ```

---

## ✅ Deployment (On Your Server)

- [ ] SSH to server: `ssh root@your-server-ip`
- [ ] Navigate to project: `cd /srv/primrose`
- [ ] Pull latest code: `git pull origin master`
- [ ] Verify new files exist:
  ```bash
  ls -lh scripts/check-tunnel.sh
  ls -lh scripts/diagnose-cloudflare-tunnel.sh
  ```
- [ ] Make scripts executable (if needed):
  ```bash
  chmod +x scripts/check-tunnel.sh
  chmod +x scripts/diagnose-cloudflare-tunnel.sh
  ```

---

## ✅ Diagnosis

- [ ] Run quick check:
  ```bash
  bash scripts/check-tunnel.sh
  ```
- [ ] Note any errors reported
- [ ] Get your health token from output
- [ ] Save the health token somewhere secure

---

## ✅ Fix Issues

### If Backend Service is Down (0/1 replicas):
- [ ] Restart backend:
  ```bash
  cd /srv/primrose
  sudo ./deploy.sh --force
  ```
- [ ] Wait 30-60 seconds for startup
- [ ] Check status: `sudo docker stack services primrose`
- [ ] Should show 1/1 replicas

### If Cloudflare Config is Wrong:
- [ ] View current config:
  ```bash
  sudo cat /root/.cloudflared/config.yml
  ```
- [ ] Check if it says `service: http://localhost:8080`
- [ ] If not, edit it:
  ```bash
  sudo nano /root/.cloudflared/config.yml
  ```
- [ ] Change to: `service: http://localhost:8080`
- [ ] Save: Ctrl+O, Enter, Ctrl+X
- [ ] Restart tunnel:
  ```bash
  sudo systemctl restart cloudflared
  ```

### If Cloudflare Tunnel is Down:
- [ ] Check status:
  ```bash
  sudo systemctl status cloudflared
  ```
- [ ] If not active, start it:
  ```bash
  sudo systemctl start cloudflared
  ```
- [ ] If active but not working, restart it:
  ```bash
  sudo systemctl restart cloudflared
  ```

---

## ✅ Verification

### On Server:
- [ ] Test local backend:
  ```bash
  HEALTH_TOKEN=$(cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN | cut -d= -f2)
  curl http://localhost:8080/health -H "X-Health-Token: $HEALTH_TOKEN"
  ```
- [ ] Should return: `{"status":"ok"}`

- [ ] Test via Cloudflare tunnel:
  ```bash
  curl https://api.primrose.work/health -H "X-Health-Token: $HEALTH_TOKEN"
  ```
- [ ] Should return: `{"status":"ok"}`

### In Postman (on your PC):
- [ ] Create new GET request
- [ ] Set URL: `https://api.primrose.work/health`
- [ ] Add header:
  - Name: `X-Health-Token`
  - Value: `<paste_your_token_here>`
- [ ] Send request
- [ ] Verify response: `{"status":"ok"}`
- [ ] Verify status code: 200 OK

---

## ✅ Additional Verification

- [ ] Backend service running:
  ```bash
  sudo docker stack services primrose
  ```
  Should show 1/1 for primrose-backend

- [ ] Port 8080 listening:
  ```bash
  sudo ss -tlnp | grep 8080
  ```
  Should show LISTEN on :8080

- [ ] Cloudflare tunnel running:
  ```bash
  sudo systemctl status cloudflared
  ```
  Should show "active (running)"

- [ ] No errors in backend logs:
  ```bash
  sudo docker service logs primrose_primrose-backend --tail 20
  ```
  Check for any errors

- [ ] No errors in tunnel logs:
  ```bash
  sudo journalctl -u cloudflared --since "5 minutes ago"
  ```
  Should show "Connection established"

---

## ✅ Final Test

- [ ] Test from Postman on your computer
- [ ] Test from browser: `https://api.primrose.work/health` (will fail without token header, that's OK)
- [ ] Test from curl on server (both local and remote)
- [ ] All tests pass? ✅ You're done!

---

## ❌ If Still Broken

- [ ] Run full diagnostic:
  ```bash
  cd /srv/primrose
  bash scripts/diagnose-cloudflare-tunnel.sh
  ```
- [ ] Read the output carefully
- [ ] Follow the recommendations in "Summary and Recommendations" section
- [ ] Check the detailed guides:
  - FIX-NOW.md (automated fix)
  - QUICK-FIX-503.md (manual steps)
  - CLOUDFLARE_TUNNEL_TROUBLESHOOTING.md (detailed guide)

---

## 🆘 Emergency Reset (Last Resort)

If nothing works and you just want to start fresh:

- [ ] Run emergency reset:
  ```bash
  cd /srv/primrose
  sudo docker stack rm primrose
  sleep 15
  sudo ./deploy.sh --force
  sleep 30
  sudo systemctl restart cloudflared
  sleep 5
  ```

- [ ] Test again:
  ```bash
  HEALTH_TOKEN=$(cat PrimroseBackend/.env | grep HEALTH_TOKEN | cut -d= -f2)
  curl https://api.primrose.work/health -H "X-Health-Token: $HEALTH_TOKEN"
  ```

---

## 📝 Notes

**Health Token Location:**
```bash
/srv/primrose/PrimroseBackend/.env
```

**Cloudflare Config Location:**
```bash
/root/.cloudflared/config.yml
```

**Correct Config Format:**
```yaml
tunnel: <your-tunnel-id>
credentials-file: /root/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: api.primrose.work
    service: http://localhost:8080    # ← Must be HTTP!
  - service: http_status:404
```

---

## ✅ Success Criteria

Your setup is working correctly when:

1. ✅ `sudo docker stack services primrose` shows 1/1 replicas
2. ✅ `sudo ss -tlnp | grep 8080` shows port listening
3. ✅ `sudo systemctl status cloudflared` shows active (running)
4. ✅ Local curl returns `{"status":"ok"}`
5. ✅ Remote curl via tunnel returns `{"status":"ok"}`
6. ✅ Postman request returns `{"status":"ok"}` with 200 status

---

**Date:** 2026-01-23  
**Issue:** 503 Service Unavailable on api.primrose.work  
**Solution:** Troubleshooting tools + config validation + automated fixes  
**Files Created:** 10 new files  
**Status:** ✅ Ready to deploy

