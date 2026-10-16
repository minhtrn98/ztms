# ======================================
# Check this machine's ztms setup and list what's missing:
#   - tools the configured features need (git always; dotnet only with
#     services, psql/pg_dump with databases, node/yarn with a frontend, ...)
#   - tms.config.json + the folders it points at
#   - every user-level env var ztms reads (see Get-TmsUserEnvVars), and
#     whether tms.env.local values were persisted / are out of date
#   - custom HTTP Toolkit clone/branch/PATH/release, if httptoolkit is configured
#   - PMS shortcut + auto-update task, if pms.dev is configured
#   - global hotkey + its listener, if SETUP > install-hotkey was run
# Read-only — changes nothing. Exits 1 if anything is FAIL (WARN is fine).
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Pms.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\HttpToolkit.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Hotkey.psm1") -Force

$results = @()
function Add-Check {
    param([string]$Section, [string]$Name, [ValidateSet("OK", "WARN", "FAIL")][string]$Status, [string]$Detail = "")
    $script:results += [PSCustomObject]@{ Section = $Section; Name = $Name; Status = $Status; Detail = $Detail }
}
function Test-Tool {
    param([string]$Name, [string]$Why, [string]$Status = "WARN")
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { Add-Check "Tools" $Name "OK" $cmd.Source }
    else { Add-Check "Tools" $Name $Status "not on PATH — needed for $Why" }
}

# --- Config -----------------------------------------------------------------------
$config = $null
$configPath = Get-TmsConfigPath
if (Test-Path $configPath) {
    try { $config = Get-TmsConfig; Add-Check "Config" "tms.config.json" "OK" $configPath }
    catch { Add-Check "Config" "tms.config.json" "FAIL" "invalid JSON: $($_.Exception.Message)" }
} else {
    Add-Check "Config" "tms.config.json" "FAIL" "missing — run SETUP > import (from another machine) or SETUP > init-config"
}

if ($config) {
    if ($config.reposRoot -and (Test-Path $config.reposRoot)) { Add-Check "Config" "reposRoot" "OK" $config.reposRoot }
    else { Add-Check "Config" "reposRoot" "FAIL" "folder not found: $($config.reposRoot)" }

    if ($config.deployRoot -and (Test-Path $config.deployRoot)) { Add-Check "Config" "deployRoot" "OK" $config.deployRoot }
    else { Add-Check "Config" "deployRoot" "WARN" "folder not found: $($config.deployRoot) (created on first publish)" }

    $services = @($config.services)
    if ($services.Count -gt 0 -and $config.reposRoot) {
        $missing = @($services | Where-Object { -not (Test-Path (Join-Path $config.reposRoot $_.name)) } | ForEach-Object { $_.name })
        if ($missing.Count -eq 0) { Add-Check "Config" "service repos" "OK" "$($services.Count) found under reposRoot" }
        else { Add-Check "Config" "service repos" "WARN" "not cloned yet: $($missing -join ', ') — run COMMON > pull-all after cloning" }
    }

    if (Test-Path (Get-TmsEnvFilePath)) { Add-Check "Config" "tms.env.local" "OK" "" }
    else { Add-Check "Config" "tms.env.local" "WARN" "missing — services may lack runtime config (copy tms.env.example, or SETUP > import)" }
}

# --- Tools ----------------------------------------------------------------------------
Test-Tool "git" "everything (pull-all, update)" "FAIL"
if ($config) {
    if (@($config.services).Count -gt 0) { Test-Tool "dotnet" "BACKEND run/publish" }
    if ($config.database -and @($config.database.databases).Count -gt 0) {
        foreach ($t in "psql", "pg_dump", "pg_restore") { Test-Tool $t "DATABASE clone/restore" }
    }
    if (($config.database -and @($config.database.databases).Count -gt 0) -or ($config.redis -and $config.redis.container)) {
        Test-Tool "docker" "local Postgres/Redis containers"
    }
    if ($config.frontend -and $config.frontend.path) {
        Test-Tool "node" "FRONTEND run"
        if ("$($config.frontend.buildCommand) $($config.frontend.startCommand)" -match '\byarn\b') { Test-Tool "yarn" "FRONTEND build/start commands" }
    }
    if ($config.android -and $config.android.emulatorPath) {
        $emu = Join-Path $config.android.emulatorPath "emulator.exe"
        if (Test-Path $emu) { Add-Check "Tools" "emulator" "OK" $emu }
        else { Add-Check "Tools" "emulator" "WARN" "not found at $emu — needed for ANDROID" }
    }
}
Test-Tool "code" "open-vscode"
$shim = Join-Path $env:LocalAppData "Microsoft\WindowsApps\ztms.cmd"
if (Test-Path $shim) { Add-Check "Tools" "ztms command" "OK" $shim }
else { Add-Check "Tools" "ztms command" "WARN" "not installed — run install-ztms.ps1" }

# --- Env vars ------------------------------------------------------------------------------
$envFileValues = if (Test-Path (Get-TmsEnvFilePath)) { Read-TmsEnvFile -Path (Get-TmsEnvFilePath) } else { @{} }
foreach ($v in Get-TmsUserEnvVars -Config $config) {
    $value = [Environment]::GetEnvironmentVariable($v.Name, "User")
    if ($v.Kind -eq "secret") {
        if ($value) { Add-Check "Env vars" $v.Name "OK" $v.Source }
        else { Add-Check "Env vars" $v.Name "WARN" "not set ($($v.Source)) — scripts will prompt for it when needed" }
    } else {
        if ($null -eq $value) { Add-Check "Env vars" $v.Name "WARN" "in tms.env.local but not persisted — run SETUP > set-env and choose to persist" }
        elseif ($value -cne $envFileValues[$v.Name]) { Add-Check "Env vars" $v.Name "WARN" "user-level value differs from tms.env.local — re-run SETUP > set-env to persist" }
        else { Add-Check "Env vars" $v.Name "OK" $v.Source }
    }
}

# --- HTTP Toolkit -----------------------------------------------------------------------------
if ($config -and $config.httptoolkit -and $config.httptoolkit.repoPath) {
    $htk = Get-TmsHttpToolkitConfig -Config $config
    foreach ($row in Get-TmsHttpToolkitStatus -Htk $htk) { Add-Check "HTTP Toolkit" $row.Name $row.Status $row.Detail }
}

# --- PMS ------------------------------------------------------------------------------------
if ($config -and $config.pms -and $config.pms.dev -and $config.pms.dev.root) {
    $pms = Get-TmsPmsDevConfig -Config $config
    foreach ($row in Get-TmsPmsStatus -Pms $pms) { Add-Check "PMS" $row.Name $row.Status $row.Detail }
}

# --- Hotkey ---------------------------------------------------------------------------------
foreach ($row in Get-TmsHotkeyStatus -Config $config) { Add-Check "Hotkey" $row.Name $row.Status $row.Detail }

# --- Report ---------------------------------------------------------------------------------
$colors = @{ OK = "Green"; WARN = "Yellow"; FAIL = "Red" }
Write-Host "=== ztms doctor ===" -ForegroundColor Magenta
foreach ($group in $results | Group-Object Section) {
    Write-Host "`n[$($group.Name)]" -ForegroundColor Cyan
    foreach ($r in $group.Group) {
        Write-Host ("  {0,-5}" -f $r.Status) -ForegroundColor $colors[$r.Status] -NoNewline
        Write-Host (" {0,-30}" -f $r.Name) -NoNewline
        Write-Host " $($r.Detail)" -ForegroundColor Gray
    }
}

$ok = @($results | Where-Object Status -eq "OK").Count
$warn = @($results | Where-Object Status -eq "WARN").Count
$fail = @($results | Where-Object Status -eq "FAIL").Count
Write-Host "`n$ok OK, $warn WARN, $fail FAIL" -ForegroundColor $(if ($fail) { "Red" } elseif ($warn) { "Yellow" } else { "Green" })
if ($fail -gt 0) { exit 1 }
