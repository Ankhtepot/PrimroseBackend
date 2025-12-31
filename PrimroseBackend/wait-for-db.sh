#!/usr/bin/env bash
set -e

# Wait for SQL Server TCP port to be available
echo "Waiting for db at db:1433..."
until bash -c 'echo > /dev/tcp/db/1433' >/dev/null 2>&1; do
  echo "waiting for db at db:1433"
  sleep 1
done

# Ensure DataProtection directory exists and is writable by the app user
DP_DIR="/home/app/.aspnet/DataProtection-Keys"
# determine the runtime user to own the directory: prefer 'app' user if present
if id -u app >/dev/null 2>&1; then
  TARGET_UID=$(id -u app)
  TARGET_GID=$(id -g app)
  TARGET_USER=app
else
  # fall back to APP_UID env if set
  TARGET_UID=${APP_UID:-1000}
  TARGET_GID=${APP_UID:-1000}
  TARGET_USER=$TARGET_UID
fi

echo "Ensuring DataProtection dir exists and owned by ${TARGET_USER} (uid:${TARGET_UID} gid:${TARGET_GID}): ${DP_DIR}"
mkdir -p "$DP_DIR"
chown -R "${TARGET_UID}:${TARGET_GID}" "$(dirname "$DP_DIR")" || true
chmod -R 700 "$DP_DIR" || true

# remove any stale tmp files older than 5 minutes (best-effort)
find "${DP_DIR}" -name "*.tmp" -mmin +5 -type f -exec rm -f {} \; || true

echo "DB is listening on 1433, starting the app"
# Drop privileges to the target user and exec the app
exec gosu "${TARGET_USER}" dotnet PrimroseBackend.dll
