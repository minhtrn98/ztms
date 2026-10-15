# ======================================
# Set up PMS DEV on this machine: download the latest build if none is
# installed, create the "PMS Dev" desktop shortcut (always opens the newest
# build) and register the "PMS Dev Auto Update" scheduled task (runs
# pms\update-dev.ps1 every minute). Safe to re-run — replaces both in place.
# See Install-TmsPmsDev in Pms.psm1.
# Reads pms.dev.* from tms.config.json — see tms.config.example.json.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Pms.psm1") -Force

$config = Get-TmsConfig
$pms = Get-TmsPmsDevConfig -Config $config
Install-TmsPmsDev -Pms $pms -ScriptsRoot (Split-Path $PSScriptRoot -Parent)

if ($pms.PasswordEnvVar -and -not [Environment]::GetEnvironmentVariable($pms.PasswordEnvVar, "User")) {
    Write-Host "`nTip: set the PMS login password once so [dev] start copies it to the clipboard:" -ForegroundColor Gray
    Write-Host "  [Environment]::SetEnvironmentVariable('$($pms.PasswordEnvVar)', '<password>', 'User')" -ForegroundColor Gray
}

Write-Host "`n🎉 DONE" -ForegroundColor Magenta
