# ======================================
# Removes the global ztms hotkey: stops the listener and unregisters the
# "ztms Hotkey" scheduled task that setup\install-hotkey.ps1 created.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Hotkey.psm1") -Force

Uninstall-TmsHotkey
