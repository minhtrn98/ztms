# ======================================
# Open one or more configured services' solutions in Visual Studio: the
# repo's .sln/.slnx, opened directly (with whichever Visual Studio the file
# association picks) — not through the repo's <Name>.sln.bat.
# -Service <name>[,<name>]: open those directly, no picker (what the hotkey
# window's "VISUAL STUDIO" entries run — e.g. type "order vs").
# Reads service list/reposRoot from tms.config.json — run 900_init-config.ps1 first.
# ======================================

param([string[]]$Service)

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\ProjectMenu.psm1") -Force

$config = Get-TmsConfig
$serviceNames = @($config.services | ForEach-Object { $_.name })

if ($serviceNames.Count -eq 0) {
    Write-Host "No services configured. Edit tms.config.json or re-run 900_init-config.ps1." -ForegroundColor Red
    exit 1
}

if ($Service) {
    $selectedNames = @($Service | ForEach-Object {
        $wanted = $_
        $known = $serviceNames | Where-Object { $_ -eq $wanted } | Select-Object -First 1
        if ($known) { $known } else { Write-Host "Unknown service: $wanted (not in tms.config.json services)" -ForegroundColor Red }
    })
    if ($selectedNames.Count -eq 0) { exit 1 }
} else {
    $selectedNames = Show-ProjectSelection -Items $serviceNames
}

$failed = $false
foreach ($name in $selectedNames) {
    $servicePath = Join-Path $config.reposRoot $name
    if (-not (Test-Path -LiteralPath $servicePath)) {
        Write-Host "⚠️ Folder not found, skipping: $servicePath" -ForegroundColor DarkYellow
        $failed = $true
        continue
    }

    # By extension, not -Filter: "*.sln" would also match .sln.bat (8.3 wildcard quirk)
    $sln = Get-ChildItem -LiteralPath $servicePath -File | Where-Object { $_.Extension -in ".sln", ".slnx" } | Select-Object -First 1
    if (-not $sln) {
        Write-Host "⚠️ No .sln in $servicePath, skipping" -ForegroundColor DarkYellow
        $failed = $true
        continue
    }

    Write-Host "-> " -ForegroundColor Green -NoNewline
    Write-Host "Opening in Visual Studio: " -ForegroundColor White -NoNewline
    Write-Host "$($sln.FullName)" -ForegroundColor Cyan
    Start-Process -FilePath $sln.FullName
}

Write-Host "`n🎉 DONE" -ForegroundColor Magenta
if ($failed) { exit 1 }
