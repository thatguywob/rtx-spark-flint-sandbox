param(
    [string]$Url = "http://127.0.0.1:8080/health",
    [int]$TimeoutSeconds = 120
)

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host "Waiting for Flint sandbox endpoint to be healthy at $Url (timeout: ${TimeoutSeconds}s)..."
while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
    try {
        $headers = @{}
        if ($env:FLINT_API_KEY) {
            $headers["Authorization"] = "Bearer $env:FLINT_API_KEY"
        }
        $response = Invoke-RestMethod -Uri $Url -Headers $headers -Method Get -TimeoutSec 2 -ErrorAction Stop
        if ($response.status -eq "ok" -or $response.status -eq "loading model") {
            if ($response.status -eq "ok") {
                Write-Host "Endpoint is HEALTHY after $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s."
                exit 0
            }
        }
    } catch {
        # Endpoint not yet listening or connection refused
    }
    Start-Sleep -Seconds 2
}

Write-Error "Timed out waiting for $Url after ${TimeoutSeconds}s."
exit 1
