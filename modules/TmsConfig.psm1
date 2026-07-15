# Shared config/secret loading for the generalized TMS scripts.
# Config lives at tms.config.json in the repo root (gitignored, created by 900_init-config.ps1).

function Get-TmsConfigPath {
    Join-Path (Split-Path $PSScriptRoot -Parent) "tms.config.json"
}

function Get-TmsConfig {
    $configPath = Get-TmsConfigPath
    if (-not (Test-Path $configPath)) {
        throw "Config not found at $configPath. Run '.\900_init-config.ps1' first to create it."
    }
    Get-Content $configPath -Raw | ConvertFrom-Json
}

function Get-TmsSecret {
    <#
    Reads a secret from a user-level environment variable. If unset, prompts
    (hidden input) and sets it for the current process so child scripts inherit it.
    -Default supplies a non-interactive fallback for low-sensitivity values
    (e.g. a local-only docker password) instead of prompting.
    #>
    param(
        [Parameter(Mandatory)][string]$EnvVarName,
        [Parameter(Mandatory)][string]$PromptMessage,
        [string]$Default
    )

    $value = [System.Environment]::GetEnvironmentVariable($EnvVarName, "User")
    if (-not [string]::IsNullOrEmpty($value)) { return $value }

    if ($Default) {
        return $Default
    }

    Write-Host "Environment variable '$EnvVarName' not set." -ForegroundColor Yellow
    $secure = Read-Host $PromptMessage -AsSecureString
    $value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    )
    [System.Environment]::SetEnvironmentVariable($EnvVarName, $value, "Process")
    return $value
}

Export-ModuleMember -Function Get-TmsConfigPath, Get-TmsConfig, Get-TmsSecret
