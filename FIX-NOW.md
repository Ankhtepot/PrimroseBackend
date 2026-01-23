# Copy-Paste Commands to Fix 503 Error

## 🎯 SSH to your server and run this entire block:

```bash
# Navigate to project
cd /srv/primrose

# Run quick diagnostic
echo "=== Running Quick Diagnostic ==="
bash scripts/check-tunnel.sh

echo ""
echo "=== Checking Cloudflare Config ==="
echo "Your config at /root/.cloudflared/config.yml:"
sudo cat /root/.cloudflared/config.yml
echo ""

# Get health token
HEALTH_TOKEN=$(cat /srv/primrose/PrimroseBackend/.env 2>/dev/null | grep -E "^(HEALTH_TOKEN|PRIMROSE_HEALTH_TOKEN)=" | cut -d= -f2 | tr -d '\r\n' | head -n1)

echo "=== Your Health Token ==="
echo "$HEALTH_TOKEN"
echo ""
echo "Copy this token and use it in Postman as header:"
echo "X-Health-Token: $HEALTH_TOKEN"
echo ""

# Test local connectivity
echo "=== Testing Local Connection ==="
if [ -n "$HEALTH_TOKEN" ]; then
    RESULT=$(curl -s -w "\n%{http_code}" http://localhost:8080/health -H "X-Health-Token: $HEALTH_TOKEN")
    HTTP_CODE=$(echo "$RESULT" | tail -n1)
    BODY=$(echo "$RESULT" | head -n-1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ Local test PASSED: $BODY"
    else
        echo "✗ Local test FAILED with code: $HTTP_CODE"
        echo "   Response: $BODY"
        echo ""
        echo "Backend is not responding correctly. Restarting..."
        sudo ./deploy.sh --force
        echo "Waiting 30 seconds for service to start..."
        sleep 30
    fi
else
    echo "✗ No health token found in .env file"
fi

echo ""
echo "=== Testing via Cloudflare Tunnel ==="
if [ -n "$HEALTH_TOKEN" ]; then
    RESULT=$(curl -s -w "\n%{http_code}" https://api.primrose.work/health -H "X-Health-Token: $HEALTH_TOKEN")
    HTTP_CODE=$(echo "$RESULT" | tail -n1)
    BODY=$(echo "$RESULT" | head -n-1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ Tunnel test PASSED: $BODY"
        echo ""
        echo "🎉 SUCCESS! Your API is working correctly!"
        echo "   Test in Postman:"
        echo "   URL: https://api.primrose.work/health"
        echo "   Header: X-Health-Token: $HEALTH_TOKEN"
    else
        echo "✗ Tunnel test FAILED with code: $HTTP_CODE"
        echo "   Response: $BODY"
        echo ""
        echo "Local works but tunnel doesn't. Checking tunnel..."
        
        # Check tunnel status
        if ! systemctl is-active --quiet cloudflared; then
            echo "Cloudflare tunnel is not running. Starting it..."
            sudo systemctl start cloudflared
            sleep 5
        else
            echo "Cloudflare tunnel is running. Restarting it..."
            sudo systemctl restart cloudflared
            sleep 5
        fi
        
        echo "Testing again..."
        sleep 2
        RESULT2=$(curl -s -w "\n%{http_code}" https://api.primrose.work/health -H "X-Health-Token: $HEALTH_TOKEN")
        HTTP_CODE2=$(echo "$RESULT2" | tail -n1)
        BODY2=$(echo "$RESULT2" | head -n-1)
        
        if [ "$HTTP_CODE2" = "200" ]; then
            echo "✓ Tunnel test NOW PASSED: $BODY2"
            echo ""
            echo "🎉 SUCCESS after restart!"
        else
            echo "✗ Still failing. Please check your config manually:"
            echo "   sudo nano /root/.cloudflared/config.yml"
            echo ""
            echo "Ensure it has:"
            echo "  ingress:"
            echo "    - hostname: api.primrose.work"
            echo "      service: http://localhost:8080"
        fi
    fi
fi

echo ""
echo "=== Summary ==="
echo "Backend service status:"
sudo docker stack services primrose | grep primrose-backend || echo "Stack not deployed!"
echo ""
echo "Cloudflare tunnel status:"
sudo systemctl status cloudflared --no-pager | grep "Active:" || echo "Service not found!"
```

---

## What This Script Does:

1. ✅ Runs quick diagnostic
2. ✅ Shows your Cloudflare config
3. ✅ Extracts and displays your health token
4. ✅ Tests local backend connection
5. ✅ Tests via Cloudflare tunnel
6. ✅ Auto-fixes common issues
7. ✅ Shows you exactly what to put in Postman

---

## After Running the Script:

### If Successful (you see "🎉 SUCCESS"):
1. Open Postman
2. Create GET request to: `https://api.primrose.work/health`
3. Add header: `X-Health-Token: <the_value_shown_in_output>`
4. Send request
5. You should get: `{"status":"ok"}`

### If Still Failing:
The script will tell you what's wrong. Common fixes:

**If config is wrong:**
```bash
sudo nano /root/.cloudflared/config.yml
```
Make sure it says:
```yaml
ingress:
  - hostname: api.primrose.work
    service: http://localhost:8080
```
Then: `sudo systemctl restart cloudflared`

**If service won't start:**
```bash
cd /srv/primrose
sudo docker stack rm primrose
sleep 15
sudo ./deploy.sh --force
```

---

## Manual Testing in Postman

Once you have your health token from the script output:

```
URL: https://api.primrose.work/health
Method: GET
Headers:
  X-Health-Token: <paste_token_here>
```

Expected response: `{"status":"ok"}` with 200 status code

---

## Need More Help?

Run full diagnostics:
```bash
cd /srv/primrose
bash scripts/diagnose-cloudflare-tunnel.sh
```

Or read the guides:
- `QUICK-FIX-503.md`
- `CLOUDFLARE_TUNNEL_TROUBLESHOOTING.md`
- `CLOUDFLARE-SETUP.md`

