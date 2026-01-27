# scripts/check_update.ps1
# Проверяет, доступна ли новая версия Ollama

$logFile = Join-Path $PSScriptRoot "..\logs\update_check_$(Get-Date -Format 'yyyy-MM-dd').log"
Start-Transcript -Path $logFile -Append

$ollamaExe = Join-Path $PSScriptRoot "..\bin\ollama.exe"
$downloadUrl = "https://github.com/ollama/ollama/releases/latest"
$tempFile = Join-Path $env:TEMP "ollama_latest.html"

try {
    # Получаем последнюю страницу релизов
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile -UseBasicParsing -TimeoutSec 15
    $content = Get-Content $tempFile -Raw

    # Ищем ссылку на Windows (ollama-windows-amd64.exe)
    if ($content -match 'href="([^"]+ollama-windows-amd64\.exe[^"]+)"') {
        $latestUrl = "https://github.com$($matches[1])"
        Write-Host "[+] Found latest version URL: $latestUrl" -ForegroundColor Green

        # Сравним версию (простая проверка по дате файла)
        $remoteLastWrite = (Invoke-WebRequest -Uri $latestUrl -Method Head).Headers.'Last-Modified'
        $localLastWrite = (Get-Item $ollamaExe).LastWriteTime.ToString("R")

        if ([DateTimeOffset]::Parse($remoteLastWrite) -gt [DateTimeOffset]::Parse($localLastWrite)) {
            Write-Host "[!] New version available!" -ForegroundColor Yellow
            Write-Host "    Current: $localLastWrite"
            Write-Host "    Latest:  $remoteLastWrite"
            Write-Host "    Download: $latestUrl"
        } else {
            Write-Host "[+] Ollama is up to date." -ForegroundColor Green
        }
    } else {
        Write-Warning "Could not find download link for Windows."
    }
} catch {
    Write-Error "Failed to check update: $_"
}

Stop-Transcript
