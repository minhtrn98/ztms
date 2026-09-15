# ======================================
# PostgreSQL Parallel Database Clone Tool (dev -> local). See
# db/clone-db-stg.ps1 for the staging counterpart -- both are thin wrappers
# around Invoke-TmsDbClone in Db.psm1.
# Reads database/host settings from tms.config.json — run setup\init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Db.psm1") -Force

$config = Get-TmsConfig
Invoke-TmsDbClone -Config $config -Environment "dev" -ScriptsRoot $PSScriptRoot
