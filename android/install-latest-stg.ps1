# ======================================
# Install the latest STAGING build onto a running Android emulator: calls
# the staging deploy API for the latest version, downloads the APK, copies
# it to the device, installs it, then deletes the APK (device + local
# copy). See android/install-latest-dev.ps1 for the dev counterpart --
# both are thin wrappers around Invoke-TmsAndroidInstallLatest in
# Android.psm1.
# Reads android.emulatorPath and android.deploy.stg.{apiUrl,apiKey,appId,
# userActionId} from tms.config.json -- run setup\init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\ProjectMenu.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Android.psm1") -Force

$config = Get-TmsConfig
Invoke-TmsAndroidInstallLatest -Config $config -Environment "stg"
