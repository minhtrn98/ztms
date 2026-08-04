# ======================================
# Open the working folder (reposRoot) in File Explorer.
# Reads reposRoot from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig

if (-not $config.reposRoot -or -not (Test-Path $config.reposRoot)) {
    Write-Host "reposRoot not found: $($config.reposRoot). Edit tms.config.json or re-run 900_init-config.ps1." -ForegroundColor Red
    exit 1
}

Write-Host "-> " -ForegroundColor Green -NoNewline
Write-Host "Opening working folder: " -ForegroundColor White -NoNewline
Write-Host "$($config.reposRoot)" -ForegroundColor Cyan

Start-Process explorer.exe $config.reposRoot
