# ======================================
# Smoke test for this repo — run this before packaging/publishing.
#
# What it checks:
#   1. Every .ps1/.psm1 parses cleanly (catches typos, broken here-strings).
#   2. Each script's guard clauses behave correctly against an incomplete,
#      synthetic config — no real Docker/dotnet/Postgres/Redis is touched.
#
# What it does NOT check (do this manually, once, before a real release):
#   - Actually running a service (`backend/run.ps1` against a real repo)
#   - Actually cloning a DB or Redis cache from a real dev server
#   - `setup/init-config.ps1` / `setup/set-env.ps1`'s interactive prompts
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
        stgHost = ""; stgUser = "stg"; stgPasswordEnvVar = "STG_DB_PASSWORD"
        backupFolder = "_db_backups"; databases = @(); excludeTableDataPattern = ""
    }
    redis             = [ordered]@{
        devHost = ""; devPort = 6379; devPasswordEnvVar = "DEV_REDIS_PW"
        stgHost = ""; stgPort = 6379; stgPasswordEnvVar = "STG_REDIS_PW"
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

Test-Step "backend/run.ps1 exits cleanly with no services configured" {
    Invoke-Guarded "backend\run.ps1" "No services configured"
}
Test-Step "backend/run-published.ps1 exits cleanly with no services configured" {
    Invoke-Guarded "backend\run-published.ps1" "No services configured"
}
Test-Step "frontend/run.ps1 exits cleanly with no frontend configured" {
    Invoke-Guarded "frontend\run.ps1" "No frontend configured"
}
Test-Step "frontend/open-vscode.ps1 exits cleanly with no frontend configured" {
    Invoke-Guarded "frontend\open-vscode.ps1" "No frontend configured"
}
Test-Step "db/clone-db-dev.ps1 exits cleanly with no databases configured" {
    Invoke-Guarded "db\clone-db-dev.ps1" "No databases configured"
}
Test-Step "db/clone-db-stg.ps1 exits cleanly with no databases configured" {
    Invoke-Guarded "db\clone-db-stg.ps1" "No databases configured"
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
Test-Step "redis/clone-redis-stg.ps1 exits cleanly with no stgHost configured" {
    Invoke-Guarded "redis\clone-redis-stg.ps1" "No redis.stgHost configured"
}
Test-Step "backend/stop.ps1 reports no tagged processes" {
    Invoke-Guarded "backend\stop.ps1" "No processes tagged"
}
Test-Step "common/pull-all.ps1 runs to completion against an empty reposRoot" {
    $full = Join-Path $testRoot "common\pull-all.ps1"
    & pwsh -NoProfile -File $full | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Exit code $LASTEXITCODE" }
}
Test-Step "common/open-vscode.ps1 exits cleanly with no services configured" {
    Invoke-Guarded "common\open-vscode.ps1" "No services configured"
}
Test-Step "common/open-vs.ps1 exits cleanly with no services configured" {
    Invoke-Guarded "common\open-vs.ps1" "No services configured"
}
Test-Step "android/start.ps1 exits cleanly with no android.emulatorPath configured" {
    Invoke-Guarded "android\start.ps1" "No android.emulatorPath configured"
}
Test-Step "android/start-default.ps1 exits cleanly with no android.emulatorPath configured" {
    Invoke-Guarded "android\start-default.ps1" "No android.emulatorPath configured"
}
Test-Step "android/stop.ps1 exits cleanly with no android.emulatorPath configured" {
    Invoke-Guarded "android\stop.ps1" "No android.emulatorPath configured"
}
Test-Step "android/set-location.ps1 exits cleanly with no android.emulatorPath configured" {
    Invoke-Guarded "android\set-location.ps1" "No android.emulatorPath configured"
}
Test-Step "android/install-latest-dev.ps1 exits cleanly with no android.emulatorPath configured" {
    Invoke-Guarded "android\install-latest-dev.ps1" "No android.emulatorPath configured"
}
Test-Step "android/install-latest-stg.ps1 exits cleanly with no android.emulatorPath configured" {
    Invoke-Guarded "android\install-latest-stg.ps1" "No android.emulatorPath configured"
}
foreach ($pmsScript in "start-dev", "update-dev", "install-dev") {
    Test-Step "pms/$pmsScript.ps1 exits cleanly with no pms.dev.root configured" {
        Invoke-Guarded "pms\$pmsScript.ps1" "No pms.dev.root configured"
    }
}
Test-Step "setup/doctor.ps1 runs and prints a report" {
    $output = & pwsh -NoProfile -File (Join-Path $testRoot "setup\doctor.ps1") 2>&1 | Out-String
    if ($output -notmatch "=== ztms doctor ===" -or $output -notmatch "\d+ OK, \d+ WARN, \d+ FAIL") { throw "Unexpected output:`n$output" }
}
Test-Step "setup/import.ps1 exits cleanly with a missing backup file" {
    $output = & pwsh -NoProfile -File (Join-Path $testRoot "setup\import.ps1") -Path (Join-Path $testRoot "nope.ztmsbak") 2>&1 | Out-String
    if ($LASTEXITCODE -ne 1 -or $output -notmatch "Backup file not found") { throw "Expected 'Backup file not found' + exit 1. Got ($LASTEXITCODE):`n$output" }
}
Test-Step "Backup.psm1 round-trips and rejects a wrong passphrase" {
    Import-Module (Join-Path $testRoot "modules\Backup.psm1") -Force
    $bytes = Protect-TmsBackup -PlainText '{"k":"giá trị"}' -Passphrase "correct horse"
    if ((Unprotect-TmsBackup -Data $bytes -Passphrase "correct horse") -ne '{"k":"giá trị"}') { throw "Round-trip mismatch" }
    $rejected = $false
    try { Unprotect-TmsBackup -Data $bytes -Passphrase "wrong" | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw "Wrong passphrase was accepted" }
}
Test-Step "Get-TmsUserEnvVars derives env var names from config" {
    Import-Module (Join-Path $testRoot "modules\TmsConfig.psm1") -Force
    $names = @(Get-TmsUserEnvVars -Config (Get-Content (Join-Path $testRoot "tms.config.json") -Raw | ConvertFrom-Json) | ForEach-Object Name)
    foreach ($expected in "TMS_LOCAL_DB_PASSWORD", "DEV_DB_PASSWORD", "STG_DB_PASSWORD", "DEV_REDIS_PW", "STG_REDIS_PW") {
        if ($names -notcontains $expected) { throw "Missing $expected (got: $($names -join ', '))" }
    }
}
Test-Step "Hotkey.psm1 parses hotkey strings and rejects bad ones" {
    Import-Module (Join-Path $testRoot "modules\Hotkey.psm1") -Force
    $hk = ConvertTo-TmsHotkey -Keys "ctrl+space"
    if ($hk.Vk -ne 0x20 -or ($hk.Modifiers -band 0xF) -ne 0x2 -or $hk.Display -ne "Ctrl+Space") { throw "ctrl+space -> $($hk | ConvertTo-Json -Compress)" }
    $hk = ConvertTo-TmsHotkey -Keys "Win+Shift+5"
    if ($hk.Vk -ne 0x35 -or ($hk.Modifiers -band 0xF) -ne 0xC) { throw "Win+Shift+5 -> $($hk | ConvertTo-Json -Compress)" }
    $hk = Get-TmsHotkey -Config ([PSCustomObject]@{})
    if ($hk.Display -ne "Ctrl+Space" -or $hk.WidthPercent -ne 50 -or $hk.HeightPercent -ne 80 -or $hk.SearchHeightPercent -ne 35) { throw "Missing hotkey section should default to Ctrl+Space 50x80 (search 35), got $($hk | ConvertTo-Json -Compress)" }
    if ($hk.FontSize -ne 14 -or $hk.Padding -ne 16 -or $hk.Opacity -ne 85 -or $hk.Acrylic) { throw "Missing hotkey section should default to font 14 / padding 16 / opacity 85 / no acrylic, got $($hk | ConvertTo-Json -Compress)" }
    $hk = Get-TmsHotkey -Config ([PSCustomObject]@{ hotkey = [PSCustomObject]@{ keys = "Alt+Q"; widthPercent = 5; heightPercent = 150; fontSize = 99; padding = 0 } })
    if ($hk.WidthPercent -ne 20 -or $hk.HeightPercent -ne 100) { throw "Window percents should clamp to 20..100, got $($hk | ConvertTo-Json -Compress)" }
    if ($hk.FontSize -ne 48 -or $hk.Padding -ne 0) { throw "fontSize should clamp to 48 and padding 0 should be kept, got $($hk | ConvertTo-Json -Compress)" }
    foreach ($bad in "Space", "Ctrl+Alt", "Ctrl+Nope", "Ctrl+A+B", "Ctrl+65") {
        $rejected = $false
        try { ConvertTo-TmsHotkey -Keys $bad | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw "'$bad' was accepted" }
    }
}
Test-Step "Every ztms menu entry has a Desc (it's what search matches on)" {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $testRoot "ztms.ps1"), [ref]$null, [ref]$null)
    $assign = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$groups' }, $true)
    $missing = @((Invoke-Expression $assign.Right.Extent.Text) | ForEach-Object { $_.Entries } | Where-Object { [string]::IsNullOrWhiteSpace($_.Desc) } | ForEach-Object Path)
    if ($missing.Count -gt 0) { throw "No Desc: $($missing -join ', ')" }
}
Test-Step "MenuSearch.psm1 finds entries by meaning (synonyms, Vietnamese, no accents needed)" {
    Import-Module (Join-Path $testRoot "modules\MenuSearch.psm1") -Force
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $testRoot "ztms.ps1"), [ref]$null, [ref]$null)
    $assign = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$groups' }, $true)
    $menuGroups = Invoke-Expression $assign.Right.Extent.Text
    $expectTop = [ordered]@{
        "tắt service"              = "backend\stop.ps1"
        "TAT SERVICE"              = "backend\stop.ps1"
        "kéo db dev"               = "db\clone-db-dev.ps1"
        "database staging offline" = "db\restore-db-stg.ps1"
        "khởi động lại proxy"      = "httptoolkit\restart.ps1"
        "toạ độ bưu cục"           = "android\set-location.ps1"
        "kiểm tra"                 = "setup\doctor.ps1"
        "nhánh"                    = "common\checkout-branch.ps1"
        "pul"                      = "common\pull-all.ps1"
        "git pull"                 = "common\pull-all.ps1"
        "pull db stg"              = "db\clone-db-stg.ps1"
        "pull redis"               = "redis\clone-redis-dev.ps1"
    }
    foreach ($q in $expectTop.Keys) {
        $top = @(Find-MenuEntries -Groups $menuGroups -Query $q)[0]
        if (-not $top -or $top.Entry.Path -ne $expectTop[$q]) { throw "'$q' -> $(if ($top) { $top.Entry.Path } else { 'nothing' }), expected $($expectTop[$q])" }
    }
    # the hotkey window's per-service "VS CODE" entries (same shape ztms.ps1 builds with --spotlight)
    $vsGroups = @($menuGroups) + [ordered]@{ Name = "VS CODE"; Entries = @(
        foreach ($svc in "TMS.OrderService", "tms.fleetservice", "TMS.RouteService") { [ordered]@{ DisplayName = $svc; Path = "common\open-vscode.ps1"; Args = @("-Service", $svc); Quick = $true; Desc = "Open the $svc repo in VS Code" } }
    ) }
    $vsGroups += [ordered]@{ Name = "VISUAL STUDIO"; Entries = @(
        foreach ($svc in "TMS.OrderService", "tms.fleetservice", "TMS.RouteService") { [ordered]@{ DisplayName = $svc; Path = "common\open-vs.ps1"; Args = @("-Service", $svc); Quick = $true; Desc = "Open the $svc solution in Visual Studio" } }
    ) }
    $expectGroup = [ordered]@{
        "order code" = "VS CODE"; "vs code order" = "VS CODE"; "order vs code" = "VS CODE"; "vscode order" = "VS CODE"; "mở order bằng vs code" = "VS CODE"
        "order vs" = "VISUAL STUDIO"; "vs order" = "VISUAL STUDIO"; "order visual studio" = "VISUAL STUDIO"; "order sln" = "VISUAL STUDIO"
    }
    foreach ($q in $expectGroup.Keys) {
        $top = @(Find-MenuEntries -Groups $vsGroups -Query $q)[0]
        if (-not $top -or $top.Entry.DisplayName -ne "TMS.OrderService" -or $top.Group -ne $expectGroup[$q] -or $top.Partial) { throw "'$q' -> $(if ($top) { "$($top.Group) $($top.Entry.DisplayName)" } else { 'nothing' }), expected $($expectGroup[$q]) TMS.OrderService" }
    }
    if (@(Find-MenuEntries -Groups $menuGroups -Query "zzzq").Count -ne 0) { throw "'zzzq' should match nothing" }
    if (@(Find-MenuEntries -Groups $menuGroups -Query "").Count -ne @($menuGroups | ForEach-Object { $_.Entries }).Count) { throw "Empty query should return every entry" }
}
Test-Step "ztms.ps1 suggests matches for an unknown target" {
    $output = & pwsh -NoProfile -File (Join-Path $testRoot "ztms.ps1") tat service 2>&1 | Out-String
    if ($LASTEXITCODE -ne 1 -or $output -notmatch "Did you mean:\s+backend stop-all") { throw "Expected 'Did you mean: backend stop-all' + exit 1. Got ($LASTEXITCODE):`n$output" }
}
foreach ($htkScript in "start", "stop", "restart", "build", "install") {
    Test-Step "httptoolkit/$htkScript.ps1 exits cleanly with no httptoolkit.repoPath configured" {
        Invoke-Guarded "httptoolkit\$htkScript.ps1" "No httptoolkit.repoPath configured"
    }
}
Test-Step "ztms.ps1 hides HTTPTOOLKIT and PMS entries when not configured" {
    $output = & pwsh -NoProfile -File (Join-Path $testRoot "ztms.ps1") nope/nope 2>&1 | Out-String
    if ($output -match "(?m)^\s+(httptoolkit|pms) ") { throw "Expected no httptoolkit/pms entries. Got:`n$output" }
}
Test-Step "ztms.ps1 --spotlight doesn't count as a direct-run target" {
    $output = & pwsh -NoProfile -File (Join-Path $testRoot "ztms.ps1") --spotlight nope/nope 2>&1 | Out-String
    if ($LASTEXITCODE -ne 1 -or $output -notmatch "Unknown script: nope/nope\r?\n") { throw "Expected 'Unknown script: nope/nope' (flag stripped) + exit 1. Got ($LASTEXITCODE):`n$output" }
}
Test-Step "ztms.ps1 rejects an unknown direct-run target" {
    $output = & pwsh -NoProfile -File (Join-Path $testRoot "ztms.ps1") nope/nope 2>&1 | Out-String
    if ($LASTEXITCODE -ne 1 -or $output -notmatch "Unknown script") { throw "Expected 'Unknown script' + exit 1. Got ($LASTEXITCODE):`n$output" }
}

# --- 5. Cleanup --------------------------------------------------------------
Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue

# --- Summary ------------------------------------------------------------
Write-Host "`n=== Summary ===" -ForegroundColor Magenta
$pass = @($results | Where-Object Status -eq "PASS").Count
$fail = @($results | Where-Object Status -eq "FAIL").Count
Write-Host "$pass passed, $fail failed" -ForegroundColor $(if ($fail -gt 0) { "Red" } else { "Green" })
if ($fail -gt 0) { exit 1 }
