# ======================================
# Open the latest installed PMS DEV build: runs the machine's PMS start
# script, which picks the newest version folder (the app updates itself into
# a new folder per version, so a fixed shortcut goes stale).
# Reads pms.dev.startScript from tms.config.json — run setup\init-config.ps1
# first, or add the 'pms' section by hand (see tms.config.example.json).
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig
$startScript = if ($config.pms -and $config.pms.dev) { $config.pms.dev.startScript }

if ([string]::IsNullOrWhiteSpace($startScript)) {
    Write-Host "No pms.dev.startScript configured. Edit tms.config.json (add a 'pms' section) — see tms.config.example.json." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $startScript)) {
    Write-Host "PMS start script not found: $startScript" -ForegroundColor Red
    exit 1
}

Write-Host "-> " -ForegroundColor Green -NoNewline
Write-Host "Starting PMS DEV: " -ForegroundColor White -NoNewline
Write-Host "$startScript" -ForegroundColor Cyan

& pwsh -NoProfile -ExecutionPolicy Bypass -File $startScript

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n❌ Failed to start PMS DEV (exit code $LASTEXITCODE)" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`n🎉 DONE" -ForegroundColor Magenta
