# ======================================
# HTTP Toolkit: run `htk restart`.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\HttpToolkit.psm1") -Force

Invoke-TmsHttpToolkit -Action restart
