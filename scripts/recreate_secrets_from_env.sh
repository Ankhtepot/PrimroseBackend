#!/usr/bin/env bash
set -euo pipefail

# recreate_secrets_from_env.sh
# Removes project Docker secrets (if present) and creates new secrets from PrimroseBackend/.env
# Usage: sudo ./scripts/recreate_secrets_from_env.sh [path-to-env]
# Example: sudo ./scripts/recreate_secrets_from_env.sh /srv/primrose/PrimroseBackend/.env

ENV_PATH_ARG=${1:-}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV="$SCRIPT_DIR/../PrimroseBackend/.env"
ENV_FILE="${ENV_PATH_ARG:-$DEFAULT_ENV}"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env file not found at $ENV_FILE"
  exit 1
fi

echo "Using env file: $ENV_FILE"

# Ensure Docker is available
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found. Install docker and ensure you can run docker commands (sudo may be required)."
  exit 1
fi

# Ensure Swarm active (secrets require swarm)
SWARM_STATE=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")
if [ "$SWARM_STATE" != "active" ]; then
  echo "Docker Swarm not active - initializing single-node swarm"
  sudo docker swarm init --advertise-addr $(hostname -I | awk '{print $1}') >/dev/null 2>&1 || true
else
  echo "Swarm active"
fi

# Helper: read value from .env (handles quoted values)
get_env() {
  local key="$1"
  local val
  val=$(grep -E "^${key}=" "$ENV_FILE" | sed -E "s/^${key}=//" | sed -E "s/^\"(.*)\"$|^'(.*)'$/\1\2/") || true
  printf '%s' "$val"
}

# Extract DB password: prefer ConnectionStrings__Default Password=..., then SA_PASSWORD
extract_db_password() {
  local conn
  conn=$(get_env "ConnectionStrings__Default")
  if [ -n "$conn" ]; then
    # try to extract Password=... from connection string
    if echo "$conn" | grep -qi "password="; then
      # extract value after Password= until semicolon
      echo "$conn" | sed -nE "s/.*[Pp]assword=([^;]*).*/\1/p"
      return 0
    fi
  fi
  # fallback to SA_PASSWORD
  get_env "SA_PASSWORD"
}

# Map env keys -> secret names
# db_password   <- ConnectionStrings__Default (Password=...) or SA_PASSWORD
# primrose_shared <- SharedSecret
# primrose_jwt  <- JwtSecret
# primrose_admin_username <- ADMIN_USERNAME
# primrose_admin_password <- ADMIN_PASSWORD
# primrose_health_token <- PRIMROSE_HEALTH_TOKEN

SECRETS=(
  "db_password:$(extract_db_password)"
  "primrose_shared:$(get_env 'SharedSecret')"
  "primrose_jwt:$(get_env 'JwtSecret')"
  "primrose_admin_username:$(get_env 'ADMIN_USERNAME')"
  "primrose_admin_password:$(get_env 'ADMIN_PASSWORD')"
  "primrose_health_token:$(get_env 'PRIMROSE_HEALTH_TOKEN')"
)

# Remove existing secrets and create new ones (skip empty values)
created=()
skipped=()
for entry in "${SECRETS[@]}"; do
  name="${entry%%:*}"
  value="${entry#*:}"

  # Remove existing secret if present
  if docker secret ls --format '{{.Name}}' | grep -q "^${name}$"; then
    echo "Removing existing secret: $name"
    docker secret rm "$name" || true
  fi

  if [ -z "$value" ]; then
    echo "Skipping $name: no value found in $ENV_FILE"
    skipped+=("$name")
    continue
  fi

  # Create secret from value (pass via stdin, no echo)
  printf '%s' "$value" | docker secret create "$name" - >/dev/null
  echo "Created secret: $name"
  created+=("$name")
done

# Summary
echo "--- Summary ---"
if [ ${#created[@]} -gt 0 ]; then
  echo "Created secrets: ${created[*]}"
else
  echo "No secrets were created."
fi
if [ ${#skipped[@]} -gt 0 ]; then
  echo "Skipped (missing in .env): ${skipped[*]}"
fi

echo "Done. Verify with: docker secret ls"
exit 0

