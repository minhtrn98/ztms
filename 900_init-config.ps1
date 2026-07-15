# ======================================
# Interactive first-run setup — creates tms.config.json next to this script.
# Run this once before using any other script in this repo.
# ======================================

function Read-WithDefault {
    param([string]$Prompt, [string]$Default)
    Write-Host "$Prompt " -ForegroundColor Cyan -NoNewline
    Write-Host "(Default: $Default): " -ForegroundColor DarkGray -NoNewline
    $ans = Read-Host
    if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
    return $ans
}

$configPath = Join-Path $PSScriptRoot "tms.config.json"
if (Test-Path $configPath) {
    Write-Host "Config already exists at $configPath" -ForegroundColor Yellow
    Write-Host "# Overwrite it? [y/N] (Default: N): " -ForegroundColor Cyan -NoNewline
    $ans = Read-Host
    if ($ans -notmatch '^[yY]') {
        Write-Host "Cancelled." -ForegroundColor DarkYellow
        exit 0
    }
}

Write-Host "`n=== TMS scripts setup ===" -ForegroundColor Magenta
Write-Host "Answers are saved to $configPath (not committed to git).`n" -ForegroundColor Gray

# --- Paths -----------------------------------------------------------------
# No reliable way to guess your service repos' root from wherever this repo
# happened to be cloned — default to the current directory and let the user
# correct it.
$defaultReposRoot = (Get-Location).Path
$reposRoot = Read-WithDefault "Root folder containing your service repos" $defaultReposRoot
$deployRoot = Read-WithDefault "Root folder for published (dotnet publish) output" (Join-Path (Split-Path $reposRoot -Parent) "Deployments")
$processTag = Read-WithDefault "Tag used to identify/stop this stack's processes (used to match window titles)" "tms"

# --- Services ----------------------------------------------------------------
Write-Host "`n--- Services ---" -ForegroundColor Magenta
Write-Host "Enter each service's repo folder name (must sit directly under '$reposRoot') and its port."
Write-Host "Disabled services are still configured (known port, publishable) but won't be"
Write-Host "pre-checked when picking services to run — handy for services you rarely run locally."
Write-Host "Leave the name blank to stop adding services.`n"

$services = @()
while ($true) {
    $name = Read-Host "  Service folder name"
    if ([string]::IsNullOrWhiteSpace($name)) { break }
    $port = Read-Host "  Port for $name"
    if (-not ($port -as [int])) {
        Write-Host "  Invalid port, skipping $name" -ForegroundColor Red
        continue
    }
    $enabledAns = Read-Host "  Include in local run rotation by default? [Y/n] (Default: Y)"
    $enabled = [string]::IsNullOrWhiteSpace($enabledAns) -or $enabledAns -match '^[yY]'
    $services += [ordered]@{ name = $name; port = [int]$port; enabled = $enabled }
}
if ($services.Count -eq 0) {
    Write-Host "No services entered — you can edit tms.config.json by hand later." -ForegroundColor DarkYellow
}

# --- Pull-all ignore list ----------------------------------------------------
$ignoreDefault = "scripts,db_backups"
$ignoreInput = Read-WithDefault "Folders under '$reposRoot' to skip when pulling all repos (comma-separated)" $ignoreDefault
$pullIgnoreFolders = $ignoreInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

# --- Database ----------------------------------------------------------------
Write-Host "`n--- Database (Postgres) ---" -ForegroundColor Magenta
$dbLocalHost = Read-WithDefault "Local Postgres host" "localhost"
$dbLocalUser = Read-WithDefault "Local Postgres user" "postgres"
$dbDevHost = Read-WithDefault "Dev Postgres host (leave blank to skip dev-clone scripts)" ""
$dbDevUser = Read-WithDefault "Dev Postgres user" "dev"
$dbNamesInput = Read-Host "Database names to manage (comma-separated, blank = none)"
$databases = @($dbNamesInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$excludeTableDataPattern = Read-Host "Table name pattern to exclude row data for during clone, e.g. a job-scheduler table like 'qrtz_*' (blank = clone everything)"

# --- Redis -------------------------------------------------------------------
Write-Host "`n--- Redis ---" -ForegroundColor Magenta
$redisDevHost = Read-WithDefault "Dev Redis host (leave blank to skip redis-clone script)" ""
$redisDevPort = Read-WithDefault "Dev Redis port" "6379"
$redisContainer = Read-WithDefault "Local Redis container name" "my-redis"
$redisVolume = Read-WithDefault "Local Redis docker volume name" "redis_data"

# --- Assemble config -----------------------------------------------------
$config = [ordered]@{
    reposRoot         = $reposRoot
    deployRoot        = $deployRoot
    processTag        = $processTag
    services          = $services
    pullIgnoreFolders = $pullIgnoreFolders
    database          = [ordered]@{
        localHost           = $dbLocalHost
        localUser           = $dbLocalUser
        localPasswordEnvVar = "TMS_LOCAL_DB_PASSWORD"
        devHost             = $dbDevHost
        devUser             = $dbDevUser
        devPasswordEnvVar   = "DEV_DB_PASSWORD"
        backupFolder        = "db_backups"
        databases           = $databases
        excludeTableDataPattern = $excludeTableDataPattern
    }
    redis             = [ordered]@{
        devHost           = $redisDevHost
        devPort           = [int]$redisDevPort
        devPasswordEnvVar = "DEV_REDIS_PW"
        container         = $redisContainer
        volume            = $redisVolume
        backupFolder      = "db_backups"
    }
}

$config | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8

Write-Host "`nSaved config to $configPath" -ForegroundColor Green
Write-Host "Edit this file by hand any time to adjust services, ports, or DB/Redis settings." -ForegroundColor Gray
Write-Host "`nSecrets are NOT stored here — set these Windows user env vars when needed:" -ForegroundColor Gray
Write-Host "  DEV_DB_PASSWORD, DEV_REDIS_PW  (scripts will prompt if unset)" -ForegroundColor Gray
