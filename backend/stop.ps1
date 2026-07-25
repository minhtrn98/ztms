# ======================================
# Stop all running processes tagged with config.processTag
# Reads processTag from tms.config.json — run 900_init-config.ps1 first.
# ======================================

Import-Module (Join-Path $PSScriptRoot "modules\TmsConfig.psm1") -Force

$config = Get-TmsConfig
$tag = $config.processTag

# Match by command line, not window title: cmd.exe is launched with
# "/k Title [$tag] ..." (see 001_run-services.ps1 / 002_run-published.ps1), and
# that whole argument string — including the tag — is part of cmd.exe's own
# CommandLine, regardless of whether it opened its own console window or is
# hosted as a tab inside Windows Terminal / VS Code (in that case cmd.exe has
# no MainWindowHandle of its own, so MainWindowTitle is always empty even
# though the process is very much alive).
$taggedCmdProcs = Get-CimInstance Win32_Process -Filter "name = 'cmd.exe'" |
    Where-Object { $_.CommandLine -like "*$tag*" }

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
