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
        [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
        [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
        [DllImport("user32.dll")] static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT placement);
        [DllImport("user32.dll")] static extern bool SetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT placement);
        [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
        [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

        const uint WM_HOTKEY = 0x0312;

        // Un-maximize (Windows Terminal's launchMode may be "maximized") and
        // center the window on the monitor under the mouse, sized as a
        // percentage of that monitor's work area (taskbar excluded).
        public static void Center(IntPtr hWnd, int widthPercent, int heightPercent) {
            // Real pixels, so the math holds on scaled (125%/150%) monitors
            SetThreadDpiAwarenessContext(new IntPtr(-4));  // PER_MONITOR_AWARE_V2
            POINT cursor;
            GetCursorPos(out cursor);
            Place(hWnd, MonitorFromPoint(cursor, 2), widthPercent, heightPercent);  // MONITOR_DEFAULTTONEAREST
        }

        // Same, but re-centered on the monitor the window is already on — for
        // resizing it in place (search box <-> full size) without it jumping
        // to wherever the mouse happens to be.
        public static void Resize(IntPtr hWnd, int widthPercent, int heightPercent) {
            SetThreadDpiAwarenessContext(new IntPtr(-4));
            Place(hWnd, MonitorFromWindow(hWnd, 2), widthPercent, heightPercent);
        }

        // True if hWnd is a visible terminal window (see ListTerminalWindows).
        public static bool IsTerminalWindow(IntPtr hWnd) { return TerminalWindows(false).Contains(hWnd); }

        // The centered rect (screen coordinates) on that monitor's work area.
        static bool TargetRect(IntPtr monitor, int widthPercent, int heightPercent, out int x, out int y, out int w, out int h) {
            x = y = w = h = 0;
            var info = new MONITORINFO();
            info.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
            if (!GetMonitorInfo(monitor, ref info)) return false;
            var work = info.rcWork;
            int areaW = work.Right - work.Left, areaH = work.Bottom - work.Top;
            w = areaW * widthPercent / 100; h = areaH * heightPercent / 100;
            x = work.Left + (areaW - w) / 2; y = work.Top + (areaH - h) / 2;
            return true;
        }

        static void Place(IntPtr hWnd, IntPtr monitor, int widthPercent, int heightPercent) {
            int x, y, w, h;
            if (!TargetRect(monitor, widthPercent, heightPercent, out x, out y, out w, out h)) return;

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
        // and gets it centered on the monitor under the mouse. Windows
        // Terminal creates the window hidden ~100ms before showing it, so
        // busy-polling from launch catches it while hidden and moves it then:
        // it first appears already in place. If it's shown maximized anyway
        // (wt's global launchMode, when not launched with --focus), it's
        // re-placed the instant it's shown, which keeps the maximized frame
        // to a few ms. Returns the window, or Zero if none appeared.
        public static IntPtr WaitForNewWindow(IntPtr[] before, int timeoutMs, int widthPercent, int heightPercent) {
            SetThreadDpiAwarenessContext(new IntPtr(-4));  // PER_MONITOR_AWARE_V2
            POINT cursor;
            GetCursorPos(out cursor);
            IntPtr monitor = MonitorFromPoint(cursor, 2);  // MONITOR_DEFAULTTONEAREST
            int x, y, w, h;
            bool haveTarget = TargetRect(monitor, widthPercent, heightPercent, out x, out y, out w, out h);

            var known = new HashSet<IntPtr>(before);
            var watch = System.Diagnostics.Stopwatch.StartNew();
            IntPtr found = IntPtr.Zero;
            bool moved = false;
            while (watch.ElapsedMilliseconds < timeoutMs) {
                if (found == IntPtr.Zero) {
                    foreach (var hw in TerminalWindows(true)) { if (!known.Contains(hw)) { found = hw; break; } }
                }
                if (found != IntPtr.Zero && haveTarget && !moved && !IsWindowVisible(found)) {
                    SetWindowPos(found, IntPtr.Zero, x, y, w, h, 0x0014);  // SWP_NOZORDER | SWP_NOACTIVATE (no SWP_SHOWWINDOW: stays hidden)
                    moved = true;
                }
                if (found != IntPtr.Zero && IsWindowVisible(found)) {
                    RECT r;
                    GetWindowRect(found, out r);
                    if (IsZoomed(found) || r.Left != x || r.Top != y || r.Right - r.Left != w || r.Bottom - r.Top != h) {
                        Place(found, monitor, widthPercent, heightPercent);
                    }
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
    # Also carries the window's look: size as a percentage of the monitor's
    # work area (clamped to 20..100) — widthPercent (default 50),
    # heightPercent (80, while a script runs), searchHeightPercent (35, the
    # search box the hotkey opens) — plus fontSize (14), padding (16 px),
    # opacity (85 %) and acrylic (false: plain see-through; true: blurred,
    # needs Windows' "Transparency effects" on) for its Windows Terminal
    # profile (Set-TmsHotkeyWtProfile).
    param($Config)
    $section = if ($Config -and $Config.hotkey) { $Config.hotkey }
    $hotkey = ConvertTo-TmsHotkey -Keys $(if ($section) { $section.keys })
    # name, default, min, max
    foreach ($s in @(@("widthPercent", 50, 20, 100), @("heightPercent", 80, 20, 100), @("searchHeightPercent", 35, 20, 100), @("fontSize", 14, 6, 48), @("padding", 16, 0, 64), @("opacity", 85, 0, 100))) {
        $value = if ($section -and $null -ne $section.($s[0])) { [int]$section.($s[0]) } else { $s[1] }
        $hotkey | Add-Member -NotePropertyName ($s[0].Substring(0, 1).ToUpper() + $s[0].Substring(1)) -NotePropertyValue ([Math]::Min($s[3], [Math]::Max($s[2], $value)))
    }
    $hotkey | Add-Member -NotePropertyName Acrylic -NotePropertyValue ([bool]($section -and $section.acrylic))
    $hotkey
}

# The hotkey window's own Windows Terminal profile, kept in the user's
# settings.json. A JSON fragment would be tidier, but the user's
# profiles.defaults outrank fragment profiles, so a fragment can't change
# the font size (or anything else defaults already set) — only settings.json
# entries can. Fixed GUID so install/uninstall find exactly this entry.
$script:WtProfileGuid = "{6f3c2a1e-9b4d-4e57-8a2f-7d1c0e5b3a90}"
$script:WtProfileName = "ztms (hotkey)"

function Get-TmsWtSettingsPath {
    # Stable (Store), Preview, then unpackaged Windows Terminal; $null if none.
    foreach ($p in @(
            (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"),
            (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"),
            (Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\settings.json"))) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Update-TmsWtSettings {
    <#
    Read-modify-write of Windows Terminal's settings.json: $Change gets the
    parsed settings (ordered hashtables) and edits them in place. Keeps a
    one-time backup (<settings.json>.ztms-backup, from before ztms first
    touched it). WT notices the write and reloads by itself. Returns $false
    (and changes nothing) if there's no settings.json or it can't be parsed.
    #>
    param([Parameter(Mandatory)][scriptblock]$Change)
    $path = Get-TmsWtSettingsPath
    if (-not $path) { return $false }
    try { $settings = [IO.File]::ReadAllText($path) | ConvertFrom-Json -AsHashtable }
    catch {
        Write-Host "Couldn't parse $path ($($_.Exception.Message)) — leaving it alone." -ForegroundColor Yellow
        return $false
    }
    $backup = "$path.ztms-backup"
    if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $path -Destination $backup }
    & $Change $settings
    [IO.File]::WriteAllText($path, ($settings | ConvertTo-Json -Depth 64), [Text.UTF8Encoding]::new($false))
    return $true
}

function Set-TmsHotkeyWtProfile {
    <#
    Adds/replaces the hidden "ztms (hotkey)" profile: the look of the user's
    default profile (color scheme, font face, opacity, ...; profiles.defaults
    still apply underneath) with hotkey.fontSize and hotkey.padding on top.
    Also drops any profile stub left by a ztms fragment ("source": "ztms").
    #>
    param([Parameter(Mandatory)]$Hotkey)
    Update-TmsWtSettings -Change {
        param($settings)
        if (-not $settings.profiles) { $settings.profiles = [ordered]@{} }
        if ($settings.profiles -is [System.Collections.IList]) { $settings.profiles = [ordered]@{ list = $settings.profiles } }  # legacy flat list
        $list = [Collections.Generic.List[object]]::new()
        foreach ($p in @($settings.profiles.list)) { if ($p -and $p.guid -ne $script:WtProfileGuid -and $p.source -ne "ztms") { $list.Add($p) } }

        $wtProfile = [ordered]@{ guid = $script:WtProfileGuid; name = $script:WtProfileName; hidden = $true; commandline = "pwsh.exe -NoProfile" }
        $default = $list | Where-Object { $_.guid -eq $settings.defaultProfile } | Select-Object -First 1
        if ($default) {
            foreach ($key in $default.Keys) {
                if ($key -notin "guid", "name", "source", "commandline", "hidden", "icon", "startingDirectory", "tabTitle", "elevate", "fontSize", "fontFace", "padding", "opacity", "useAcrylic") { $wtProfile[$key] = $default[$key] }
            }
        }
        $font = [ordered]@{}
        if ($default -and $default.font) { foreach ($key in $default.font.Keys) { $font[$key] = $default.font[$key] } }
        $font.size = $Hotkey.FontSize
        $wtProfile.font = $font
        $wtProfile.padding = "$($Hotkey.Padding)"
        # Set explicitly: profiles.defaults may carry opacity 0 + acrylic, which
        # without acrylic (or with Windows transparency effects off) would mean
        # a fully transparent or fully solid background
        $wtProfile.opacity = $Hotkey.Opacity
        $wtProfile.useAcrylic = $Hotkey.Acrylic
        $list.Add($wtProfile)
        $settings.profiles.list = $list
    }
}

function Remove-TmsHotkeyWtProfile {
    # Undo Set-TmsHotkeyWtProfile (no-op if it isn't there).
    $path = Get-TmsWtSettingsPath
    if (-not $path -or -not ([IO.File]::ReadAllText($path).Contains($script:WtProfileGuid) -or [IO.File]::ReadAllText($path).Contains('"source": "ztms"'))) { return $false }
    Update-TmsWtSettings -Change {
        param($settings)
        $settings.profiles.list = @($settings.profiles.list | Where-Object { $_.guid -ne $script:WtProfileGuid -and $_.source -ne "ztms" })
    }
}

function Test-TmsHotkeyWtProfile {
    # Is the profile in settings.json? (cheap text check — runs on every hotkey press)
    $path = Get-TmsWtSettingsPath
    return [bool]($path -and [IO.File]::ReadAllText($path).Contains($script:WtProfileGuid))
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
    console window — centered, not maximized (see Center). It opens as a
    short search box: ztms.ps1 --spotlight shows only the search line + a few
    results, and grows the window itself while a script runs
    (Set-TmsSpotlightWindowSize).
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
        # -w new: a window of its own even with windowingBehavior=useExisting.
        # --focus: focus mode — no tab row, no title bar (Spotlight-like), and
        # it overrides launchMode, so the window is never shown maximized.
        # -p: the hotkey's own profile (bigger font + padding) once install-hotkey added it
        $profileArg = if (Test-TmsHotkeyWtProfile) { "-p `"$($script:WtProfileGuid)`" " } else { "" }
        Start-Process wt.exe -ArgumentList "-w new --focus new-tab $profileArg--title $($script:HotkeyTabTitle) --suppressApplicationTitle `"$pwsh`" -NoProfile -ExecutionPolicy Bypass -File `"$ztms`" --spotlight"
    } else {
        Start-Process $pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ztms`" --spotlight"
    }

    # Remember the first terminal window that shows up as "ours" (up to 5s),
    # centered as it appears (WaitForNewWindow), and make sure it's the one in
    # front — the launch alone doesn't always win focus
    $script:MenuWindow = $native::WaitForNewWindow($before, 5000, $Hotkey.WidthPercent, $Hotkey.SearchHeightPercent)
    if ($script:MenuWindow -ne [IntPtr]::Zero) {
        # wt may still apply launchMode a beat after first showing the window — re-center if so
        Start-Sleep -Milliseconds 150
        if ($native::IsZoomed($script:MenuWindow)) { $native::Center($script:MenuWindow, $Hotkey.WidthPercent, $Hotkey.SearchHeightPercent) }
        if ($native::GetForegroundWindow() -ne $script:MenuWindow) { $native::Activate($script:MenuWindow) }
    }
}

function Set-TmsSpotlightWindowSize {
    <#
    Called by ztms.ps1 --spotlight from inside the hotkey window: -Full
    before running a script (room for its output), without it afterwards
    (back to the short search box). Resizes the foreground window — that's
    this one, the user just pressed a key in it — and does nothing if the
    foreground window isn't a terminal.

    Returns only once the console itself reports the new size: the resize
    reaches the console (through wt/ConPTY) asynchronously, and drawing the
    menu before it lands lays it out for the old height — after shrinking,
    the terminal then scrolls the search line off the top.
    #>
    param(
        [Parameter(Mandatory)]$Hotkey,
        [switch]$Full
    )
    $native = [Ztms.HotkeyNative]
    $hwnd = $native::GetForegroundWindow()
    if (-not $native::IsTerminalWindow($hwnd)) { return }
    $rowsBefore = [Console]::WindowHeight
    $native::Resize($hwnd, $Hotkey.WidthPercent, $(if ($Full) { $Hotkey.HeightPercent } else { $Hotkey.SearchHeightPercent }))
    # Up to 1s; normally a few tens of ms. (Already the right size = no change to wait for, just the timeout.)
    for ($i = 0; $i -lt 50 -and [Console]::WindowHeight -eq $rowsBefore; $i++) { Start-Sleep -Milliseconds 20 }
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

    if (Set-TmsHotkeyWtProfile -Hotkey $Hotkey) {
        Write-Host "Windows Terminal profile: '$($script:WtProfileName)' (hidden; font $($Hotkey.FontSize), padding $($Hotkey.Padding), opacity $($Hotkey.Opacity)%$(if ($Hotkey.Acrylic) { ', acrylic' })) in $(Get-TmsWtSettingsPath)" -ForegroundColor Green
        Write-Host "  backup of your settings from before ztms first changed them: $(Get-TmsWtSettingsPath).ztms-backup" -ForegroundColor Gray
    }
}

function Uninstall-TmsHotkey {
    Stop-TmsHotkeyListener
    if (Remove-TmsHotkeyWtProfile) { Write-Host "Removed Windows Terminal profile '$($script:WtProfileName)'." -ForegroundColor Green }
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

Export-ModuleMember -Function ConvertTo-TmsHotkey, Get-TmsHotkey, Get-TmsHotkeyListenerProcess, Stop-TmsHotkeyListener, Show-TmsHotkeyMenu, Set-TmsSpotlightWindowSize, Start-TmsHotkeyListener, Test-TmsHotkeyAvailable, Install-TmsHotkey, Uninstall-TmsHotkey, Get-TmsHotkeyStatus
