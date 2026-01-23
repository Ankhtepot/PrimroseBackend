#!/usr/bin/env bash
# One-liner to check and display Cloudflare tunnel configuration
# Usage: bash check-tunnel.sh

echo "=== Quick Cloudflare Tunnel Status ==="
echo ""

# Check if service is running
echo "1. Backend Service Status:"
sudo docker stack services primrose 2>/dev/null || echo "   Stack not deployed!"
echo ""

# Check port
echo "2. Port 8080 Status:"
sudo ss -tlnp | grep 8080 || echo "   Port 8080 not listening!"
echo ""

# Check Cloudflare tunnel
echo "3. Cloudflare Tunnel Status:"
if sudo systemctl status cloudflared --no-pager | grep "Active:" 2>/dev/null; then
    echo "   Service is running"
elif pgrep -f cloudflared >/dev/null 2>&1; then
    echo "   Process is running (not as systemd service)"
    ps aux | grep cloudflared | grep -v grep
else
    echo "   Cloudflare tunnel not running!"
fi
echo ""

# Show config
echo "4. Cloudflare Config:"
if [ -f /root/.cloudflared/config.yml ]; then
    cat /root/.cloudflared/config.yml
else
    echo "   Config not found at /root/.cloudflared/config.yml"
fi
echo ""

# Test health endpoint
echo "5. Local Health Check:"
HEALTH_TOKEN=$(grep -E "^(HEALTH_TOKEN|PRIMROSE_HEALTH_TOKEN)=" /srv/primrose/PrimroseBackend/.env 2>/dev/null | cut -d= -f2 | tr -d '\r\n' | head -n1)
if [ -n "$HEALTH_TOKEN" ]; then
    echo "   Testing with token..."
    curl -s --max-time 5 http://localhost:8080/health -H "X-Health-Token: $HEALTH_TOKEN" || echo "   Failed or timed out!"
else
    echo "   No health token found, testing without..."
    curl -s --max-time 5 http://localhost:8080/health || echo "   Failed or timed out!"
fi
echo ""
echo ""

# Show recent logs
echo "6. Recent Backend Logs (last 5 lines):"
sudo docker service logs primrose_primrose-backend --tail 5 2>/dev/null || echo "   Cannot get logs!"
echo ""

# Show recent tunnel logs
echo "7. Recent Tunnel Logs:"
sudo journalctl -u cloudflared --since "2 minutes ago" --no-pager | tail -n 5 || echo "   Cannot get logs!"
echo ""

echo "=== Done ==="
echo ""
echo "To fix issues:"
echo "  - Restart backend: cd /srv/primrose && sudo ./deploy.sh --force"
echo "  - Restart tunnel:  sudo systemctl restart cloudflared"
echo "  - Edit config:     sudo nano /root/.cloudflared/config.yml"

