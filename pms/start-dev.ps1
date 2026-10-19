# ======================================
# Open the latest installed PMS DEV build. The app updates itself into a new
# version folder each release, so this resolves the newest one at run time
# (see Start-TmsPmsLatest in Pms.psm1), copies the login password from
# pms.dev.passwordEnvVar to the clipboard and types it into the login form
# once that appears. The desktop shortcut created by
# pms\install-dev.ps1 points here.
# Reads pms.dev.* from tms.config.json — see tms.config.example.json.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Pms.psm1") -Force

$config = Get-TmsConfig
$pms = Get-TmsPmsDevConfig -Config $config
Start-TmsPmsLatest -Pms $pms
