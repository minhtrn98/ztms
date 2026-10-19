# ======================================
# Open one or more configured services' solutions in Visual Studio.
# Prefers the repo's <Name>.sln.bat when there is one — it sets up the dev
# env vars (call ..\config.bat) before starting the .sln, so Visual Studio and
# the services it runs inherit them — otherwise opens the .sln/.slnx directly
# (with whichever Visual Studio the file association picks).
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

    # By extension, not -Filter: "*.sln" would also match .sln.bat/.slnx (8.3 wildcard quirk)
    $files = @(Get-ChildItem -LiteralPath $servicePath -File)
    $bat = $files | Where-Object { $_.Name -like "*.sln.bat" } | Select-Object -First 1
    $sln = $files | Where-Object { $_.Extension -in ".sln", ".slnx" } | Select-Object -First 1
    if (-not $bat -and -not $sln) {
        Write-Host "⚠️ No .sln in $servicePath, skipping" -ForegroundColor DarkYellow
        $failed = $true
        continue
    }

    Write-Host "-> " -ForegroundColor Green -NoNewline
    Write-Host "Opening in Visual Studio: " -ForegroundColor White -NoNewline
    if ($bat) {
        Write-Host "$($bat.FullName)" -ForegroundColor Cyan
        # The .bat uses paths relative to the repo (..\config.bat), so run it from there
        Start-Process cmd.exe -ArgumentList "/c `"`"$($bat.FullName)`"`"" -WorkingDirectory $servicePath -WindowStyle Hidden
    } else {
        Write-Host "$($sln.FullName)" -ForegroundColor Cyan
        Start-Process -FilePath $sln.FullName
    }
}

Write-Host "`n🎉 DONE" -ForegroundColor Magenta
if ($failed) { exit 1 }
