# ======================================
# Stop a running Android emulator.
# Reads android.emulatorPath from tms.config.json -- run setup\init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\ProjectMenu.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Android.psm1") -Force

$config = Get-TmsConfig
$emulatorExe = Get-TmsAndroidEmulatorExe -Config $config
$adbExe = Get-TmsAndroidAdbExe -Config $config
$avd = Select-TmsAvd -EmulatorExe $emulatorExe -Prompt "Select an AVD to stop"

# `adb devices` only lists emulator-XXXX serials, not AVD names -- resolve
# each running serial's AVD name to find the one the user picked.
$serials = & $adbExe devices 2>$null |
    Select-String '^emulator-\d+' |
    ForEach-Object { ($_ -split '\s+')[0] }

$targetSerial = $null
foreach ($serial in $serials) {
    $runningAvd = (& $adbExe -s $serial emu avd name 2>$null | Select-Object -First 1)
    if ($runningAvd -and $runningAvd.Trim() -eq $avd) { $targetSerial = $serial; break }
}

if (-not $targetSerial) {
    Write-Host "'$avd' is not currently running." -ForegroundColor DarkYellow
    exit 0
}

Write-Host "-> " -ForegroundColor Green -NoNewline
Write-Host "Stopping: " -ForegroundColor White -NoNewline
Write-Host "$avd ($targetSerial)" -ForegroundColor Cyan

& $adbExe -s $targetSerial emu kill
