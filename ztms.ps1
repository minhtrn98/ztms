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
#
# Non-interactive: pass a target to skip the menu and run one script directly,
# e.g. `ztms frontend run` (group + entry name) or `ztms frontend/run` (path
# without .ps1). Exits with that script's exit code instead of looping.
# ======================================

Import-Module (Join-Path $PSScriptRoot "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\ProjectMenu.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\UpdateCheck.psm1") -Force

# Config may not exist yet on a first run (SETUP > init-config creates it), so
# the hide list is best-effort — no config just means nothing is hidden.
$hiddenMenuItems = @()
$config = $null
try {
    $config = Get-TmsConfig
    if ($config.hiddenMenuItems) { $hiddenMenuItems = @($config.hiddenMenuItems | ForEach-Object { $_.Replace('\', '/').ToLowerInvariant() }) }
} catch {}

# install-latest-* needs its android.deploy.<env>.apiKey configured to call
# the deploy API — hide the ones missing that rather than showing an entry
# that will just guard-clause exit.
foreach ($env in @("dev", "stg")) {
    if (-not ($config -and $config.android -and $config.android.deploy -and $config.android.deploy.$env -and $config.android.deploy.$env.apiKey)) {
        $hiddenMenuItems += "android/install-latest-$env.ps1"
    }
}

# Same for PMS: only machines with a PMS update script configured get the entry.
if (-not ($config -and $config.pms -and $config.pms.dev -and $config.pms.dev.updateScript)) {
    $hiddenMenuItems += "pms/update-dev.ps1"
}

$groups = @(
    [ordered]@{
        Name    = "COMMON"
        Entries = @(
            [ordered]@{ DisplayName = "pull-all"; Path = "common\pull-all.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "checkout-branch"; Path = "common\checkout-branch.ps1"; Desc = "" }
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
            [ordered]@{ DisplayName = "[stg] clone-restore"; Path = "redis\clone-redis-stg.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "[stg] restore"; Path = "redis\restore-redis-stg.ps1"; Desc = "" }
        )
    }
    [ordered]@{
        Name    = "DATABASE"
        Entries = @(
            [ordered]@{ DisplayName = "[dev] clone-restore"; Path = "db\clone-db-dev.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "[dev] restore"; Path = "db\restore-db-dev.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "[stg] clone-restore"; Path = "db\clone-db-stg.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "[stg] restore"; Path = "db\restore-db-stg.ps1"; Desc = "" }
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
            [ordered]@{ DisplayName = "[dev] install-latest"; Path = "android\install-latest-dev.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "[stg] install-latest"; Path = "android\install-latest-stg.ps1"; Desc = "" }
        )
    }
    [ordered]@{
        Name    = "HTTPTOOLKIT"
        Entries = @(
            [ordered]@{ DisplayName = "start"; Path = "httptoolkit\start.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "stop"; Path = "httptoolkit\stop.ps1"; Desc = "" }
            [ordered]@{ DisplayName = "restart"; Path = "httptoolkit\restart.ps1"; Desc = "" }
        )
    }
    [ordered]@{
        Name    = "PMS"
        Entries = @(
            [ordered]@{ DisplayName = "[dev] update"; Path = "pms\update-dev.ps1"; Desc = "" }
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
    # Drop groups left with no entries (e.g. PMS on a machine without it) so no empty header shows
    $groups = @($groups | Where-Object { $_.Entries.Count -gt 0 })
}

if ($args.Count -gt 0) {
    $target = (($args -join " ").Trim() -replace '\\', '/').ToLowerInvariant()
    $match = $null
    foreach ($group in $groups) {
        foreach ($entry in $group.Entries) {
            $byName = "$($group.Name) $($entry.DisplayName)".ToLowerInvariant()
            $byPath = ($entry.Path -replace '\\', '/' -replace '\.ps1$', '').ToLowerInvariant()
            if ($target -eq $byName -or $target -eq $byPath -or $target -eq "$byPath.ps1") { $match = $entry; break }
        }
        if ($match) { break }
    }

    if (-not $match) {
        Write-Host "Unknown script: $($args -join ' ')" -ForegroundColor Red
        Write-Host "Available:" -ForegroundColor Gray
        foreach ($group in $groups) {
            foreach ($entry in $group.Entries) {
                Write-Host "  $($group.Name.ToLowerInvariant()) $($entry.DisplayName)" -ForegroundColor Gray
            }
        }
        exit 1
    }

    Write-Host "-> Running: $($match.Path)`n" -ForegroundColor Green
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $match.Path)
    exit $LASTEXITCODE
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
