#!/usr/bin/env bash
set -e

# Wait for SQL Server TCP port to be available
echo "Waiting for db at db:1433..."
until bash -c 'echo > /dev/tcp/db/1433' >/dev/null 2>&1; do
  echo "waiting for db at db:1433"
  sleep 1
done

echo "DB is listening on 1433, starting the app"
exec dotnet PrimroseBackend.dll

