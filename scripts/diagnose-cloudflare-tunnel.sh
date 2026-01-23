#!/usr/bin/env bash
# Server-side Cloudflare Tunnel Diagnostics
# Run this on your Hetzner server to diagnose connectivity issues

set -euo pipefail

echo "=== PrimroseBackend Cloudflare Tunnel Diagnostics ==="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Get sudo if needed
SUDO=""
if [ "$EUID" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO=sudo
  fi
fi

ENV_FILE="/srv/primrose/PrimroseBackend/.env"

# Test 1: Check if Docker Swarm is active
echo -e "${YELLOW}Test 1: Checking Docker Swarm status...${NC}"
SWARM_STATE=$($SUDO docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "error")
if [ "$SWARM_STATE" = "active" ]; then
    echo -e "${GREEN}✓ Docker Swarm is active${NC}"
else
    echo -e "${RED}✗ Docker Swarm is not active (state: $SWARM_STATE)${NC}"
    echo -e "${YELLOW}  Run: sudo docker swarm init${NC}"
fi
echo ""

# Test 2: Check if stack is deployed
echo -e "${YELLOW}Test 2: Checking if stack is deployed...${NC}"
if $SUDO docker stack ls --format '{{.Name}}' | grep -q "^primrose$"; then
    echo -e "${GREEN}✓ Stack 'primrose' is deployed${NC}"
    
    # Check service replicas
    echo -e "${GRAY}  Service status:${NC}"
    $SUDO docker stack services primrose --format "table {{.Name}}\t{{.Replicas}}\t{{.Image}}" | tail -n +2 | while read line; do
        if echo "$line" | grep -q "0/"; then
            echo -e "${RED}    $line${NC}"
        elif echo "$line" | grep -qE "[0-9]+/[0-9]+"; then
            replicas=$(echo "$line" | awk '{print $2}')
            current=$(echo "$replicas" | cut -d/ -f1)
            desired=$(echo "$replicas" | cut -d/ -f2)
            if [ "$current" = "$desired" ]; then
                echo -e "${GREEN}    $line${NC}"
            else
                echo -e "${YELLOW}    $line${NC}"
            fi
        else
            echo -e "${GRAY}    $line${NC}"
        fi
    done
else
    echo -e "${RED}✗ Stack 'primrose' is not deployed${NC}"
    echo -e "${YELLOW}  Run: cd /srv/primrose && sudo ./deploy.sh${NC}"
fi
echo ""

# Test 3: Check if service is listening on port 8080
echo -e "${YELLOW}Test 3: Checking if service is listening on port 8080...${NC}"
if $SUDO netstat -tlnp 2>/dev/null | grep -q ":8080" || $SUDO ss -tlnp 2>/dev/null | grep -q ":8080"; then
    echo -e "${GREEN}✓ Service is listening on port 8080${NC}"
    $SUDO netstat -tlnp 2>/dev/null | grep ":8080" || $SUDO ss -tlnp 2>/dev/null | grep ":8080" | head -n 1
else
    echo -e "${RED}✗ No service listening on port 8080${NC}"
    echo -e "${YELLOW}  Check service logs: sudo docker service logs primrose_primrose-backend --tail 50${NC}"
fi
echo ""

# Test 4: Get health token from .env
echo -e "${YELLOW}Test 4: Checking health token configuration...${NC}"
if [ -f "$ENV_FILE" ]; then
    if grep -q "HEALTH_TOKEN" "$ENV_FILE" || grep -q "PRIMROSE_HEALTH_TOKEN" "$ENV_FILE"; then
        echo -e "${GREEN}✓ Health token is configured in .env${NC}"
        HEALTH_TOKEN=$(grep -E "^(HEALTH_TOKEN|PRIMROSE_HEALTH_TOKEN)=" "$ENV_FILE" | cut -d= -f2 | tr -d '\r\n' | head -n1)
        if [ -n "$HEALTH_TOKEN" ]; then
            echo -e "${GRAY}  Token: ${HEALTH_TOKEN:0:8}...${NC}"
        else
            echo -e "${YELLOW}  Warning: Token variable exists but is empty${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Health token not found in .env (optional)${NC}"
        echo -e "${GRAY}  Health endpoint will be open without authentication${NC}"
        HEALTH_TOKEN=""
    fi
else
    echo -e "${RED}✗ .env file not found at $ENV_FILE${NC}"
    HEALTH_TOKEN=""
fi
echo ""

# Test 5: Test local health endpoint
echo -e "${YELLOW}Test 5: Testing local health endpoint...${NC}"

# Test without token first
echo -e "${GRAY}  Testing without token...${NC}"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health 2>/dev/null || echo "000")
if [ "$RESPONSE" = "200" ]; then
    echo -e "${GREEN}  ✓ Health endpoint responds: 200 OK (no token required)${NC}"
elif [ "$RESPONSE" = "403" ]; then
    echo -e "${YELLOW}  ⚠ Health endpoint responds: 403 Forbidden (token required)${NC}"
    
    # Test with token if available
    if [ -n "$HEALTH_TOKEN" ]; then
        echo -e "${GRAY}  Testing with token...${NC}"
        RESPONSE_WITH_TOKEN=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Health-Token: $HEALTH_TOKEN" http://localhost:8080/health 2>/dev/null || echo "000")
        if [ "$RESPONSE_WITH_TOKEN" = "200" ]; then
            echo -e "${GREEN}  ✓ Health endpoint responds: 200 OK (with token)${NC}"
            BODY=$(curl -s -H "X-Health-Token: $HEALTH_TOKEN" http://localhost:8080/health 2>/dev/null || echo "{}")
            echo -e "${GRAY}  Response: $BODY${NC}"
        else
            echo -e "${RED}  ✗ Health endpoint responds: $RESPONSE_WITH_TOKEN (with token)${NC}"
        fi
    fi
elif [ "$RESPONSE" = "000" ]; then
    echo -e "${RED}  ✗ Cannot connect to health endpoint${NC}"
    echo -e "${YELLOW}  Service may not be running${NC}"
else
    echo -e "${RED}  ✗ Health endpoint responds: $RESPONSE${NC}"
fi
echo ""

# Test 6: Check Cloudflare tunnel status
echo -e "${YELLOW}Test 6: Checking Cloudflare tunnel status...${NC}"
if systemctl is-active --quiet cloudflared 2>/dev/null; then
    echo -e "${GREEN}✓ Cloudflare tunnel service is running${NC}"
    echo -e "${GRAY}  Status:${NC}"
    $SUDO systemctl status cloudflared --no-pager -l | grep -E "(Active:|Main PID:)" | sed 's/^/    /'
elif $SUDO docker ps --format '{{.Names}}' | grep -q cloudflared; then
    echo -e "${GREEN}✓ Cloudflare tunnel running in Docker${NC}"
    $SUDO docker ps --filter "name=cloudflared" --format "table {{.Names}}\t{{.Status}}" | sed 's/^/    /'
else
    echo -e "${YELLOW}⚠ Cloudflare tunnel service not detected${NC}"
    echo -e "${GRAY}  Check if tunnel is running manually: cloudflared tunnel list${NC}"
fi
echo ""

# Test 7: Check recent backend logs
echo -e "${YELLOW}Test 7: Checking recent backend logs...${NC}"
if $SUDO docker stack ls --format '{{.Name}}' | grep -q "^primrose$"; then
    echo -e "${GRAY}  Last 10 log lines:${NC}"
    $SUDO docker service logs primrose_primrose-backend --tail 10 2>/dev/null | sed 's/^/    /' || echo -e "${RED}    Failed to get logs${NC}"
else
    echo -e "${YELLOW}  Stack not deployed, skipping logs${NC}"
fi
echo ""

# Test 8: Check secrets
echo -e "${YELLOW}Test 8: Checking Docker secrets...${NC}"
REQUIRED_SECRETS=("primrose_jwt" "primrose_shared" "db_password" "primrose_admin_username" "primrose_admin_password")
MISSING_SECRETS=()
for secret in "${REQUIRED_SECRETS[@]}"; do
    if $SUDO docker secret ls --format '{{.Name}}' | grep -q "^${secret}$"; then
        echo -e "${GREEN}  ✓ $secret${NC}"
    else
        echo -e "${RED}  ✗ $secret (missing)${NC}"
        MISSING_SECRETS+=("$secret")
    fi
done

if $SUDO docker secret ls --format '{{.Name}}' | grep -q "^primrose_health_token$"; then
    echo -e "${GREEN}  ✓ primrose_health_token${NC}"
else
    echo -e "${YELLOW}  ⚠ primrose_health_token (optional, not found)${NC}"
fi

if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}Missing secrets detected!${NC}"
    echo -e "${YELLOW}Run: cd /srv/primrose && sudo bash scripts/recreate_secrets_from_env.sh${NC}"
fi
echo ""

# Summary
echo -e "${CYAN}=== Summary and Recommendations ===${NC}"
echo ""

if [ "$SWARM_STATE" != "active" ]; then
    echo -e "${RED}1. Initialize Docker Swarm:${NC}"
    echo -e "${GRAY}   sudo docker swarm init${NC}"
    echo ""
fi

if ! $SUDO docker stack ls --format '{{.Name}}' | grep -q "^primrose$"; then
    echo -e "${RED}2. Deploy the stack:${NC}"
    echo -e "${GRAY}   cd /srv/primrose && sudo ./deploy.sh${NC}"
    echo ""
elif [ "$RESPONSE" = "000" ] || [ "$RESPONSE" = "503" ]; then
    echo -e "${YELLOW}2. Service appears to be down, try redeploying:${NC}"
    echo -e "${GRAY}   cd /srv/primrose && sudo ./deploy.sh --force${NC}"
    echo ""
fi

if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
    echo -e "${RED}3. Create missing secrets:${NC}"
    echo -e "${GRAY}   cd /srv/primrose && sudo bash scripts/recreate_secrets_from_env.sh${NC}"
    echo ""
fi

if [ "$RESPONSE" = "200" ] || [ "$RESPONSE_WITH_TOKEN" = "200" ] 2>/dev/null; then
    echo -e "${GREEN}✓ Service is healthy and responding correctly!${NC}"
    echo ""
    echo -e "${CYAN}For Postman testing:${NC}"
    if [ -n "$HEALTH_TOKEN" ]; then
        echo -e "${GRAY}Add header: X-Health-Token: $HEALTH_TOKEN${NC}"
    fi
    echo -e "${GRAY}URL: https://api.primrose.work/health${NC}"
else
    echo -e "${YELLOW}Check the Cloudflare tunnel configuration:${NC}"
    echo -e "${GRAY}1. Edit config: sudo nano /root/.cloudflared/config.yml${NC}"
    echo -e "${GRAY}   Ensure service points to: http://localhost:8080${NC}"
    echo -e "${GRAY}2. Restart tunnel: sudo systemctl restart cloudflared${NC}"
    echo -e "${GRAY}3. Check tunnel logs: sudo journalctl -u cloudflared -f${NC}"
fi

echo ""
echo -e "${CYAN}=== Diagnostics Complete ===${NC}"

