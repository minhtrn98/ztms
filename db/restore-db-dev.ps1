# ======================================
# Restore local Postgres databases from already-downloaded dev dumps.
# Does NOT touch the dev server — just re-applies the .dump/-schema-pre.sql/
# -schema-post.sql files from database.backupFolder (see clone-db-dev.ps1)
# onto the local server. See db/restore-db-stg.ps1 for the staging
# counterpart -- both are thin wrappers around Invoke-TmsDbRestore in
# Db.psm1.
# Reads database/host settings from tms.config.json — run setup\init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Db.psm1") -Force

$config = Get-TmsConfig
Invoke-TmsDbRestore -Config $config -Environment "dev" -ScriptsRoot $PSScriptRoot
