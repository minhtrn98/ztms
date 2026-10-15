# ======================================
# Set up the custom HTTP Toolkit fork on this machine: clone
# httptoolkit.gitUrl into httptoolkit.repoPath (or use the existing clone),
# check out httptoolkit.branch, add <repo>\scripts to the user PATH so the
# `htk` command works in any terminal, then `htk build` (npm install on first
# run, build, deploy, start). Safe to re-run — also how you update it.
# See Install-TmsHttpToolkit in HttpToolkit.psm1.
# Reads httptoolkit.* from tms.config.json — see tms.config.example.json.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\HttpToolkit.psm1") -Force

$htk = Get-TmsHttpToolkitConfig -Config (Get-TmsConfig)
Install-TmsHttpToolkit -Htk $htk
