param(
    [string]$Path = $env:MODEL_PATH,
    [string]$ExpectedHash = "97cc8009ff9b132d5cf3c488e6767962bb5a5dc158a90ed661bbbddf876b8bde",
    [long]$ExpectedSize = 22863084160
)

if (-not $Path) {
    Write-Error "MODEL_PATH is not set. Please set MODEL_PATH in your .env file or pass -Path <path>."
    exit 1
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "Model file not found at: $Path"
    exit 1
}

$file = Get-Item -LiteralPath $Path
Write-Host "Checking model file: $($file.FullName)"
Write-Host "File size: $($file.Length) bytes (expected: $ExpectedSize bytes)"

if ($file.Length -ne $ExpectedSize) {
    Write-Error "Size mismatch: got $($file.Length), expected $ExpectedSize"
    exit 1
}

Write-Host "Computing SHA-256 hash (this may take 10-20 seconds for 21 GB)..."
$stream = [System.IO.File]::OpenRead($file.FullName)
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha256.ComputeHash($stream)
$stream.Close()
$actualHash = -join ($hashBytes | ForEach-Object { "{0:x2}" -f $_ })

Write-Host "Actual SHA-256:   $actualHash"
Write-Host "Expected SHA-256: $ExpectedHash"

if ($actualHash.ToLower() -ne $ExpectedHash.ToLower()) {
    Write-Error "Hash mismatch! Model may be corrupted."
    exit 1
}

Write-Host "Model verification PASSED."
exit 0
