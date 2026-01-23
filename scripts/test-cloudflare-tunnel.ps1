# Cloudflare Tunnel Diagnostic Script
# Run this from your Windows machine to test the API through Cloudflare

param(
    [string]$ApiUrl = "https://api.primrose.work",
    [string]$HealthToken = ""
)

Write-Host "=== Cloudflare Tunnel Diagnostics for PrimroseBackend ===" -ForegroundColor Cyan
Write-Host ""

# Disable SSL validation for PowerShell 5.1 compatibility
if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type) {
    $certCallback = @"
        using System;
        using System.Net;
        using System.Net.Security;
        using System.Security.Cryptography.X509Certificates;
        public class ServerCertificateValidationCallback
        {
            public static void Ignore()
            {
                if(ServicePointManager.ServerCertificateValidationCallback == null)
                {
                    ServicePointManager.ServerCertificateValidationCallback += 
                        delegate
                        (
                            Object obj, 
                            X509Certificate certificate, 
                            X509Chain chain, 
                            SslPolicyErrors errors
                        )
                        {
                            return true;
                        };
                }
            }
        }
"@
    Add-Type $certCallback
}
[ServerCertificateValidationCallback]::Ignore()

# Test 1: Basic connectivity
Write-Host "Test 1: Testing basic connectivity..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$ApiUrl/health" -Method GET -TimeoutSec 10 -ErrorAction Stop
    Write-Host "✓ Connected successfully" -ForegroundColor Green
    Write-Host "  Status: $($response.StatusCode)" -ForegroundColor Gray
} catch {
    Write-Host "✗ Connection failed" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
    
    if ($_.Exception.Response.StatusCode -eq 503) {
        Write-Host ""
        Write-Host "503 Error detected! Possible causes:" -ForegroundColor Red
        Write-Host "  1. Backend service is not running" -ForegroundColor Yellow
        Write-Host "  2. Cloudflare tunnel cannot reach the backend" -ForegroundColor Yellow
        Write-Host "  3. Service is starting up (check logs)" -ForegroundColor Yellow
    } elseif ($_.Exception.Response.StatusCode -eq 403) {
        Write-Host ""
        Write-Host "403 Error detected! This usually means:" -ForegroundColor Red
        Write-Host "  - Health token is required but not provided" -ForegroundColor Yellow
        Write-Host "  - Health token is incorrect" -ForegroundColor Yellow
    }
}

Write-Host ""

# Test 2: Test with health token if provided
if ($HealthToken) {
    Write-Host "Test 2: Testing with health token..." -ForegroundColor Yellow
    try {
        $headers = @{
            "X-Health-Token" = $HealthToken
        }
        $response = Invoke-WebRequest -Uri "$ApiUrl/health" -Method GET -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        Write-Host "✓ Health check passed with token" -ForegroundColor Green
        Write-Host "  Status: $($response.StatusCode)" -ForegroundColor Gray
        Write-Host "  Body: $($response.Content)" -ForegroundColor Gray
    } catch {
        Write-Host "✗ Health check failed with token" -ForegroundColor Red
        Write-Host "  Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Gray
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
    }
} else {
    Write-Host "Test 2: Skipped (no health token provided)" -ForegroundColor Gray
    Write-Host "  Usage: .\test-cloudflare-tunnel.ps1 -HealthToken 'your-token-here'" -ForegroundColor Gray
}

Write-Host ""

# Test 3: DNS resolution
Write-Host "Test 3: Testing DNS resolution..." -ForegroundColor Yellow
try {
    $hostname = ([System.Uri]$ApiUrl).Host
    $dnsResult = Resolve-DnsName -Name $hostname -ErrorAction Stop
    Write-Host "✓ DNS resolution successful" -ForegroundColor Green
    foreach ($record in $dnsResult) {
        if ($record.Type -eq "A") {
            Write-Host "  IP: $($record.IPAddress)" -ForegroundColor Gray
        } elseif ($record.Type -eq "CNAME") {
            Write-Host "  CNAME: $($record.NameHost)" -ForegroundColor Gray
        }
    }
} catch {
    Write-Host "✗ DNS resolution failed" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
}

Write-Host ""

# Test 4: TCP connectivity
Write-Host "Test 4: Testing TCP connectivity..." -ForegroundColor Yellow
$hostname = ([System.Uri]$ApiUrl).Host
$port = if (([System.Uri]$ApiUrl).Scheme -eq "https") { 443 } else { 80 }
try {
    $tcpTest = Test-NetConnection -ComputerName $hostname -Port $port -WarningAction SilentlyContinue
    if ($tcpTest.TcpTestSucceeded) {
        Write-Host "✓ TCP connection successful on port $port" -ForegroundColor Green
    } else {
        Write-Host "✗ TCP connection failed on port $port" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ TCP test failed" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== Diagnostics Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "1. SSH to your server and run:" -ForegroundColor White
Write-Host "   sudo docker stack services primrose" -ForegroundColor Gray
Write-Host "   sudo docker service logs primrose_primrose-backend --tail 50" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Check Cloudflare tunnel status:" -ForegroundColor White
Write-Host "   sudo systemctl status cloudflared" -ForegroundColor Gray
Write-Host "   sudo journalctl -u cloudflared -f" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Verify tunnel configuration:" -ForegroundColor White
Write-Host "   cat /root/.cloudflared/config.yml" -ForegroundColor Gray
Write-Host ""
Write-Host "For more help, see CLOUDFLARE_TUNNEL_TROUBLESHOOTING.md" -ForegroundColor Yellow

