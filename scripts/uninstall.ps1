# scripts/uninstall.ps1
$rootDir = Join-Path $PSScriptRoot ".."
$binDir = Join-Path $rootDir "bin"
$nssmPath = Join-Path $binDir "nssm.exe"
$service = "OllamaService"

# Остановить и удалить службу
if (Get-Service $service -ErrorAction SilentlyContinue) {
    Write-Host "[*] Stopping service: $service"
    & $nssmPath stop $service
    & $nssmPath remove $service confirm
}

# Удалить задачи
Unregister-ScheduledTask -TaskName "Ollama - Daily Restart" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "Ollama - Update Models" -Confirm:$false -ErrorAction SilentlyContinue

# Удалить правило брандмауэра
Remove-NetFirewallRule -DisplayName "Ollama - TCP 11434 Inbound" -ErrorAction SilentlyContinue

# Удалить пользователя
try {
    Remove-LocalUser -Name "OllamaService" -ErrorAction Stop
    Write-Host "User OllamaService removed."
} catch {
    Write-Warning "Could not remove user: $_"
}

# Удалить папку сервиса
if (Test-Path $rootDir) {
    Remove-Item $rootDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Directory removed: $rootDir"
}

Write-Host "[+] Uninstallation complete."
