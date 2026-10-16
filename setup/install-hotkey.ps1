# ======================================
# Spotlight-style global hotkey for the ztms menu: press it anywhere in
# Windows to open ztms, press again to hide it. Registers the "ztms Hotkey"
# scheduled task (starts setup\hotkey-listener.ps1 headless at logon) and
# starts it now. Safe to re-run — also how a changed hotkey is picked up.
# Reads hotkey.keys from tms.config.json (default "Ctrl+Space").
# Undo with SETUP > uninstall-hotkey. See Install-TmsHotkey in Hotkey.psm1.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Hotkey.psm1") -Force

$config = Get-TmsConfig

try { $hotkey = Get-TmsHotkey -Config $config }
catch {
    Write-Host "Invalid hotkey.keys in tms.config.json: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Install-TmsHotkey -Hotkey $hotkey -ScriptsRoot (Split-Path $PSScriptRoot -Parent)

Write-Host "`nPress $($hotkey.Display) anywhere to open ztms; press it again to hide it." -ForegroundColor Cyan
if ($hotkey.Display -eq "Ctrl+Space") {
    Write-Host "Note: this takes Ctrl+Space from every app (e.g. VS Code's 'trigger suggest'). To use another combo, set hotkey.keys in tms.config.json and re-run." -ForegroundColor Gray
}

Write-Host "`n🎉 DONE" -ForegroundColor Magenta
