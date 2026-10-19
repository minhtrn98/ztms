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
#
# --spotlight (what the global hotkey launches): search box only — no
# grouped list, no header — in a short window that grows while a script
# runs and shrinks back afterwards.
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

# HTTP Toolkit (custom fork) only shows once httptoolkit.repoPath is configured.
if (-not ($config -and $config.httptoolkit -and $config.httptoolkit.repoPath)) {
    $hiddenMenuItems += @("httptoolkit/start.ps1", "httptoolkit/stop.ps1", "httptoolkit/restart.ps1", "httptoolkit/build.ps1", "httptoolkit/install.ps1")
}

# Same for PMS: only machines with pms.dev.root configured get the PMS entries.
if (-not ($config -and $config.pms -and $config.pms.dev -and $config.pms.dev.root)) {
    $hiddenMenuItems += @("pms/start-dev.ps1", "pms/update-dev.ps1", "pms/install-dev.ps1")
}

$groups = @(
    [ordered]@{
        Name    = "COMMON"
        Entries = @(
            [ordered]@{ DisplayName = "pull-all"; Path = "common\pull-all.ps1"; Desc = "git pull every repo under reposRoot (in parallel)" }
            [ordered]@{ DisplayName = "checkout-branch"; Path = "common\checkout-branch.ps1"; Desc = "Switch every repo to the same git branch" }
            [ordered]@{ DisplayName = "open-vscode"; Path = "common\open-vscode.ps1"; Desc = "Open selected service repos in VS Code" }
        )
    }
    [ordered]@{
        Name    = "BACKEND"
        Entries = @(
            [ordered]@{ DisplayName = "run-published"; Path = "backend\run-published.ps1"; Desc = "Run services from their published build (fast start)" }
            [ordered]@{ DisplayName = "publish"; Path = "backend\publish.ps1"; Desc = "Build selected services with dotnet publish into deployRoot" }
            [ordered]@{ DisplayName = "stop-all"; Path = "backend\stop.ps1"; Desc = "Stop all running backend services" }
            [ordered]@{ DisplayName = "build-run"; Path = "backend\run.ps1"; Desc = "Build + run selected services with dotnet run (dev mode)" }
        )
    }
    [ordered]@{
        Name    = "REDIS"
        Entries = @(
            [ordered]@{ DisplayName = "[dev] clone-restore"; Path = "redis\clone-redis-dev.ps1"; Desc = "Copy the dev Redis cache down into local Redis" }
            [ordered]@{ DisplayName = "[dev] restore"; Path = "redis\restore-redis-dev.ps1"; Desc = "Re-apply the last downloaded dev Redis dump (offline)" }
            [ordered]@{ DisplayName = "[stg] clone-restore"; Path = "redis\clone-redis-stg.ps1"; Desc = "Copy the staging Redis cache down into local Redis" }
            [ordered]@{ DisplayName = "[stg] restore"; Path = "redis\restore-redis-stg.ps1"; Desc = "Re-apply the last downloaded staging Redis dump (offline)" }
        )
    }
    [ordered]@{
        Name    = "DATABASE"
        Entries = @(
            [ordered]@{ DisplayName = "[dev] clone-restore"; Path = "db\clone-db-dev.ps1"; Desc = "Dump the dev Postgres databases and restore them locally" }
            [ordered]@{ DisplayName = "[dev] restore"; Path = "db\restore-db-dev.ps1"; Desc = "Re-apply the last downloaded dev database dumps (offline)" }
            [ordered]@{ DisplayName = "[stg] clone-restore"; Path = "db\clone-db-stg.ps1"; Desc = "Dump the staging Postgres databases and restore them locally" }
            [ordered]@{ DisplayName = "[stg] restore"; Path = "db\restore-db-stg.ps1"; Desc = "Re-apply the last downloaded staging database dumps (offline)" }
        )
    }
    [ordered]@{
        Name    = "FRONTEND"
        Entries = @(
            [ordered]@{ DisplayName = "run"; Path = "frontend\run.ps1"; Desc = "Build and run the frontend web app in this terminal" }
            [ordered]@{ DisplayName = "open-vscode"; Path = "frontend\open-vscode.ps1"; Desc = "Open the frontend repo in VS Code" }
        )
    }
    [ordered]@{
        Name    = "ANDROID"
        Entries = @(
            [ordered]@{ DisplayName = "start"; Path = "android\start.ps1"; Desc = "Start an Android emulator (resumes its saved snapshot)" }
            [ordered]@{ DisplayName = "start-default"; Path = "android\start-default.ps1"; Desc = "Cold-boot an Android emulator (ignores the saved snapshot)" }
            [ordered]@{ DisplayName = "stop"; Path = "android\stop.ps1"; Desc = "Stop a running Android emulator" }
            [ordered]@{ DisplayName = "set-location"; Path = "android\set-location.ps1"; Desc = "Set the emulator GPS location from lat,lng or a post office" }
            [ordered]@{ DisplayName = "[dev] install-latest"; Path = "android\install-latest-dev.ps1"; Desc = "Install the latest dev APK build on a running emulator" }
            [ordered]@{ DisplayName = "[stg] install-latest"; Path = "android\install-latest-stg.ps1"; Desc = "Install the latest staging APK build on a running emulator" }
        )
    }
    [ordered]@{
        Name    = "HTTPTOOLKIT"
        Entries = @(
            [ordered]@{ DisplayName = "start"; Path = "httptoolkit\start.ps1"; Desc = "Start the custom HTTP Toolkit (proxy to intercept requests)" }
            [ordered]@{ DisplayName = "stop"; Path = "httptoolkit\stop.ps1"; Desc = "Stop HTTP Toolkit" }
            [ordered]@{ DisplayName = "restart"; Path = "httptoolkit\restart.ps1"; Desc = "Restart HTTP Toolkit" }
            [ordered]@{ DisplayName = "build"; Path = "httptoolkit\build.ps1"; Desc = "Rebuild HTTP Toolkit from its source, redeploy and restart" }
            [ordered]@{ DisplayName = "install"; Path = "httptoolkit\install.ps1"; Desc = "Clone/update the HTTP Toolkit fork and put htk on PATH" }
        )
    }
    [ordered]@{
        Name    = "PMS"
        Entries = @(
            [ordered]@{ DisplayName = "[dev] start"; Path = "pms\start-dev.ps1"; Desc = "Open the newest PMS dev build (copies the password)" }
            [ordered]@{ DisplayName = "[dev] update"; Path = "pms\update-dev.ps1"; Desc = "Download the latest PMS dev build now" }
            [ordered]@{ DisplayName = "[dev] install"; Path = "pms\install-dev.ps1"; Desc = "Set up PMS dev: desktop shortcut + auto-update task" }
        )
    }
    [ordered]@{
        Name    = "SETUP"
        Entries = @(
            [ordered]@{ DisplayName = "doctor"; Path = "setup\doctor.ps1"; Desc = "Check what this machine's setup is missing" }
            [ordered]@{ DisplayName = "init-config"; Path = "setup\init-config.ps1"; Desc = "Create or edit tms.config.json step by step" }
            [ordered]@{ DisplayName = "set-env"; Path = "setup\set-env.ps1"; Desc = "Load env vars/secrets from tms.env.local (optionally persist)" }
            [ordered]@{ DisplayName = "export"; Path = "setup\export.ps1"; Desc = "Back up config + secrets into one encrypted file" }
            [ordered]@{ DisplayName = "import"; Path = "setup\import.ps1"; Desc = "Restore config + secrets from an export (new machine)" }
            [ordered]@{ DisplayName = "update"; Path = "setup\update.ps1"; Desc = "Update ztms itself (git pull these scripts)" }
            [ordered]@{ DisplayName = "install-hotkey"; Path = "setup\install-hotkey.ps1"; Desc = "Global hotkey (Ctrl+Space) that opens ztms from anywhere" }
            [ordered]@{ DisplayName = "uninstall-hotkey"; Path = "setup\uninstall-hotkey.ps1"; Desc = "Remove the global ztms hotkey" }
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

# --spotlight: opened by the global hotkey (see Hotkey.psm1). Search box only,
# no grouped list, in a short window that grows while a script runs.
$spotlight = @($args) -contains '--spotlight'
$targetArgs = @($args | Where-Object { $_ -ne '--spotlight' })

# Hotkey window only: one "VS CODE" entry per configured service (whose repo
# folder exists), so typing "order code" / "vs code order" opens that repo
# straight away. Args are passed to the script; Quick = run it and close the
# window, Spotlight-style, instead of the usual full-size run + "press any
# key". Not in the plain menu — it would add a row per service.
if ($spotlight -and $config -and $config.services -and $config.reposRoot -and $hiddenMenuItems -notcontains "common/open-vscode.ps1") {
    $vscodeEntries = @(foreach ($svc in $config.services) {
        if ($svc.name -and (Test-Path -LiteralPath (Join-Path $config.reposRoot $svc.name))) {
            [ordered]@{ DisplayName = $svc.name; Path = "common\open-vscode.ps1"; Args = @("-Service", $svc.name); Quick = $true; Desc = "Open the $($svc.name) repo in VS Code" }
        }
    })
    if ($vscodeEntries.Count -gt 0) { $groups += [ordered]@{ Name = "VS CODE"; Entries = $vscodeEntries } }
}

if ($targetArgs.Count -gt 0) {
    $target = (($targetArgs -join " ").Trim() -replace '\\', '/').ToLowerInvariant()
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
        Write-Host "Unknown script: $($targetArgs -join ' ')" -ForegroundColor Red
        # Not an exact name — treat it as a search (same as typing in the
        # menu). ProjectMenu already loaded MenuSearch; importing it without
        # -Force just exposes its functions here instead of rebuilding it.
        Import-Module (Join-Path $PSScriptRoot "modules\MenuSearch.psm1")
        $suggestions = @(Find-MenuEntries -Groups $groups -Query ($targetArgs -join ' ') | Select-Object -First 5)
        if ($suggestions.Count -gt 0) {
            Write-Host "Did you mean:" -ForegroundColor Gray
            foreach ($s in $suggestions) {
                Write-Host ("  {0,-34} {1}" -f "$($s.Group.ToLowerInvariant()) $($s.Entry.DisplayName)", $s.Entry.Desc) -ForegroundColor Gray
            }
        } else {
            Write-Host "Available:" -ForegroundColor Gray
            foreach ($group in $groups) {
                foreach ($entry in $group.Entries) {
                    Write-Host "  $($group.Name.ToLowerInvariant()) $($entry.DisplayName)" -ForegroundColor Gray
                }
            }
        }
        exit 1
    }

    Write-Host "-> Running: $($match.Path)`n" -ForegroundColor Green
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $match.Path)
    exit $LASTEXITCODE
}

$spotlightHotkey = $null
while ($true) {
    Clear-Host
    if (-not $spotlight) {
        Write-Host "=== TMS scripts ===" -ForegroundColor Magenta
        Write-Host "$PSScriptRoot`n" -ForegroundColor Gray
    }

    # $latestVersion = Test-TmsUpdateAvailable -RepoRoot $PSScriptRoot
    # if ($latestVersion) {
    #     Write-Host "New version available: v$latestVersion (you have v$(Get-TmsLocalVersion -RepoRoot $PSScriptRoot)) - run 'update' from SETUP to upgrade.`n" -ForegroundColor Yellow
    # }

    $selected = Show-GroupedMenu -Groups $groups -Prompt "Choose a script to run" -SearchOnly:$spotlight

    if (-not $selected) {
        Write-Host "`nBye." -ForegroundColor DarkYellow
        break
    }

    # Quick entries (open something) stay in the small window; anything else
    # gets the window grown for its output
    $expanded = $false
    if ($spotlight -and -not $selected.Quick) {
        # Imported only now: its Add-Type compile would delay the search box
        if (-not $spotlightHotkey) {
            Import-Module (Join-Path $PSScriptRoot "modules\Hotkey.psm1") -Force
            try { $spotlightHotkey = Get-TmsHotkey -Config $config } catch {}  # bad hotkey.keys: just don't resize
        }
        if ($spotlightHotkey) { Set-TmsSpotlightWindowSize -Hotkey $spotlightHotkey -Full; $expanded = $true }
    }

    $scriptPath = Join-Path $PSScriptRoot $selected.Path
    $entryArgs = @(if ($selected.Args) { $selected.Args })
    Write-Host "`n-> Running: $($selected.Path) $($entryArgs -join ' ')`n" -ForegroundColor Green

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath @entryArgs

    # Done and it worked: close the window like Spotlight does. (On failure,
    # fall through so the error stays readable.)
    if ($spotlight -and $selected.Quick -and $LASTEXITCODE -eq 0) { break }

    Write-Host "`nPress any key to return to the menu..." -ForegroundColor Gray
    [Console]::CursorVisible = $false
    $null = [Console]::ReadKey($true)
    [Console]::CursorVisible = $true

    if ($expanded) { Set-TmsSpotlightWindowSize -Hotkey $spotlightHotkey }
}
