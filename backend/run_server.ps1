# ===============================================================
# run_server.ps1 - Backend FastAPI runner
#
# - Cd's into its own dir so it works no matter where it's invoked from
# - Activates venv (clear error if missing)
# - Syncs deps from requirements.txt every run (idempotent + fast)
# - Verifies a critical import to catch silent install failures
# - Dual logging in backend/server_logs/ (FULL + APP)
#
# Script is ASCII-only on purpose: PowerShell 5.1 reads .ps1 files as
# ANSI unless they have a UTF-8 BOM, so non-ASCII would break parsing.
#
# Usage:  .\run_server.ps1
# ===============================================================

# Always run from the script's own directory (so 'requirements.txt'
# and 'venv\' resolve correctly even if invoked as backend\run_server.ps1)
Set-Location -LiteralPath $PSScriptRoot

# UTF-8 for emoji and diacritics in CHILD process output (Python logs)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = "utf-8"
chcp 65001 | Out-Null

# Check venv
if (-not (Test-Path ".\venv\Scripts\Activate.ps1")) {
    Write-Host "[ERROR] Venv missing. Create it once with:" -ForegroundColor Red
    Write-Host "        python -m venv venv" -ForegroundColor Yellow
    exit 1
}

& ".\venv\Scripts\Activate.ps1"

# --- Sync dependencies -----------------------------------------------
# Run pip install -r requirements.txt every time. When everything is
# already satisfied it's idempotent and fast (~1-2s). Initial install
# of TensorFlow + CREPE takes a few minutes the first time only.
#
# PIP_CONSTRAINT makes pip honor constraints.txt in BOTH the venv and
# the isolated build environments it spawns for sdist packages. This
# pins setuptools<81 so 'import pkg_resources' still works in legacy
# setup.py scripts (crepe deps: hmmlearn / resampy).
#
# IMPORTANT: pip splits PIP_CONSTRAINT on whitespace, so the path must
# NOT contain spaces. The repo lives under "Lucrare de licenta" (with
# spaces), so we copy the constraints file into TEMP first.
$tempConstraint = Join-Path $env:TEMP "gtune_constraints.txt"
Copy-Item -Path ".\constraints.txt" -Destination $tempConstraint -Force
$env:PIP_CONSTRAINT = $tempConstraint
$env:PIP_DISABLE_PIP_VERSION_CHECK = "1"

Write-Host ""
Write-Host "[deps] Constraints staged at: $tempConstraint" -ForegroundColor DarkGray
Write-Host "[deps] Upgrading pip and build tools..." -ForegroundColor Yellow
python -m pip install --upgrade pip --quiet
python -m pip install --upgrade "setuptools<81" wheel --quiet

Write-Host "[deps] Syncing dependencies from requirements.txt..." -ForegroundColor Yellow
python -m pip install -r requirements.txt --prefer-binary --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERROR] pip install failed (exit $LASTEXITCODE). Server NOT started." -ForegroundColor Red
    exit $LASTEXITCODE
}

# Pre-flight: import a critical package to make sure install really worked.
# (multipart = FastAPI uploads; crepe = AI pipeline; bcrypt + jwt = auth;
#  dns = email domain validation.)
python -c "import multipart, crepe, tensorflow, numpy, bcrypt, jwt, dns.resolver" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERROR] Critical package import failed. Run manually:" -ForegroundColor Red
    Write-Host "        python -m pip install -r requirements.txt" -ForegroundColor Yellow
    exit 1
}
Write-Host "[deps] OK." -ForegroundColor Green

# --- Dual logging ----------------------------------------------------
if (-not (Test-Path "server_logs")) {
    New-Item -ItemType Directory -Path "server_logs" | Out-Null
}
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$fullLogFile = "server_logs\session_${timestamp}_FULL.txt"
$appLogFile  = "server_logs\session_${timestamp}_APP.txt"

$header = @"
===============================================================
GUITAR TUNER AI - Server Session Log
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Working directory: $(Get-Location)
===============================================================

"@

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText((Resolve-Path "." | Join-Path -ChildPath $fullLogFile), $header, $utf8NoBom)
[System.IO.File]::WriteAllText((Resolve-Path "." | Join-Path -ChildPath $appLogFile),  $header, $utf8NoBom)

$fullPath = (Resolve-Path $fullLogFile).Path
$appPath  = (Resolve-Path $appLogFile).Path
$fullWriter = New-Object System.IO.StreamWriter($fullPath, $true, $utf8NoBom)
$appWriter  = New-Object System.IO.StreamWriter($appPath,  $true, $utf8NoBom)
$fullWriter.AutoFlush = $true
$appWriter.AutoFlush  = $true

# --- LAN IP discovery & sanity check ---------------------------------
# The mobile app hardcodes a LAN IP in mobile-app/lib/utils/constants.dart.
# Wi-Fi networks change, DHCP rotates IPs, so the value can go stale and
# the phone times out with no obvious cause. We surface the current IP
# and warn if it doesn't match what the app expects.
$lanIPs = @(
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -like '192.168.*' -or
            $_.IPAddress -like '10.*' -or
            $_.IPAddress -like '172.1[6-9].*' -or
            $_.IPAddress -like '172.2[0-9].*' -or
            $_.IPAddress -like '172.3[01].*'
        } |
        Where-Object { $_.InterfaceAlias -notlike 'vEthernet*' -and $_.InterfaceAlias -notlike '*VirtualBox*' } |
        Select-Object -ExpandProperty IPAddress
)

$constantsFile = "..\mobile-app\lib\utils\constants.dart"
$expectedIP = $null
if (Test-Path $constantsFile) {
    $constantsContent = Get-Content $constantsFile -Raw
    if ($constantsContent -match "http://(\d+\.\d+\.\d+\.\d+):8000") {
        $expectedIP = $Matches[1]
    }
}

Write-Host ""
Write-Host "Backend started on:" -ForegroundColor Green
Write-Host "  Root:    http://localhost:8000" -ForegroundColor Cyan
Write-Host "  Health:  http://localhost:8000/api/health" -ForegroundColor Cyan
Write-Host "  Docs:    http://localhost:8000/docs" -ForegroundColor Cyan
Write-Host ""
Write-Host "LAN access (from phone, same Wi-Fi):" -ForegroundColor Green
foreach ($ip in $lanIPs) {
    Write-Host "  http://${ip}:8000" -ForegroundColor Cyan
}

if ($expectedIP) {
    if ($lanIPs -contains $expectedIP) {
        Write-Host ""
        Write-Host "[net] App expects $expectedIP - matches a current LAN IP. OK." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "[net] WARNING: App expects $expectedIP but laptop has $($lanIPs -join ', ')" -ForegroundColor Yellow
        Write-Host "[net] Update mobile-app/lib/utils/constants.dart (_baseUrlDebug) and hot-restart." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "FULL log: $fullLogFile" -ForegroundColor Cyan
Write-Host "APP  log: $appLogFile" -ForegroundColor Green
Write-Host ""

# App log lines use the custom timestamp formatter
# "HH:MM:SS.mmm | LEVEL | logger | ...". Everything else is uvicorn's
# native output and goes only to the FULL log.
$appPattern = '^\d{2}:\d{2}:\d{2}'

try {
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload 2>&1 | ForEach-Object {
        $line = $_.ToString()
        Write-Host $line
        $fullWriter.WriteLine($line)
        if ($line -match $appPattern) {
            $cleaned = $line -replace '\x1B\[[0-9;]*[a-zA-Z]', ''
            $appWriter.WriteLine($cleaned)
        }
    }
}
finally {
    $fullWriter.Close()
    $appWriter.Close()
    Write-Host ""
    Write-Host "Logs saved:" -ForegroundColor Yellow
    Write-Host "   FULL: $fullLogFile" -ForegroundColor Cyan
    Write-Host "   APP:  $appLogFile" -ForegroundColor Green
}