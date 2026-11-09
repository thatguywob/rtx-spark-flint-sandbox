param(
    [string]$ContainerName = "flint-nvfp4",
    [string]$HealthUrl = $null,
    [string]$ApiKey = $env:FLINT_API_KEY,
    [string]$TailnetUrl = $env:TAILNET_ENDPOINT
)

if (-not $HealthUrl) {
    $port = if ($env:PORT) { $env:PORT } else { "8080" }
    $HealthUrl = "http://127.0.0.1:$port/health"
}
Write-Host "=== Flint Sandbox Status ==="
$listOutput = wslc list
$matched = $listOutput | Where-Object { $_ -match "\b$ContainerName\b" }

if ($matched) {
    Write-Host "[Container State]: Running ($ContainerName)"
    Write-Host "`nContainer Details:"
    $listOutput | Select-Object -First 1
    $matched

    Write-Host "`nLive Resource Snapshot:"
    wslc stats $ContainerName

    Write-Host "`nHealthcheck Status:"
    try {
        $headers = @{ "Authorization" = "Bearer $ApiKey" }
        $res = Invoke-RestMethod -Uri $HealthUrl -Headers $headers -Method Get -TimeoutSec 3 -ErrorAction Stop
        Write-Host "Endpoint: $HealthUrl -> status: $($res.status)"
    } catch {
        Write-Host "Endpoint: $HealthUrl -> unreachable or error: $_"
    }

    Write-Host "`nTailnet Endpoint:"
    if ($TailnetUrl) {
        try {
            $probeUrl = "$($TailnetUrl.TrimEnd('/'))/health"
            $resTailnet = Invoke-RestMethod -Uri $probeUrl -Headers $headers -Method Get -TimeoutSec 3 -ErrorAction Stop
            Write-Host "Endpoint: $probeUrl -> status: $($resTailnet.status)"
        } catch {
            Write-Host "Endpoint: $TailnetUrl -> not accessible: $_"
        }
    } else {
        Write-Host "Tailnet endpoint not configured (set TAILNET_ENDPOINT in .env to verify)."
    }
} else {
    Write-Host "[Container State]: Stopped ($ContainerName not found in active containers)"
}
Write-Host "============================"
