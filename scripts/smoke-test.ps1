param(
    [string]$Url = $env:FLINT_API_URL,
    [string]$ApiKey = $env:FLINT_API_KEY
)

if (-not $Url) {
    $port = if ($env:PORT) { $env:PORT } else { "8080" }
    $Url = "http://127.0.0.1:$port/v1/chat/completions"
}
if (-not $ApiKey) {
    Write-Error "FLINT_API_KEY is not set. Please set FLINT_API_KEY in your .env or environment."
    exit 1
}
$env:FLINT_API_URL = $Url
$env:FLINT_API_KEY = $ApiKey

uv run scripts/smoke-test.py
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
exit 0
