# Shared helpers for the custom HTTP Toolkit fork (httptoolkit\*.ps1 and
# setup\doctor.ps1). The fork's scripts\release.ps1 (also exposed as the
# `htk` command via scripts\htk.cmd) builds the UI, deploys it + the server
# runtime to a deployment folder, and runs it hidden on http://localhost:8080.
#
# Reads httptoolkit.{repoPath,gitUrl,branch,deployDir} from tms.config.json.

function Get-TmsHttpToolkitConfig {
    <#
    Guard-checks httptoolkit.repoPath and returns the section with defaults.
    Exits the calling script (exit 1) when it isn't configured.
    #>
    param([Parameter(Mandatory)]$Config)

    $h = $Config.httptoolkit
    if (-not $h -or [string]::IsNullOrWhiteSpace($h.repoPath)) {
        Write-Host "No httptoolkit.repoPath configured. Edit tms.config.json (add an 'httptoolkit' section) — see tms.config.example.json." -ForegroundColor Red
        exit 1
    }

    [PSCustomObject]@{
        RepoPath   = $h.repoPath
        GitUrl     = $h.gitUrl
        Branch     = $h.branch
        DeployDir  = $h.deployDir
        ScriptsDir = Join-Path $h.repoPath "scripts"
        Release    = Join-Path $h.repoPath "scripts\release.ps1"
    }
}

function Invoke-TmsHttpToolkit {
    # Runs the fork's release.ps1 <Action> straight from the configured repo
    # (no reliance on `htk` being on PATH in this process).
    param(
        [Parameter(Mandatory)]$Htk,
        [Parameter(Mandatory)][ValidateSet("start", "stop", "restart", "build", "status")][string]$Action
    )

    if (-not (Test-Path -LiteralPath $Htk.Release)) {
        Write-Host "release.ps1 not found at $($Htk.Release). Run HTTPTOOLKIT > install first." -ForegroundColor Red
        exit 1
    }
    if ($Htk.DeployDir) { $env:HTK_DEPLOY_DIR = $Htk.DeployDir }

    Write-Host "-> " -ForegroundColor Green -NoNewline
    Write-Host "Running: " -ForegroundColor White -NoNewline
    Write-Host "htk $Action" -ForegroundColor Cyan

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $Htk.Release $Action
    if ($LASTEXITCODE -ne 0) {
        Write-Host "htk $Action failed (exit code $LASTEXITCODE)." -ForegroundColor Red
        exit $LASTEXITCODE
    }

    Write-Host "`nDONE" -ForegroundColor Magenta
}

function Test-TmsUserPathContains {
    param([Parameter(Mandatory)][string]$Dir)
    $userPath = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment").GetValue("Path", "", "DoNotExpandEnvironmentNames")
    $target = $Dir.TrimEnd('\')
    return [bool](($userPath -split ';') | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ieq $target })
}

function Add-TmsUserPath {
    <#
    Appends a folder to the user-level PATH if missing. Writes the registry
    value directly as REG_EXPAND_SZ (Environment.SetEnvironmentVariable would
    rewrite it as REG_SZ and break entries like %USERPROFILE%\...), then
    broadcasts WM_SETTINGCHANGE so newly opened terminals pick it up.
    #>
    param([Parameter(Mandatory)][string]$Dir)

    if (Test-TmsUserPathContains -Dir $Dir) { return $false }

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
    try {
        $current = $key.GetValue("Path", "", "DoNotExpandEnvironmentNames")
        $new = if ([string]::IsNullOrEmpty($current)) { $Dir } else { "$($current.TrimEnd(';'));$Dir" }
        $key.SetValue("Path", $new, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally { $key.Close() }

    if (-not ("TmsNative.Env" -as [type])) {
        Add-Type -Namespace TmsNative -Name Env -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    [void][TmsNative.Env]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result)

    $env:Path = "$($env:Path.TrimEnd(';'));$Dir"
    return $true
}

function Install-TmsHttpToolkit {
    <#
    One-shot setup of the custom HTTP Toolkit fork:
      1. Clone httptoolkit.gitUrl into repoPath if it isn't there yet.
      2. git fetch, then check out httptoolkit.branch (or fast-forward it if
         already on it). Never forces: a dirty working tree is reported and
         left alone rather than losing work.
      3. Add <repo>\scripts to the user PATH so `htk` works in any terminal;
         persist HTK_DEPLOY_DIR if httptoolkit.deployDir is set.
      4. `htk build`: npm install (first time), build, deploy, start.
    Safe to re-run.
    #>
    param([Parameter(Mandatory)]$Htk)

    # --- Prerequisites ---
    foreach ($tool in "git", "node", "npm") {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            Write-Host "'$tool' not found on PATH — install it first (Node.js >= 20 for node/npm)." -ForegroundColor Red
            exit 1
        }
    }
    $nodeMajor = [int]((node --version).TrimStart('v').Split('.')[0])
    if ($nodeMajor -lt 20) {
        Write-Host "Node.js $(node --version) is too old — the HTTP Toolkit UI needs Node >= 20." -ForegroundColor Red
        exit 1
    }

    # --- Clone ---
    $repo = $Htk.RepoPath
    if (-not (Test-Path -LiteralPath (Join-Path $repo ".git"))) {
        if ((Test-Path -LiteralPath $repo) -and (Get-ChildItem -LiteralPath $repo -Force | Select-Object -First 1)) {
            Write-Host "$repo exists but isn't a git repo — point httptoolkit.repoPath at your clone, or clear that folder." -ForegroundColor Red
            exit 1
        }
        if ([string]::IsNullOrWhiteSpace($Htk.GitUrl)) {
            Write-Host "No clone at $repo and no httptoolkit.gitUrl configured to clone from." -ForegroundColor Red
            exit 1
        }
        Write-Host "Cloning $($Htk.GitUrl) into $repo ..." -ForegroundColor Cyan
        git clone $Htk.GitUrl $repo
        if ($LASTEXITCODE -ne 0) { Write-Host "git clone failed." -ForegroundColor Red; exit 1 }
    }

    # --- Branch ---
    git -C $repo fetch origin --prune
    if ($LASTEXITCODE -ne 0) { Write-Host "git fetch failed." -ForegroundColor Red; exit 1 }
    $current = git -C $repo branch --show-current
    $dirty = [bool](git -C $repo status --porcelain)
    if ($Htk.Branch -and $current -ne $Htk.Branch) {
        if ($dirty) {
            Write-Host "$repo has uncommitted changes on '$current' — commit or stash them, then re-run to switch to '$($Htk.Branch)'." -ForegroundColor Red
            exit 1
        }
        Write-Host "Checking out $($Htk.Branch) ..." -ForegroundColor Cyan
        git -C $repo checkout $Htk.Branch
        if ($LASTEXITCODE -ne 0) { Write-Host "git checkout $($Htk.Branch) failed." -ForegroundColor Red; exit 1 }
    } elseif ($dirty) {
        Write-Host "Uncommitted changes in $repo — skipping git pull, building what's there." -ForegroundColor Yellow
    } else {
        git -C $repo pull --ff-only
        if ($LASTEXITCODE -ne 0) { Write-Host "git pull --ff-only failed (branch diverged?) — building what's there." -ForegroundColor Yellow }
    }
    Write-Host "Branch: $(git -C $repo branch --show-current) @ $(git -C $repo log -1 --format='%h %s')" -ForegroundColor Gray

    # --- PATH + env ---
    if (Add-TmsUserPath -Dir $Htk.ScriptsDir) { Write-Host "Added $($Htk.ScriptsDir) to user PATH — open a new terminal to use 'htk'." -ForegroundColor Green }
    else { Write-Host "$($Htk.ScriptsDir) already on user PATH." -ForegroundColor Gray }
    if ($Htk.DeployDir) {
        [Environment]::SetEnvironmentVariable("HTK_DEPLOY_DIR", $Htk.DeployDir, "User")
        Write-Host "HTK_DEPLOY_DIR = $($Htk.DeployDir) (user env)" -ForegroundColor Green
    }

    # --- Release ---
    Invoke-TmsHttpToolkit -Htk $Htk -Action build
}

function Get-TmsHttpToolkitStatus {
    # Rows for setup\doctor.ps1: { Name, Status (OK/WARN/FAIL), Detail }.
    param([Parameter(Mandatory)]$Htk)

    $fix = "run HTTPTOOLKIT > install"
    $rows = @()
    if (-not (Test-Path -LiteralPath (Join-Path $Htk.RepoPath ".git"))) {
        return @([PSCustomObject]@{ Name = "htk repo"; Status = "WARN"; Detail = "no clone at $($Htk.RepoPath) — $fix" })
    }
    $branch = git -C $Htk.RepoPath branch --show-current
    $rows += if (-not $Htk.Branch -or $branch -eq $Htk.Branch) { [PSCustomObject]@{ Name = "htk repo"; Status = "OK"; Detail = "$($Htk.RepoPath) ($branch)" } }
             else { [PSCustomObject]@{ Name = "htk repo"; Status = "WARN"; Detail = "on '$branch', expected '$($Htk.Branch)' — $fix" } }

    $rows += if (Test-TmsUserPathContains -Dir $Htk.ScriptsDir) { [PSCustomObject]@{ Name = "htk on PATH"; Status = "OK"; Detail = $Htk.ScriptsDir } }
             else { [PSCustomObject]@{ Name = "htk on PATH"; Status = "WARN"; Detail = "$($Htk.ScriptsDir) not in user PATH — $fix" } }

    $deployDir = if ($Htk.DeployDir) { $Htk.DeployDir } elseif ($env:HTK_DEPLOY_DIR) { $env:HTK_DEPLOY_DIR } else { "D:\Deployments\custom-http-toolkit" }
    $rows += if (Test-Path -LiteralPath (Join-Path $deployDir "ui\index.html")) { [PSCustomObject]@{ Name = "htk release"; Status = "OK"; Detail = $deployDir } }
             else { [PSCustomObject]@{ Name = "htk release"; Status = "WARN"; Detail = "nothing deployed in $deployDir — $fix" } }
    return $rows
}

Export-ModuleMember -Function Get-TmsHttpToolkitConfig, Invoke-TmsHttpToolkit, Install-TmsHttpToolkit, Get-TmsHttpToolkitStatus