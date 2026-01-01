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

# --- new GC config (safe image garbage-collection) -------------------------
# CLEAN_OLD_IMAGES: if 'false' will skip automatic GC. Default: true
# GC_DRY_RUN: if 'true' will only show what would be removed (no deletion). Default: false
# You can override these by setting env vars before running the script, e.g.
#   CLEAN_OLD_IMAGES=false ./deploy.sh
#   GC_DRY_RUN=true ./deploy.sh
CLEAN_OLD_IMAGES="${CLEAN_OLD_IMAGES:-true}"
GC_DRY_RUN="${GC_DRY_RUN:-false}"
# ---------------------------------------------------------------------------

echo "[deploy] Working directory: $SCRIPT_DIR"

# ...existing code...

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

  # New: safe GC function - respects CLEAN_OLD_IMAGES and GC_DRY_RUN
  cleanup_old_images() {
    if [ "${CLEAN_OLD_IMAGES}" = "false" ]; then
      echo "[deploy] CLEAN_OLD_IMAGES=false - skipping image GC"
      return 0
    fi

    echo "[deploy] GC_DRY_RUN=${GC_DRY_RUN}"

    # list tags and IDs for the repository
    $SUDO docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | awk '/^primrose-primrose-backend:/{print $1" "$2}' | while read -r TAG_ENTRY IMG_ID; do
      # skip the two tags we want to keep
      if [ "$TAG_ENTRY" = "$IMAGE_TAG" ] || [ "$TAG_ENTRY" = "primrose-primrose-backend:latest" ]; then
        continue
      fi
      echo "[deploy][gc] Considering old image tag: $TAG_ENTRY (id: $IMG_ID)"

      # Check if any container references this image id (docker inspect .Image returns full id); use substring match
      IN_USE=0
      CONTAINERS=$($SUDO docker ps -a -q || true)
      if [ -n "$CONTAINERS" ]; then
        for CID in $CONTAINERS; do
          CID_IMG=$($SUDO docker inspect --format '{{.Image}}' "$CID" 2>/dev/null || true)
          if echo "$CID_IMG" | grep -q "$IMG_ID"; then
            IN_USE=1
            break
          fi
        done
      fi

      if [ "$IN_USE" -eq 1 ]; then
        echo "[deploy][gc] Skipping removal of $TAG_ENTRY - image is used by a container"
        continue
      fi

      if [ "${GC_DRY_RUN}" = "true" ]; then
        echo "[deploy][gc] DRY-RUN: would remove tag $TAG_ENTRY"
        continue
      fi

      echo "[deploy][gc] Removing old image tag: $TAG_ENTRY"
      # attempt removal and log failures; do not force by default
      if $SUDO docker rmi "$TAG_ENTRY" 2>/tmp/deploy_rmi_err || true; then
        echo "[deploy][gc] Removed $TAG_ENTRY"
      else
        RMI_ERR=$(cat /tmp/deploy_rmi_err || true)
        echo "[deploy][gc] Failed to remove $TAG_ENTRY: $RMI_ERR"
        # If removal failed because image is still referenced, keep it and continue
      fi
    done
  }

  # run GC
  cleanup_old_images
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

