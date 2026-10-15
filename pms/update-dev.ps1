# ======================================
# Download + unzip the latest PMS DEV build if it isn't installed yet (see
# Invoke-TmsPmsUpdate in Pms.psm1). Run from the menu to update on demand;
# the "PMS Dev Auto Update" scheduled task created by pms\install-dev.ps1
# also runs this every minute. Toasts on install/error.
# Reads pms.dev.* from tms.config.json — see tms.config.example.json.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Pms.psm1") -Force

$config = Get-TmsConfig
$pms = Get-TmsPmsDevConfig -Config $config
if (-not (Invoke-TmsPmsUpdate -Pms $pms)) { exit 1 }
