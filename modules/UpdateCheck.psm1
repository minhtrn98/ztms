# Lightweight "new version available" check for the ztms menu.
#
# Versioning is a plain VERSION file at the repo root (bumped by hand on
# releases) rather than git tags, so comparing it doesn't need a full clone
# history. The check runs a bounded-time `git fetch` in the background (so a
# slow/offline network can't hang menu startup) and caches the result next
# to .pull-changed.json for a few hours so ztms.ps1 isn't hitting the
# network on every loop iteration / relaunch.

function Get-TmsLocalVersion {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $versionPath = Join-Path $RepoRoot "VERSION"
    if (-not (Test-Path $versionPath)) { return $null }
    (Get-Content $versionPath -Raw).Trim()
}

function Test-TmsUpdateAvailable {
    <#
    Returns the remote VERSION string if it differs from the local one, or
    $null if up to date / offline / not a git checkout. Never throws.
    #>
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [int]$CacheHours = 6,
        [int]$FetchTimeoutSeconds = 4
    )

    $cachePath = Join-Path $RepoRoot ".update-check-cache.json"
    if (Test-Path $cachePath) {
        try {
            $cache = Get-Content $cachePath -Raw | ConvertFrom-Json
            if (((Get-Date) - [datetime]$cache.CheckedAt).TotalHours -lt $CacheHours) {
                if ($cache.UpdateAvailable) { return $cache.LatestVersion }
                return $null
            }
        } catch {
            # Corrupt/unreadable cache — fall through and re-check.
        }
    }

    $localVersion = Get-TmsLocalVersion -RepoRoot $RepoRoot
    if (-not $localVersion) { return $null }
    if (-not (Test-Path (Join-Path $RepoRoot ".git"))) { return $null }

    $branch = git -C $RepoRoot rev-parse --abbrev-ref HEAD 2>$null
    if (-not $branch) { return $null }

    $job = Start-Job -ScriptBlock {
        param($root)
        git -C $root fetch --quiet origin 2>&1 | Out-Null
    } -ArgumentList $RepoRoot

    $completed = Wait-Job $job -Timeout $FetchTimeoutSeconds
    if (-not $completed) {
        Stop-Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $job -Force -ErrorAction SilentlyContinue | Out-Null
        return $null
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue | Out-Null

    $remoteVersion = git -C $RepoRoot show "origin/${branch}:VERSION" 2>$null
    if (-not $remoteVersion) { return $null }
    $remoteVersion = $remoteVersion.Trim()

    $updateAvailable = $remoteVersion -ne $localVersion
    [ordered]@{
        CheckedAt       = (Get-Date).ToString("o")
        UpdateAvailable = $updateAvailable
        LatestVersion   = $remoteVersion
    } | ConvertTo-Json | Set-Content -Path $cachePath -Encoding utf8

    if ($updateAvailable) { return $remoteVersion }
    return $null
}

Export-ModuleMember -Function Get-TmsLocalVersion, Test-TmsUpdateAvailable
