# ======================================
# Export this machine's ztms setup into one passphrase-encrypted file, to
# restore on another machine with setup\import.ps1:
#   - tms.config.json
#   - tms.env.local (if present)
#   - the user-level values of every env var ztms reads (DB/Redis/PMS
#     secrets + tms.env.local keys — see Get-TmsUserEnvVars)
# The file holds secrets: keep it off git/chat, delete it after importing.
# ======================================

param([string]$OutFile)

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Backup.psm1") -Force

$configPath = Get-TmsConfigPath
if (-not (Test-Path $configPath)) {
    Write-Host "No tms.config.json found at $configPath — nothing to export. Run setup\init-config.ps1 first." -ForegroundColor Red
    exit 1
}

$config = Get-TmsConfig
$envFile = Get-TmsEnvFilePath

$userEnv = [ordered]@{}
$unset = @()
foreach ($v in Get-TmsUserEnvVars -Config $config) {
    $value = [Environment]::GetEnvironmentVariable($v.Name, "User")
    if ($null -ne $value) { $userEnv[$v.Name] = $value } else { $unset += $v.Name }
}

$payload = [ordered]@{
    format    = "ztms-backup"
    version   = 1
    createdAt = (Get-Date).ToString("o")
    machine   = $env:COMPUTERNAME
    config    = Get-Content $configPath -Raw
    envFile   = if (Test-Path $envFile) { Get-Content $envFile -Raw } else { $null }
    userEnv   = $userEnv
}

Write-Host "=== Export ztms setup ===" -ForegroundColor Magenta
Write-Host "  tms.config.json" -ForegroundColor Gray
Write-Host "  tms.env.local: $(if ($payload.envFile) { 'yes' } else { 'not present' })" -ForegroundColor Gray
Write-Host "  user env vars: $($userEnv.Count) ($($userEnv.Keys -join ', '))" -ForegroundColor Gray
if ($unset.Count -gt 0) {
    Write-Host "  not set here, skipped: $($unset -join ', ')" -ForegroundColor DarkYellow
}
Write-Host

if (-not $OutFile) {
    $default = Join-Path ([Environment]::GetFolderPath("Desktop")) "ztms-backup-$(Get-Date -Format yyyyMMdd).ztmsbak"
    Write-Host "Save to " -ForegroundColor Cyan -NoNewline
    Write-Host "(Default: $default): " -ForegroundColor DarkGray -NoNewline
    $OutFile = (Read-Host).Trim('"', ' ')
    if ([string]::IsNullOrWhiteSpace($OutFile)) { $OutFile = $default }
}

$passphrase = Read-TmsPassphrase -Prompt "Choose a passphrase (you'll need it to import)" -Confirm
$bytes = Protect-TmsBackup -PlainText ($payload | ConvertTo-Json -Depth 5) -Passphrase $passphrase
[IO.File]::WriteAllBytes($OutFile, $bytes)

Write-Host "`nSaved: $OutFile" -ForegroundColor Green
Write-Host "It contains secrets — copy it to the new machine directly (USB / private share), then delete it." -ForegroundColor Yellow
Write-Host "On the new machine: install ztms, then run SETUP > import." -ForegroundColor Gray

Write-Host "`n🎉 DONE" -ForegroundColor Magenta
