# ======================================
# Open the frontend folder in VS Code.
# Reads frontend.path from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig
$fe = $config.frontend

if (-not $fe -or [string]::IsNullOrWhiteSpace($fe.path)) {
    Write-Host "No frontend configured. Edit tms.config.json (add a 'frontend' section) or re-run 900_init-config.ps1." -ForegroundColor Red
    exit 1
}

if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 'code' command not found on PATH. Install VS Code and enable the 'code' shell command." -ForegroundColor Red
    exit 1
}

$fePath = if ([System.IO.Path]::IsPathRooted($fe.path)) { $fe.path } else { Join-Path $config.reposRoot $fe.path }
if (-not (Test-Path $fePath)) {
    Write-Host "Frontend folder not found: $fePath" -ForegroundColor Red
    exit 1
}

Write-Host "-> " -ForegroundColor Green -NoNewline
Write-Host "Opening in VS Code: " -ForegroundColor White -NoNewline
Write-Host "$fePath" -ForegroundColor Cyan

& code $fePath

Write-Host "`n🎉 DONE" -ForegroundColor Magenta
