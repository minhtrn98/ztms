# ======================================
# Installs a global `ztms` command (works from cmd.exe, PowerShell, or pwsh,
# from any directory) that opens the TMS scripts menu (ztms.ps1).
#
# Mechanism: drops a tiny ztms.cmd shim into
#   %LocalAppData%\Microsoft\WindowsApps
# — a per-user folder that's on PATH by default on Windows 10/11 (the same
# mechanism winget/uv/etc. use for user-scoped commands). No admin rights,
# no PATH edits needed. To uninstall: delete that one file.
# ======================================

$ztmsScript = Join-Path $PSScriptRoot "ztms.ps1"

if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Write-Host "pwsh (PowerShell 7+) not found on PATH. Install it first: https://aka.ms/powershell" -ForegroundColor Red
    exit 1
}

$shimDir = Join-Path $env:LocalAppData "Microsoft\WindowsApps"
if (-not (Test-Path $shimDir)) {
    Write-Host "$shimDir not found — this expects a standard per-user Windows 10/11 setup." -ForegroundColor Red
    Write-Host "You can still run the menu directly: .\ztms.ps1" -ForegroundColor Yellow
    exit 1
}

$shimPath = Join-Path $shimDir "ztms.cmd"
@(
    "@echo off"
    "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$ztmsScript`" %*"
) | Set-Content -Path $shimPath -Encoding ASCII

Write-Host "Installed 'ztms' -> $shimPath" -ForegroundColor Green
Write-Host "It launches: $ztmsScript" -ForegroundColor Gray

$onPath = ($env:PATH -split ';') -contains $shimDir
if ($onPath) {
    Write-Host "`nOpen a NEW terminal (cmd, PowerShell, or pwsh) anywhere and type: ztms" -ForegroundColor Cyan
} else {
    Write-Host "`n$shimDir isn't on PATH for this session (it normally is, by default, for Windows user accounts)." -ForegroundColor Yellow
    Write-Host "Open a NEW terminal and try 'ztms' — if it still isn't found, add that folder to your user PATH." -ForegroundColor Yellow
}
