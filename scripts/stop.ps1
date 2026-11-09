param(
    [string]$ContainerName = "flint-nvfp4"
)

$listOutput = wslc list
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to list containers via wslc list (exit code: $LASTEXITCODE)."
    exit $LASTEXITCODE
}

$matched = $listOutput | Where-Object { $_ -match "\b$ContainerName\b" }
if ($matched) {
    Write-Host "Stopping container $ContainerName..."
    wslc stop $ContainerName
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to stop container $ContainerName (exit code: $LASTEXITCODE)."
        exit $LASTEXITCODE
    }
} else {
    Write-Host "Container $ContainerName is already stopped."
}
exit 0
