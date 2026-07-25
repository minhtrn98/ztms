# ======================================
# Load runtime env vars for services (Redis/Kafka/RabbitMq/JWT keys/etc.)
# from tms.env.local into this session, and optionally persist them at the
# Windows user level so future terminals inherit them automatically.
#
# Run this BEFORE 001_run-services.ps1 / 002_run-published.ps1 in the same
# terminal — child processes only inherit env vars set in THIS session,
# unless you choose to persist them (see prompt below).
# ======================================

Import-Module (Join-Path $PSScriptRoot "modules\ProjectMenu.psm1") -Force

$envFile = Join-Path $PSScriptRoot "tms.env.local"
$exampleFile = Join-Path $PSScriptRoot "tms.env.example"

if (-not (Test-Path $envFile)) {
    Write-Host "tms.env.local not found." -ForegroundColor Yellow
    if (Confirm-Prompt -Message "Create it now from tms.env.example?" -DefaultYes $true) {
        Copy-Item $exampleFile $envFile
        Write-Host "Created $envFile — edit it with your real values, then re-run this script." -ForegroundColor Green
    }
    exit 0
}

function Parse-EnvFile {
    param([string]$Path)

    $pairs = [ordered]@{}
    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }

        $idx = $trimmed.IndexOf('=')
        if ($idx -lt 1) { continue }

        $key = $trimmed.Substring(0, $idx).Trim()
        $value = $trimmed.Substring($idx + 1).Trim()
        if ($value.Length -ge 2 -and (
            ($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))
        )) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $pairs[$key] = $value
    }
    return $pairs
}

$pairs = Parse-EnvFile -Path $envFile
if ($pairs.Count -eq 0) {
    Write-Host "No key=value entries found in $envFile" -ForegroundColor Yellow
    exit 0
}

foreach ($key in $pairs.Keys) {
    [System.Environment]::SetEnvironmentVariable($key, $pairs[$key], "Process")
}
Write-Host "Set $($pairs.Count) env var(s) for this session:" -ForegroundColor Green
$pairs.Keys | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

Write-Host
if (Confirm-Prompt -Message "Also persist these at the Windows user level (so new terminals get them automatically)?" -DefaultYes $false) {
    foreach ($key in $pairs.Keys) {
        [System.Environment]::SetEnvironmentVariable($key, $pairs[$key], "User")
    }
    Write-Host "Persisted for user '$env:USERNAME' — open a new terminal for it to apply there." -ForegroundColor Green
}
