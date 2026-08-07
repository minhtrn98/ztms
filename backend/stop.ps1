# ======================================
# Stop all running processes tagged with config.processTag
# Reads processTag from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig
$tag = $config.processTag

# One Win32_Process snapshot for everything below. Get-CimInstance
# Win32_Process is consistently 3-5s+ on this kind of machine no matter how
# it's filtered/scoped (measured: filtered by name, scoped to a handful of
# PIDs, cached CimSession — all ~3.5s), so there's nothing to gain from
# querying it more than once. We also need the full table (not just cmd.exe)
# to build the parent/child map used for tree-killing below.
$allProcs = Get-CimInstance Win32_Process

# Match by command line, not window title: cmd.exe is launched with
# "/k Title [$tag] ..." (see backend/run.ps1 / backend/run-published.ps1), and
# that whole argument string — including the tag — is part of cmd.exe's own
# CommandLine, regardless of whether it opened its own console window or is
# hosted as a tab inside Windows Terminal / VS Code (in that case cmd.exe has
# no MainWindowHandle of its own, so MainWindowTitle is always empty even
# though the process is very much alive).
#
# Match the literal "Title [$tag]" (brackets included), not a bare "*$tag*"
# substring — a bare substring also matches unrelated cmd.exe processes whose
# command line happens to contain the tag text anywhere (e.g. the "ztms.cmd"
# shim itself when tag is "tms"), which would stop windows that have nothing
# to do with this stack. Square brackets are -like wildcard metacharacters,
# so they're backtick-escaped to match them literally.
$taggedCmdProcs = @($allProcs | Where-Object { $_.Name -eq 'cmd.exe' -and $_.CommandLine -like "*Title ``[$tag``]*" })

if ($taggedCmdProcs.Count -eq 0) {
    Write-Host "No processes tagged '$tag' found." -ForegroundColor DarkGreen
    return
}

$taggedCmdProcs | ForEach-Object {
    Write-Host "Stopping [$($_.ProcessId)] $($_.CommandLine)" -ForegroundColor Yellow
}

# Kill the whole process tree (cmd.exe plus the dotnet/app.exe it launched)
# ourselves instead of shelling out to `taskkill /T` per process: taskkill.exe
# is itself a brand-new process per call, and on this machine that alone
# costs ~3.5s *per invocation* (measured, independent of whether the target
# PID exists) — with several tagged services that dwarfs the CIM query
# above. Stop-Process kills by PID in-process (no subprocess spawn), so we
# just need to resolve descendants ourselves from the snapshot already taken.
$byParent = @{}
foreach ($p in $allProcs) {
    if (-not $byParent.ContainsKey($p.ParentProcessId)) { $byParent[$p.ParentProcessId] = @() }
    $byParent[$p.ParentProcessId] += $p.ProcessId
}

function Get-DescendantProcessIds {
    param([uint32]$RootId, [hashtable]$ByParent)
    $result = @()
    $queue = [System.Collections.Generic.Queue[uint32]]::new()
    $queue.Enqueue($RootId)
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        foreach ($childId in $ByParent[$current]) {
            $result += $childId
            $queue.Enqueue($childId)
        }
    }
    return $result
}

$pidsToKill = @()
foreach ($proc in $taggedCmdProcs) {
    $pidsToKill += $proc.ProcessId
    $pidsToKill += (Get-DescendantProcessIds -RootId $proc.ProcessId -ByParent $byParent)
}

$pidsToKill | Select-Object -Unique | ForEach-Object {
    Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
}

Write-Host "Stopped $($taggedCmdProcs.Count) process tree(s)." -ForegroundColor Green
