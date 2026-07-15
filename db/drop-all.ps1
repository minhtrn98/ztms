# ======================================
# DROP all configured local databases — DESTRUCTIVE, asks for confirmation.
# Reads database list from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\ProjectMenu.psm1") -Force

$config = Get-TmsConfig
$db = $config.database
$databases = @($db.databases)

if ($databases.Count -eq 0) {
    Write-Host "No databases configured. Edit tms.config.json or re-run 900_init-config.ps1." -ForegroundColor Red
    exit 1
}

Write-Host "This will PERMANENTLY DROP the following local databases on $($db.localHost):" -ForegroundColor Red
$databases | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
Write-Host

$confirmed = Confirm-Prompt -Message "Type-confirm: drop ALL of the above databases?" -DefaultYes $false
if (-not $confirmed) {
    Write-Host "Cancelled." -ForegroundColor DarkYellow
    exit 0
}

$localPassword = Get-TmsSecret -EnvVarName $db.localPasswordEnvVar -PromptMessage "Enter local Postgres password" -Default "postgres"

$sql = ($databases | ForEach-Object { "drop database if exists `"$_`";" }) -join "`n"

$env:PGPASSWORD = $localPassword
$sql | psql -U $db.localUser -d postgres -h $db.localHost -a
$env:PGPASSWORD = $null
