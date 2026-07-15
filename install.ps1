# ======================================
# Bootstrap installer for ztms.
#
# Usage, from any machine with git + PowerShell 7 installed:
#   irm https://raw.githubusercontent.com/minhtrn98/ztms/master/install.ps1 | iex
#
# Clones (or updates) this repo locally, then installs the global `ztms`
# command so any terminal (cmd.exe, PowerShell, pwsh), from any directory,
# can just type `ztms` to open the scripts menu.
#
# Runs inside a script block so piping through `iex` doesn't leak variables
# into, or `return`/exit, your actual interactive session.
# ======================================

& {
    $repoUrl = "https://github.com/minhtrn98/ztms.git"

    Write-Host "=== ztms installer ===" -ForegroundColor Magenta

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "git not found on PATH — install it first: https://git-scm.com/downloads" -ForegroundColor Red
        return
    }
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Write-Host "pwsh (PowerShell 7+) not found on PATH — install it first: https://aka.ms/powershell" -ForegroundColor Red
        return
    }

    $defaultDir = Join-Path $HOME "ztms"
    Write-Host "Install location " -ForegroundColor Cyan -NoNewline
    Write-Host "(Default: $defaultDir): " -ForegroundColor DarkGray -NoNewline
    $targetDir = Read-Host
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $defaultDir }

    if (Test-Path (Join-Path $targetDir ".git")) {
        Write-Host "Found existing checkout at $targetDir — pulling latest..." -ForegroundColor Cyan
        git -C $targetDir pull
        if ($LASTEXITCODE -ne 0) {
            Write-Host "git pull failed — resolve manually and re-run." -ForegroundColor Red
            return
        }
    } elseif ((Test-Path $targetDir) -and (Get-ChildItem $targetDir -Force -ErrorAction SilentlyContinue)) {
        Write-Host "$targetDir already exists and isn't empty or a git repo — pick a different location or clear it first." -ForegroundColor Red
        return
    } else {
        Write-Host "Cloning into $targetDir ..." -ForegroundColor Cyan
        git clone $repoUrl $targetDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "git clone failed." -ForegroundColor Red
            return
        }
    }

    $installZtms = Join-Path $targetDir "install-ztms.ps1"
    if (-not (Test-Path $installZtms)) {
        Write-Host "Couldn't find $installZtms after clone — something's off." -ForegroundColor Red
        return
    }

    Write-Host "`nSetting up the 'ztms' command..." -ForegroundColor Cyan
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $installZtms

    Write-Host "`n=== Done ===" -ForegroundColor Magenta
    Write-Host "Repo: $targetDir" -ForegroundColor Gray
    Write-Host "Open a NEW terminal and type: " -ForegroundColor Cyan -NoNewline
    Write-Host "ztms" -ForegroundColor Green
    Write-Host "First time? From the menu, run '900_init-config.ps1' to set up your config." -ForegroundColor Gray
}
