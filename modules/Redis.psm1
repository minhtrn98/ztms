# Shared Redis clone/restore helpers used by redis/clone-redis-*.ps1 and
# redis/restore-redis-*.ps1. Depends on Get-TmsSecret from TmsConfig.psm1
# being imported into the caller's session first.

function Get-TmsRedisEnvConfig {
    <#
    Reads redis.<Environment>Host/Port/PasswordEnvVar (e.g. "dev" ->
    devHost/devPort/devPasswordEnvVar, "stg" -> stgHost/stgPort/
    stgPasswordEnvVar) -- the remote Redis sources clone can pull from.
    Guard-checks Host is configured before returning.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Environment
    )

    $redis = $Config.redis
    $hostProp = "${Environment}Host"
    $portProp = "${Environment}Port"
    $pwProp   = "${Environment}PasswordEnvVar"

    $hostValue = $redis.$hostProp
    if ([string]::IsNullOrWhiteSpace($hostValue)) {
        Write-Host "No redis.$hostProp configured — nothing to sync from. Edit tms.config.json." -ForegroundColor Red
        exit 1
    }

    return [PSCustomObject]@{
        Host           = $hostValue
        Port           = $redis.$portProp
        PasswordEnvVar = $redis.$pwProp
    }
}

function Invoke-TmsRedisClone {
    <#
    Full clone flow shared by redis/clone-redis-dev.ps1 and
    redis/clone-redis-stg.ps1: export an RDB from the remote Redis via
    `docker exec ... redis-cli --rdb`, copy it out of the local container,
    stop the container, clear old dump files from its volume, copy the new
    dump in as dump.rdb, and restart -- so the local container comes back up
    already loaded with the remote's data.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Environment
    )

    $redis = $Config.redis
    $envConfig = Get-TmsRedisEnvConfig -Config $Config -Environment $Environment

    $RemoteHost     = $envConfig.Host
    $RemotePort     = $envConfig.Port
    $Container      = $redis.container
    $Volume         = $redis.volume
    $DumpFile       = "dump-$Environment.rdb"
    $Folder         = Join-Path $Config.reposRoot $redis.backupFolder
    $RemotePassword = Get-TmsSecret -EnvVarName $envConfig.PasswordEnvVar -PromptMessage "Enter $Environment Redis password"

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

    $envLabel = $Environment.ToUpper()
    Log "Starting Redis sync from $envLabel ($RemoteHost`:$RemotePort) -> Local container '$Container'..."

    Log "Exporting RDB from ${envLabel}..."
    docker exec -e REDISCLI_AUTH=$RemotePassword $Container redis-cli -h $RemoteHost -p $RemotePort --no-auth-warning --rdb $DumpFile
    Assert-Success "Failed to export RDB from $envLabel"

    Log "Copying RDB out of container..."
    docker cp "${Container}:/data/${DumpFile}" "${Folder}/${DumpFile}"
    Assert-Success "Failed to copy RDB from container"

    Log "Stopping container '$Container'..."
    docker stop $Container
    Assert-Success "Failed to stop container"

    Log "Clearing old dump files from volume '$Volume'..."
    docker run --rm -v "${Volume}:/data" alpine rm -f /data/dump.rdb "/data/${DumpFile}"
    Assert-Success "Failed to clear old dump files"

    Log "Copying new dump into container..."
    docker cp "${Folder}/${DumpFile}" "${Container}:/data/dump.rdb"
    Assert-Success "Failed to copy dump into container"

    Log "Restarting container '$Container'..."
    docker restart $Container
    Assert-Success "Failed to restart container"

    Log "Sync completed successfully."
}

function Invoke-TmsRedisRestore {
    <#
    Restore flow shared by redis/restore-redis-dev.ps1 and
    redis/restore-redis-stg.ps1: replays an already-downloaded
    dump-<Environment>.rdb from redis.backupFolder (see Invoke-TmsRedisClone)
    into the local container -- no remote connection, no password needed.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Environment
    )

    $redis     = $Config.redis
    $Container = $redis.container
    $Volume    = $redis.volume
    $DumpFile  = "dump-$Environment.rdb"
    $Folder    = Join-Path $Config.reposRoot $redis.backupFolder
    $dumpPath  = Join-Path $Folder $DumpFile

    if (-not (Test-Path $dumpPath)) {
        Write-Host "No backup found at $dumpPath — run redis/clone-redis-$Environment.ps1 first (or copy a dump there manually)." -ForegroundColor Red
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
    docker run --rm -v "${Volume}:/data" alpine rm -f /data/dump.rdb "/data/${DumpFile}"
    Assert-Success "Failed to clear old dump files"

    Log "Copying dump into container..."
    docker cp "$dumpPath" "${Container}:/data/dump.rdb"
    Assert-Success "Failed to copy dump into container"

    Log "Restarting container '$Container'..."
    docker restart $Container
    Assert-Success "Failed to restart container"

    Log "Restore completed successfully."
}

Export-ModuleMember -Function Get-TmsRedisEnvConfig, Invoke-TmsRedisClone, Invoke-TmsRedisRestore
