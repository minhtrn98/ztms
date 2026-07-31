# ======================================
# Open one or more configured services in VS Code
# Reads service list/reposRoot from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\ProjectMenu.psm1") -Force

$config = Get-TmsConfig
$serviceNames = @($config.services | ForEach-Object { $_.name })

if ($serviceNames.Count -eq 0) {
    Write-Host "No services configured. Edit tms.config.json or re-run 900_init-config.ps1." -ForegroundColor Red
    exit 1
}

if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 'code' command not found on PATH. Install VS Code and enable the 'code' shell command." -ForegroundColor Red
    exit 1
}

$selectedNames = Show-ProjectSelection -Items $serviceNames

foreach ($name in $selectedNames) {
    $servicePath = Join-Path $config.reposRoot $name
    if (-not (Test-Path $servicePath)) {
        Write-Host "⚠️ Folder not found, skipping: $servicePath" -ForegroundColor DarkYellow
        continue
    }

    Write-Host "-> " -ForegroundColor Green -NoNewline
    Write-Host "Opening in VS Code: " -ForegroundColor White -NoNewline
    Write-Host "$servicePath" -ForegroundColor Cyan

    & code $servicePath
}

Write-Host "`n🎉 DONE" -ForegroundColor Magenta
