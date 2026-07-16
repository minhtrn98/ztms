# ======================================
# Build and run the frontend (blocking — runs in this terminal, not a new window).
# Reads frontend.* from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path $PSScriptRoot "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig
$fe = $config.frontend

if (-not $fe -or [string]::IsNullOrWhiteSpace($fe.path)) {
    Write-Host "No frontend configured. Edit tms.config.json (add a 'frontend' section) or re-run 900_init-config.ps1." -ForegroundColor Red
    exit 1
}

$fePath = if ([System.IO.Path]::IsPathRooted($fe.path)) { $fe.path } else { Join-Path $config.reposRoot $fe.path }
if (-not (Test-Path $fePath)) {
    Write-Host "Frontend folder not found: $fePath" -ForegroundColor Red
    exit 1
}

Set-Location $fePath

if ($fe.buildCommand) {
    Write-Host "-> " -ForegroundColor Green -NoNewline
    Write-Host "Building: " -ForegroundColor White -NoNewline
    Write-Host "$($fe.buildCommand) " -ForegroundColor Cyan -NoNewline
    Write-Host "in $fePath" -ForegroundColor White
    Invoke-Expression $fe.buildCommand
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed (exit $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }
}

if (-not $fe.startCommand) {
    Write-Host "No frontend.startCommand configured — nothing to run." -ForegroundColor Red
    exit 1
}

Write-Host "-> " -ForegroundColor Green -NoNewline
Write-Host "Starting: " -ForegroundColor White -NoNewline
Write-Host $fe.startCommand -ForegroundColor Cyan
Invoke-Expression $fe.startCommand
