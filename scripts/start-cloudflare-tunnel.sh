#!/usr/bin/env bash
# Check and start Cloudflare tunnel
# This script checks if cloudflared is running and starts it if needed

echo "=== Cloudflare Tunnel Check & Start ==="
echo ""

# Check if cloudflared is installed
if ! command -v cloudflared >/dev/null 2>&1; then
    echo "❌ cloudflared is not installed!"
    echo ""
    echo "To install:"
    echo "  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
    echo "  sudo dpkg -i cloudflared-linux-amd64.deb"
    exit 1
fi

echo "✓ cloudflared is installed: $(cloudflared --version | head -n1)"
echo ""

# Check if tunnel is running
if pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
    echo "✓ Cloudflare tunnel is running"
    echo ""
    echo "Process details:"
    ps aux | grep "cloudflared tunnel" | grep -v grep
    echo ""
else
    echo "❌ Cloudflare tunnel is NOT running"
    echo ""
    
    # Check if config exists
    if [ ! -f /root/.cloudflared/config.yml ]; then
        echo "❌ Config file not found at /root/.cloudflared/config.yml"
        exit 1
    fi
    
    echo "Config file found. Starting tunnel..."
    echo ""
    
    # Try to start as systemd service first
    if systemctl status cloudflared >/dev/null 2>&1; then
        echo "Starting as systemd service..."
        sudo systemctl start cloudflared
        sleep 2
        if systemctl is-active --quiet cloudflared; then
            echo "✓ Tunnel started as systemd service"
        else
            echo "❌ Failed to start as systemd service"
            systemctl status cloudflared --no-pager
        fi
    else
        echo "No systemd service configured. You need to either:"
        echo ""
        echo "Option 1: Run manually in background"
        echo "  nohup cloudflared tunnel --config /root/.cloudflared/config.yml run > /var/log/cloudflared.log 2>&1 &"
        echo ""
        echo "Option 2: Install as systemd service"
        echo "  sudo cloudflared service install"
        echo "  sudo systemctl start cloudflared"
        echo ""
    fi
fi

# Test connectivity
echo ""
echo "=== Testing Connectivity ==="
echo ""

# Get health token
HEALTH_TOKEN=$(grep -E "^(HEALTH_TOKEN|PRIMROSE_HEALTH_TOKEN)=" /srv/primrose/PrimroseBackend/.env 2>/dev/null | cut -d= -f2 | tr -d '\r\n' | head -n1)

# Test local
echo "Testing local backend (http://localhost:8080/health)..."
if [ -n "$HEALTH_TOKEN" ]; then
    RESPONSE=$(curl -s --max-time 5 -w "\n%{http_code}" http://localhost:8080/health -H "X-Health-Token: $HEALTH_TOKEN" 2>/dev/null)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ Local test PASSED: $BODY"
    else
        echo "❌ Local test FAILED with code: $HTTP_CODE"
        echo "   Response: $BODY"
    fi
else
    echo "⚠ No health token found - testing without token"
    RESPONSE=$(curl -s --max-time 5 -w "\n%{http_code}" http://localhost:8080/health 2>/dev/null)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    echo "   Response code: $HTTP_CODE"
    echo "   Body: $BODY"
fi

echo ""

# Test via tunnel (if running)
if pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
    echo "Testing via Cloudflare tunnel (https://api.primrose.work/health)..."
    sleep 2  # Give tunnel a moment to establish
    
    if [ -n "$HEALTH_TOKEN" ]; then
        RESPONSE=$(curl -s --max-time 10 -w "\n%{http_code}" https://api.primrose.work/health -H "X-Health-Token: $HEALTH_TOKEN" 2>/dev/null)
        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        BODY=$(echo "$RESPONSE" | head -n-1)
        
        if [ "$HTTP_CODE" = "200" ]; then
            echo "✓ Tunnel test PASSED: $BODY"
            echo ""
            echo "🎉 SUCCESS! Everything is working!"
            echo ""
            echo "Use in Postman:"
            echo "  URL: https://api.primrose.work/health"
            echo "  Header: X-Health-Token: $HEALTH_TOKEN"
        else
            echo "❌ Tunnel test FAILED with code: $HTTP_CODE"
            echo "   Response: $BODY"
            echo ""
            echo "Local works but tunnel doesn't. Check tunnel logs:"
            echo "  tail -f /var/log/cloudflared.log"
            echo "  OR"
            echo "  journalctl -u cloudflared -f"
        fi
    fi
else
    echo "⚠ Tunnel not running, skipping remote test"
fi

echo ""
echo "=== Done ==="

