#!/usr/bin/env bash
# check_stack.sh - health & readiness checks for PrimroseBackend stack (Hetzner)
# Usage: sudo ./scripts/check_stack.sh
# Writes log to ./primrose-check.log (repo root) and prints a short summary to stdout.

set -u
LOGFILE="$(pwd)/primrose-check.log"
SUDO=""
if [ "$EUID" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO=sudo
  else
    echo "Warning: running without sudo - some checks may fail"
  fi
fi

echo "========== Primrose stack check $(date -u +'%Y-%m-%dT%H:%M:%SZ') ==========" | tee -a "$LOGFILE"
failures=0

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"; }
sep() { echo "------------------------------------------------------------" | tee -a "$LOGFILE"; }

# 1) Environment/basic info
sep
log "HOSTNAME: $(hostname)"
log "OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME || true)"
log "Host IPv4: $(hostname -I 2>/dev/null | awk '{print $1}')"
log "User: $(whoami)"

# 2) NGINX checks
sep
log "NGINX checks"
if command -v nginx >/dev/null 2>&1; then
  $SUDO nginx -t 2>&1 | tee -a "$LOGFILE" || { log "nginx -t failed"; failures=$((failures+1)); }
  $SUDO systemctl status nginx --no-pager 2>&1 | sed -n '1,6p' | tee -a "$LOGFILE" || true
  $SUDO ss -lntp | grep -E ':443|:80|nginx' 2>/dev/null | tee -a "$LOGFILE" || true
else
  log "nginx not installed"
  failures=$((failures+1))
fi

# 3) TLS cert files
sep
log "TLS cert files"
CRT=/etc/ssl/certs/primrose.crt
KEY=/etc/ssl/private/primrose.key
if [ -f "$CRT" ] && [ -f "$KEY" ]; then
  ls -l "$CRT" "$KEY" | tee -a "$LOGFILE"
  openssl x509 -in "$CRT" -noout -subject -dates 2>&1 | tee -a "$LOGFILE" || true
  openssl x509 -in "$CRT" -noout -text 2>/dev/null | sed -n '/Subject Alternative Name/,/X509v3/{p}' | tee -a "$LOGFILE" || true
else
  log "Certificate or key missing ($CRT or $KEY)"
  failures=$((failures+1))
fi

# 4) Firewall (UFW)
sep
log "Firewall (UFW) status"
if command -v ufw >/dev/null 2>&1; then
  $SUDO ufw status verbose 2>&1 | tee -a "$LOGFILE" || true
else
  log "ufw not installed"
fi

# 5) Docker & Swarm
sep
log "Docker & Swarm info"
if command -v docker >/dev/null 2>&1; then
  docker info --format '{{json .Swarm}}' 2>/dev/null | tee -a "$LOGFILE" || true
  docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | tee -a "$LOGFILE" || true
  log "Listing secrets:"
  docker secret ls 2>&1 | tee -a "$LOGFILE" || true
  log "Listing networks:"
  docker network ls 2>&1 | tee -a "$LOGFILE" || true
  log "Listing stacks (services):"
  docker stack ls 2>&1 | tee -a "$LOGFILE" || true
  docker stack services primrose 2>&1 | tee -a "$LOGFILE" || true
else
  log "docker not installed"
  failures=$((failures+1))
fi

# 6) Service / task checks
sep
log "Service / task checks for primrose_primrose-backend"
if docker service ls --format '{{.Name}}' 2>/dev/null | grep -q '^primrose_primrose-backend$'; then
  docker service ps primrose_primrose-backend --no-trunc 2>&1 | tee -a "$LOGFILE" || true
  log "Recent logs from service (tail 200):"
  docker service logs primrose_primrose-backend --tail 200 2>&1 | tee -a "$LOGFILE" || true
else
  log "Service primrose_primrose-backend not found. Check stack deploy output."
  failures=$((failures+1))
fi

# 7) Inspect a running container for secrets and dataprotection mount
sep
log "Inspecting a running backend container for /run/secrets and DataProtection-Keys"
CID=$(docker ps --filter "name=primrose_primrose-backend" --format '{{.ID}}' | head -n1 || true)
if [ -n "$CID" ]; then
  log "Found container: $CID"
  docker exec "$CID" ls -l /run/secrets 2>&1 | tee -a "$LOGFILE" || true
  docker exec "$CID" stat -c '%n %a %U:%G %s' /run/secrets/primrose_jwt /run/secrets/primrose_shared 2>&1 | tee -a "$LOGFILE" || true
  docker exec "$CID" ls -ld /home/ubuntu/.aspnet /home/ubuntu/.aspnet/DataProtection-Keys 2>&1 | tee -a "$LOGFILE" || true
else
  log "No running backend container found by name filter primrose_primrose-backend"
fi

# 8) Health check (local via proxy/nginx and direct)
sep
log "Health checks"
VM_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HEALTH_URL_LOCAL="http://127.0.0.1:8080/health"
HEALTH_URL_HTTPS="https://127.0.0.1/health"
# read token from .env if present
HEALTH_TOKEN=""
ENV_FILE="PrimroseBackend/.env"
if [ -f "$ENV_FILE" ]; then
  HEALTH_TOKEN=$(grep -E '^HEALTH_TOKEN=' "$ENV_FILE" | sed -E 's/^HEALTH_TOKEN=//' || true)
fi
# If there's a docker secret primrose_health_token we note it but cannot read it from host
if docker secret ls --format '{{.Name}}' 2>/dev/null | grep -q '^primrose_health_token$'; then
  log "primrose_health_token exists as a Docker secret (value not accessible from host). If HEALTH_TOKEN isn't in .env, header tests will be skipped."
fi

# direct HTTP health (app)
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL_LOCAL" || echo "000")
log "Direct HTTP $HEALTH_URL_LOCAL -> $HTTP_STATUS"
if [ "$HTTP_STATUS" != "200" ]; then failures=$((failures+1)); fi

# HTTPS via nginx (allow insecure since cert may be self-signed)
HTTPS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -k "$HEALTH_URL_HTTPS" || echo "000")
log "HTTPS ${HEALTH_URL_HTTPS} (localhost) -> $HTTPS_STATUS"
if [ "$HTTPS_STATUS" != "200" ]; then failures=$((failures+1)); fi

# If HEALTH_TOKEN set, try header test
if [ -n "$HEALTH_TOKEN" ]; then
  STATUS_WITH_TOKEN=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Health-Token: $HEALTH_TOKEN" "$HEALTH_URL_LOCAL" || echo "000")
  log "Health with header -> $STATUS_WITH_TOKEN"
  if [ "$STATUS_WITH_TOKEN" != "200" ]; then failures=$((failures+1)); fi
else
  log "No HEALTH_TOKEN set locally; if the stack uses a Docker secret for health token, use the token in your monitor requests."
fi

# 9) Final summary
sep
if [ "$failures" -eq 0 ]; then
  log "SUMMARY: All checks passed (0 failures)."
  exit 0
else
  log "SUMMARY: Completed with $failures failure(s). Check above logs for details."
  exit 2
fi

