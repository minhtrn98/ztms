# Shared Postgres clone/restore helpers used by db/clone-db-dev.ps1,
# db/clone-db-stg.ps1, db/restore-db-dev.ps1, and db/restore-db-stg.ps1.
# Depends on Get-TmsSecret from TmsConfig.psm1 being imported into the
# caller's session first.

function Get-TmsDbEnvConfig {
    <#
    Reads database.<Environment>Host/User/PasswordEnvVar (e.g. "dev" ->
    devHost/devUser/devPasswordEnvVar, "stg" -> stgHost/stgUser/
    stgPasswordEnvVar) -- the remote Postgres sources clone can pull from.
    Guard-checks Host is configured before returning.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Environment
    )

    $db = $Config.database
    $hostProp = "${Environment}Host"
    $userProp = "${Environment}User"
    $pwProp   = "${Environment}PasswordEnvVar"

    $hostValue = $db.$hostProp
    if ([string]::IsNullOrWhiteSpace($hostValue)) {
        Write-Host "No database.$hostProp configured — nothing to clone from. Edit tms.config.json." -ForegroundColor Red
        exit 1
    }

    return [PSCustomObject]@{
        Host           = $hostValue
        User           = $db.$userProp
        PasswordEnvVar = $db.$pwProp
    }
}

function Get-TmsDbFileSuffix {
    <#
    Backup/schema/log/status file names stay suffix-free for "dev" (matches
    the naming scheme from before per-environment support existed, so
    existing dev backups keep working); every other environment gets
    "-<Environment>" so its files never collide with dev's in the same
    backupFolder.
    #>
    param([Parameter(Mandatory)][string]$Environment)
    if ($Environment -eq "dev") { return "" }
    return "-$Environment"
}

function Write-TmsDbWorkerScript {
    <#
    Writes db/db_clone_worker.ps1 (gitignored, regenerated on every run) --
    the script clone and restore both launch once per database, in its own
    window: drop/recreate, pre-data schema (tables, no indexes), parallel
    data-only restore, then post-data schema (indexes/constraints) last.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $workerScript = @'
param(
    [string]$DbName,
    [string]$FileSuffix,
    [string]$LocalHost,
    [string]$LocalUser,
    [string]$LocalPassword,
    [string]$BackupFolder
)

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "DB Restore: $DbName"
$backupFile = Join-Path $BackupFolder "$DbName$FileSuffix.dump"
$logFile = Join-Path $BackupFolder "$DbName$FileSuffix.log"
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High

function Write-Log {
    param($Message, $Color = "White")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage -ForegroundColor $Color
    Add-Content -Path $logFile -Value $logMessage
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DATABASE: $DbName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Log "Starting clone process for $DbName"

try {
    Write-Log "RESTORE TO LOCAL SERVER" "Yellow"
    $env:PGPASSWORD = $LocalPassword

    Write-Log "[1/4] Dropping existing database..." "Yellow"
    $dropOutput = dropdb -h $LocalHost -U $LocalUser $DbName 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Database dropped" "Green"
    } else {
        Write-Log "Database did not exist" "Gray"
    }

    Write-Log "[2/4] Creating database and applying pre-data schema (tables, no indexes)..." "Yellow"
    $createOutput = createdb -h $LocalHost -U $LocalUser $DbName 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create database: $createOutput"
    }
    psql -h $LocalHost -U $LocalUser -d $DbName -c "CREATE EXTENSION IF NOT EXISTS unaccent SCHEMA public;" 2>&1 | Out-Null

    $preSchemaFile = Join-Path $BackupFolder "$DbName$FileSuffix-schema-pre.sql"
    psql -h $LocalHost -U $LocalUser -d $DbName -f $preSchemaFile 2>&1 | Out-Null
    Write-Log "Pre-data schema applied" "Green"

    $listFile = Join-Path $BackupFolder "$DbName$FileSuffix-restore.list"
    pg_restore -l $backupFile 2>&1 | Set-Content $listFile

    Write-Log "[3/4] Restoring data (parallel, no indexes yet)..." "Yellow"
    pg_restore -h $LocalHost -U $LocalUser -d $DbName --no-owner --no-acl --data-only --disable-triggers -j 2 -L $listFile $backupFile 2>&1
    $restoreExitCode = $LASTEXITCODE

    Write-Log "[4/4] Creating indexes and constraints..." "Yellow"
    $postSchemaFile = Join-Path $BackupFolder "$DbName$FileSuffix-schema-post.sql"
    psql -h $LocalHost -U $LocalUser -d $DbName -c "SET maintenance_work_mem = '256MB';" -f $postSchemaFile 2>&1 | Out-Null
    Write-Log "Indexes created" "Green"

    if ($restoreExitCode -eq 0) {
        Write-Log "Restore completed successfully" "Green"
        $status = "SUCCESS"
    } else {
        Write-Log "Restore completed with warnings" "Yellow"
        $status = "WARNING"
    }

    $statusFile = Join-Path $BackupFolder "$DbName$FileSuffix.status"
    Set-Content -Path $statusFile -Value $status

    Write-Log "========================================" "Green"
    Write-Log "$DbName COMPLETED: $status" "Green"
    Write-Log "========================================" "Green"

} catch {
    Write-Log "ERROR: $($_.Exception.Message)" "Red"
    $statusFile = Join-Path $BackupFolder "$DbName$FileSuffix.status"
    Set-Content -Path $statusFile -Value "FAILED: $($_.Exception.Message)"
    Write-Log "========================================" "Red"
    Write-Log "$DbName FAILED" "Red"
    Write-Log "========================================" "Red"
} finally {
    $env:PGPASSWORD = $null
}

Write-Host ""
if ($status -ne "SUCCESS") {
    Start-Sleep -Seconds 30
    Write-Host "Press any key to close this window..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
'@

    Set-Content -Path $Path -Value $workerScript
}

function Invoke-TmsDbLaunchRestoreWorkers {
    <#
    Launches one db_clone_worker.ps1 process per database, each in its own
    visible window, in parallel -- shared by Invoke-TmsDbClone (after the
    backup phase) and Invoke-TmsDbRestore (which skips straight to this).
    #>
    param(
        [Parameter(Mandatory)][string[]]$AvailableDatabases,
        [Parameter(Mandatory)][string]$WorkerScriptPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$FileSuffix,
        [Parameter(Mandatory)][string]$LocalHost,
        [Parameter(Mandatory)][string]$LocalUser,
        [Parameter(Mandatory)][string]$LocalPassword,
        [Parameter(Mandatory)][string]$BackupFolder
    )

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "LAUNCHING PARALLEL PROCESSES" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    foreach ($dbName in $AvailableDatabases) {
        Remove-Item (Join-Path $BackupFolder "$dbName$FileSuffix.status") -Force -ErrorAction SilentlyContinue
    }

    $resolvedBackupFolder = (Resolve-Path $BackupFolder).Path
    $jobs = $AvailableDatabases | ForEach-Object -Parallel {
        $dbName = $_
        Write-Host "Launching process for: $dbName" -ForegroundColor Cyan

        # Built as one pre-quoted string, not a -ArgumentList array: Start-Process
        # silently drops empty-string array elements when composing the child's
        # command line, which shifts every flag after it and makes the worker
        # fail to bind its parameters (FileSuffix is empty for "dev"). Wrapping
        # each value in literal double quotes keeps an empty value as `""` on
        # the command line instead of vanishing.
        $argString = "-ExecutionPolicy Bypass -File `"$using:WorkerScriptPath`" -DbName `"$dbName`" " +
            "-FileSuffix `"$using:FileSuffix`" -LocalHost `"$using:LocalHost`" -LocalUser `"$using:LocalUser`" " +
            "-LocalPassword `"$using:LocalPassword`" -BackupFolder `"$using:resolvedBackupFolder`""

        $process = Start-Process powershell -ArgumentList $argString -WindowStyle Normal -PassThru
        $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
        return [PSCustomObject]@{
            Database  = $dbName
            ProcessId = $process.Id
        }
    } -ThrottleLimit 8

    Write-Host ""
    Write-Host "Launched $($jobs.Count) parallel processes" -ForegroundColor Green
    Write-Host "Backup files location: $BackupFolder" -ForegroundColor Cyan
    Write-Host "Each restore runs in its own window — check them for completion status." -ForegroundColor Cyan
}

function Invoke-TmsDbClone {
    <#
    Full clone flow shared by db/clone-db-dev.ps1 and db/clone-db-stg.ps1:
    terminate local connections, pg_dump each configured database from
    -Environment's remote host in parallel, split the schema into pre-data/
    post-data sections, then launch one restore worker per database.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Environment,
        [Parameter(Mandatory)][string]$ScriptsRoot
    )

    $db = $Config.database
    $availableDatabases = @($db.databases)

    if ($availableDatabases.Count -eq 0) {
        Write-Host "No databases configured. Edit tms.config.json or re-run setup\init-config.ps1." -ForegroundColor Red
        exit 1
    }

    $envConfig = Get-TmsDbEnvConfig -Config $Config -Environment $Environment
    $remoteServer = $envConfig.Host
    $remoteUser = $envConfig.User
    $remotePassword = Get-TmsSecret -EnvVarName $envConfig.PasswordEnvVar -PromptMessage "Enter $Environment server password"

    $localHost = $db.localHost
    $localUser = $db.localUser
    $localPassword = Get-TmsSecret -EnvVarName $db.localPasswordEnvVar -PromptMessage "Enter local Postgres password" -Default "postgres"

    $excludePattern = $db.excludeTableDataPattern
    $backupFolder = Join-Path $Config.reposRoot $db.backupFolder
    $fileSuffix = Get-TmsDbFileSuffix -Environment $Environment

    Write-Host "=== PostgreSQL Parallel Database Clone Tool ($Environment) ===" -ForegroundColor Cyan
    Write-Host "Source: $remoteServer | Destination: $localHost" -ForegroundColor Gray
    Write-Host "Databases to clone: $($availableDatabases.Count)" -ForegroundColor Gray
    Write-Host ""

    # Elevate this process so pg_dump parallel jobs inherit High priority
    [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High

    if (-not (Test-Path $backupFolder)) {
        Write-Host "Creating backup folder: $backupFolder" -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $backupFolder | Out-Null
    }

    $workerScriptPath = Join-Path $ScriptsRoot "db_clone_worker.ps1"
    Write-TmsDbWorkerScript -Path $workerScriptPath

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "PHASE 1: TERMINATE LOCAL DB CONNECTIONS" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    & (Join-Path $ScriptsRoot "terminate-connections.ps1")

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "PHASE 2: BACKUP FROM $($Environment.ToUpper()) SERVER" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    $backupResults = $availableDatabases | ForEach-Object -Parallel {
        $dbName = $_
        $backupFile = Join-Path $using:backupFolder "$dbName$using:fileSuffix.dump"

        Write-Host "Backing up: $dbName..." -ForegroundColor Yellow

        $env:PGPASSWORD = $using:remotePassword
        # Fail fast instead of hanging: --no-password stops pg_dump from ever
        # blocking on an interactive password prompt (which nothing can answer
        # inside a parallel runspace), and PGCONNECT_TIMEOUT bounds how long it
        # waits on an unreachable/unresponsive server. -v streams per-table
        # progress to stderr so a large, legitimately slow dump doesn't look stuck.
        $env:PGCONNECT_TIMEOUT = "15"
        $excludeArgs = @()
        if ($using:excludePattern) { $excludeArgs = @("--exclude-table-data=$($using:excludePattern)") }
        $backupOutput = pg_dump -h $using:remoteServer -U $using:remoteUser -d $dbName -F c -f $backupFile --no-password -v @excludeArgs 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  $dbName FAILED: $backupOutput" -ForegroundColor Red
            return [PSCustomObject]@{ DbName = $dbName; Success = $false }
        }

        Write-Host "  $dbName OK" -ForegroundColor Green

        # Extract schema in two sections — pre-data (tables/funcs, no indexes) and post-data (indexes/constraints).
        # Workers apply pre-data first so data loads without index-maintenance overhead, then build indexes in bulk.
        $preSchemaFile = Join-Path $using:backupFolder "$dbName$using:fileSuffix-schema-pre.sql"
        $postSchemaFile = Join-Path $using:backupFolder "$dbName$using:fileSuffix-schema-post.sql"
        pg_restore --section=pre-data --schema-only -f $preSchemaFile $backupFile 2>&1 | Out-Null
        # Fresh restores can resolve unaccent() to the wrong schema — pin it to public explicitly.
        $preContent = (Get-Content $preSchemaFile -Raw) -replace '(?<!public\.)unaccent\(', 'public.unaccent(' -replace "'unaccent'", "'public.unaccent'"
        Set-Content $preSchemaFile $preContent
        pg_restore --section=post-data --schema-only -f $postSchemaFile $backupFile 2>&1 | Out-Null

        return [PSCustomObject]@{ DbName = $dbName; Success = $true }
    } -ThrottleLimit 8

    $backupSuccess = ($backupResults | Where-Object { $_.Success }).Count
    if ($backupSuccess -lt $availableDatabases.Count) {
        Write-Host "  Critical error during backup phase. Aborting." -ForegroundColor Red
        exit 1
    }

    Write-Host "Backup phase completed: $backupSuccess/$($availableDatabases.Count) databases backed up" -ForegroundColor Green

    Invoke-TmsDbLaunchRestoreWorkers -AvailableDatabases $availableDatabases -WorkerScriptPath $workerScriptPath `
        -FileSuffix $fileSuffix -LocalHost $localHost -LocalUser $localUser -LocalPassword $localPassword -BackupFolder $backupFolder
}

function Invoke-TmsDbRestore {
    <#
    Restore flow shared by db/restore-db-dev.ps1 and db/restore-db-stg.ps1:
    reuses the last downloaded .dump/-schema-pre.sql/-schema-post.sql files
    for -Environment from database.backupFolder (see Invoke-TmsDbClone) and
    reruns just the terminate + worker-launch phases -- no remote
    connection, no remote password.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Environment,
        [Parameter(Mandatory)][string]$ScriptsRoot
    )

    $db = $Config.database
    $availableDatabases = @($db.databases)

    if ($availableDatabases.Count -eq 0) {
        Write-Host "No databases configured. Edit tms.config.json or re-run setup\init-config.ps1." -ForegroundColor Red
        exit 1
    }

    $localHost = $db.localHost
    $localUser = $db.localUser
    $localPassword = Get-TmsSecret -EnvVarName $db.localPasswordEnvVar -PromptMessage "Enter local Postgres password" -Default "postgres"

    $backupFolder = Join-Path $Config.reposRoot $db.backupFolder
    $fileSuffix = Get-TmsDbFileSuffix -Environment $Environment

    Write-Host "=== PostgreSQL Restore-From-Backup Tool ($Environment) ===" -ForegroundColor Cyan
    Write-Host "Destination: $localHost" -ForegroundColor Gray
    Write-Host "Backup folder: $backupFolder" -ForegroundColor Gray
    Write-Host ""

    # Every DB needs its dump + both schema slices already produced by clone-db-<env>.ps1.
    $missing = @()
    foreach ($dbName in $availableDatabases) {
        foreach ($suffix in @(".dump", "-schema-pre.sql", "-schema-post.sql")) {
            $path = Join-Path $backupFolder "$dbName$fileSuffix$suffix"
            if (-not (Test-Path $path)) { $missing += $path }
        }
    }
    if ($missing.Count -gt 0) {
        Write-Host "Missing backup file(s) — run db/clone-db-$Environment.ps1 first (or copy files there manually):" -ForegroundColor Red
        $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        exit 1
    }

    # Elevate this process so restore parallel jobs inherit High priority
    [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "PHASE 1: TERMINATE LOCAL DB CONNECTIONS" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    & (Join-Path $ScriptsRoot "terminate-connections.ps1")

    # Same worker script as clone -- drop/recreate, pre-data schema, parallel
    # data restore, then post-data schema (indexes/constraints) last.
    $workerScriptPath = Join-Path $ScriptsRoot "db_clone_worker.ps1"
    Write-TmsDbWorkerScript -Path $workerScriptPath

    Invoke-TmsDbLaunchRestoreWorkers -AvailableDatabases $availableDatabases -WorkerScriptPath $workerScriptPath `
        -FileSuffix $fileSuffix -LocalHost $localHost -LocalUser $localUser -LocalPassword $localPassword -BackupFolder $backupFolder
}

Export-ModuleMember -Function Get-TmsDbEnvConfig, Get-TmsDbFileSuffix, Write-TmsDbWorkerScript, `
    Invoke-TmsDbLaunchRestoreWorkers, Invoke-TmsDbClone, Invoke-TmsDbRestore
