<#
Create docker secrets from a .env file. Usage:
  .\create-docker-secrets.ps1 -EnvFile PrimroseBackend\.env

This script reads variables from the env file and creates Docker secrets for production use.
Note: Docker secrets are only available to services in swarm mode or via Docker stack.
#>
param(
    [string]$EnvFile = "PrimroseBackend\.env"
)

if (-not (Test-Path $EnvFile)) {
    Write-Error "Env file not found: $EnvFile"
    exit 1
}

$lines = Get-Content $EnvFile | Where-Object { $_ -and -not ($_ -match '^#') }
foreach ($line in $lines) {
    if ($line -match '^(\w+)=(.*)$') {
        $key = $matches[1]
        $value = $matches[2]
        if ($key -in @('SA_PASSWORD', 'JwtSecret', 'SharedSecret')) {
            $tmp = [System.IO.Path]::GetTempFileName()
            Set-Content -Path $tmp -Value $value -NoNewline
            Write-Host "Creating secret: $key"
            docker secret rm $key -f 2>$null | Out-Null
            docker secret create $key $tmp
            Remove-Item $tmp
        }
    }
}

Write-Host "Done. Created secrets (if Docker is in swarm mode)."
