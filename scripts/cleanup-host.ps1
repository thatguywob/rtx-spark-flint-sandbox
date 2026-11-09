# Stop lingering legacy host llama processes if running from standalone directories
Get-Process | Where-Object { $_.ProcessName -match '^llama' } | ForEach-Object {
    $procPath = try { $_.Path } catch { $null }
    if ($procPath -and ($procPath -like "$env:LOCALAPPDATA\llama.cpp\*" -or $procPath -eq "$env:LOCALAPPDATA\Microsoft\WindowsApps\llama.exe")) {
        Write-Host "Stopping legacy standalone process: $($_.ProcessName) (PID: $($_.Id), Path: $procPath)"
        Stop-Process -Id $_.Id -Force
    }
}

# 1. Clean legacy WindowsApps binary
$legacyVulkan = "$env:LOCALAPPDATA\Microsoft\WindowsApps\llama.exe"
if (Test-Path -LiteralPath $legacyVulkan) {
    Remove-Item -Force -LiteralPath $legacyVulkan
    Write-Host "Removed legacy Vulkan binary: $legacyVulkan"
} else {
    Write-Host "No legacy Vulkan binary found at: $legacyVulkan"
}

# 2. Clean standalone host llama.cpp directory
$standaloneDir = "$env:LOCALAPPDATA\llama.cpp"
if (Test-Path -LiteralPath $standaloneDir) {
    Remove-Item -Recurse -Force -LiteralPath $standaloneDir
    Write-Host "Removed standalone llama.cpp build directory: $standaloneDir"
} else {
    Write-Host "No standalone llama.cpp directory found at: $standaloneDir"
}

# 3. Clean mise download cache for llama-cpp
$miseDownloads = "$env:LOCALAPPDATA\mise\downloads\llama-cpp"
if (Test-Path -LiteralPath $miseDownloads) {
    Remove-Item -Recurse -Force -LiteralPath $miseDownloads
    Write-Host "Removed mise download cache: $miseDownloads"
}

# 4. Clean mise temp cache for llama-cpp
$miseTemp = "$env:LOCALAPPDATA\Temp\mise\llama-cpp"
if (Test-Path -LiteralPath $miseTemp) {
    Remove-Item -Recurse -Force -LiteralPath $miseTemp
    Write-Host "Removed mise temp cache: $miseTemp"
}
