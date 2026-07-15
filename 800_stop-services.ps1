# ======================================
# Stop all running processes tagged with config.processTag
# Reads processTag from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path $PSScriptRoot "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig
$tag = $config.processTag

$taggedCmdProcs = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -eq "cmd" -and $_.MainWindowTitle -like "*$tag*" }

$taggedDotnetProcs = Get-CimInstance Win32_Process -Filter "name = 'dotnet.exe'" |
    Where-Object { $_.CommandLine -like "*$tag*" } |
    ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }

$targets = @($taggedCmdProcs) + @($taggedDotnetProcs) | Where-Object { $_ }

if ($targets.Count -eq 0) {
    Write-Host "No processes tagged '$tag' found." -ForegroundColor DarkGreen
    return
}

$targets | ForEach-Object {
    Write-Host "Stopping [$($_.Id)] $($_.ProcessName) — $($_.MainWindowTitle)" -ForegroundColor Yellow
}

$targets | ForEach-Object { $_.CloseMainWindow() | Out-Null }
Start-Sleep -Seconds 2
$targets | Where-Object { -not $_.HasExited } | Stop-Process -Force

Write-Host "Stopped $($targets.Count) process(es)." -ForegroundColor Green
