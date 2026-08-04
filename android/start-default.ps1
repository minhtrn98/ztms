# ======================================
# Start an Android emulator with a cold boot (-no-snapshot-load -- ignores any saved snapshot).
# Reads android.emulatorPath from tms.config.json -- run setup\init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\ProjectMenu.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Android.psm1") -Force

$config = Get-TmsConfig
$emulatorExe = Get-TmsAndroidEmulatorExe -Config $config
$avd = Select-TmsAvd -EmulatorExe $emulatorExe -Prompt "Select an AVD to start (cold boot, no snapshot)"

Write-Host "-> " -ForegroundColor Green -NoNewline
Write-Host "Starting (cold boot): " -ForegroundColor White -NoNewline
Write-Host $avd -ForegroundColor Cyan

Start-Process -FilePath $emulatorExe -ArgumentList @("-avd", $avd, "-no-snapshot-load")
