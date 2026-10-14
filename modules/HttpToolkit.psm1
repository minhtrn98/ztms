# Shared HTTP Toolkit helper: thin wrapper around the `htk` CLI, used by
# httptoolkit/start.ps1, stop.ps1 and restart.ps1.

function Invoke-TmsHttpToolkit {
    param([Parameter(Mandatory)][ValidateSet("start", "stop", "restart")][string]$Action)

    $htk = Get-Command htk -ErrorAction SilentlyContinue
    if (-not $htk) {
        Write-Host "'htk' command not found on PATH. Install the HTTP Toolkit CLI first." -ForegroundColor Red
        exit 1
    }

    Write-Host "-> " -ForegroundColor Green -NoNewline
    Write-Host "Running: " -ForegroundColor White -NoNewline
    Write-Host "htk $Action" -ForegroundColor Cyan

    & $htk.Source $Action
    if ($LASTEXITCODE -ne 0) {
        Write-Host "htk $Action failed (exit code $LASTEXITCODE)." -ForegroundColor Red
        exit $LASTEXITCODE
    }

    Write-Host "`nDONE" -ForegroundColor Magenta
}

Export-ModuleMember -Function Invoke-TmsHttpToolkit
