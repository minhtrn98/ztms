# ======================================
# Run published (dotnet publish output) services
# Reads service list/ports/deployRoot from tms.config.json — run 900_init-config.ps1 first.
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

function Start-PublishedServices {
    param(
        [string[]]$Roots,
        [hashtable]$PortMap,
        [string]$DeployRoot,
        [string]$ProcessTag
    )

    foreach ($root in $Roots) {
        $deployPath = Join-Path $DeployRoot $root
        if (-not (Test-Path $deployPath)) {
            Write-Host "❌ Deploy folder not found: $deployPath" -ForegroundColor Red
            continue
        }

        $port = $PortMap[$root]
        if (-not $port) {
            Write-Host "⚠️ No port mapping found for $root. Skipping." -ForegroundColor DarkYellow
            continue
        }

        # Detect entry point via .runtimeconfig.json (always exactly one per published app)
        $runtimeConfig = Get-ChildItem -Path $deployPath -Filter "*.runtimeconfig.json" | Select-Object -First 1
        if (-not $runtimeConfig) {
            Write-Host "⚠️ No .runtimeconfig.json in $deployPath — was the project published?" -ForegroundColor DarkYellow
            continue
        }

        $appName = $runtimeConfig.Name -replace '\.runtimeconfig\.json$', ''
        $exePath = Join-Path $deployPath "$appName.exe"
        $runCmd = if (Test-Path $exePath) { "`"$appName.exe`"" } else { "dotnet `"$appName.dll`"" }

        Write-Host "-> " -ForegroundColor Green -NoNewline
        Write-Host "Starting: " -ForegroundColor White -NoNewline
        Write-Host "$appName " -ForegroundColor Cyan -NoNewline
        Write-Host "-> http://localhost:$port" -ForegroundColor Green

        Start-Process "cmd.exe" -ArgumentList "/k Title [$ProcessTag] $root [PUBLISHED] && cd /d `"$deployPath`" && $runCmd --urls http://localhost:$port"
    }
}

$selectedRoots = Show-ProjectSelection -Items $serviceNames -PreSelected $enabledNames
Write-Host "Selected services:" -NoNewline
Write-Host " $($selectedRoots -join ', ')" -ForegroundColor Yellow
Write-Host "Deploy root:" -NoNewline
Write-Host " $($config.deployRoot)" -ForegroundColor Yellow
Write-Host

Start-PublishedServices -Roots $selectedRoots -PortMap $portMap -DeployRoot $config.deployRoot -ProcessTag $config.processTag
Write-Host

Write-Host "`n🎉 DONE" -ForegroundColor Magenta
