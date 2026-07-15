# ======================================
# Terminate all active local connections to the configured databases
# Reads database list from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig
$db = $config.database
$databases = @($db.databases)

if ($databases.Count -eq 0) {
    Write-Host "No databases configured. Edit tms.config.json or re-run 900_init-config.ps1." -ForegroundColor Red
    exit 1
}

$localPassword = Get-TmsSecret -EnvVarName $db.localPasswordEnvVar -PromptMessage "Enter local Postgres password" -Default "postgres"

$sql = ($databases | ForEach-Object { "select pg_terminate_backend(pid) from pg_stat_activity where datname='$_';" }) -join "`n"

$env:PGPASSWORD = $localPassword
$sql | psql -U $db.localUser -d postgres -h $db.localHost -a
$env:PGPASSWORD = $null
