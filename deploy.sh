#!/usr/bin/env bash
set -euo pipefail

# deploy.sh - update repo, build backend image, and deploy stack (Swarm)
# Place this script in the repository root (/srv/primrose on the server) and run:
#   sudo ./deploy.sh

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

# --- GC config ---
CLEAN_OLD_IMAGES="${CLEAN_OLD_IMAGES:-true}"
# ---------------------------------------------------------------------------

# --- ensure Docker Swarm is active ---
echo "[deploy] Checking Docker Swarm status"
SWARM_STATE=$($SUDO docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")
if [ "$SWARM_STATE" != "active" ]; then
  echo "[deploy] Docker Swarm not active - initializing"
  $SUDO docker swarm init --advertise-addr $(hostname -I | awk '{print $1}') >/dev/null 2>&1 || true
else
  echo "[deploy] Docker Swarm is active"
fi

# --- Force build override ---
FORCE_BUILD="${FORCE_BUILD:-0}"
FRESH_START=0
PURGE_VOLUMES=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force|-f)
      FORCE_BUILD=1
      shift
      ;;
    --fresh)
      FRESH_START=1
      FORCE_BUILD=1
      shift
      ;;
    --purge-volumes)
      PURGE_VOLUMES=1
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--force] [--fresh] [--purge-volumes]"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

if [ "$FRESH_START" -eq 1 ]; then
  echo "[deploy] FRESH_START requested. Cleaning up existing stack and secrets..."
  
  if $SUDO docker stack ls --format '{{.Name}}' | grep -q "^${STACK_NAME}$"; then
    echo "[deploy] Removing stack: $STACK_NAME"
    $SUDO docker stack rm "$STACK_NAME"
    
    echo "[deploy] Waiting for services to be fully removed..."
    for i in {1..20}; do
      SERVICES_COUNT=$($SUDO docker service ls --filter "label=com.docker.stack.namespace=${STACK_NAME}" -q | wc -l)
      if [ "$SERVICES_COUNT" -eq 0 ]; then
        echo "[deploy] All services removed."
        break
      fi
      echo "[deploy] Waiting... ($SERVICES_COUNT services remaining)"
      sleep 2
    done
    sleep 5
    
    echo "[deploy] Removing network: ${STACK_NAME}_primrose-net"
    $SUDO docker network rm "${STACK_NAME}_primrose-net" || true
    sleep 2
  fi

  # Remove project secrets
  PROJECT_SECRETS=("db_password" "primrose_shared" "primrose_jwt" "primrose_admin_username" "primrose_admin_password" "primrose_health_token")
  for secret in "${PROJECT_SECRETS[@]}"; do
    if $SUDO docker secret ls --format '{{.Name}}' | grep -q "^${secret}$"; then
      echo "[deploy] Removing secret: $secret"
      $SUDO docker secret rm "$secret" || true
    fi
  done

  if [ "$PURGE_VOLUMES" -eq 1 ]; then
    echo "[deploy] PURGE_VOLUMES requested. Removing persistent volumes..."
    VOLS=("${STACK_NAME}_mssql_data" "${STACK_NAME}_primrose_dataprotection")
    for vol in "${VOLS[@]}"; do
      echo "[deploy] Attempting to remove volume: $vol"
      for i in {1..5}; do
        if $SUDO docker volume rm "$vol" 2>/dev/null; then
          echo "[deploy] Volume $vol removed."
          break
        else
          STUCK_CONTAINERS=$($SUDO docker ps -a --filter "volume=$vol" -q)
          if [ -n "$STUCK_CONTAINERS" ]; then
            echo "[deploy] Volume $vol still in use by containers: $STUCK_CONTAINERS. Force removing containers..."
            $SUDO docker rm -f $STUCK_CONTAINERS || true
          fi
          echo "[deploy] Volume $vol still in use, retrying in 2s... ($i/5)"
          sleep 2
        fi
      done
    done
  fi
  echo "[deploy] Cleanup complete."
fi

# --- create/update secrets from .env ---
if [ -f "scripts/recreate_secrets_from_env.sh" ]; then
  echo "[deploy] Ensuring Docker secrets are up to date"
  $SUDO bash scripts/recreate_secrets_from_env.sh "$ENV_PATH"
else
  echo "[deploy] Warning: scripts/recreate_secrets_from_env.sh not found; skipping auto-secret creation"
fi
# ---------------------------------------------------------------------------

echo "[deploy] Working directory: $SCRIPT_DIR"

UPDATED=1
if [ -d ".git" ]; then
  echo "[deploy] Git repo detected; fetching origin"
  git fetch origin --prune --tags || echo "[deploy] git fetch failed; continuing with local HEAD"
  LOCAL=$(git rev-parse --verify HEAD 2>/dev/null || true)
  REMOTE=$(git rev-parse --verify origin/master 2>/dev/null || true)
  if [ -n "$LOCAL" ] && [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
    echo "[deploy] Remote origin/master differs from local HEAD; updating working tree"
    if git merge --ff-only origin/master 2>/dev/null; then
      echo "[deploy] Fast-forwarded to origin/master"
    else
      echo "[deploy] Fast-forward failed; doing hard reset to origin/master"
      git reset --hard origin/master || true
    fi
    UPDATED=1
  else
    echo "[deploy] No new commits on origin/master"
    UPDATED=0
  fi
else
  echo "[deploy] No .git directory found; assuming current working tree is what should be deployed"
  UPDATED=1
fi

if [ "${FORCE_BUILD}" = "1" ]; then
  echo "[deploy] FORCE_BUILD requested; forcing rebuild and deploy regardless of git updates"
  UPDATED=1
fi

NEW_REV=$(git rev-parse --verify HEAD 2>/dev/null || true)
if [ -z "$NEW_REV" ]; then
  echo "[deploy] No git commit found; proceeding with stack deploy using existing compose file"
  $SUDO docker stack deploy --compose-file "$COMPOSE_FILE" "$STACK_NAME"
else
  if [ "$UPDATED" -eq 0 ]; then
    RUNNING=$($SUDO docker service ps --filter desired-state=running "${STACK_NAME}_primrose-backend" --format '{{.CurrentState}}' 2>/dev/null | grep -c "Running" || true)
    if [ "$RUNNING" -ge 1 ]; then
      echo "[deploy] No updates from origin/master and service is running; nothing to do"
      exit 0
    else
      echo "[deploy] No updates from origin/master but service is not running; proceeding to (re)deploy using current HEAD"
    fi
  fi

  TAG=$(echo "$NEW_REV" | cut -c1-8)
  IMAGE_TAG="primrose-primrose-backend:${TAG}"
  echo "[deploy] Building image tag $IMAGE_TAG"

  if $SUDO docker compose build primrose-backend; then
    echo "[deploy] docker compose build succeeded"
    BUILT_ID=$($SUDO docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep "primrose-backend" | head -n1 | awk '{print $2}') || true
    if [ -n "$BUILT_ID" ]; then
      echo "[deploy] Found image from docker compose: $BUILT_ID"
      $SUDO docker tag "$BUILT_ID" "$IMAGE_TAG" || true
    else
      echo "[deploy] docker compose built but primrose-primrose-backend:latest not found; falling back to docker build"
      $SUDO docker build -f PrimroseBackend/Dockerfile -t "$IMAGE_TAG" .
    fi
  else
    echo "[deploy] docker compose build failed or not available; using docker build"
    $SUDO docker build -f PrimroseBackend/Dockerfile -t "$IMAGE_TAG" .
  fi

  echo "[deploy] Tagging image ${IMAGE_TAG} as primrose-primrose-backend:latest"
  $SUDO docker tag "$IMAGE_TAG" primrose-primrose-backend:latest || true

  TMP_COMPOSE="${SCRIPT_DIR}/docker-compose.deploy.${TAG}.yaml"
  awk -v img="$IMAGE_TAG" '
    BEGIN{p=0}
    { if ($0 ~ /^\s*image: primrose-primrose-backend/) { sub(/image:.*/, "image: " img); print; next } print }
  ' "$COMPOSE_FILE" > "$TMP_COMPOSE"

  echo "[deploy] Deploying stack using temporary compose $TMP_COMPOSE"
  $SUDO docker stack deploy --compose-file "$TMP_COMPOSE" "$STACK_NAME"
  rm -f "$TMP_COMPOSE"

  echo "[deploy] Forcing service ${STACK_NAME}_primrose-backend to use image $IMAGE_TAG"
  $SUDO docker service update --image "$IMAGE_TAG" "${STACK_NAME}_primrose-backend" --force || true

  if [ "${CLEAN_OLD_IMAGES}" = "true" ]; then
    echo "[deploy] Cleaning up unused images and stopped containers"
    # Remove stopped containers
    $SUDO docker container prune -f || true
    # Remove dangling images
    $SUDO docker image prune -f || true
    # Remove old primrose-backend images that are not the current TAG and not latest
    if [ -n "${TAG:-}" ]; then
      echo "[deploy] Cleaning up old backend images (keeping :latest and :${TAG})"
      $SUDO docker images primrose-primrose-backend --format '{{.Repository}}:{{.Tag}}' | grep -v ":latest$" | grep -v ":${TAG}$" | xargs -r $SUDO docker rmi || true
    fi
  fi
fi

echo "[deploy] Waiting for backend service tasks to reach RUNNING state"
set +e
for i in {1..30}; do
  RUNNING=$($SUDO docker service ps --filter desired-state=running "${STACK_NAME}_primrose-backend" --format '{{.CurrentState}}' 2>/dev/null | grep -c "Running" || true)
  if [ "$RUNNING" -ge 1 ]; then
    echo "[deploy] Backend has running tasks"
    break
  fi
  echo "[deploy] waiting for tasks... ($i)"
  sleep 2
done
set -e

HEALTH_URL="http://127.0.0.1:8080/health"
HEALTH_TOKEN=""
if $SUDO docker secret ls --format '{{.Name}}' | grep -q '^primrose_health_token$'; then
  echo "[deploy] primrose_health_token secret present; ensure HEALTH_TOKEN available in .env or monitoring uses header"
fi
# If PRIMROSE_HEALTH_TOKEN or HEALTH_TOKEN present in .env, use it
if [ -f "$ENV_PATH" ]; then
  env_ht=$(grep -E '^PRIMROSE_HEALTH_TOKEN=' "$ENV_PATH" | sed -E 's/^PRIMROSE_HEALTH_TOKEN=//') || true
  if [ -z "$env_ht" ]; then
    env_ht=$(grep -E '^HEALTH_TOKEN=' "$ENV_PATH" | sed -E 's/^HEALTH_TOKEN=//') || true
  fi
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

echo "[deploy] Health check failed after retries."
echo "[deploy] --- Diagnostics ---"
$SUDO docker stack services "$STACK_NAME"
$SUDO docker service ps "$SERVICE_NAME" --no-trunc
$SUDO docker service logs "$SERVICE_NAME" --tail 50
FAILED_TASK_ID=$($SUDO docker service ps "$SERVICE_NAME" --filter "desired-state=shutdown" --format '{{.ID}}' | head -n1 || true)
if [ -n "$FAILED_TASK_ID" ]; then
  $SUDO docker inspect "$FAILED_TASK_ID" --format 'Status: {{.Status.State}}, Error: {{.Status.Err}}, ExitCode: {{.Status.ContainerStatus.ExitCode}}' || true
fi
exit 2

