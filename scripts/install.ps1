# scripts/install.ps1
param(
    [string]$ServiceUser = "OllamaService"
)

# --- Функция: сравнение двух SecureString ---
function Test-SecureStringsEqual {
    param([Security.SecureString]$a, [Security.SecureString]$b)
    $bstrA = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($a)
    $bstrB = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($b)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstrA) -eq [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstrB)
    } finally {
        [Runtime.InteropServices.Marshal]::FreeBSTR($bstrA)
        [Runtime.InteropServices.Marshal]::FreeBSTR($bstrB)
    }
}

# --- Запрос пароля с подтверждением ---
Write-Host "`n[*] Setting up password for user '$ServiceUser'..." -ForegroundColor Cyan

$ServicePassword = $null
while (-not $ServicePassword) {
    Write-Host "Enter password for user '$ServiceUser':" -ForegroundColor Yellow
    $password1 = Read-Host -AsSecureString

    Write-Host "Confirm password:" -ForegroundColor Yellow
    $password2 = Read-Host -AsSecureString

    if (Test-SecureStringsEqual $password1 $password2) {
        $ServicePassword = $password1
        Write-Host "[+] Password confirmed." -ForegroundColor Green
    } else {
        Write-Warning "Passwords do not match. Please try again."
    }
}

# --- Helper function: SecureString -> PlainText (for PowerShell 5.1) ---
function ConvertTo-PlainText {
    param([Security.SecureString]$SecureString)
    $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
    } finally {
        [Runtime.InteropServices.Marshal]::FreeBSTR($BSTR)
    }
}

# --- Start ---
Write-Host "Install script started!" -ForegroundColor Green
Write-Host "Running as: $env:USERDOMAIN\$env:USERNAME"
Write-Host "Press Enter to continue..." -ForegroundColor Yellow
Read-Host

$ErrorActionPreference = 'Stop'
$rootDir = Join-Path $PSScriptRoot ".."
$binDir = Join-Path $rootDir "bin"
$logDir = Join-Path $rootDir "logs"
$configDir = Join-Path $rootDir "config"
$nssmPath = Join-Path $binDir "nssm.exe"
$curlPath = Join-Path $binDir "curl.exe"
$localOllama = Join-Path $binDir "ollama.exe"
$envPath = Join-Path $configDir ".env"

# Логируем начало
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
"[$(Get-Date)] Install script started by: $env:USERDOMAIN\$env:USERNAME" | Out-File "$logDir\install.log" -Append -Encoding UTF8

# --- Check admin rights ---
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole("Administrators")) {
        Write-Error "Administrator rights are required."
        exit 1
    }
} catch {
    Write-Warning "[!] Could not verify admin rights. Running with current privileges..."
}

# --- Step 1: Create user ---
try {
    $user = Get-LocalUser -Name $ServiceUser -ErrorAction Stop
    Write-Host "User $ServiceUser already exists." -ForegroundColor Yellow
} catch {
    Write-Host "[*] Creating user $ServiceUser..."
    New-LocalUser `
        -Name $ServiceUser `
        -Password $ServicePassword `
        -FullName "Ollama Background Service" `
        -Description "Dedicated service account for Ollama" `
        -PasswordNeverExpires `
        -UserMayNotChangePassword | Out-Null
    Write-Host "Add '$ServiceUser' to 'Log on as a service' via secpol.msc" -ForegroundColor Yellow
}

# --- Step 2: Find ollama.exe ---
Write-Host "[*] Searching for ollama.exe..." -ForegroundColor Cyan
$systemOllama = Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object {
    $p = "C:\Users\$($_.Name)\AppData\Local\Programs\Ollama\ollama.exe"
    if (Test-Path $p) { $p }
} | Select-Object -First 1

if (-not $systemOllama) {
    Write-Error "[!] Ollama not found. Please install it manually."
    exit 1
}
Write-Host "[+] Found: $systemOllama"

# --- Step 3: Copy to bin ---
New-Item -ItemType Directory -Path $binDir -Force | Out-Null
Copy-Item -Path $systemOllama -Destination $localOllama -Force
$ollamaExe = $localOllama

# --- Step 4: Check signature ---
$signature = Get-AuthenticodeSignature $ollamaExe
if ($signature.Status -ne 'Valid') {
    Write-Warning "Invalid or missing signature. Continue? (y/N)"
    $confirm = Read-Host
    if ($confirm -notmatch '^y') { exit 1 }
}

# --- Step 5: Prompt user for model path ---
Write-Host "[*] Searching for existing Ollama models in user profiles..." -ForegroundColor Cyan

$defaultModelDir = $null
foreach ($userDir in (Get-ChildItem -Path "C:\Users" -Directory)) {
    $path = "C:\Users\$($userDir.Name)\.ollama\models"
    if (Test-Path $path) {
        $defaultModelDir = $path
        break
    }
}

if ($defaultModelDir) {
    Write-Host "[+] Found models at: $defaultModelDir" -ForegroundColor Green
} else {
    Write-Warning "No existing Ollama models found."
}

# --- Prompt user ---
Write-Host "`nYou can use an existing models directory (e.g., C:\Users\YourName\.ollama\models)" -ForegroundColor Yellow
Write-Host "Or press Enter to use the default location." -ForegroundColor Yellow
$customPath = Read-Host "Enter path to models directory (or leave empty)"

# --- Determine final modelDir ---
if ($customPath -and (Test-Path $customPath)) {
    $modelDir = Resolve-Path $customPath
    Write-Host "[+] Using user-specified model directory: $modelDir" -ForegroundColor Green
} elseif ($customPath -and (-not (Test-Path $customPath))) {
    Write-Warning "Specified path does not exist: $customPath"
    Write-Host "Falling back to automatic detection..." -ForegroundColor Yellow
    if ($defaultModelDir) {
        $modelDir = $defaultModelDir
        Write-Host "[+] Using detected model directory: $modelDir" -ForegroundColor Green
    } else {
        Write-Warning "No valid model path found. Creating local folder."
        $modelDir = Join-Path $rootDir "models"
        New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
    }
} else {
    # Empty input → use auto-found or local
    if ($defaultModelDir) {
        $modelDir = $defaultModelDir
        Write-Host "[+] Using automatically detected model directory: $modelDir" -ForegroundColor Green
    } else {
        Write-Warning "No existing models found. Using local storage."
        $modelDir = Join-Path $rootDir "models"
        New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
    }
}

# --- Create symlink (if needed) ---
$localModelDir = Join-Path $rootDir "models"
if (Test-Path $localModelDir -PathType Container) {
    Remove-Item -Path $localModelDir -Recurse -Force
}
$resolvedModelDir = (Resolve-Path $modelDir).Path
if ($resolvedModelDir -ne $localModelDir -and (Test-Path (Split-Path $localModelDir))) {
    try {
        New-Item -ItemType SymbolicLink -Path $localModelDir -Target $modelDir -ErrorAction Stop | Out-Null
        Write-Host "[+] Symlink created: $localModelDir -> $modelDir" -ForegroundColor Green
    } catch {
        Write-Warning "Could not create symlink: $_"
    }
}

# --- Step 6: ACL ---
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$account = "${env:COMPUTERNAME}\$ServiceUser"
icacls $modelDir /grant "${account}`:(OI)(CI)F" /T /C | Out-Null
icacls $logDir /grant "${account}`:(OI)(CI)M" /T /C | Out-Null
icacls $rootDir /grant "${account}`:(OI)(CI)RX" /T /C | Out-Null

# --- Step 7: .env file ---
Set-Content -Path $envPath -Value "OLLAMA_MODELS=$modelDir" -Encoding UTF8
Write-Host "[+] Environment saved: OLLAMA_MODELS=$modelDir"

# --- Step 8: Install service ---
$serviceName = "OllamaService"
if (Get-Service $serviceName -ErrorAction SilentlyContinue) {
    & $nssmPath stop $serviceName
    & $nssmPath remove $serviceName confirm
}

& $nssmPath install $serviceName $ollamaExe serve
& $nssmPath set $serviceName AppDirectory $binDir
$plainPassword = ConvertTo-PlainText $ServicePassword
& $nssmPath set $serviceName ObjectName ".\$ServiceUser" $plainPassword
& $nssmPath set $serviceName Start SERVICE_AUTO_START
& $nssmPath set $serviceName AppStdout "$logDir\out.log"
& $nssmPath set $serviceName AppStderr "$logDir\err.log"
& $nssmPath start $serviceName

# --- Final status ---
Write-Host "[*] Restarting OllamaService..." -ForegroundColor Cyan
try {
    Restart-Service OllamaService -Force -ErrorAction Stop
    Start-Sleep -Seconds 3
} catch {
    Write-Warning "Failed to restart service: $_"
}

Write-Host "[*] Service status:" -ForegroundColor Cyan
$status = Get-Service OllamaService | Select-Object Status, Name
Write-Host "    Status: $($status.Status)" -ForegroundColor Green

Write-Host "[?] Checking API at http://localhost:11434/api/version ..." -ForegroundColor Cyan
try {
    $result = & $curlPath -s http://localhost:11434/api/version
    if ($result) {
        Write-Host "    [+] API is available: $result" -ForegroundColor Green
    } else {
        Write-Warning "API returned empty response"
    }
} catch {
    Write-Warning "API not reachable: $_"
}

# --- Network info ---
$hostname = $env:COMPUTERNAME
if (-not $hostname) { $hostname = try { [System.Net.Dns]::GetHostName() } catch { "localhost" } }

$ip = $null
try {
    $ip = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled=true" |
          Select-Object -ExpandProperty IPAddress |
          Where-Object { $_ -like "*.*.*.*" -and $_ -notlike "127.*" } |
          Select-Object -First 1
} catch {}

if (-not $ip) {
    try {
        $addr = [System.Net.Dns]::GetHostEntry([System.Net.Dns]::GetHostName()).AddressList
        $ip = $addr | Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -notlike "127.*" } |
              Select-Object -First 1 |
              ForEach-Object { $_.ToString() }
    } catch {}
}

Write-Host "`n[+] INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host "    Local access: http://localhost:11434"
if ($hostname) { Write-Host "    Network access (hostname): http://${hostname}:11434" }
if ($ip)       { Write-Host "    Network access (IP): http://${ip}:11434" }
Write-Host "    Models: $modelDir"
Write-Host "    Logs: $logDir\out.log"
Write-Host "    Reboot PC to verify auto-start." -ForegroundColor Yellow
Write-Host "    You can now close this window." -ForegroundColor Gray
