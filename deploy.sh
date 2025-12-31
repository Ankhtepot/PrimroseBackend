#!/usr/bin/env bash
set -euo pipefail

# deploy.sh - update repo, build backend image, and deploy stack (Swarm)
# Place this script in the repository root (/srv/primrose on the server) and run:
#   sudo ./deploy.sh
# It will:
#  - pull latest from origin/master (if repo exists)
#  - ensure Docker Swarm is active
#  - create missing Docker secrets from PrimroseBackend/.env (if present)
#  - build the backend image with a unique tag (commit SHA) when there are updates
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

# 1) Update repository: fetch and check for changes
if [ -d .git ]; then
  echo "[deploy] Fetching origin/master"
  git fetch origin master
  REMOTE_REV=$(git rev-parse --verify origin/master 2>/dev/null || true)
  LOCAL_REV=$(git rev-parse --verify HEAD 2>/dev/null || true)
  echo "[deploy] local=$LOCAL_REV remote=$REMOTE_REV"
  if [ "$LOCAL_REV" = "$REMOTE_REV" ]; then
    echo "[deploy] No changes in origin/master"
    # If service exists and is healthy, do nothing
    if docker service ls --format '{{.Name}}' 2>/dev/null | grep -q "^${SERVICE_NAME}$"; then
      RUNNING_COUNT=$(docker service ps --filter desired-state=running "${SERVICE_NAME}" --format '{{.CurrentState}}' | grep -c "Running" || true)
      if [ "$RUNNING_COUNT" -ge 1 ]; then
        echo "[deploy] Service ${SERVICE_NAME} already running and healthy. No deploy necessary."
        exit 0
      else
        echo "[deploy] Service ${SERVICE_NAME} not running; proceeding to deploy."
      fi
    else
      echo "[deploy] Service ${SERVICE_NAME} not found; proceeding to deploy."
    fi
  else
    echo "[deploy] origin/master has updates; will deploy new image"
    git reset --hard origin/master
  fi
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
if docker network ls --filter name=${STACK_NAME}_primrose-net -q | grep -q .; then
  echo "[deploy] Removing local network ${STACK_NAME}_primrose-net to allow overlay creation"
  $SUDO docker network rm ${STACK_NAME}_primrose-net 2>/dev/null || true
fi

# 5) Build backend image and deploy only if updates were detected or service missing
# Determine current HEAD (after possible reset above)
NEW_REV=$(git rev-parse --verify HEAD 2>/dev/null || true)
if [ -z "$NEW_REV" ]; then
  echo "[deploy] No git commit found; proceeding with stack deploy using existing compose file"
  # Deploy using existing compose file
  $SUDO docker stack deploy --compose-file "$COMPOSE_FILE" "$STACK_NAME"
else
  TAG=$(echo "$NEW_REV" | cut -c1-8)
  IMAGE_TAG="primrose-primrose-backend:${TAG}"
  echo "[deploy] Building image tag $IMAGE_TAG"

  # Prefer docker compose build (uses the same build context and args as compose). Fall back to docker build.
  if $SUDO docker compose build primrose-backend >/dev/null 2>&1; then
    echo "[deploy] docker compose build succeeded"
    # try to find image created by compose
    BUILT_ID=$($SUDO docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | awk '/^primrose-primrose-backend:latest /{print $2; exit}') || true
    if [ -n "$BUILT_ID" ]; then
      echo "[deploy] Found image from docker compose: $BUILT_ID"
      # tag it with commit SHA
      $SUDO docker tag "$BUILT_ID" "$IMAGE_TAG" || true
    else
      echo "[deploy] docker compose built but primrose-primrose-backend:latest not found; falling back to docker build"
      $SUDO docker build -f PrimroseBackend/Dockerfile -t "$IMAGE_TAG" .
    fi
  else
    echo "[deploy] docker compose build failed or not available; using docker build"
    $SUDO docker build -f PrimroseBackend/Dockerfile -t "$IMAGE_TAG" .
  fi

  # Ensure :latest tag also exists
  echo "[deploy] Tagging image ${IMAGE_TAG} as primrose-primrose-backend:latest"
  $SUDO docker tag "$IMAGE_TAG" primrose-primrose-backend:latest || true

  # Create a temporary compose file that references the new image tag
  TMP_COMPOSE="${SCRIPT_DIR}/docker-compose.deploy.${TAG}.yaml"
  awk -v img="$IMAGE_TAG" '
    BEGIN{p=0}
    { if ($0 ~ /^\s*image: primrose-primrose-backend/) { sub(/image:.*/, "image: " img); print; next } print }
  ' "$COMPOSE_FILE" > "$TMP_COMPOSE"

  echo "[deploy] Deploying stack using temporary compose $TMP_COMPOSE"
  $SUDO docker stack deploy --compose-file "$TMP_COMPOSE" "$STACK_NAME"
  rm -f "$TMP_COMPOSE"

  # Ensure the service tasks all use the exact built image - force update to replace running tasks
  echo "[deploy] Forcing service ${STACK_NAME}_primrose-backend to use image $IMAGE_TAG"
  $SUDO docker service update --image "$IMAGE_TAG" "${STACK_NAME}_primrose-backend" --force || true

  # Clean up other tags for this repository to avoid accidental reuse of old images
  echo "[deploy] Cleaning up other tags for primrose-primrose-backend (non-current)"
  for TAG_ENTRY in $($SUDO docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep '^primrose-primrose-backend:' | awk '{print $1}'); do
    # skip the two tags we want to keep
    if [ "$TAG_ENTRY" = "$IMAGE_TAG" ] || [ "$TAG_ENTRY" = "primrose-primrose-backend:latest" ]; then
      continue
    fi
    echo "[deploy] Removing old image tag: $TAG_ENTRY"
    $SUDO docker rmi "$TAG_ENTRY" || true
  done
fi

# 6) Wait for backend service tasks to be running
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

# 7) Health check (HTTP) with retries
HEALTH_URL="http://127.0.0.1:8080/health"
# If a health token secret exists, read it to use in header
HEALTH_TOKEN=""
if docker secret ls --format '{{.Name}}' | grep -q '^primrose_health_token$'; then
  echo "[deploy] primrose_health_token secret present; ensure HEALTH_TOKEN available in .env or monitoring uses header"
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

