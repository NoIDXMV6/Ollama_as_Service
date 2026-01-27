# scripts/update_models.ps1
# Интерактивное обновление моделей с поддержкой внешнего пути

$logFile = Join-Path $PSScriptRoot "..\logs\model_update_$(Get-Date -Format 'yyyy-MM-dd').log"
Start-Transcript -Path $logFile -Append

$ollamaExe = Join-Path $PSScriptRoot "..\bin\ollama.exe"
$tempDir = Join-Path $env:TEMP "ollama-update"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Определяем путь к моделям из .env
$envPath = Join-Path $PSScriptRoot "..\config\.env"
if (Test-Path $envPath) {
    $envVars = Get-Content $envPath | Where-Object { $_ -match '^OLLAMA_MODELS=(.+)' }
    if ($envVars) {
        $modelDir = $matches[1]
        Write-Host "[*] Using models path from .env: $modelDir" -ForegroundColor Cyan
    } else {
        Write-Warning "OLLAMA_MODELS not found in .env. Using default path."
        $modelDir = Join-Path $PSScriptRoot "..\models"
    }
} else {
    Write-Warning ".env file not found. Using default path."
    $modelDir = Join-Path $PSScriptRoot "..\models"
}

# Проверка доступа
if (-not (Test-Path $modelDir)) {
    Write-Error "Models directory not found: $modelDir"
    Stop-Transcript
    exit 1
}

Write-Host "[?] Getting list of installed models..." -ForegroundColor Cyan

try {
    $models = & $ollamaExe list | Select-Object -Skip 1 | ForEach-Object {
        if ($_ -match '^\s*(\S+):\s*(\S+)\s+(\d+)\s+([^\s]+)\s+(\S+)') {
            [PSCustomObject]@{
                Name      = $matches[1]
                Tag       = $matches[2]
                Size      = $matches[5]
                FullTag   = "$($matches[1]):$($matches[2])"
                LastUsed  = $matches[4]
            }
        }
    } | Where-Object { $_ }

    if (-not $models) {
        Write-Host "[-] No models found." -ForegroundColor Yellow
        Stop-Transcript
        exit 0
    }

    Write-Host "`n[+] Installed models:" -ForegroundColor Green
    $models | Format-Table -Property Name, Tag, Size -AutoSize | Out-String | Write-Host
} catch {
    Write-Error "[-] Failed to get model list: $_"
    Stop-Transcript
    exit 1
}

function Test-ModelUpdate {
    param([string]$model)
    try {
        $check = & $ollamaExe show --modelfile $model 2>&1
        if ($LASTEXITCODE -ne 0) {
            if ($check -like "*not found*") {
                Write-Warning "Model $model does not exist."
                return $null
            }
            return $null
        }
        return $true
    } catch {
        return $null
    }
}

$modelsToUpdate = @()
Write-Host "`n[*] Checking for updates..." -ForegroundColor Cyan

foreach ($model in $models) {
    $fullTag = $model.FullTag
    Write-Host "Checking: $fullTag..." -NoNewline
    $hasUpdate = Test-ModelUpdate -model $fullTag
    if ($hasUpdate -eq $true) {
        Write-Host " UPDATE AVAILABLE" -ForegroundColor Yellow
        $size = $model.Size
        $modelsToUpdate += [PSCustomObject]@{
            FullTag = $fullTag
            Size    = $size
        }
    } elseif ($hasUpdate -eq $null) {
        Write-Host " CHECK FAILED" -ForegroundColor Red
    } else {
        Write-Host " Up to date" -ForegroundColor Green
    }
}

if ($modelsToUpdate.Count -eq 0) {
    Write-Host "`n[+] All models are up to date. Nothing to update." -ForegroundColor Green
    Stop-Transcript
    exit 0
}

Write-Host "`n[*] Updates available for the following models:" -ForegroundColor Yellow
$modelsToUpdate | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "`n[*] Select models to update." -ForegroundColor White
Write-Host "Format: enter numbers separated by commas (e.g.: 1,3) or 'all' for all." -ForegroundColor Gray

for ($i = 0; $i -lt $modelsToUpdate.Count; $i++) {
    $m = $modelsToUpdate[$i]
    Write-Host "$($i+1). $($m.FullTag) ($($m.Size))"
}

$response = Read-Host "`nYour choice"

$selectedModels = @()

if ($response.Trim() -eq "all") {
    $selectedModels = $modelsToUpdate
} else {
    $indices = $response -split ',' | ForEach-Object { $_.Trim() }
    foreach ($idx in $indices) {
        if ([int]::TryParse($idx, [ref]$num)) {
            $index = $num - 1
            if ($index -ge 0 -and $index -lt $modelsToUpdate.Count) {
                $selectedModels += $modelsToUpdate[$index]
            } else {
                Write-Warning "Invalid number: $idx"
            }
        } else {
            Write-Warning "Invalid input: $idx"
        }
    }
}

if ($selectedModels.Count -eq 0) {
    Write-Host "[-] No models selected. Exiting." -ForegroundColor Red
    Stop-Transcript
    exit 0
}

Write-Host "`n[+] Selected models:" -ForegroundColor Green
$selectedModels | ForEach-Object { Write-Host "  • $($_.FullTag)" }

$confirm = Read-Host "`nContinue? (y/N)"
if ($confirm -inotmatch '^y$|^yes$') {
    Write-Host "[-] Operation cancelled by user." -ForegroundColor Yellow
    Stop-Transcript
    exit 0
}

Write-Host "`n[*] Starting update..." -ForegroundColor Cyan

foreach ($model in $selectedModels) {
    Write-Host "[*] Updating: $($model.FullTag)" -ForegroundColor Yellow
    try {
        $pullArgs = "pull", $model.FullTag
        $proc = Start-Process -FilePath $ollamaExe -ArgumentList $pullArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $tempDir "pull_$($model.Name).log")

        if ($proc.ExitCode -eq 0) {
            Write-Host "[+] Successfully updated: $($model.FullTag)" -ForegroundColor Green
        } else {
            Write-Error "[-] Failed to update $($model.FullTag). Exit code: $($proc.ExitCode)"
        }
    } catch {
        Write-Error "[-] Failed to update $($model.FullTag): $_"
    }
}

Write-Host "`n[+] Update completed successfully." -ForegroundColor Green
Stop-Transcript
