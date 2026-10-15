# ======================================
# Restore a ztms setup exported by setup\export.ps1 on another machine:
# decrypts the backup, lets you adjust the machine-specific paths in
# tms.config.json (reposRoot, deployRoot, ...), writes tms.config.json +
# tms.env.local, sets the user-level env vars, then runs setup\doctor.ps1.
# Existing tms.config.json / tms.env.local are kept as *.bak before being
# replaced.
# ======================================

param([string]$Path)

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\ProjectMenu.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Backup.psm1") -Force

function Read-WithDefault {
    param([string]$Prompt, [string]$Default)
    Write-Host "$Prompt " -ForegroundColor Cyan -NoNewline
    Write-Host "(Default: $Default): " -ForegroundColor DarkGray -NoNewline
    $ans = (Read-Host).Trim('"', ' ')
    if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
    return $ans
}

if (-not $Path) {
    $Path = (Read-Host "Backup file (.ztmsbak) to import").Trim('"', ' ')
}
if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    Write-Host "Backup file not found: $Path" -ForegroundColor Red
    exit 1
}

$data = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
try {
    $json = Unprotect-TmsBackup -Data $data -Passphrase (Read-TmsPassphrase -Prompt "Backup passphrase")
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
$backup = $json | ConvertFrom-Json
if ($backup.format -ne "ztms-backup") {
    Write-Host "Not a ztms backup file." -ForegroundColor Red
    exit 1
}

$envNames = @($backup.userEnv.PSObject.Properties.Name)
Write-Host "`n=== Import ztms setup ===" -ForegroundColor Magenta
Write-Host "  from machine '$($backup.machine)', exported $($backup.createdAt)" -ForegroundColor Gray
Write-Host "  tms.env.local: $(if ($backup.envFile) { 'yes' } else { 'no' })" -ForegroundColor Gray
Write-Host "  user env vars: $($envNames.Count) ($($envNames -join ', '))" -ForegroundColor Gray

# --- tms.config.json: adjust machine-specific paths -------------------------
Write-Host "`n--- Paths (Enter keeps the exported value) ---" -ForegroundColor Magenta
$config = $backup.config | ConvertFrom-Json
$config.reposRoot = Read-WithDefault "Root folder containing your service repos" $config.reposRoot
$config.deployRoot = Read-WithDefault "Root folder for published (dotnet publish) output" $config.deployRoot
if ($config.frontend -and $config.frontend.path -and [IO.Path]::IsPathRooted($config.frontend.path)) {
    $config.frontend.path = Read-WithDefault "Frontend folder" $config.frontend.path
}
if ($config.android -and $config.android.emulatorPath) {
    $config.android.emulatorPath = Read-WithDefault "Android SDK 'emulator' folder" $config.android.emulatorPath
}
if ($config.httptoolkit -and $config.httptoolkit.repoPath) {
    $config.httptoolkit.repoPath = Read-WithDefault "HTTP Toolkit repo folder (existing clone, or where to clone it)" $config.httptoolkit.repoPath
}
if ($config.pms -and $config.pms.dev -and $config.pms.dev.root) {
    $config.pms.dev.root = Read-WithDefault "PMS DEV install folder" $config.pms.dev.root
}

$configPath = Get-TmsConfigPath
if (Test-Path $configPath) {
    Write-Host
    if (-not (Confirm-Prompt -Message "tms.config.json already exists. Replace it (old one saved as tms.config.json.bak)?" -DefaultYes $true)) {
        Write-Host "Cancelled — nothing changed." -ForegroundColor DarkYellow
        exit 0
    }
    Copy-Item $configPath "$configPath.bak" -Force
}
$config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8
Write-Host "Wrote $configPath" -ForegroundColor Green

# --- tms.env.local ------------------------------------------------------------
if ($backup.envFile) {
    $envFile = Get-TmsEnvFilePath
    if (Test-Path $envFile) { Copy-Item $envFile "$envFile.bak" -Force }
    Set-Content -Path $envFile -Value $backup.envFile -Encoding UTF8 -NoNewline
    Write-Host "Wrote $envFile" -ForegroundColor Green
}

# --- User-level env vars --------------------------------------------------------
if ($envNames.Count -gt 0) {
    $changed = @($envNames | Where-Object { $null -ne [Environment]::GetEnvironmentVariable($_, "User") -and [Environment]::GetEnvironmentVariable($_, "User") -cne $backup.userEnv.$_ })
    if ($changed.Count -gt 0) { Write-Host "`nThese already exist here with a different value and will be overwritten: $($changed -join ', ')" -ForegroundColor DarkYellow }
    if (Confirm-Prompt -Message "Set $($envNames.Count) user-level env var(s) on this machine?" -DefaultYes $true) {
        foreach ($name in $envNames) {
            [Environment]::SetEnvironmentVariable($name, [string]$backup.userEnv.$name, "User")
        }
        Write-Host "Set $($envNames.Count) env var(s) — open a new terminal for them to apply there." -ForegroundColor Green
    }
}

Write-Host "`nYou can delete the backup file now: $Path" -ForegroundColor Yellow
if ($config.httptoolkit -and $config.httptoolkit.repoPath) {
    Write-Host "HTTP Toolkit is configured — run HTTPTOOLKIT > install to clone/build it and put 'htk' on PATH." -ForegroundColor Gray
}
if ($config.pms -and $config.pms.dev -and $config.pms.dev.root) {
    Write-Host "PMS is configured — run PMS > [dev] install to set up its shortcut + auto-update task." -ForegroundColor Gray
}

# --- Check the result --------------------------------------------------------------
Write-Host
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "doctor.ps1")
