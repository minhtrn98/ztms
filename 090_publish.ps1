# ======================================
# dotnet publish selected services to deployRoot
# Reads services/reposRoot/deployRoot from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path $PSScriptRoot "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\ProjectMenu.psm1") -Force

$config = Get-TmsConfig
$serviceNames = @($config.services | ForEach-Object { $_.name })

if ($serviceNames.Count -eq 0) {
    Write-Host "No services configured. Edit tms.config.json or re-run 900_init-config.ps1." -ForegroundColor Red
    exit 1
}

function Publish-SelectedServices {
    param(
        [string[]]$Roots,
        [string]$ReposRoot,
        [string]$DeployRoot,
        [bool]$CleanOutput
    )

    foreach ($root in $Roots) {
        $rootFullPath = Join-Path $ReposRoot $root
        if (-not (Test-Path $rootFullPath)) {
            Write-Host "❌ Repo folder not found: $rootFullPath" -ForegroundColor Red
            continue
        }

        $apiFolders = Get-ChildItem -Path "$rootFullPath\src" -Directory -Filter "*.Api" -ErrorAction SilentlyContinue
        if (-not $apiFolders -or $apiFolders.Count -eq 0) {
            Write-Host "⚠️ No *.Api folder found in $root" -ForegroundColor DarkYellow
            continue
        }

        foreach ($apiFolder in $apiFolders) {
            $csproj = Get-ChildItem -Path $apiFolder.FullName -Filter *.csproj -Recurse | Select-Object -First 1
            if (-not $csproj) {
                Write-Host "⚠️ No .csproj found in $($apiFolder.Name)" -ForegroundColor DarkRed
                continue
            }

            $outputPath = Join-Path $DeployRoot $root
            $branch = git -C $apiFolder.FullName rev-parse --abbrev-ref HEAD 2>$null

            if ($CleanOutput -and (Test-Path $outputPath)) {
                Remove-Item -Recurse -Force $outputPath
                Write-Host "  Cleaned: $outputPath" -ForegroundColor DarkGray
            }

            Write-Host "-> " -ForegroundColor Green -NoNewline
            Write-Host "Publishing: " -ForegroundColor White -NoNewline
            Write-Host "$($apiFolder.Name) " -ForegroundColor Cyan -NoNewline
            Write-Host "[$branch]" -ForegroundColor Yellow -NoNewline
            Write-Host " -> " -ForegroundColor White -NoNewline
            Write-Host $outputPath -ForegroundColor Green

            Start-Process "cmd.exe" -ArgumentList "/c Title Publishing $root && cd /d `"$($apiFolder.FullName)`" && dotnet publish -c Release -o `"$outputPath`""
        }
    }
}

$preSelected = @()
$pullStateFile = Join-Path $PSScriptRoot ".pull-changed.json"
if (Test-Path $pullStateFile) {
    try { $preSelected = @(Get-Content $pullStateFile -Raw | ConvertFrom-Json) } catch { $preSelected = @() }
}
if ($preSelected.Count -gt 0) {
    Write-Host "Suggested from last pull (changed): " -ForegroundColor Magenta -NoNewline
    Write-Host "$($preSelected -join ', ')" -ForegroundColor Yellow
    Write-Host ""
}

$selectedRoots = Show-ProjectSelection -Items $serviceNames -PreSelected $preSelected
Write-Host "Selected services:" -NoNewline
Write-Host " $($selectedRoots -join ', ')" -ForegroundColor Yellow
Write-Host "Deploy root:" -NoNewline
Write-Host " $($config.deployRoot)" -ForegroundColor Yellow
Write-Host

$cleanOutput = Confirm-Prompt -Message "Existing output folders detected — clean before publish?" -DefaultYes $true
Write-Host

Publish-SelectedServices -Roots $selectedRoots -ReposRoot $config.reposRoot -DeployRoot $config.deployRoot -CleanOutput $cleanOutput
Write-Host

if (Test-Path $pullStateFile) {
    $remaining = @($preSelected | Where-Object { $selectedRoots -notcontains $_ })
    ConvertTo-Json -InputObject $remaining | Set-Content -Path $pullStateFile -Encoding UTF8
}

Write-Host "`n🎉 DONE — check each window for publish results." -ForegroundColor Magenta
