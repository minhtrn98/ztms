# Shared Android emulator helpers: resolving emulator.exe/adb.exe from
# config.android.emulatorPath, listing AVDs, and the AVD-picker menu used by
# all three android/*.ps1 scripts. Depends on Show-Menu from ProjectMenu.psm1
# being imported into the caller's session first.

function Get-TmsAndroidEmulatorExe {
    param([Parameter(Mandatory)]$Config)

    $emulatorFolder = $Config.android.emulatorPath
    if ([string]::IsNullOrWhiteSpace($emulatorFolder)) {
        Write-Host "No android.emulatorPath configured. Edit tms.config.json or re-run setup\init-config.ps1." -ForegroundColor Red
        exit 1
    }

    $exe = Join-Path $emulatorFolder "emulator.exe"
    if (-not (Test-Path $exe)) {
        Write-Host "emulator.exe not found at $exe" -ForegroundColor Red
        exit 1
    }
    return $exe
}

function Get-TmsAndroidAdbExe {
    <#
    adb.exe isn't separately configured -- it's derived as a sibling of the
    emulator folder (<sdk>\platform-tools\adb.exe), same SDK layout Android
    Studio uses. Falls back to a bare "adb" call (relies on PATH) if that
    folder doesn't exist.
    #>
    param([Parameter(Mandatory)]$Config)

    $sdkRoot = Split-Path $Config.android.emulatorPath -Parent
    $adb = Join-Path $sdkRoot "platform-tools\adb.exe"
    if (Test-Path $adb) { return $adb }
    return "adb"
}

function Get-TmsAndroidAvds {
    param([Parameter(Mandatory)][string]$EmulatorExe)

    $output = & $EmulatorExe -list-avds 2>$null
    return @($output | Where-Object { $_ -and ($_ -notmatch '^(INFO|WARNING|ERROR)') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Select-TmsAvd {
    <#
    Lists AVDs via `emulator -list-avds` and shows the Show-Menu picker.
    Exits the script (code 0) if the user cancels, or (code 1) if there are
    no AVDs to pick from -- callers can assume a non-empty return.
    #>
    param(
        [Parameter(Mandatory)][string]$EmulatorExe,
        [string]$Prompt = "Select an AVD"
    )

    $avds = Get-TmsAndroidAvds -EmulatorExe $EmulatorExe
    if ($avds.Count -eq 0) {
        Write-Host "No AVDs found. Create one in Android Studio's Device Manager first." -ForegroundColor Red
        exit 1
    }

    $index = Show-Menu -Labels $avds -Prompt $Prompt
    if ($index -eq -1) {
        Write-Host "Cancelled." -ForegroundColor DarkYellow
        exit 0
    }
    return $avds[$index]
}

Export-ModuleMember -Function Get-TmsAndroidEmulatorExe, Get-TmsAndroidAdbExe, Get-TmsAndroidAvds, Select-TmsAvd
