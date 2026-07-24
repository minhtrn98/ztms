# ======================================
# Restore local Postgres databases from already-downloaded dumps.
# Does NOT touch the dev server — just re-applies the .dump/-schema-pre.sql/
# -schema-post.sql files from database.backupFolder (see clone-db-dev.ps1)
# onto the local server.
# Reads database/host settings from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig
$db = $config.database
$availableDatabases = @($db.databases)

if ($availableDatabases.Count -eq 0) {
    Write-Host "No databases configured. Edit tms.config.json or re-run 900_init-config.ps1." -ForegroundColor Red
    exit 1
}

$localHost = $db.localHost
$localUser = $db.localUser
$localPassword = Get-TmsSecret -EnvVarName $db.localPasswordEnvVar -PromptMessage "Enter local Postgres password" -Default "postgres"

$backupFolder = Join-Path $config.reposRoot $db.backupFolder

Write-Host "=== PostgreSQL Restore-From-Backup Tool ===" -ForegroundColor Cyan
Write-Host "Destination: $localHost" -ForegroundColor Gray
Write-Host "Backup folder: $backupFolder" -ForegroundColor Gray
Write-Host ""

# Every DB needs its dump + both schema slices already produced by clone-db-dev.ps1.
$missing = @()
foreach ($dbName in $availableDatabases) {
    foreach ($suffix in @(".dump", "-schema-pre.sql", "-schema-post.sql")) {
        $path = Join-Path $backupFolder "$dbName$suffix"
        if (-not (Test-Path $path)) { $missing += $path }
    }
}
if ($missing.Count -gt 0) {
    Write-Host "Missing backup file(s) — run db/clone-db-dev.ps1 first (or copy files there manually):" -ForegroundColor Red
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

& (Join-Path $PSScriptRoot "terminate-connections.ps1")

# Same worker script as clone-db-dev.ps1 — drop/recreate, pre-data schema,
# parallel data restore, then post-data schema (indexes/constraints) last.
$workerScriptPath = Join-Path $PSScriptRoot "db_clone_worker.ps1"
$workerScript = @'
param(
    [string]$DbName,
    [string]$LocalHost,
    [string]$LocalUser,
    [string]$LocalPassword,
    [string]$BackupFolder
)

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "DB Restore: $DbName"
$backupFile = Join-Path $BackupFolder "$DbName.dump"
$logFile = Join-Path $BackupFolder "$DbName.log"
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
Write-Log "Starting restore process for $DbName"

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

    $preSchemaFile = Join-Path $BackupFolder "$DbName-schema-pre.sql"
    psql -h $LocalHost -U $LocalUser -d $DbName -f $preSchemaFile 2>&1 | Out-Null
    Write-Log "Pre-data schema applied" "Green"

    $listFile = Join-Path $BackupFolder "$DbName-restore.list"
    pg_restore -l $backupFile 2>&1 | Set-Content $listFile

    Write-Log "[3/4] Restoring data (parallel, no indexes yet)..." "Yellow"
    pg_restore -h $LocalHost -U $LocalUser -d $DbName --no-owner --no-acl --data-only --disable-triggers -j 2 -L $listFile $backupFile 2>&1
    $restoreExitCode = $LASTEXITCODE

    Write-Log "[4/4] Creating indexes and constraints..." "Yellow"
    $postSchemaFile = Join-Path $BackupFolder "$DbName-schema-post.sql"
    psql -h $LocalHost -U $LocalUser -d $DbName -c "SET maintenance_work_mem = '256MB';" -f $postSchemaFile 2>&1 | Out-Null
    Write-Log "Indexes created" "Green"

    if ($restoreExitCode -eq 0) {
        Write-Log "Restore completed successfully" "Green"
        $status = "SUCCESS"
    } else {
        Write-Log "Restore completed with warnings" "Yellow"
        $status = "WARNING"
    }

    $statusFile = Join-Path $BackupFolder "$DbName.status"
    Set-Content -Path $statusFile -Value $status

    Write-Log "========================================" "Green"
    Write-Log "$DbName COMPLETED: $status" "Green"
    Write-Log "========================================" "Green"

} catch {
    Write-Log "ERROR: $($_.Exception.Message)" "Red"
    $statusFile = Join-Path $BackupFolder "$DbName.status"
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

Set-Content -Path $workerScriptPath -Value $workerScript

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "LAUNCHING PARALLEL PROCESSES" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Get-ChildItem -Path $backupFolder -Filter "*.status" | Remove-Item -Force

$resolvedBackupFolder = (Resolve-Path $backupFolder).Path
$jobs = $availableDatabases | ForEach-Object -Parallel {
    $dbName = $_
    Write-Host "Launching process for: $dbName" -ForegroundColor Cyan

    $arguments = @(
        "-ExecutionPolicy", "Bypass",
        "-File", $using:workerScriptPath,
        "-DbName", $dbName,
        "-LocalHost", $using:localHost,
        "-LocalUser", $using:localUser,
        "-LocalPassword", $using:localPassword,
        "-BackupFolder", $using:resolvedBackupFolder
    )

    $process = Start-Process powershell -ArgumentList $arguments -WindowStyle Normal -PassThru
    $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
    return [PSCustomObject]@{
        Database  = $dbName
        ProcessId = $process.Id
    }
} -ThrottleLimit 8

Write-Host ""
Write-Host "Launched $($jobs.Count) parallel processes" -ForegroundColor Green
Write-Host "Backup files location: $backupFolder" -ForegroundColor Cyan
Write-Host "Each restore runs in its own window — check them for completion status." -ForegroundColor Cyan
