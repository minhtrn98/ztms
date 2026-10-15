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

$configPath = Join-Path (Split-Path $PSScriptRoot -Parent) "tms.config.json"
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

# --- Frontend (optional) ------------------------------------------------------
Write-Host "`n--- Frontend (optional) ---" -ForegroundColor Magenta
$fePath = Read-Host "Frontend folder (absolute, or relative to reposRoot; blank to skip 003_run-frontend.ps1)"
$feBuildCommand = ""
$feStartCommand = ""
if (-not [string]::IsNullOrWhiteSpace($fePath)) {
    $feBuildCommand = Read-WithDefault "Build command (blank to skip building)" "yarn build"
    $feStartCommand = Read-WithDefault "Start command" "yarn start"
}

# --- Android (optional) --------------------------------------------------
Write-Host "`n--- Android emulator (optional) ---" -ForegroundColor Magenta
$androidEmulatorPath = Read-WithDefault "Android SDK 'emulator' folder (blank to skip android\*.ps1 scripts)" "C:\Program Files (x86)\Android\android-sdk\emulator"

# --- HTTP Toolkit fork (optional) -------------------------------------------
Write-Host "`n--- Custom HTTP Toolkit (optional) ---" -ForegroundColor Magenta
Write-Host "Local folder for the custom-http-toolkit clone: an existing clone, or where to clone it."
$htkRepoPath = Read-Host "HTTP Toolkit repo folder, e.g. D:\OpenSources\custom-http-toolkit (blank to skip httptoolkit\*.ps1)"
$htkGitUrl = ""
$htkBranch = ""
if (-not [string]::IsNullOrWhiteSpace($htkRepoPath)) {
    $htkGitUrl = Read-WithDefault "Git URL (used only if the folder isn't cloned yet)" "https://github.com/xizot/custom-http-toolkit.git"
    $htkBranch = Read-WithDefault "Branch to check out" "window-minh"
}

# --- PMS (optional) --------------------------------------------------------
Write-Host "`n--- PMS desktop app (optional) ---" -ForegroundColor Magenta
$pmsRoot = Read-Host "PMS DEV install folder, e.g. D:\PMS\PMSDev (blank to skip pms\*.ps1 scripts)"
$pmsUpdateUrl = ""
if (-not [string]::IsNullOrWhiteSpace($pmsRoot)) {
    # PMSSetup.exe.config in that folder carries the update server URL — offer it as the default.
    $setupConfig = Join-Path $pmsRoot "PMSSetup.exe.config"
    $detectedUrl = if (Test-Path $setupConfig) { ([xml](Get-Content $setupConfig -Raw)).configuration.appSettings.add | Where-Object key -eq "NewUpdateUrl" | ForEach-Object value }
    $pmsUpdateUrl = Read-WithDefault "PMS update server URL" "$detectedUrl"
}

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
    frontend          = [ordered]@{
        path         = $fePath
        buildCommand = $feBuildCommand
        startCommand = $feStartCommand
    }
    android           = [ordered]@{
        emulatorPath = $androidEmulatorPath
    }
    httptoolkit       = [ordered]@{
        repoPath  = $htkRepoPath
        gitUrl    = $htkGitUrl
        branch    = $htkBranch
        deployDir = ""
    }
    pms               = [ordered]@{
        dev = [ordered]@{
            root           = $pmsRoot
            updateUrl      = $pmsUpdateUrl
            product        = "PMSx64"
            passwordEnvVar = "PMS_DEV_PASSWORD"
        }
    }
}

$config | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8

Write-Host "`nSaved config to $configPath" -ForegroundColor Green
Write-Host "Edit this file by hand any time to adjust services, ports, or DB/Redis settings." -ForegroundColor Gray
Write-Host "`nSecrets are NOT stored here — they're Windows user env vars (scripts prompt if unset)." -ForegroundColor Gray
Write-Host "Run SETUP > doctor to see every env var/tool this config needs and what's still missing." -ForegroundColor Gray
if ($htkRepoPath) { Write-Host "HTTP Toolkit configured — run HTTPTOOLKIT > install to clone/build it and put 'htk' on PATH." -ForegroundColor Gray }
