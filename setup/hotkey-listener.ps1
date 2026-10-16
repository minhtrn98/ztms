# ======================================
# Long-running, headless: registers the global ztms hotkey (hotkey.keys,
# default Ctrl+Space) and toggles the ztms menu window on each press.
# Started at logon by the "ztms Hotkey" scheduled task that
# setup\install-hotkey.ps1 registers — not a menu entry, not meant to be run
# by hand. See Hotkey.psm1.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Hotkey.psm1") -Force

# No config yet just means the default hotkey
$config = $null
try { $config = Get-TmsConfig } catch {}

try { $hotkey = Get-TmsHotkey -Config $config }
catch {
    Write-Host "Invalid hotkey.keys: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not (Start-TmsHotkeyListener -Hotkey $hotkey -ScriptsRoot (Split-Path $PSScriptRoot -Parent))) {
    Write-Host "$($hotkey.Display) is already taken by another app." -ForegroundColor Red
    exit 1
}
