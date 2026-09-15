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

function Get-TmsAndroidDeployConfig {
    <#
    Reads android.deploy.<Environment>.{apiUrl,apiKey,appId,userActionId} --
    the internal deploy API used by android/install-latest-*.ps1 to look up
    the latest build for that environment (e.g. "dev", "stg" -- each is a
    different host/AppId/UserActionId). ApiKey/UserActionId here are
    app-level identifiers the deploy API expects in its request body, not
    login secrets, so (like the rest of android.*) they live in
    tms.config.json rather than behind Get-TmsSecret.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Environment
    )

    $deploy = $Config.android.deploy.$Environment
    if (-not $deploy -or [string]::IsNullOrWhiteSpace($deploy.apiUrl) -or
        [string]::IsNullOrWhiteSpace($deploy.apiKey) -or [string]::IsNullOrWhiteSpace($deploy.appId) -or
        [string]::IsNullOrWhiteSpace($deploy.userActionId)) {
        Write-Host "No android.deploy.$Environment configured (apiUrl/apiKey/appId/userActionId). Edit tms.config.json or re-run setup\init-config.ps1." -ForegroundColor Red
        exit 1
    }
    return $deploy
}

function Get-TmsAndroidRunningDevices {
    <#
    Lists currently running emulator serials via `adb devices` and resolves
    each one's AVD name -- `adb devices` only prints emulator-XXXX serials,
    not AVD names, same lookup android/stop.ps1 does per-serial.
    #>
    param([Parameter(Mandatory)][string]$AdbExe)

    $serials = & $AdbExe devices 2>$null |
        Select-String '^emulator-\d+' |
        ForEach-Object { ($_ -split '\s+')[0] }

    return @($serials | ForEach-Object {
        $serial = $_
        $avdName = (& $AdbExe -s $serial emu avd name 2>$null | Select-Object -First 1)
        [PSCustomObject]@{ Serial = $serial; AvdName = if ($avdName) { $avdName.Trim() } else { $serial } }
    })
}

function Select-TmsRunningAndroidDevice {
    <#
    Picks a running emulator to target. Auto-selects with no prompt if
    exactly one is running; shows a picker if several are. Exits the script
    (code 1) if none are running, so callers can assume a non-null return.
    #>
    param(
        [Parameter(Mandatory)][string]$AdbExe,
        [string]$Prompt = "Select a running emulator"
    )

    $devices = Get-TmsAndroidRunningDevices -AdbExe $AdbExe
    if ($devices.Count -eq 0) {
        Write-Host "No running Android emulator found. Start one first (android/start.ps1)." -ForegroundColor Red
        exit 1
    }
    if ($devices.Count -eq 1) { return $devices[0] }

    $labels = @($devices | ForEach-Object { "$($_.AvdName) ($($_.Serial))" })
    $index = Show-Menu -Labels $labels -Prompt $Prompt
    if ($index -eq -1) {
        Write-Host "Cancelled." -ForegroundColor DarkYellow
        exit 0
    }
    return $devices[$index]
}

function Invoke-TmsAndroidInstallLatest {
    <#
    Full install-latest flow shared by android/install-latest-dev.ps1 and
    android/install-latest-stg.ps1: resolve exes/config, pick a running
    emulator, call the deploy API for -Environment, pick the newest
    DEPLOY-status version, download its APK, adb push + pm install it, then
    delete both the device and local copies.

    The two environments' deploy APIs return differently-shaped responses
    (dev's GetAppInfoById nests versions under .Data.Versions; stg's
    GetAppHistoryById returns .Versions at the top level, alongside an
    IsError/ErrorMessage pair) -- both are handled here.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Environment
    )

    $emulatorExe = Get-TmsAndroidEmulatorExe -Config $Config
    $adbExe = Get-TmsAndroidAdbExe -Config $Config
    $deploy = Get-TmsAndroidDeployConfig -Config $Config -Environment $Environment

    $device = Select-TmsRunningAndroidDevice -AdbExe $adbExe -Prompt "Select a running emulator to install onto"

    Write-Host "-> " -ForegroundColor Green -NoNewline
    Write-Host "Target: " -ForegroundColor White -NoNewline
    Write-Host "$($device.AvdName) ($($device.Serial))" -ForegroundColor Cyan

    Write-Host "-> Fetching latest $Environment build info for $($deploy.appId)..." -ForegroundColor Green
    $body = @{ ApiKey = $deploy.apiKey; UserActionId = $deploy.userActionId; AppId = $deploy.appId } | ConvertTo-Json
    try {
        $response = Invoke-RestMethod -Uri $deploy.apiUrl -Method Post -ContentType "application/json" -Body $body
    } catch {
        Write-Host "Failed to call deploy API: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    if ($response.IsError) {
        Write-Host "Deploy API returned an error: $($response.ErrorMessage)" -ForegroundColor Red
        exit 1
    }

    $versions = if ($response.Data) { $response.Data.Versions } else { $response.Versions }
    $latest = @($versions | Where-Object { $_.DeployStatus -eq "DEPLOY" }) |
        Sort-Object { [datetime]$_.StartTime } -Descending |
        Select-Object -First 1

    if (-not $latest) {
        Write-Host "No deployed version found for $($deploy.appId)." -ForegroundColor Red
        exit 1
    }

    Write-Host "-> " -ForegroundColor Green -NoNewline
    Write-Host "Latest: " -ForegroundColor White -NoNewline
    Write-Host "v$($latest.Version) - $($latest.Description)" -ForegroundColor Cyan

    $fileName = Split-Path $latest.FileUrl -Leaf
    $localPath = Join-Path ([System.IO.Path]::GetTempPath()) $fileName
    $remotePath = "/data/local/tmp/$fileName"

    Write-Host "-> Downloading $fileName..." -ForegroundColor Green
    try {
        Invoke-WebRequest -Uri $latest.FileUrl -OutFile $localPath
    } catch {
        Write-Host "Failed to download APK: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    try {
        Write-Host "-> Copying to emulator..." -ForegroundColor Green
        & $adbExe -s $device.Serial push $localPath $remotePath | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "adb push failed (exit $LASTEXITCODE)" }

        Write-Host "-> Installing..." -ForegroundColor Green
        $installOutput = & $adbExe -s $device.Serial shell pm install -r $remotePath 2>&1
        if ($LASTEXITCODE -ne 0 -or $installOutput -notmatch "Success") {
            throw "pm install failed: $installOutput"
        }

        Write-Host "-> " -ForegroundColor Green -NoNewline
        Write-Host "Installed " -ForegroundColor White -NoNewline
        Write-Host "v$($latest.Version) ($Environment) on $($device.AvdName)." -ForegroundColor Cyan
    } catch {
        Write-Host "Install failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    } finally {
        Write-Host "-> Cleaning up APK..." -ForegroundColor Green
        & $adbExe -s $device.Serial shell rm -f $remotePath 2>&1 | Out-Null
        Remove-Item $localPath -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Get-TmsAndroidEmulatorExe, Get-TmsAndroidAdbExe, Get-TmsAndroidAvds, Select-TmsAvd, `
    Get-TmsAndroidDeployConfig, Get-TmsAndroidRunningDevices, Select-TmsRunningAndroidDevice, Invoke-TmsAndroidInstallLatest
