# ======================================
# Restore local Redis docker container from an already-downloaded RDB dump.
# Does NOT touch the dev server — just replays dump-dev.rdb from
# redis.backupFolder (see clone-redis-dev.ps1) into the local container.
# Reads redis settings from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig
$redis = $config.redis

$Container = $redis.container
$Volume    = $redis.volume
$DumpFile  = "dump-dev.rdb"
$Folder    = Join-Path $config.reposRoot $redis.backupFolder
$dumpPath  = Join-Path $Folder $DumpFile

if (-not (Test-Path $dumpPath)) {
    Write-Host "No backup found at $dumpPath — run redis/clone-redis-dev.ps1 first (or copy a dump there manually)." -ForegroundColor Red
    exit 1
}

function Log([string]$msg) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg"
}

function Assert-Success([string]$msg) {
    if ($LASTEXITCODE -ne 0) {
        Write-Error $msg
        exit 1
    }
}

trap {
    Log "Error encountered — attempting to restart '$Container'..."
    docker start $Container
    exit 1
}

Log "Restoring local container '$Container' from $dumpPath..."

Log "Stopping container '$Container'..."
docker stop $Container
Assert-Success "Failed to stop container"

Log "Clearing old dump files from volume '$Volume'..."
docker run --rm -v "${Volume}:/data" alpine rm -f /data/dump.rdb /data/dump-dev.rdb
Assert-Success "Failed to clear old dump files"

Log "Copying dump into container..."
docker cp "$dumpPath" "${Container}:/data/dump.rdb"
Assert-Success "Failed to copy dump into container"

Log "Restarting container '$Container'..."
docker restart $Container
Assert-Success "Failed to restart container"

Log "Restore completed successfully."
