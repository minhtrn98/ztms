# ======================================
# Stop all running processes tagged with config.processTag
# Reads processTag from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig
$tag = $config.processTag

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
$taggedCmdProcs = Get-CimInstance Win32_Process -Filter "name = 'cmd.exe'" |
    Where-Object { $_.CommandLine -like "*Title ``[$tag``]*" }

if ($taggedCmdProcs.Count -eq 0) {
    Write-Host "No processes tagged '$tag' found." -ForegroundColor DarkGreen
    return
}

$taggedCmdProcs | ForEach-Object {
    Write-Host "Stopping [$($_.ProcessId)] $($_.CommandLine)" -ForegroundColor Yellow
}

# taskkill /T kills the whole process tree (cmd.exe plus the dotnet/app.exe it
# launched) directly by PID — no window to close, so this works the same way
# whether cmd.exe has its own window or is a Windows Terminal/VS Code tab.
$taggedCmdProcs | ForEach-Object {
    taskkill /PID $_.ProcessId /T /F 2>$null | Out-Null
}

Write-Host "Stopped $($taggedCmdProcs.Count) process tree(s)." -ForegroundColor Green
