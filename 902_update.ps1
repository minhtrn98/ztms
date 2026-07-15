# ======================================
# Update these scripts via `git pull`.
#
# The global `ztms` command (ztms.cmd) points at this checkout by absolute
# path, so pulling here is all that's needed — no reinstall of the shim.
# Only re-run install-ztms.ps1 if you move this repo to a different path.
# ======================================

$scriptsRepoRoot = $PSScriptRoot

if (-not (Test-Path (Join-Path $scriptsRepoRoot ".git"))) {
    Write-Host "$scriptsRepoRoot doesn't look like a git repo — nothing to pull." -ForegroundColor Red
    exit 1
}

$branch = git -C $scriptsRepoRoot rev-parse --abbrev-ref HEAD
Write-Host "Updating $scriptsRepoRoot " -ForegroundColor Cyan -NoNewline
Write-Host "[$branch]" -ForegroundColor Yellow
Write-Host ""

$output = git -C $scriptsRepoRoot pull 2>&1
Write-Host $output
$pullExitCode = $LASTEXITCODE

Write-Host ""
if ($pullExitCode -ne 0) {
    Write-Host "git pull failed — resolve manually (uncommitted local changes? merge conflict?)." -ForegroundColor Red
    exit 1
} elseif ($output -match "Already up to date") {
    Write-Host "Already up to date." -ForegroundColor Green
} else {
    Write-Host "Updated. 'ztms' already points at this checkout — nothing else to do." -ForegroundColor Green
}
