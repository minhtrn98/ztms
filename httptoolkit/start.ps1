# ======================================
# HTTP Toolkit: run `htk start`.
# Reads httptoolkit.* from tms.config.json — see tms.config.example.json.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\HttpToolkit.psm1") -Force

$htk = Get-TmsHttpToolkitConfig -Config (Get-TmsConfig)
Invoke-TmsHttpToolkit -Htk $htk -Action start
