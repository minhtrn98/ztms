# Global "Spotlight-style" hotkey for the ztms menu, used by
# setup\install-hotkey.ps1, setup\uninstall-hotkey.ps1, setup\hotkey-listener.ps1
# and setup\doctor.ps1.
#
# A headless pwsh listener (setup\hotkey-listener.ps1), started at logon by the
# "ztms Hotkey" scheduled task, registers the hotkey via RegisterHotKey and on
# each press toggles the ztms window: opens a new one if none is open, brings
# it to the front if it's behind other windows, minimizes it if it's already
# in front. The listener remembers the window handle it opened (the terminal
# window that appears right after launching) rather than matching by title —
# Windows Terminal titles every window "Terminal" when
# showTerminalTitleInTitlebar is off — so only that window is toggled; a
# `ztms` typed into your own terminal is left alone.
#
# Reads hotkey.keys from tms.config.json (default "Ctrl+Space").

$script:HotkeyTaskName = "ztms Hotkey"
$script:HotkeyTabTitle = "ztms"
$script:HotkeyDefaultKeys = "Ctrl+Space"
$script:HotkeyId = 1
$script:MenuWindow = [IntPtr]::Zero
$script:HotkeyLogPath = Join-Path $env:TEMP "ztms-hotkey.log"

if (-not ('Ztms.HotkeyNative' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace Ztms {
    public static class HotkeyNative {
        [StructLayout(LayoutKind.Sequential)]
        struct MSG { public IntPtr hwnd; public uint message; public UIntPtr wParam; public IntPtr lParam; public uint time; public int x; public int y; }
        delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [StructLayout(LayoutKind.Sequential)]
        struct POINT { public int X; public int Y; }
        [StructLayout(LayoutKind.Sequential)]
        struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
        [StructLayout(LayoutKind.Sequential)]
        struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
        [StructLayout(LayoutKind.Sequential)]
        struct WINDOWPLACEMENT { public int length; public int flags; public int showCmd; public POINT ptMinPosition; public POINT ptMaxPosition; public RECT rcNormalPosition; }

        [DllImport("user32.dll", SetLastError = true)] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
        [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
        [DllImport("user32.dll")] static extern int GetMessage(out MSG msg, IntPtr hWnd, uint filterMin, uint filterMax);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hWnd, StringBuilder name, int maxCount);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int processId);
        [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hWnd);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        [DllImport("user32.dll")] static extern bool AttachThreadInput(uint attach, uint attachTo, bool doAttach);
        [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
        [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT point);
        [DllImport("user32.dll")] static extern IntPtr MonitorFromPoint(POINT point, uint flags);
        [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
        [DllImport("user32.dll")] static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT placement);
        [DllImport("user32.dll")] static extern bool SetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT placement);
        [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);

        const uint WM_HOTKEY = 0x0312;

        // Un-maximize (Windows Terminal's launchMode may be "maximized") and
        // center the window on the monitor under the mouse, sized as a
        // percentage of that monitor's work area (taskbar excluded).
        public static void Center(IntPtr hWnd, int widthPercent, int heightPercent) {
            // Real pixels, so the math holds on scaled (125%/150%) monitors
            SetThreadDpiAwarenessContext(new IntPtr(-4));  // PER_MONITOR_AWARE_V2
            POINT cursor;
            GetCursorPos(out cursor);
            var info = new MONITORINFO();
            info.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
            if (!GetMonitorInfo(MonitorFromPoint(cursor, 2), ref info)) return;  // MONITOR_DEFAULTTONEAREST
            var work = info.rcWork;
            int areaW = work.Right - work.Left, areaH = work.Bottom - work.Top;
            int w = areaW * widthPercent / 100, h = areaH * heightPercent / 100;
            int x = work.Left + (areaW - w) / 2, y = work.Top + (areaH - h) / 2;

            // One SetWindowPlacement call un-maximizes straight into the
            // centered rect (ShowWindow restore + SetWindowPos would flash the
            // window's old restored rect in between). Its rect is in
            // workspace coordinates: screen coordinates shifted by the
            // primary monitor's taskbar when that sits on the top/left edge.
            var primary = new MONITORINFO();
            primary.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
            GetMonitorInfo(MonitorFromPoint(new POINT(), 1), ref primary);  // MONITOR_DEFAULTTOPRIMARY
            int dx = primary.rcWork.Left - primary.rcMonitor.Left, dy = primary.rcWork.Top - primary.rcMonitor.Top;

            var placement = new WINDOWPLACEMENT();
            placement.length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
            GetWindowPlacement(hWnd, ref placement);
            placement.flags = 0;
            placement.showCmd = 1;  // SW_SHOWNORMAL
            placement.rcNormalPosition = new RECT { Left = x - dx, Top = y - dy, Right = x - dx + w, Bottom = y - dy + h };
            SetWindowPlacement(hWnd, ref placement);
        }

        // Restore + bring to front. Windows' foreground lock sometimes refuses
        // a plain SetForegroundWindow from a background process; sharing the
        // current foreground thread's input state gets past it.
        public static void Activate(IntPtr hWnd) {
            if (IsIconic(hWnd)) ShowWindow(hWnd, 9);  // SW_RESTORE
            if (SetForegroundWindow(hWnd) && GetForegroundWindow() == hWnd) return;
            uint pid;
            uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), out pid);
            uint me = GetCurrentThreadId();
            if (fgThread != 0 && fgThread != me && AttachThreadInput(me, fgThread, true)) {
                BringWindowToTop(hWnd);
                SetForegroundWindow(hWnd);
                AttachThreadInput(me, fgThread, false);
            }
        }

        // Blocks until a hotkey registered on this thread fires. False once
        // the thread's message loop is told to quit (WM_QUIT).
        public static bool WaitForHotkey() {
            MSG msg;
            return GetMessage(out msg, IntPtr.Zero, WM_HOTKEY, WM_HOTKEY) > 0;
        }

        // Visible top-level terminal windows: Windows Terminal or classic conhost.
        public static List<IntPtr> ListTerminalWindows() { return TerminalWindows(false); }

        // includeHiddenWt: also Windows Terminal windows that exist but aren't
        // shown yet (hidden conhost windows are left out — every headless /
        // pseudo console has one).
        static List<IntPtr> TerminalWindows(bool includeHiddenWt) {
            var result = new List<IntPtr>();
            EnumWindows((hWnd, lParam) => {
                var name = new StringBuilder(64);
                GetClassName(hWnd, name, name.Capacity);
                var cls = name.ToString();
                bool visible = IsWindowVisible(hWnd);
                if ((cls == "CASCADIA_HOSTING_WINDOW_CLASS" && (visible || includeHiddenWt)) || (cls == "ConsoleWindowClass" && visible)) result.Add(hWnd);
                return true;
            }, IntPtr.Zero);
            return result;
        }

        public static List<IntPtr> ListTerminalWindowsIncludingHidden() { return TerminalWindows(true); }

        // Waits (up to timeoutMs) for a terminal window that isn't in `before`
        // and centers it the moment it becomes visible. Windows Terminal
        // creates the window hidden and shows it already maximized when
        // launchMode is "maximized" (no CLI flag overrides that, and it
        // ignores the launch show-state), so busy-polling from creation and
        // centering right at show time keeps the maximized frame from
        // lingering on screen. Returns the window, or Zero if none appeared.
        public static IntPtr WaitForNewWindow(IntPtr[] before, int timeoutMs, int widthPercent, int heightPercent) {
            var known = new HashSet<IntPtr>(before);
            var watch = System.Diagnostics.Stopwatch.StartNew();
            IntPtr found = IntPtr.Zero;
            while (watch.ElapsedMilliseconds < timeoutMs) {
                if (found == IntPtr.Zero) {
                    foreach (var h in TerminalWindows(true)) { if (!known.Contains(h)) { found = h; break; } }
                }
                if (found != IntPtr.Zero && IsWindowVisible(found)) {
                    Center(found, widthPercent, heightPercent);
                    return found;
                }
                System.Threading.Thread.Yield();
            }
            return found;
        }
    }
}
"@
}

function ConvertTo-TmsHotkey {
    <#
    Parses "Ctrl+Space" / "Ctrl+Alt+Z" / "Win+Shift+F1" into RegisterHotKey's
    modifier flags + virtual-key code. Throws on an unknown key, more than one
    non-modifier key, or no modifier at all (a bare key would swallow normal
    typing everywhere).
    #>
    param([string]$Keys)

    if ([string]::IsNullOrWhiteSpace($Keys)) { $Keys = $script:HotkeyDefaultKeys }

    $modifiers = 0
    $modNames = @()
    $key = $null
    foreach ($part in ($Keys -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        switch -Regex ($part) {
            '^(ctrl|control)$' { $modifiers = $modifiers -bor 0x2; $modNames += "Ctrl"; continue }
            '^alt$' { $modifiers = $modifiers -bor 0x1; $modNames += "Alt"; continue }
            '^shift$' { $modifiers = $modifiers -bor 0x4; $modNames += "Shift"; continue }
            '^win$' { $modifiers = $modifiers -bor 0x8; $modNames += "Win"; continue }
            default {
                if ($null -ne $key) { throw "'$Keys' has more than one non-modifier key" }
                # [ConsoleKey] values are the Windows virtual-key codes
                $name = if ($part -match '^space$') { "Spacebar" } elseif ($part -match '^\d$') { "D$part" } else { $part }
                if ($name -match '^\d+$' -or -not [Enum]::IsDefined([ConsoleKey], [string]($name -as [ConsoleKey]))) { throw "unknown key '$part' in '$Keys'" }
                $key = $name -as [ConsoleKey]
            }
        }
    }
    if ($null -eq $key) { throw "'$Keys' has no key, only modifiers" }
    if ($modifiers -eq 0) { throw "'$Keys' needs at least one of Ctrl/Alt/Shift/Win" }

    [PSCustomObject]@{
        Modifiers = $modifiers -bor 0x4000  # MOD_NOREPEAT: holding the keys down fires once
        Vk        = [int]$key
        Display   = (@($modNames | Select-Object -Unique) + $(if ($key -eq [ConsoleKey]::Spacebar) { "Space" } else { "$key" -replace '^D(\d)$', '$1' })) -join "+"
    }
}

function Get-TmsHotkey {
    # hotkey.keys from config, defaulting to Ctrl+Space when the section is
    # missing (or there's no config at all). Throws on an invalid value.
    # Also carries the window size: hotkey.widthPercent/heightPercent of the
    # monitor's work area (default 50 x 80, clamped to 20..100).
    param($Config)
    $section = if ($Config -and $Config.hotkey) { $Config.hotkey }
    $hotkey = ConvertTo-TmsHotkey -Keys $(if ($section) { $section.keys })
    foreach ($dim in @(@("widthPercent", 50), @("heightPercent", 80))) {
        $value = if ($section -and $section.($dim[0])) { [int]$section.($dim[0]) } else { $dim[1] }
        $hotkey | Add-Member -NotePropertyName ($dim[0].Substring(0, 1).ToUpper() + $dim[0].Substring(1)) -NotePropertyValue ([Math]::Min(100, [Math]::Max(20, $value)))
    }
    $hotkey
}

function Get-TmsHotkeyListenerProcess {
    Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*hotkey-listener.ps1*" }
}

function Stop-TmsHotkeyListener {
    foreach ($p in Get-TmsHotkeyListenerProcess) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Show-TmsHotkeyMenu {
    <#
    What one hotkey press does: toggle the ztms window this listener opened
    earlier, or — if it's gone (ztms exited / window closed) — open a new one,
    in a fresh Windows Terminal window when wt is installed, otherwise a plain
    console window — centered, not maximized (see Center).
    #>
    param(
        [Parameter(Mandatory)]$Hotkey,
        [Parameter(Mandatory)][string]$ScriptsRoot
    )

    $native = [Ztms.HotkeyNative]
    $hwnd = $script:MenuWindow
    # Still a live terminal window (not closed, handle not recycled by another app)?
    if ($hwnd -ne [IntPtr]::Zero -and @($native::ListTerminalWindows()) -contains $hwnd) {
        if ($native::GetForegroundWindow() -eq $hwnd) {
            [void]$native::ShowWindow($hwnd, 6)  # SW_MINIMIZE
        } else {
            $native::Activate($hwnd)
        }
        return
    }

    $ztms = Join-Path $ScriptsRoot "ztms.ps1"
    $pwsh = (Get-Command pwsh).Source
    # We got the keypress, so we may take the foreground — pass that right on
    # to whatever process ends up owning the new window (wt hands off to an
    # already-running WindowsTerminal.exe).
    [void]$native::AllowSetForegroundWindow(-1)  # ASFW_ANY
    $before = [IntPtr[]]@($native::ListTerminalWindowsIncludingHidden())
    if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
        # -w new: a window of its own even with windowingBehavior=useExisting
        Start-Process wt.exe -ArgumentList "-w new new-tab --title $($script:HotkeyTabTitle) --suppressApplicationTitle `"$pwsh`" -NoProfile -ExecutionPolicy Bypass -File `"$ztms`""
    } else {
        Start-Process $pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ztms`""
    }

    # Remember the first terminal window that shows up as "ours" (up to 5s),
    # centered as it appears (WaitForNewWindow), and make sure it's the one in
    # front — the launch alone doesn't always win focus
    $script:MenuWindow = $native::WaitForNewWindow($before, 5000, $Hotkey.WidthPercent, $Hotkey.HeightPercent)
    if ($script:MenuWindow -ne [IntPtr]::Zero) {
        # wt may still apply launchMode a beat after first showing the window — re-center if so
        Start-Sleep -Milliseconds 150
        if ($native::IsZoomed($script:MenuWindow)) { $native::Center($script:MenuWindow, $Hotkey.WidthPercent, $Hotkey.HeightPercent) }
        if ($native::GetForegroundWindow() -ne $script:MenuWindow) { $native::Activate($script:MenuWindow) }
    }
}

function Start-TmsHotkeyListener {
    <#
    Registers the hotkey on this thread and handles presses until the process
    is killed (Stop-TmsHotkeyListener). Returns $false right away if the
    hotkey can't be registered — another app (or another listener) owns it.
    #>
    param(
        [Parameter(Mandatory)]$Hotkey,
        [Parameter(Mandatory)][string]$ScriptsRoot
    )

    $native = [Ztms.HotkeyNative]
    if (-not $native::RegisterHotKey([IntPtr]::Zero, $script:HotkeyId, $Hotkey.Modifiers, $Hotkey.Vk)) { return $false }
    try {
        while ($native::WaitForHotkey()) {
            # Headless, so errors go to a log instead of a console nobody sees
            try { Show-TmsHotkeyMenu -Hotkey $Hotkey -ScriptsRoot $ScriptsRoot }
            catch { Add-Content -Path $script:HotkeyLogPath -Value "$(Get-Date -Format s) $($_ | Out-String)" }
        }
    } finally {
        [void]$native::UnregisterHotKey([IntPtr]::Zero, $script:HotkeyId)
    }
    return $true
}

function Test-TmsHotkeyAvailable {
    # True if nothing else currently owns the hotkey (registers + releases it).
    param([Parameter(Mandatory)]$Hotkey)
    $native = [Ztms.HotkeyNative]
    if (-not $native::RegisterHotKey([IntPtr]::Zero, $script:HotkeyId, $Hotkey.Modifiers, $Hotkey.Vk)) { return $false }
    [void]$native::UnregisterHotKey([IntPtr]::Zero, $script:HotkeyId)
    return $true
}

function Install-TmsHotkey {
    <#
    Stops any running listener, checks the hotkey is free, registers the
    "ztms Hotkey" scheduled task (at logon, headless via conhost --headless,
    no time limit, restarted if it dies) and starts it now. Re-running
    replaces the task in place — that's also how a changed hotkey.keys is
    picked up.
    #>
    param(
        [Parameter(Mandatory)]$Hotkey,
        [Parameter(Mandatory)][string]$ScriptsRoot
    )

    Stop-TmsHotkeyListener
    if (-not (Test-TmsHotkeyAvailable -Hotkey $Hotkey)) {
        Write-Host "$($Hotkey.Display) is already taken by another app. Pick another one in tms.config.json (hotkey.keys, e.g. `"Ctrl+Alt+Space`") and re-run." -ForegroundColor Red
        exit 1
    }

    $pwsh = (Get-Command pwsh).Source
    $listener = Join-Path $ScriptsRoot "setup\hotkey-listener.ps1"
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $action = New-ScheduledTaskAction -Execute "conhost.exe" -Argument "--headless `"$pwsh`" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$listener`"" -WorkingDirectory $ScriptsRoot
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $script:HotkeyTaskName -Description "Global $($Hotkey.Display) hotkey that opens the ztms menu" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $script:HotkeyTaskName

    # Ready once the listener owns the hotkey (pwsh start + Add-Type compile take a moment)
    for ($i = 0; $i -lt 30 -and (Test-TmsHotkeyAvailable -Hotkey $Hotkey); $i++) { Start-Sleep -Milliseconds 500 }
    if (-not (Get-TmsHotkeyListenerProcess) -or (Test-TmsHotkeyAvailable -Hotkey $Hotkey)) {
        Write-Host "Scheduled task '$($script:HotkeyTaskName)' registered, but the listener didn't take the hotkey. Check the task in Task Scheduler and $($script:HotkeyLogPath)." -ForegroundColor Red
        exit 1
    }
    Write-Host "Scheduled task: '$($script:HotkeyTaskName)' (at logon, running now)" -ForegroundColor Green
}

function Uninstall-TmsHotkey {
    Stop-TmsHotkeyListener
    if (Get-ScheduledTask -TaskName $script:HotkeyTaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $script:HotkeyTaskName -Confirm:$false
        Write-Host "Removed scheduled task '$($script:HotkeyTaskName)'." -ForegroundColor Green
    } else {
        Write-Host "No '$($script:HotkeyTaskName)' scheduled task — nothing to remove." -ForegroundColor Gray
    }
}

function Get-TmsHotkeyStatus {
    # Rows for setup\doctor.ps1: { Name, Status (OK/WARN/FAIL), Detail }.
    # Empty when the hotkey was never installed — it's optional.
    param($Config)

    $task = Get-ScheduledTask -TaskName $script:HotkeyTaskName -ErrorAction SilentlyContinue
    if (-not $task) { return @() }

    $rows = @()
    $display = try { (Get-TmsHotkey -Config $Config).Display } catch { $null }
    $rows += if ($display) { [PSCustomObject]@{ Name = "Hotkey"; Status = "OK"; Detail = $display } }
             else { [PSCustomObject]@{ Name = "Hotkey"; Status = "FAIL"; Detail = "invalid hotkey.keys in tms.config.json" } }
    $rows += if (Get-TmsHotkeyListenerProcess) { [PSCustomObject]@{ Name = "Hotkey listener"; Status = "OK"; Detail = "running" } }
             else { [PSCustomObject]@{ Name = "Hotkey listener"; Status = "WARN"; Detail = "not running — run SETUP > install-hotkey" } }
    return $rows
}

Export-ModuleMember -Function ConvertTo-TmsHotkey, Get-TmsHotkey, Get-TmsHotkeyListenerProcess, Stop-TmsHotkeyListener, Show-TmsHotkeyMenu, Start-TmsHotkeyListener, Test-TmsHotkeyAvailable, Install-TmsHotkey, Uninstall-TmsHotkey, Get-TmsHotkeyStatus
