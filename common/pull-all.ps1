# ======================================
# git pull across all sibling repos under reposRoot (parallel)
# Reads reposRoot/pullIgnoreFolders from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path $PSScriptRoot "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig
$ignore = @($config.pullIgnoreFolders)

$dirs = Get-ChildItem -Path $config.reposRoot -Directory | Where-Object { $ignore -notcontains $_.Name }

$results = $dirs | ForEach-Object -Parallel {
    $path   = $_.FullName
    $branch = git -C $path rev-parse --abbrev-ref HEAD 2>&1
    $output = git -C $path pull 2>&1

    [PSCustomObject]@{
        Path   = $path
        Name   = $_.Name
        Branch = $branch
        Output = $output -join "`n"
    }
} -ThrottleLimit 8

$results | ForEach-Object {
    Write-Host "-> " -ForegroundColor Green -NoNewline
    Write-Host "Pulled: " -ForegroundColor White -NoNewline
    Write-Host "$($_.Path) " -ForegroundColor Cyan -NoNewline
    Write-Host "on " -ForegroundColor White -NoNewline
    Write-Host "$($_.Branch)" -ForegroundColor Yellow
    Write-Host $_.Output
    Write-Host ""
}

# Track which repos actually pulled changes so 090_publish.ps1 can
# suggest them automatically on the next publish run.
$changed = $results | Where-Object {
    $_.Output -notmatch "Already up to date" -and $_.Output -notmatch "fatal:"
} | Select-Object -ExpandProperty Name

$pullStateFile = Join-Path $PSScriptRoot ".pull-changed.json"
ConvertTo-Json -InputObject @($changed) | Set-Content -Path $pullStateFile -Encoding UTF8

if ($changed.Count -gt 0) {
    Write-Host "Changed repos (saved for publish suggestion): " -ForegroundColor Magenta -NoNewline
    Write-Host "$($changed -join ', ')" -ForegroundColor Yellow
    Write-Host ""
}
