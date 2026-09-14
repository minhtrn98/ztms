# ======================================
# Install the latest deployed build onto a running Android emulator:
# calls the deploy API for the latest version, downloads the APK, copies it
# to the device, installs it, then deletes the APK (device + local copy).
# Reads android.emulatorPath and android.deploy.{apiUrl,apiKey,appId} from
# tms.config.json -- run setup\init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\ProjectMenu.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Android.psm1") -Force

$config = Get-TmsConfig
$emulatorExe = Get-TmsAndroidEmulatorExe -Config $config
$adbExe = Get-TmsAndroidAdbExe -Config $config
$deploy = Get-TmsAndroidDeployConfig -Config $config

$device = Select-TmsRunningAndroidDevice -AdbExe $adbExe -Prompt "Select a running emulator to install onto"

Write-Host "-> " -ForegroundColor Green -NoNewline
Write-Host "Target: " -ForegroundColor White -NoNewline
Write-Host "$($device.AvdName) ($($device.Serial))" -ForegroundColor Cyan

Write-Host "-> Fetching latest build info for $($deploy.appId)..." -ForegroundColor Green
$body = @{ ApiKey = $deploy.apiKey; UserActionId = "ADMIN"; AppId = $deploy.appId } | ConvertTo-Json
try {
    $response = Invoke-RestMethod -Uri $deploy.apiUrl -Method Post -ContentType "application/json" -Body $body
} catch {
    Write-Host "Failed to call deploy API: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$latest = @($response.Data.Versions | Where-Object { $_.DeployStatus -eq "DEPLOY" }) |
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
    Write-Host "v$($latest.Version) on $($device.AvdName)." -ForegroundColor Cyan
} catch {
    Write-Host "Install failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Write-Host "-> Cleaning up APK..." -ForegroundColor Green
    & $adbExe -s $device.Serial shell rm -f $remotePath 2>&1 | Out-Null
    Remove-Item $localPath -Force -ErrorAction SilentlyContinue
}
