# ═══════════════════════════════════════════════════════════════
# run_server.ps1 - Pornire backend FastAPI cu encoding UTF-8 corect
# 
# Folosinta:
#   .\run_server.ps1
# ═══════════════════════════════════════════════════════════════

# Forteaza UTF-8 pentru emoji si diacritice
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = "utf-8"
chcp 65001 | Out-Null

# Activeaza virtual environment
& ".\venv\Scripts\Activate.ps1"

Write-Host ""
Write-Host "Backend pornit pe:" -ForegroundColor Green
Write-Host "  Root:    http://localhost:8000" -ForegroundColor Cyan
Write-Host "  Health:  http://localhost:8000/api/health" -ForegroundColor Cyan
Write-Host "  Docs:    http://localhost:8000/docs" -ForegroundColor Cyan
Write-Host ""

# Porneste server
uvicorn main:app --host 0.0.0.0 --port 8000 --reload