# ═══════════════════════════════════════════════════════════════
# run_dev.ps1 - Rulare aplicatie cu salvare log-uri pentru dev
# 
# Genereaza 2 fisiere per sesiune:
#   - session_TIMESTAMP_FULL.txt  -> tot output-ul flutter run
#   - session_TIMESTAMP_APP.txt   -> doar mesajele AppLogger ([APP_LOG])
# 
# Folosinta: .\run_dev.ps1
# ═══════════════════════════════════════════════════════════════

# Forteaza UTF-8 pentru tot output-ul
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

# Genereaza nume fisiere cu timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$fullLogFile = "dev_logs\session_${timestamp}_FULL.txt"
$appLogFile  = "dev_logs\session_${timestamp}_APP.txt"

# Asigura-te ca folderul dev_logs exista
if (-not (Test-Path "dev_logs")) {
    New-Item -ItemType Directory -Path "dev_logs" | Out-Null
}

# Header informativ
$header = @"
===============================================================
GUITAR TUNER AI - Dev Session Log
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Working directory: $(Get-Location)
===============================================================

"@

# Scrie header in ambele fisiere folosind streams (fara BOM, UTF-8 curat)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText((Resolve-Path "." | Join-Path -ChildPath $fullLogFile), $header, $utf8NoBom)
[System.IO.File]::WriteAllText((Resolve-Path "." | Join-Path -ChildPath $appLogFile), $header, $utf8NoBom)

# Cai absolute pentru append (StreamWriter)
$fullPath = (Resolve-Path $fullLogFile).Path
$appPath  = (Resolve-Path $appLogFile).Path

# Deschide stream writers UTF-8 (mai rapid, fara BOM, append)
$fullWriter = New-Object System.IO.StreamWriter($fullPath, $true, $utf8NoBom)
$appWriter  = New-Object System.IO.StreamWriter($appPath, $true, $utf8NoBom)
$fullWriter.AutoFlush = $true
$appWriter.AutoFlush  = $true

Write-Host ""
Write-Host "FULL log: $fullLogFile" -ForegroundColor Cyan
Write-Host "APP log:  $appLogFile" -ForegroundColor Green
Write-Host "Pornesc aplicatia..." -ForegroundColor Yellow
Write-Host ""

# Navigheaza in mobile-app si ruleaza
Set-Location mobile-app

try {
    flutter run 2>&1 | ForEach-Object {
        $line = $_.ToString()
        
        # Scrie in consola (vezi in PowerShell)
        Write-Host $line
        
        # Scrie in FULL log (tot)
        $fullWriter.WriteLine($line)
        
        # Scrie in APP log (doar liniile cu [APP_LOG])
        if ($line -match '\[APP_LOG\]') {
            # Curata codurile ANSI de culoare pentru fisier
            $cleaned = $line -replace '\x1B\[[0-9;]*[a-zA-Z]', ''
            $appWriter.WriteLine($cleaned)
        }
    }
}
finally {
    # Inchide stream writers chiar daca apare eroare
    $fullWriter.Close()
    $appWriter.Close()
    Set-Location ..
}

Write-Host ""
Write-Host "Log-uri salvate:" -ForegroundColor Yellow
Write-Host "   FULL: $fullLogFile" -ForegroundColor Cyan
Write-Host "   APP:  $appLogFile" -ForegroundColor Green