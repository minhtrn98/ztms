# ======================================
# TMS scripts menu — lists every script in this folder and runs the one you pick.
# Meant to be launched via the global `ztms` command (see install-ztms.ps1),
# but also works directly: .\ztms.ps1
#
# Each choice runs as its own child pwsh process, so a script's `exit` only
# ends that script — you're always returned to this menu afterward.
# ======================================

Import-Module (Join-Path $PSScriptRoot "modules\ProjectMenu.psm1") -Force

$entries = @(
    # [ordered]@{ Path = "001_run-services.ps1"; Desc = "" }
    [ordered]@{ DisplayName = "run-publish-be"; Path = "002_run-published.ps1"; Desc = "" }
    [ordered]@{ DisplayName = "run-frontend"; Path = "003_run-frontend.ps1"; Desc = "" }
    [ordered]@{ DisplayName = "pull-all"; Path = "010_pull-all.ps1"; Desc = "" }
    [ordered]@{ DisplayName = "publish-be"; Path = "090_publish.ps1"; Desc = "" }
    [ordered]@{ DisplayName = "stop-be"; Path = "800_stop-services.ps1"; Desc = "" }
    [ordered]@{ DisplayName = "clone-redis-dev"; Path = "redis\clone-redis-dev.ps1"; Desc = "" }
    [ordered]@{ DisplayName = "restore-redis-dev"; Path = "redis\restore-redis-dev.ps1"; Desc = "" }
    [ordered]@{ DisplayName = "clone-db-dev"; Path = "db\clone-db-dev.ps1"; Desc = "" }
    [ordered]@{ DisplayName = "restore-db-dev"; Path = "db\restore-db-dev.ps1"; Desc = "" }
    [ordered]@{ DisplayName = "init-config"; Path = "900_init-config.ps1"; Desc = "" }
    [ordered]@{ DisplayName = "set-env"; Path = "901_set-env.ps1"; Desc = "" }
    [ordered]@{ DisplayName = "update"; Path = "902_update.ps1"; Desc = "" }
)

while ($true) {
    Clear-Host
    Write-Host "=== TMS scripts ===" -ForegroundColor Magenta
    Write-Host "$PSScriptRoot`n" -ForegroundColor Gray

    $labels = $entries | ForEach-Object { "{0,-32} {1}" -f $_.DisplayName, $_.Desc }
    $choice = Show-Menu -Labels $labels -Prompt "Choose a script to run"

    if ($choice -lt 0) {
        Write-Host "`nBye." -ForegroundColor DarkYellow
        break
    }

    $scriptPath = Join-Path $PSScriptRoot $entries[$choice].Path
    Write-Host "`n-> Running: $($entries[$choice].Path)`n" -ForegroundColor Green

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath

    Write-Host "`nPress any key to return to the menu..." -ForegroundColor Gray
    [Console]::CursorVisible = $false
    $null = [Console]::ReadKey($true)
    [Console]::CursorVisible = $true
}
