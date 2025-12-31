#!/usr/bin/env bash
set -euo pipefail

# deploy.sh - update repo, build backend image, and deploy stack (Swarm)
# Place this script in the repository root (/srv/primrose on the server) and run:
#   sudo ./deploy.sh
# It will:
#  - pull latest from origin/master
#  - ensure Docker Swarm is active
#  - create missing Docker secrets from PrimroseBackend/.env (if present)
#  - build the backend image (docker compose build)
#  - deploy the stack with docker stack deploy (uses external secrets)
#  - wait for the backend to become healthy (poll /health)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SUDO=""
if [ "$EUID" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO=sudo
  else
    echo "Run as root or install sudo." >&2
    exit 1
  fi
fi

COMPOSE_FILE="docker-compose.yaml"
STACK_NAME="primrose"
SERVICE_NAME="${STACK_NAME}_primrose-backend"
ENV_PATH="${SCRIPT_DIR}/PrimroseBackend/.env"

echo "[deploy] Working directory: $SCRIPT_DIR"

# 1) Update repository
if [ -d .git ]; then
  echo "[deploy] Pulling latest from origin/master"
  git fetch origin master
  git reset --hard origin/master
else
  echo "[deploy] No git repository found in $SCRIPT_DIR - skipping git pull"
fi

# 2) Ensure Docker Swarm is active
SWARM_STATE=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")
if [ "$SWARM_STATE" != "active" ]; then
  echo "[deploy] Docker Swarm not active - initializing single-node swarm"
  $SUDO docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
else
  echo "[deploy] Swarm is active"
fi

# 3) Ensure required external secrets exist (create from .env if possible)
create_secret_if_missing() {
  name="$1"; env_key="$2"
  if docker secret ls --format '{{.Name}}' | grep -q "^${name}$"; then
    echo "[deploy] secret ${name} already exists"
    return 0
  fi
  if [ -f "$ENV_PATH" ]; then
    val=$(grep -E "^${env_key}=" "$ENV_PATH" | sed -E "s/^${env_key}=//") || true
    if [ -n "$val" ]; then
      echo "[deploy] Creating secret ${name} from ${ENV_PATH}:${env_key}"
      printf '%s' "$val" | $SUDO docker secret create "$name" -
      return 0
    fi
  fi
  echo "[deploy] secret ${name} missing and no ${env_key} found in .env - please create it manually"
  return 1
}

# Try to create primrose_jwt and primrose_shared if missing
create_secret_if_missing primrose_jwt JwtSecret || true
create_secret_if_missing primrose_shared SharedSecret || true
# primrose_health_token optional - do not auto-create

# 4) Remove any old non-swarm network with the same name to avoid conflicts
BRIDGE_NET_NAME="${STACK_NAME}_${STACK_NAME}-net"
# The compose created network name may vary; attempt to remove a same-named bridge network if present
if docker network ls --filter name=${STACK_NAME}_primrose-net -q | grep -q .; then
  echo "[deploy] Removing local network primrose_primrose-net to allow overlay creation"
  $SUDO docker network rm primrose_primrose-net 2>/dev/null || true
fi

# 5) Build backend image using docker compose build
echo "[deploy] Building backend image via docker compose"
$SUDO docker compose build primrose-backend

# 6) Deploy stack via docker stack deploy (swarm will use external secrets)
echo "[deploy] Deploying stack with docker stack deploy (stack=$STACK_NAME)"
$SUDO docker stack deploy --compose-file "$COMPOSE_FILE" "$STACK_NAME"

# 7) Wait for backend service tasks to be running
echo "[deploy] Waiting for backend service tasks to reach RUNNING state"
set +e
for i in {1..30}; do
  RUNNING=$(docker service ps --filter desired-state=running "${STACK_NAME}_primrose-backend" --format '{{.CurrentState}}' 2>/dev/null | grep -c "Running" || true)
  if [ "$RUNNING" -ge 1 ]; then
    echo "[deploy] Backend has running tasks"
    break
  fi
  echo "[deploy] waiting for tasks... ($i)"
  sleep 2
done
set -e

# 8) Health check (HTTP) with retries
HEALTH_URL="http://127.0.0.1:8080/health"
# If a health token secret exists, read it to use in header
HEALTH_TOKEN=""
if docker secret ls --format '{{.Name}}' | grep -q '^primrose_health_token$'; then
  # create a temporary container to read the secret safely
  HEALTH_TOKEN=$(docker secret inspect primrose_health_token --format '{{.Spec.Name}}' >/dev/null 2>&1 || true)
  # On swarm, secrets are mounted only into tasks; reading directly from host isn't straightforward.
  # We'll prefer HEALTH_TOKEN from .env if present. (Better to set HEALTH_TOKEN in .env on server.)
fi
# If HEALTH_TOKEN present in .env, use it
if [ -f "$ENV_PATH" ]; then
  env_ht=$(grep -E '^HEALTH_TOKEN=' "$ENV_PATH" | sed -E 's/^HEALTH_TOKEN=//') || true
  if [ -n "$env_ht" ]; then
    HEALTH_TOKEN="$env_ht"
  fi
fi

echo "[deploy] Performing health check against $HEALTH_URL"
for i in {1..20}; do
  if [ -n "$HEALTH_TOKEN" ]; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Health-Token: $HEALTH_TOKEN" "$HEALTH_URL") || HTTP_STATUS=000
  else
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL") || HTTP_STATUS=000
  fi
  echo "[deploy] Health check attempt $i -> status $HTTP_STATUS"
  if [ "$HTTP_STATUS" = "200" ]; then
    echo "[deploy] Health check passed"
    exit 0
  fi
  sleep 3
done

echo "[deploy] Health check failed after retries. Check logs with: sudo docker service logs ${STACK_NAME}_primrose-backend --tail 200"
exit 2

