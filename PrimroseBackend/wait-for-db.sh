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
if [ -n "${APP_UID:-}" ]; then
  echo "Ensuring DataProtection dir exists and owned by UID ${APP_UID}: ${DP_DIR}"
  mkdir -p "$DP_DIR"
  chown -R "${APP_UID}:${APP_UID}" "$(dirname "$DP_DIR")" || true
  chmod -R 700 "$DP_DIR" || true
else
  echo "APP_UID not set; skipping DataProtection chown"
fi

echo "DB is listening on 1433, starting the app"
# Drop privileges to the APP_UID user and exec the app
exec gosu "${APP_UID}" dotnet PrimroseBackend.dll
