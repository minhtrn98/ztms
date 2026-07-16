# ======================================
# Smoke test for this repo — run this before packaging/publishing.
#
# What it checks:
#   1. Every .ps1/.psm1 parses cleanly (catches typos, broken here-strings).
#   2. Each script's guard clauses behave correctly against an incomplete,
#      synthetic config — no real Docker/dotnet/Postgres/Redis is touched.
#
# What it does NOT check (do this manually, once, before a real release):
#   - Actually running a service (`001_run-services.ps1` against a real repo)
#   - Actually cloning a DB or Redis cache from a real dev server
#   - `900_init-config.ps1` / `901_set-env.ps1`'s interactive prompts
#
# Requires PowerShell 7+ (pwsh) — same requirement as the scripts themselves.
# ======================================

$publicRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "tms_public_smoketest_$(Get-Random)"

Write-Host "=== TMS public scripts smoke test ===" -ForegroundColor Magenta
Write-Host "Isolated working copy: $testRoot`n" -ForegroundColor Gray

$results = @()

function Test-Step {
    param([string]$Name, [scriptblock]$Action)
    try {
        & $Action
        $script:results += [PSCustomObject]@{ Name = $Name; Status = "PASS" }
        Write-Host "PASS " -ForegroundColor Green -NoNewline
        Write-Host $Name
    } catch {
        $script:results += [PSCustomObject]@{ Name = $Name; Status = "FAIL"; Detail = $_.Exception.Message }
        Write-Host "FAIL " -ForegroundColor Red -NoNewline
        Write-Host "$Name"
        Write-Host "     $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

# --- 1. Engine check --------------------------------------------------------
Test-Step "Running under PowerShell 7+ (required for ForEach-Object -Parallel)" {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "Running under PS $($PSVersionTable.PSVersion) — re-run this with 'pwsh', not 'powershell'"
    }
}

# --- 2. Syntax check every script ------------------------------------------
$scriptFiles = Get-ChildItem -Path $publicRoot -Recurse -Include "*.ps1", "*.psm1" |
    Where-Object { $_.FullName -notlike "*\tests\*" }

foreach ($f in $scriptFiles) {
    $relPath = $f.FullName.Substring($publicRoot.Length + 1)
    Test-Step "Parses cleanly: $relPath" {
        $err = $null
        [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$err) | Out-Null
        if ($err.Count -gt 0) { throw ($err -join "; ") }
    }
}

# --- 3. Isolated working copy + synthetic (intentionally incomplete) config -
Copy-Item -Recurse $publicRoot $testRoot
Remove-Item (Join-Path $testRoot "tests") -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $testRoot "_dummyRepo") | Out-Null

$syntheticConfig = [ordered]@{
    reposRoot         = $testRoot
    deployRoot        = Join-Path $testRoot "_deploy"
    processTag        = "tms-smoketest-$(Get-Random)"
    services          = @()
    pullIgnoreFolders = @()
    database          = [ordered]@{
        localHost = "localhost"; localUser = "postgres"; localPasswordEnvVar = "TMS_LOCAL_DB_PASSWORD"
        devHost = ""; devUser = "dev"; devPasswordEnvVar = "DEV_DB_PASSWORD"
        backupFolder = "_db_backups"; databases = @(); excludeTableDataPattern = ""
    }
    redis             = [ordered]@{
        devHost = ""; devPort = 6379; devPasswordEnvVar = "DEV_REDIS_PW"
        container = "smoketest-redis"; volume = "smoketest_data"; backupFolder = "_db_backups"
    }
}
$syntheticConfig | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $testRoot "tms.config.json") -Encoding UTF8

# --- 4. Guard-clause behavior on incomplete config --------------------------
function Invoke-Guarded {
    param([string]$RelativePath, [string]$ExpectedSubstring)
    $full = Join-Path $testRoot $RelativePath
    $output = & pwsh -NoProfile -File $full 2>&1 | Out-String
    if ($output -notmatch [regex]::Escape($ExpectedSubstring)) {
        throw "Expected output to contain '$ExpectedSubstring'. Got:`n$output"
    }
}

Test-Step "001_run-services.ps1 exits cleanly with no services configured" {
    Invoke-Guarded "001_run-services.ps1" "No services configured"
}
Test-Step "002_run-published.ps1 exits cleanly with no services configured" {
    Invoke-Guarded "002_run-published.ps1" "No services configured"
}
Test-Step "003_run-frontend.ps1 exits cleanly with no frontend configured" {
    Invoke-Guarded "003_run-frontend.ps1" "No frontend configured"
}
Test-Step "db/clone-db-dev.ps1 exits cleanly with no databases configured" {
    Invoke-Guarded "db\clone-db-dev.ps1" "No databases configured"
}
Test-Step "db/drop-all.ps1 exits cleanly with no databases configured" {
    Invoke-Guarded "db\drop-all.ps1" "No databases configured"
}
Test-Step "db/terminate-connections.ps1 exits cleanly with no databases configured" {
    Invoke-Guarded "db\terminate-connections.ps1" "No databases configured"
}
Test-Step "redis/clone-redis-dev.ps1 exits cleanly with no devHost configured" {
    Invoke-Guarded "redis\clone-redis-dev.ps1" "No redis.devHost configured"
}
Test-Step "800_stop-services.ps1 reports no tagged processes" {
    Invoke-Guarded "800_stop-services.ps1" "No processes tagged"
}
Test-Step "010_pull-all.ps1 runs to completion against an empty reposRoot" {
    $full = Join-Path $testRoot "010_pull-all.ps1"
    & pwsh -NoProfile -File $full | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Exit code $LASTEXITCODE" }
}

# --- 5. Cleanup --------------------------------------------------------------
Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue

# --- Summary ------------------------------------------------------------
Write-Host "`n=== Summary ===" -ForegroundColor Magenta
$pass = @($results | Where-Object Status -eq "PASS").Count
$fail = @($results | Where-Object Status -eq "FAIL").Count
Write-Host "$pass passed, $fail failed" -ForegroundColor $(if ($fail -gt 0) { "Red" } else { "Green" })
if ($fail -gt 0) { exit 1 }
