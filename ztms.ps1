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

Import-Module (Join-Path $PSScriptRoot "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\ProjectMenu.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\UpdateCheck.psm1") -Force

# Config may not exist yet on a first run (SETUP > init-config creates it), so
# the hide list is best-effort — no config just means nothing is hidden.
$hiddenMenuItems = @()
try {
    $config = Get-TmsConfig
    if ($config.hiddenMenuItems) { $hiddenMenuItems = @($config.hiddenMenuItems | ForEach-Object { $_.Replace('\', '/').ToLowerInvariant() }) }
} catch {}

$groups = @(
    [ordered]@{
        Name    = "COMMON"
        Entries = @(
            [ordered]@{ DisplayName = "pull-all"; Path = "common\pull-all.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "open-vscode"; Path = "common\open-vscode.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "open-working-folder"; Path = "common\open-working-folder.ps1"; Desc = "" }
        )
    }
    [ordered]@{
        Name    = "BACKEND"
        Entries = @(
            [ordered]@{ DisplayName = "run-published"; Path = "backend\run-published.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "publish"; Path = "backend\publish.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "stop-all"; Path = "backend\stop.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "build-run"; Path = "backend\run.ps1"; Desc = "" }
        )
    }
    [ordered]@{
        Name    = "REDIS"
        Entries = @(
            [ordered]@{ DisplayName = "[dev] clone-restore"; Path = "redis\clone-redis-dev.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "[dev] restore"; Path = "redis\restore-redis-dev.ps1"; Desc = "" }
        )
    }
    [ordered]@{
        Name    = "DATABASE"
        Entries = @(
            [ordered]@{ DisplayName = "[dev] clone-restore"; Path = "db\clone-db-dev.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "[dev] restore"; Path = "db\restore-db-dev.ps1"; Desc = "" }
        )
    }
    [ordered]@{
        Name    = "FRONTEND"
        Entries = @(
            [ordered]@{ DisplayName = "run"; Path = "frontend\run.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "open-vscode"; Path = "frontend\open-vscode.ps1"; Desc = "" }
        )
    }
    [ordered]@{
        Name    = "ANDROID"
        Entries = @(
            [ordered]@{ DisplayName = "start"; Path = "android\start.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "start-default"; Path = "android\start-default.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "stop"; Path = "android\stop.ps1"; Desc = "" }
        )
    }
    [ordered]@{
        Name    = "SETUP"
        Entries = @(
            [ordered]@{ DisplayName = "init-config"; Path = "setup\init-config.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "set-env"; Path = "setup\set-env.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "update"; Path = "setup\update.ps1"; Desc = "" }
        )
    }
)

if ($hiddenMenuItems.Count -gt 0) {
    foreach ($group in $groups) {
        $group.Entries = @($group.Entries | Where-Object { $hiddenMenuItems -notcontains $_.Path.Replace('\', '/').ToLowerInvariant() })
    }
}

while ($true) {
    Clear-Host
    Write-Host "=== TMS scripts ===" -ForegroundColor Magenta
    Write-Host "$PSScriptRoot`n" -ForegroundColor Gray

    # $latestVersion = Test-TmsUpdateAvailable -RepoRoot $PSScriptRoot
    # if ($latestVersion) {
    #     Write-Host "New version available: v$latestVersion (you have v$(Get-TmsLocalVersion -RepoRoot $PSScriptRoot)) - run 'update' from SETUP to upgrade.`n" -ForegroundColor Yellow
    # }

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
