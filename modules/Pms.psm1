# Shared PMS (Postal Management System) DEV helpers, used by pms\*.ps1 and
# setup\doctor.ps1. The PMS desktop app updates itself into a new
# <pms.dev.root>\<x.y.z> folder per version, which leaves fixed shortcuts
# pointing at stale builds — so everything here resolves "the newest version
# folder that has PMS.exe" at run time instead.
#
# Reads pms.dev.{root,updateUrl,product,passwordEnvVar} from tms.config.json.

$script:PmsTaskName = "PMS Dev Auto Update"
$script:PmsShortcutName = "PMS Dev.lnk"
$script:PmsKeepVersions = 2
$script:PmsModulePath = $PSCommandPath

function Get-TmsPmsDevConfig {
    <#
    Guard-checks pms.dev and returns it with defaults applied. Exits the
    calling script (exit 1) when pms.dev.root isn't configured, matching the
    other modules' guard-clause pattern.
    #>
    param([Parameter(Mandatory)]$Config)

    $pms = if ($Config.pms) { $Config.pms.dev }
    if (-not $pms -or [string]::IsNullOrWhiteSpace($pms.root)) {
        Write-Host "No pms.dev.root configured. Edit tms.config.json (add a 'pms' section) — see tms.config.example.json." -ForegroundColor Red
        exit 1
    }

    [PSCustomObject]@{
        Root           = $pms.root
        UpdateUrl      = if ($pms.updateUrl) { $pms.updateUrl.TrimEnd('/') } else { $null }
        Product        = if ($pms.product) { $pms.product } else { "PMSx64" }
        PasswordEnvVar = $pms.passwordEnvVar
    }
}

function Get-TmsPmsLatestInstalled {
    # Newest <Root>\<x.y.z> folder that actually contains PMS.exe (the app
    # leaves emptied folders behind for old versions), or $null.
    param([Parameter(Mandatory)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) { return $null }
    Get-ChildItem -LiteralPath $Root -Directory |
        Where-Object { $_.Name -as [version] } |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "PMS.exe") } |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
}

function Start-TmsPmsLatest {
    <#
    Launches the newest installed build (StartPMS.exe if present, else
    PMS.exe), then copies the login password from the user-level env var
    named by pms.dev.passwordEnvVar to the clipboard, if set, and starts a
    hidden background pwsh (Invoke-TmsPmsLoginAutofill) that types it into
    the login form once that appears.
    #>
    param([Parameter(Mandatory)]$Pms)

    $latest = Get-TmsPmsLatestInstalled -Root $Pms.Root
    if (-not $latest) {
        Write-Host "No PMS build found under $($Pms.Root). Run PMS > [dev] update first." -ForegroundColor Red
        exit 1
    }

    $exe = Join-Path $latest.FullName "StartPMS.exe"
    if (-not (Test-Path -LiteralPath $exe)) { $exe = Join-Path $latest.FullName "PMS.exe" }

    # PMS is single-instance (mutex PMS.Singleton.<Environment>): if one is
    # already running, the new one exits silently — no login form to fill.
    $alreadyRunning = Get-Process PMS -ErrorAction SilentlyContinue

    Write-Host "-> " -ForegroundColor Green -NoNewline
    Write-Host "Starting PMS DEV $($latest.Name): " -ForegroundColor White -NoNewline
    Write-Host $exe -ForegroundColor Cyan
    Start-Process -FilePath $exe -WorkingDirectory $latest.FullName

    if ($Pms.PasswordEnvVar) {
        # Read from the registry, not the process env: the desktop shortcut's
        # parent (Explorer) may predate the variable being set.
        $pw = [Environment]::GetEnvironmentVariable($Pms.PasswordEnvVar, "User")
        if ($pw) {
            Set-Clipboard -Value $pw
            Write-Host "Password copied to clipboard ($($Pms.PasswordEnvVar))." -ForegroundColor Gray
            if ($alreadyRunning) {
                Write-Host "PMS is already running (pid $($alreadyRunning.Id -join ', ')) — the new instance will exit; close it first." -ForegroundColor Yellow
            } else {
                # Only the env var name goes on the command line; the child reads the value itself.
                $cmd = "Import-Module '$($script:PmsModulePath -replace "'", "''")' -Force; Invoke-TmsPmsLoginAutofill -PasswordEnvVar '$($Pms.PasswordEnvVar -replace "'", "''")'"
                $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
                Start-Process -FilePath (Get-Command pwsh).Source -WindowStyle Hidden -ArgumentList "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $enc"
            }
        }
    }
}

function Invoke-TmsPmsLoginAutofill {
    <#
    Waits up to $TimeoutSeconds for the PMS login form and types the password
    from the user-level env var $PasswordEnvVar into it. Runs in the hidden
    pwsh that Start-TmsPmsLatest spawns. PMS doesn't expose control names to
    UI Automation (AutomationId is just the HWND, IsPassword is False), so the
    password box is found by EM_GETPASSWORDCHAR: the EDIT window with a
    password char set — the inner EDIT of a Janus EditBox, which is a
    ContainerControl, so the password is typed with SendKeys rather than set
    underneath it. Types only when that box has focus and is still empty.
    Assumes the password box comes right after the username box in tab
    order (frmLogin: txtUserName 0, txtPassword 1).
    Errors go to %TEMP%\ztms-pms-autofill.log.
    #>
    param(
        [Parameter(Mandatory)][string]$PasswordEnvVar,
        [int]$TimeoutSeconds = 180
    )

    try {
        $pw = [Environment]::GetEnvironmentVariable($PasswordEnvVar, "User")
        if (-not $pw) { return }

        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
        if (-not ("Tms.PmsWin32" -as [type])) {
            Add-Type -Namespace Tms -Name PmsWin32 -MemberDefinition '[DllImport("user32.dll")] public static extern System.IntPtr SendMessage(System.IntPtr hWnd, int msg, System.IntPtr wParam, System.IntPtr lParam);'
        }
        $EM_GETPASSWORDCHAR = 0xD2
        $WM_GETTEXTLENGTH = 0x0E
        $uia = [System.Windows.Automation.AutomationElement]
        $scope = [System.Windows.Automation.TreeScope]
        $send = { param($el, $msg) [int][Tms.PmsWin32]::SendMessage([IntPtr]$el.Current.NativeWindowHandle, $msg, [IntPtr]::Zero, [IntPtr]::Zero) }

        $tabs = 0
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $box = $null
            foreach ($id in @(Get-Process PMS -ErrorAction SilentlyContinue).Id) {
                $byPid = [System.Windows.Automation.PropertyCondition]::new($uia::ProcessIdProperty, $id)
                foreach ($win in $uia::RootElement.FindAll($scope::Children, $byPid)) {
                    $box = $win.FindAll($scope::Descendants, [System.Windows.Automation.Condition]::TrueCondition) |
                        Where-Object { $_.Current.ClassName -like "*.EDIT.*" -and (& $send $_ $EM_GETPASSWORDCHAR) -ne 0 } |
                        Select-Object -First 1
                    if ($box) { break }
                }
                if ($box) { break }
            }
            if (-not $box) { continue }
            if ((& $send $box $WM_GETTEXTLENGTH) -gt 0) { return }   # already typed by hand

            # UIA SetFocus is refused on that inner EDIT ("cannot receive focus"),
            # but Tab from the username box (TabIndex 0) lands on it (TabIndex 1).
            # Press Tab only while focus is inside PMS, and only a few times.
            $focused = $uia::FocusedElement.Current
            if ($focused.NativeWindowHandle -ne $box.Current.NativeWindowHandle) {
                if ($focused.ProcessId -ne $box.Current.ProcessId -or $tabs -ge 6) { continue }
                [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
                $tabs++
                Start-Sleep -Milliseconds 200
                # Never type the password into anything but that box
                if ($uia::FocusedElement.Current.NativeWindowHandle -ne $box.Current.NativeWindowHandle) { continue }
            }
            # SendKeys treats + ^ % ~ ( ) { } [ ] as commands — wrap them in {}
            [System.Windows.Forms.SendKeys]::SendWait(($pw -replace '[+^%~(){}\[\]]', '{$0}'))
            return
        }
    } catch {
        Add-Content -LiteralPath (Join-Path $env:TEMP "ztms-pms-autofill.log") -Value "[$(Get-Date -Format s)] $($_.Exception.Message)"
    }
}

function Show-TmsToast {
    # Windows toast notification. pwsh 7 can't load WinRT types, so this hands
    # off to Windows PowerShell 5.1 (always present on Windows 10/11).
    param([string]$Title, [string]$Text)

    $esc = { param($s) [Security.SecurityElement]::Escape($s) }
    $xml = "<toast><visual><binding template='ToastGeneric'><text>$(& $esc $Title)</text><text>$(& $esc $Text)</text></binding></visual></toast>"
    $ps = @"
`$ProgressPreference = 'SilentlyContinue'
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
`$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
`$doc.LoadXml('$($xml -replace "'", "''")')
`$appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(`$appId).Show([Windows.UI.Notifications.ToastNotification]::new(`$doc))
"@
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ps))
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -EncodedCommand $enc
}

function Invoke-TmsPmsUpdate {
    <#
    Checks <updateUrl>/api/Update/GetLastVersion/<product>; if that version
    isn't installed yet, downloads <updateUrl>/<product>/<version>.zip into
    <Root>\PMSUpd and unzips it into <Root>\<version> — the same layout the
    app's own updater produces. Download and unzip go to .part/.partial names
    first and are renamed at the end, so Start-TmsPmsLatest never picks a
    half-written build. Then trims old version folders (keeping the newest
    $PmsKeepVersions, never one PMS is running from) and old zips.

    Shows a toast on install and on error — an error toasts once until a run
    succeeds again, so the every-minute scheduled task doesn't spam. Logs to
    <Root>\PMSUpd\auto-update.log (last 500 lines). Returns $true on success.
    #>
    param([Parameter(Mandatory)]$Pms)

    if (-not $Pms.UpdateUrl) {
        Write-Host "No pms.dev.updateUrl configured. Edit tms.config.json — see tms.config.example.json." -ForegroundColor Red
        exit 1
    }

    $root = $Pms.Root
    $updDir = Join-Path $root "PMSUpd"
    $log = Join-Path $updDir "auto-update.log"
    $errState = Join-Path $updDir "last-error.txt"

    $writeLog = {
        param($msg)
        $line = "[{0:yyyy-MM-dd HH:mm:ss}] $msg" -f (Get-Date)
        Add-Content -LiteralPath $log -Value $line -Encoding utf8
        Write-Host $line
    }

    # One update at a time: the scheduled task and a manual menu run can
    # otherwise collide on the same staging folder.
    $mutex = [System.Threading.Mutex]::new($false, "Local\ztms-pms-dev-update")
    if (-not $mutex.WaitOne(0)) {
        Write-Host "Another PMS update is already running — skipping." -ForegroundColor Yellow
        $mutex.Dispose()
        return $true
    }

    $failed = $false
    try {
        New-Item -ItemType Directory -Force $updDir | Out-Null

        $latest = Invoke-RestMethod "$($Pms.UpdateUrl)/api/Update/GetLastVersion/$($Pms.Product)" -Headers @{ Accept = "application/json" } -UserAgent "PMS" -TimeoutSec 20
        if (-not ($latest -as [version])) { throw "Update API returned an invalid version: '$latest'" }

        $target = Join-Path $root $latest
        if (Test-Path -LiteralPath (Join-Path $target "PMS.exe")) {
            Write-Host "Already on the latest version: $latest" -ForegroundColor Green
        } elseif ((Test-Path -LiteralPath $target) -and (Get-ChildItem -LiteralPath $target -Force | Select-Object -First 1)) {
            & $writeLog "$latest folder has files but no PMS.exe yet (the app is probably updating itself) — skipping this run"
        } else {
            & $writeLog "New version $latest available, downloading..."
            $zip = Join-Path $updDir "$latest.zip"
            $part = "$zip.part"
            Invoke-WebRequest "$($Pms.UpdateUrl)/$($Pms.Product)/$latest.zip" -UserAgent "PMS" -OutFile $part -TimeoutSec 600
            Move-Item -LiteralPath $part -Destination $zip -Force

            $staging = "$target.partial"
            if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
            Expand-Archive -LiteralPath $zip -DestinationPath $staging -Force
            if (-not (Test-Path -LiteralPath (Join-Path $staging "PMS.exe"))) { throw "Zip $latest has no PMS.exe" }
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }   # empty leftover
            Move-Item -LiteralPath $staging -Destination $target
            & $writeLog "Installed $latest into $target"
            try { Show-TmsToast "PMS Dev updated" "Installed $latest. Open the PMS Dev shortcut to use it." } catch { & $writeLog "Toast failed: $($_.Exception.Message)" }
        }
    } catch {
        $failed = $true
        $msg = $_.Exception.Message
        & $writeLog "Error: $msg"
        $prev = Get-Content -LiteralPath $errState -Raw -ErrorAction SilentlyContinue
        if ("$prev".Trim() -ne $msg) {
            Set-Content -LiteralPath $errState -Value $msg -Encoding utf8 -ErrorAction SilentlyContinue
            try { Show-TmsToast "PMS Dev update failed" $msg } catch {}
        }
    } finally {
        if (-not $failed) { Remove-Item -LiteralPath $errState -ErrorAction SilentlyContinue }

        try {
            Get-ChildItem -LiteralPath $updDir -Filter "*.zip" -ErrorAction SilentlyContinue |
                Where-Object { $_.BaseName -as [version] } |
                Sort-Object { [version]$_.BaseName } -Descending |
                Select-Object -Skip 1 |
                Remove-Item -Force -ErrorAction SilentlyContinue

            $inUse = Get-Process PMS, StartPMS -ErrorAction SilentlyContinue | ForEach-Object { Split-Path $_.Path -Parent }
            Get-ChildItem -LiteralPath $root -Directory |
                Where-Object { $_.Name -as [version] } |
                Sort-Object { [version]$_.Name } -Descending |
                Select-Object -Skip $script:PmsKeepVersions |
                Where-Object { $_.FullName -notin $inUse } |
                ForEach-Object {
                    $dir = $_
                    try { Remove-Item -LiteralPath $dir.FullName -Recurse -Force; & $writeLog "Removed old version $($dir.Name)" }
                    catch {
                        # Log a stuck folder once, not every minute
                        $msg = "Couldn't remove $($dir.Name): $($_.Exception.Message)"
                        $last = Get-Content -LiteralPath $log -Tail 1 -ErrorAction SilentlyContinue
                        if (-not "$last".EndsWith($msg)) { & $writeLog $msg }
                    }
                }
        } catch { & $writeLog "Cleanup error: $($_.Exception.Message)" }

        if (Test-Path -LiteralPath $log) {
            $lines = Get-Content -LiteralPath $log -Tail 500
            Set-Content -LiteralPath $log -Value $lines -Encoding utf8
        }
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
    return -not $failed
}

function Get-TmsPmsShortcutPath {
    Join-Path ([Environment]::GetFolderPath("Desktop")) $script:PmsShortcutName
}

function Install-TmsPmsDev {
    <#
    One-shot machine setup for PMS DEV:
      1. Downloads the latest build if none is installed yet.
      2. Desktop shortcut "PMS Dev" -> pms\start-dev.ps1 (always opens the
         newest build), with the app's icon saved to <Root>\PMS.ico so it
         survives old version folders being deleted.
      3. Scheduled task "PMS Dev Auto Update" running pms\update-dev.ps1 every
         minute, headless (conhost --headless, so no console flashes).
    Re-running replaces the shortcut and task in place.
    #>
    param(
        [Parameter(Mandatory)]$Pms,
        [Parameter(Mandatory)][string]$ScriptsRoot
    )

    New-Item -ItemType Directory -Force $Pms.Root | Out-Null

    if (-not (Get-TmsPmsLatestInstalled -Root $Pms.Root)) {
        Write-Host "No PMS build installed yet — downloading the latest..." -ForegroundColor Cyan
        if (-not (Invoke-TmsPmsUpdate -Pms $Pms)) {
            Write-Host "Download failed — fix the error above and re-run." -ForegroundColor Red
            exit 1
        }
    }
    $latest = Get-TmsPmsLatestInstalled -Root $Pms.Root
    if (-not (Get-ChildItem -LiteralPath $Pms.Root -Directory -Filter "Microsoft.WebView2.FixedVersionRuntime*" -ErrorAction SilentlyContinue)) {
        Write-Host "⚠️ No Microsoft.WebView2.FixedVersionRuntime* folder in $($Pms.Root) — PMS screens that use WebView2 may not work until you run the official PMS installer once." -ForegroundColor Yellow
    }

    # --- Icon ---
    Add-Type -AssemblyName System.Drawing
    $icoPath = Join-Path $Pms.Root "PMS.ico"
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Join-Path $latest.FullName "PMS.exe"))
    $fs = [IO.File]::Create($icoPath)
    try { $icon.Save($fs) } finally { $fs.Close() }

    # --- Desktop shortcut ---
    # WScript.Shell can't save to a path with non-ASCII characters (e.g. a
    # Vietnamese Windows username in the Desktop path), so build the .lnk in
    # the always-ASCII Public folder and move it into place.
    $pwsh = (Get-Command pwsh).Source
    $startScript = Join-Path $ScriptsRoot "pms\start-dev.ps1"
    $tmpLnk = Join-Path $env:PUBLIC "ztms-$(Get-Random).lnk"
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($tmpLnk)
    $lnk.TargetPath = $pwsh
    $lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startScript`""
    $lnk.WorkingDirectory = $Pms.Root
    $lnk.IconLocation = "$icoPath,0"
    $lnk.WindowStyle = 7
    $lnk.Description = "Open the latest PMS DEV build"
    $lnk.Save()
    if ($lnk.Arguments -ne "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startScript`"") {
        Write-Host "⚠️ Shortcut arguments got mangled (non-ASCII path?): $($lnk.Arguments)" -ForegroundColor Yellow
    }
    $shortcutPath = Get-TmsPmsShortcutPath
    Move-Item -LiteralPath $tmpLnk -Destination $shortcutPath -Force
    Write-Host "Shortcut: $shortcutPath" -ForegroundColor Green

    # --- Scheduled task ---
    $updateScript = Join-Path $ScriptsRoot "pms\update-dev.ps1"
    $action = New-ScheduledTaskAction -Execute "conhost.exe" -Argument "--headless `"$pwsh`" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$updateScript`"" -WorkingDirectory $Pms.Root
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $script:PmsTaskName -Description "Every minute: download the latest PMS DEV build into $($Pms.Root) (ztms)" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Write-Host "Scheduled task: '$($script:PmsTaskName)' (every minute)" -ForegroundColor Green
}

function Get-TmsPmsStatus {
    # Rows for setup\doctor.ps1: { Name, Status (OK/WARN/FAIL), Detail }.
    param([Parameter(Mandatory)]$Pms)

    $rows = @()
    $latest = Get-TmsPmsLatestInstalled -Root $Pms.Root
    $rows += if ($latest) { [PSCustomObject]@{ Name = "PMS build"; Status = "OK"; Detail = "$($latest.Name) in $($Pms.Root)" } }
             else { [PSCustomObject]@{ Name = "PMS build"; Status = "WARN"; Detail = "none in $($Pms.Root) — run PMS > [dev] install" } }

    $task = Get-ScheduledTask -TaskName $script:PmsTaskName -ErrorAction SilentlyContinue
    $rows += if ($task) { [PSCustomObject]@{ Name = "PMS auto-update task"; Status = "OK"; Detail = "$($task.State)" } }
             else { [PSCustomObject]@{ Name = "PMS auto-update task"; Status = "WARN"; Detail = "not registered — run PMS > [dev] install" } }

    $rows += if (Test-Path -LiteralPath (Get-TmsPmsShortcutPath)) { [PSCustomObject]@{ Name = "PMS desktop shortcut"; Status = "OK"; Detail = "" } }
             else { [PSCustomObject]@{ Name = "PMS desktop shortcut"; Status = "WARN"; Detail = "missing — run PMS > [dev] install" } }
    return $rows
}

Export-ModuleMember -Function Get-TmsPmsDevConfig, Get-TmsPmsLatestInstalled, Start-TmsPmsLatest, Invoke-TmsPmsLoginAutofill, Show-TmsToast, Invoke-TmsPmsUpdate, Install-TmsPmsDev, Get-TmsPmsStatus, Get-TmsPmsShortcutPath