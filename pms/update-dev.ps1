# ======================================
# Manually trigger the PMS DEV auto-update: runs the machine's PMS update
# script now instead of waiting for its scheduled task. That script checks
# the latest version, downloads + unzips it into a new version folder, and
# shows a Windows notification on success/error.
# Reads pms.dev.updateScript from tms.config.json — run setup\init-config.ps1
# first, or add the 'pms' section by hand (see tms.config.example.json).
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig
$updateScript = if ($config.pms -and $config.pms.dev) { $config.pms.dev.updateScript }

if ([string]::IsNullOrWhiteSpace($updateScript)) {
    Write-Host "No pms.dev.updateScript configured. Edit tms.config.json (add a 'pms' section) — see tms.config.example.json." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $updateScript)) {
    Write-Host "PMS update script not found: $updateScript" -ForegroundColor Red
    exit 1
}

Write-Host "-> " -ForegroundColor Green -NoNewline
Write-Host "Running PMS DEV update: " -ForegroundColor White -NoNewline
Write-Host "$updateScript`n" -ForegroundColor Cyan

& pwsh -NoProfile -ExecutionPolicy Bypass -File $updateScript

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n❌ PMS DEV update failed (exit code $LASTEXITCODE)" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`n🎉 DONE" -ForegroundColor Magenta
