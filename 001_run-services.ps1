# ======================================
# Run selected services with `dotnet run` (dev mode)
# Reads service list/ports from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path $PSScriptRoot "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\ProjectMenu.psm1") -Force

$config = Get-TmsConfig
$serviceNames = @($config.services | ForEach-Object { $_.name })
$enabledNames = @($config.services | Where-Object { $_.enabled -ne $false } | ForEach-Object { $_.name })
$portMap = @{}
foreach ($s in $config.services) { $portMap[$s.name] = $s.port }

if ($serviceNames.Count -eq 0) {
    Write-Host "No services configured. Edit tms.config.json or re-run 900_init-config.ps1." -ForegroundColor Red
    exit 1
}

function Start-SelectedServices {
    param(
        [string[]]$Roots,
        [string]$Mode,
        [hashtable]$PortMap,
        [string]$ReposRoot,
        [string]$ProcessTag
    )

    foreach ($root in $Roots) {
        $rootFullPath = Join-Path $ReposRoot $root
        if (-not (Test-Path $rootFullPath)) {
            Write-Host "❌ Repo folder not found: $rootFullPath" -ForegroundColor Red
            continue
        }

        $port = $PortMap[$root]
        if (-not $port) {
            Write-Host "⚠️ No port mapping found for $root. Skipping." -ForegroundColor DarkYellow
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
                Write-Host "⚠️ No csproj found in $($apiFolder.Name)" -ForegroundColor DarkRed
                continue
            }

            $branch = git -C $apiFolder.FullName rev-parse --abbrev-ref HEAD 2>$null

            Write-Host "-> " -ForegroundColor Green -NoNewline
            Write-Host "Running: " -ForegroundColor White -NoNewline
            Write-Host "$($apiFolder.Name) " -ForegroundColor Cyan -NoNewline
            Write-Host "on " -ForegroundColor White -NoNewline
            Write-Host "$branch" -ForegroundColor Yellow -NoNewline
            Write-Host " -> http://localhost:$port" -ForegroundColor Green

            Start-Process "cmd.exe" -ArgumentList "/k Title [$ProcessTag] $root on #$branch && cd /d `"$apiFolder`" && dotnet run -c $Mode --urls http://localhost:$port"
        }
    }
}

$selectedRoots = Show-ProjectSelection -Items $serviceNames -PreSelected $enabledNames
Write-Host "Selected services:" -NoNewline
Write-Host " $($selectedRoots -join ', ')" -ForegroundColor Yellow
Write-Host

Start-SelectedServices -Roots $selectedRoots -Mode "Release" -PortMap $portMap -ReposRoot $config.reposRoot -ProcessTag $config.processTag
Write-Host

Write-Host "`n🎉 DONE" -ForegroundColor Magenta
