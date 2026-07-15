# ======================================
# Sync Redis cache from dev to local docker container
# Reads redis settings from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig
$redis = $config.redis

if ([string]::IsNullOrWhiteSpace($redis.devHost)) {
    Write-Host "No redis.devHost configured — nothing to sync from. Edit tms.config.json." -ForegroundColor Red
    exit 1
}

$DevHost     = $redis.devHost
$DevPort     = $redis.devPort
$Container   = $redis.container
$Volume      = $redis.volume
$DumpFile    = "dump-dev.rdb"
$Folder      = Join-Path $config.reposRoot $redis.backupFolder
$DevPassword = Get-TmsSecret -EnvVarName $redis.devPasswordEnvVar -PromptMessage "Enter dev Redis password"

if (-not (Test-Path $Folder)) {
    New-Item -ItemType Directory -Path $Folder | Out-Null
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

Log "Starting Redis sync from DEV ($DevHost : $DevPort) -> Local container '$Container'..."

Log "Exporting RDB from DEV..."
docker exec -e REDISCLI_AUTH=$DevPassword $Container redis-cli -h $DevHost -p $DevPort --no-auth-warning --rdb $DumpFile
Assert-Success "Failed to export RDB from DEV"

Log "Copying RDB out of container..."
docker cp "${Container}:/data/${DumpFile}" "${Folder}/${DumpFile}"
Assert-Success "Failed to copy RDB from container"

Log "Stopping container '$Container'..."
docker stop $Container
Assert-Success "Failed to stop container"

Log "Clearing old dump files from volume '$Volume'..."
docker run --rm -v "${Volume}:/data" alpine rm -f /data/dump.rdb /data/dump-dev.rdb
Assert-Success "Failed to clear old dump files"

Log "Copying new dump into container..."
docker cp "${Folder}/${DumpFile}" "${Container}:/data/dump.rdb"
Assert-Success "Failed to copy dump into container"

Log "Restarting container '$Container'..."
docker restart $Container
Assert-Success "Failed to restart container"

Log "Sync completed successfully."
