# YOUR SPECIFIC ISSUE - Commands to Run NOW

Based on your log output, here's what's happening and how to fix it:

## 🔍 Current Status

✅ **Backend is running** - 1/1 replicas  
✅ **Port 8080 is listening** - dockerd has it open  
✅ **Config file exists** - `/root/.cloudflared/config.yml` looks correct  
❌ **Cloudflare tunnel is NOT running** - "Unit cloudflared.service could not be found"  
⚠️ **Health check hanging** - backend might not be responding properly  

---

## 🚀 COMMANDS TO RUN NOW (in order)

### 1. First, let's test if backend actually responds:

```bash
# Test with a timeout to see if it hangs
curl -v --max-time 5 http://localhost:8080/health
```

**If this hangs/times out:** Your backend has an issue. Check logs:
```bash
sudo docker service logs primrose_primrose-backend --tail 50
```

**If you get 403:** You need the health token. Get it:
```bash
cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN
```

Then test with token:
```bash
HEALTH_TOKEN=$(cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN | cut -d= -f2 | tr -d '\r\n')
curl -v --max-time 5 http://localhost:8080/health -H "X-Health-Token: $HEALTH_TOKEN"
```

### 2. Check if cloudflared is installed:

```bash
cloudflared --version
```

**If not found, install it:**
```bash
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb
```

### 3. Check if cloudflared tunnel is running (but not as systemd):

```bash
ps aux | grep cloudflared
```

**If nothing is running**, start the tunnel:

**Option A: Install as systemd service (recommended):**
```bash
sudo cloudflared service install
sudo systemctl start cloudflared
sudo systemctl enable cloudflared
sudo systemctl status cloudflared
```

**Option B: Run manually in background:**
```bash
cd /root/.cloudflared
nohup cloudflared tunnel --config /root/.cloudflared/config.yml run > /var/log/cloudflared.log 2>&1 &
```

**Check if it started:**
```bash
ps aux | grep cloudflared
tail -f /var/log/cloudflared.log
```

### 4. Once tunnel is running, test via Cloudflare:

```bash
HEALTH_TOKEN=$(cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN | cut -d= -f2 | tr -d '\r\n')
curl -v https://api.primrose.work/health -H "X-Health-Token: $HEALTH_TOKEN"
```

**Expected result:** `{"status":"ok"}` with 200 status

---

## 🔥 QUICK FIX - Copy Paste This Entire Block:

```bash
#!/bin/bash
echo "=== Quick Fix Script ==="
echo ""

# Get health token
HEALTH_TOKEN=$(cat /srv/primrose/PrimroseBackend/.env 2>/dev/null | grep -E "^(HEALTH_TOKEN|PRIMROSE_HEALTH_TOKEN)=" | cut -d= -f2 | tr -d '\r\n' | head -n1)
echo "Health Token: $HEALTH_TOKEN"
echo ""

# Test backend locally
echo "1. Testing local backend..."
RESPONSE=$(timeout 5 curl -s -w "\n%{http_code}" http://localhost:8080/health -H "X-Health-Token: $HEALTH_TOKEN" 2>/dev/null || echo -e "\nTIMEOUT")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "   ✓ Backend responds: $BODY"
elif [ "$HTTP_CODE" = "TIMEOUT" ]; then
    echo "   ❌ Backend TIMED OUT - checking logs..."
    sudo docker service logs primrose_primrose-backend --tail 20
    echo ""
    echo "   Try restarting backend:"
    echo "   cd /srv/primrose && sudo ./deploy.sh --force"
    exit 1
else
    echo "   ❌ Backend error: HTTP $HTTP_CODE"
    echo "   Response: $BODY"
    exit 1
fi

echo ""

# Check if cloudflared is installed
echo "2. Checking cloudflared installation..."
if ! command -v cloudflared >/dev/null 2>&1; then
    echo "   Installing cloudflared..."
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    sudo dpkg -i cloudflared-linux-amd64.deb
    rm cloudflared-linux-amd64.deb
    echo "   ✓ Installed"
else
    echo "   ✓ Already installed: $(cloudflared --version | head -n1)"
fi

echo ""

# Check if tunnel is running
echo "3. Checking tunnel status..."
if pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
    echo "   ✓ Tunnel is already running"
else
    echo "   ❌ Tunnel not running. Starting..."
    
    # Try systemd first
    if systemctl list-unit-files | grep -q cloudflared; then
        sudo systemctl start cloudflared
        sleep 3
        if systemctl is-active --quiet cloudflared; then
            echo "   ✓ Started as systemd service"
        else
            echo "   ❌ Systemd start failed, trying manual start..."
            cd /root/.cloudflared
            nohup cloudflared tunnel --config /root/.cloudflared/config.yml run > /var/log/cloudflared.log 2>&1 &
            sleep 3
            if pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
                echo "   ✓ Started manually"
            else
                echo "   ❌ Failed to start. Check: tail -f /var/log/cloudflared.log"
                exit 1
            fi
        fi
    else
        # Install as systemd service
        echo "   Installing cloudflared as systemd service..."
        sudo cloudflared service install
        sudo systemctl start cloudflared
        sudo systemctl enable cloudflared
        sleep 3
        if systemctl is-active --quiet cloudflared; then
            echo "   ✓ Installed and started as systemd service"
        else
            echo "   ❌ Failed. Check: journalctl -u cloudflared -n 50"
            exit 1
        fi
    fi
fi

echo ""

# Test via tunnel
echo "4. Testing via Cloudflare tunnel..."
sleep 2  # Give tunnel time to connect
RESPONSE=$(timeout 10 curl -s -w "\n%{http_code}" https://api.primrose.work/health -H "X-Health-Token: $HEALTH_TOKEN" 2>/dev/null || echo -e "\nTIMEOUT")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "   ✓ Tunnel test PASSED: $BODY"
    echo ""
    echo "🎉 SUCCESS! Your API is working!"
    echo ""
    echo "Test in Postman:"
    echo "  URL: https://api.primrose.work/health"
    echo "  Header: X-Health-Token: $HEALTH_TOKEN"
elif [ "$HTTP_CODE" = "TIMEOUT" ]; then
    echo "   ❌ Tunnel request timed out"
    echo "   Check tunnel logs:"
    if systemctl is-active --quiet cloudflared 2>/dev/null; then
        echo "   journalctl -u cloudflared -f"
    else
        echo "   tail -f /var/log/cloudflared.log"
    fi
else
    echo "   ❌ Tunnel test FAILED: HTTP $HTTP_CODE"
    echo "   Response: $BODY"
    echo ""
    echo "   Check tunnel logs and restart if needed"
fi

echo ""
echo "=== Done ==="
```

---

## 📊 Understanding Your Config

Your config shows:
```yaml
service: http://127.0.0.1:8080
```

This is **CORRECT** (127.0.0.1 and localhost are the same).

The issue is that **the tunnel daemon is not running at all**.

---

## ✅ Quick Verification Commands

After starting the tunnel, verify with:

```bash
# Check tunnel process
ps aux | grep cloudflared | grep -v grep

# Check if systemd service exists
systemctl status cloudflared

# Check tunnel logs
journalctl -u cloudflared -f
# OR (if running manually)
tail -f /var/log/cloudflared.log

# Test the connection
HEALTH_TOKEN=$(cat /srv/primrose/PrimroseBackend/.env | grep HEALTH_TOKEN | cut -d= -f2 | tr -d '\r\n')
curl https://api.primrose.work/health -H "X-Health-Token: $HEALTH_TOKEN"
```

---

## 🆘 If Backend is Hanging

If the curl to `localhost:8080/health` hangs forever, your backend has an issue.

**Check logs:**
```bash
sudo docker service logs primrose_primrose-backend --tail 100 --follow
```

**Look for:**
- Database connection issues
- Startup errors
- Health endpoint errors

**Fix by restarting:**
```bash
cd /srv/primrose
sudo ./deploy.sh --force
```

---

## 📝 Summary

Your issues are:
1. **Cloudflare tunnel NOT running** - Need to start it
2. **Health endpoint might be hanging** - Need to test with timeout
3. **BOM in script** - Fixed in updated scripts

Run the quick fix script above, and it will handle everything!

