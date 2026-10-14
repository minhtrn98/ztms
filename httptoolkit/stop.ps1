# ======================================
# HTTP Toolkit: run `htk stop`.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\HttpToolkit.psm1") -Force

Invoke-TmsHttpToolkit -Action stop
