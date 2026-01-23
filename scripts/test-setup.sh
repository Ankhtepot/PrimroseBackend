#!/usr/bin/env bash
# Simple test script - just verify everything works, don't restart anything

echo "=== Testing Your Setup ==="
echo ""

# Get health token
HEALTH_TOKEN=$(cat /srv/primrose/PrimroseBackend/.env 2>/dev/null | grep -E "^(HEALTH_TOKEN|PRIMROSE_HEALTH_TOKEN)=" | cut -d= -f2 | tr -d '\r\n' | head -n1)

if [ -z "$HEALTH_TOKEN" ]; then
    echo "❌ Could not find HEALTH_TOKEN in .env file"
    exit 1
fi

echo "Health Token: $HEALTH_TOKEN"
echo ""

# Test 1: Backend locally
echo "1. Testing backend locally (http://localhost:8080/health)..."
RESPONSE=$(timeout 5 curl -s -w "\n%{http_code}" http://localhost:8080/health -H "X-Health-Token: $HEALTH_TOKEN" 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "   ✓ Backend responds: $BODY"
elif [ -z "$HTTP_CODE" ]; then
    echo "   ❌ Backend timed out or no response"
    echo "   Check logs: sudo docker service logs primrose_primrose-backend --tail 30"
    exit 1
else
    echo "   ❌ Backend error: HTTP $HTTP_CODE"
    echo "   Response: $BODY"
    exit 1
fi

echo ""

# Test 2: Check if cloudflared is running
echo "2. Checking cloudflared status..."
if pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
    echo "   ✓ Cloudflared tunnel is running"
    echo ""
    echo "   Process:"
    ps aux | grep "cloudflared tunnel" | grep -v grep | head -n1 | awk '{print "   PID: "$2", CMD: "$11" "$12" "$13" "$14" "$15}'
else
    echo "   ❌ Cloudflared tunnel is NOT running"
    echo ""
    echo "   Start it with:"
    echo "   cd /root/.cloudflared"
    echo "   cloudflared tunnel --config config.yml run"
    exit 1
fi

echo ""

# Test 3: Via Cloudflare tunnel
echo "3. Testing via Cloudflare tunnel (https://api.primrose.work/health)..."
sleep 2  # Give tunnel a moment if it just started

RESPONSE=$(timeout 10 curl -s -w "\n%{http_code}" https://api.primrose.work/health -H "X-Health-Token: $HEALTH_TOKEN" 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "   ✓ Tunnel test PASSED: $BODY"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎉 SUCCESS! Everything is working! 🎉"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Your API is live at: https://api.primrose.work"
    echo ""
    echo "Test in Postman:"
    echo "  URL:    https://api.primrose.work/health"
    echo "  Method: GET"
    echo "  Header: X-Health-Token: $HEALTH_TOKEN"
    echo ""
    echo "Expected response:"
    echo '  {"status":"ok"}'
    echo ""
    echo "Status: 200 OK"
    echo ""
elif [ -z "$HTTP_CODE" ]; then
    echo "   ❌ Request timed out"
    echo ""
    echo "   Possible issues:"
    echo "   1. Tunnel is not fully connected yet (wait 10-20 seconds)"
    echo "   2. Cloudflare config points to wrong address"
    echo "   3. Network/firewall issue"
    echo ""
    echo "   Check config:"
    echo "   cat /root/.cloudflared/config.yml"
    echo ""
    echo "   Should contain:"
    echo "   service: http://localhost:8080"
    echo "   or"
    echo "   service: http://127.0.0.1:8080"
else
    echo "   ❌ Request failed: HTTP $HTTP_CODE"
    echo "   Response: $BODY"
    echo ""
    if [ "$HTTP_CODE" = "503" ]; then
        echo "   503 means Cloudflare can't reach your backend."
        echo ""
        echo "   Check your config:"
        echo "   cat /root/.cloudflared/config.yml"
        echo ""
        echo "   Ensure it has:"
        echo "   service: http://localhost:8080"
        echo "   (or http://127.0.0.1:8080)"
    fi
fi

echo ""
echo "=== Test Complete ==="

