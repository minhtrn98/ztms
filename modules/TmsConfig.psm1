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

function Get-TmsEnvFilePath {
    Join-Path (Split-Path $PSScriptRoot -Parent) "tms.env.local"
}

function Read-TmsEnvFile {
    <#
    Parses a KEY=VALUE env file (tms.env.local format) into an ordered hashtable.
    Blank lines and # comments are skipped; values may be wrapped in quotes.
    #>
    param([Parameter(Mandatory)][string]$Path)

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

function Get-TmsUserEnvVars {
    <#
    Every user-level environment variable this toolkit reads, derived from
    config rather than hardcoded so a new *PasswordEnvVar or tms.env.local key
    is picked up automatically by setup\doctor / export / import:
      - Secrets: every database.*PasswordEnvVar / redis.*PasswordEnvVar, plus
        pms.dev.passwordEnvVar.
      - Service runtime vars: every key in tms.env.local (if present).
    Returns objects { Name, Source, Kind } where Kind is 'secret' or 'runtime'.
    #>
    param($Config)

    $vars = [ordered]@{}
    if ($Config) {
        foreach ($section in @("database", "redis")) {
            $s = $Config.$section
            if (-not $s) { continue }
            foreach ($p in $s.PSObject.Properties) {
                if ($p.Name -like "*PasswordEnvVar" -and -not [string]::IsNullOrWhiteSpace($p.Value) -and -not $vars.Contains($p.Value)) {
                    $vars[$p.Value] = [PSCustomObject]@{ Name = $p.Value; Source = "$section.$($p.Name)"; Kind = "secret" }
                }
            }
        }
        $pmsVar = if ($Config.pms -and $Config.pms.dev) { $Config.pms.dev.passwordEnvVar }
        if (-not [string]::IsNullOrWhiteSpace($pmsVar) -and -not $vars.Contains($pmsVar)) {
            $vars[$pmsVar] = [PSCustomObject]@{ Name = $pmsVar; Source = "pms.dev.passwordEnvVar"; Kind = "secret" }
        }
    }

    $envFile = Get-TmsEnvFilePath
    if (Test-Path $envFile) {
        foreach ($key in (Read-TmsEnvFile -Path $envFile).Keys) {
            if (-not $vars.Contains($key)) {
                $vars[$key] = [PSCustomObject]@{ Name = $key; Source = "tms.env.local"; Kind = "runtime" }
            }
        }
    }

    return @($vars.Values)
}

Export-ModuleMember -Function Get-TmsConfigPath, Get-TmsConfig, Get-TmsSecret, Get-TmsEnvFilePath, Read-TmsEnvFile, Get-TmsUserEnvVars
