# ======================================
# TMS scripts menu — lists every script in this folder and runs the one you pick.
# Meant to be launched via the global `ztms` command (see install-ztms.ps1),
# but also works directly: .\ztms.ps1
#
# Each choice runs as its own child pwsh process, so a script's `exit` only
# ends that script — you're always returned to this menu afterward.
#
# Grouped, always-expanded menu: group names (BE, FE, ...) render as
# non-selectable headers; Up/Down skip over them so only scripts are
# highlighted. Escape exits.
# ======================================

Import-Module (Join-Path $PSScriptRoot "modules\ProjectMenu.psm1") -Force

$groups = @(
    [ordered]@{
        Name    = "Backend"
        Entries = @(
            [ordered]@{ DisplayName = "run-published"; Path = "002_run-published.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "publish"; Path = "090_publish.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "stop-all"; Path = "800_stop-services.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "pull-all"; Path = "010_pull-all.ps1"; Desc = "" }
            # [ordered]@{ DisplayName = "build-run"; Path = "001_run-services.ps1"; Desc = "" }
        )
    }
    [ordered]@{
        Name    = "Frontend"
        Entries = @(
            [ordered]@{ DisplayName = "run"; Path = "003_run-frontend.ps1"; Desc = "" }
        )
    }
    [ordered]@{
        Name    = "DB"
        Entries = @(
            [ordered]@{ DisplayName = "[dev] clone-restore"; Path = "db\clone-db-dev.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "[dev] restore"; Path = "db\restore-db-dev.ps1"; Desc = "" }
        )
    }
    [ordered]@{
        Name    = "Redis"
        Entries = @(
            [ordered]@{ DisplayName = "[dev] clone-restore"; Path = "redis\clone-redis-dev.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "[dev] restore"; Path = "redis\restore-redis-dev.ps1"; Desc = "" }
        )
    }
    [ordered]@{
        Name    = "Setup"
        Entries = @(
            [ordered]@{ DisplayName = "init-config"; Path = "900_init-config.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "set-env"; Path = "901_set-env.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "update"; Path = "902_update.ps1"; Desc = "" }
        )
    }
)

while ($true) {
    Clear-Host
    Write-Host "=== TMS scripts ===" -ForegroundColor Magenta
    Write-Host "$PSScriptRoot`n" -ForegroundColor Gray

    $selected = Show-GroupedMenu -Groups $groups -Prompt "Choose a script to run"

    if (-not $selected) {
        Write-Host "`nBye." -ForegroundColor DarkYellow
        break
    }

    $scriptPath = Join-Path $PSScriptRoot $selected.Path
    Write-Host "`n-> Running: $($selected.Path)`n" -ForegroundColor Green

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath

    Write-Host "`nPress any key to return to the menu..." -ForegroundColor Gray
    [Console]::CursorVisible = $false
    $null = [Console]::ReadKey($true)
    [Console]::CursorVisible = $true
}
