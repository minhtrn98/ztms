# ======================================
# git checkout across all sibling repos under reposRoot to one branch you
# type in. `git checkout` refuses (rather than discarding) when a repo has
# local changes that would be overwritten, so a bad branch name or dirty
# repo just shows up as a per-repo failure below instead of losing work.
# Reads reposRoot/pullIgnoreFolders from tms.config.json — run setup\init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\ProjectMenu.psm1") -Force

$config = Get-TmsConfig
$ignore = @($config.pullIgnoreFolders)

$dirs = @(Get-ChildItem -Path $config.reposRoot -Directory | Where-Object { $ignore -notcontains $_.Name })

if ($dirs.Count -eq 0) {
    Write-Host "No repos found under $($config.reposRoot)." -ForegroundColor Red
    exit 1
}

$branch = Read-Host "Branch to checkout across all repos"
if ([string]::IsNullOrWhiteSpace($branch)) {
    Write-Host "No branch entered. Cancelled." -ForegroundColor DarkYellow
    exit 0
}
$branch = $branch.Trim()

Write-Host ""
Write-Host "This will run 'git fetch' + 'git checkout $branch' in:" -ForegroundColor Cyan
$dirs | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Yellow }
Write-Host ""

$confirmed = Confirm-Prompt -Message "Checkout '$branch' in all $($dirs.Count) repos above?" -DefaultYes $true
if (-not $confirmed) {
    Write-Host "Cancelled." -ForegroundColor DarkYellow
    exit 0
}

Write-Host ""

$results = $dirs | ForEach-Object -Parallel {
    $path = $_.FullName
    $branch = $using:branch

    git -C $path fetch --quiet 2>&1 | Out-Null
    $output = git -C $path checkout $branch 2>&1
    $success = $LASTEXITCODE -eq 0

    [PSCustomObject]@{
        Name    = $_.Name
        Success = $success
        Output  = ($output | Out-String).Trim()
    }
} -ThrottleLimit 8

foreach ($result in ($results | Sort-Object Name)) {
    if ($result.Success) {
        Write-Host "-> " -ForegroundColor Green -NoNewline
        Write-Host "$($result.Name): " -ForegroundColor Cyan -NoNewline
        Write-Host "checked out '$branch'" -ForegroundColor White
    } else {
        Write-Host "-> " -ForegroundColor Red -NoNewline
        Write-Host "$($result.Name): " -ForegroundColor Cyan -NoNewline
        Write-Host "FAILED" -ForegroundColor Red
    }
    if ($result.Output) { Write-Host $result.Output }
}

$failed = @($results | Where-Object { -not $_.Success })
Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "$($results.Count - $failed.Count)/$($results.Count) repos checked out to '$branch'." -ForegroundColor Yellow
    Write-Host "Failed: $($failed.Name -join ', ')" -ForegroundColor Red
} else {
    Write-Host "All $($results.Count) repos checked out to '$branch'." -ForegroundColor Green
}
