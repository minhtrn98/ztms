# Shared interactive checkbox menu, deduplicated from the original per-script copies.

Import-Module (Join-Path $PSScriptRoot "MenuTheme.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "MenuSearch.psm1") -Force

function Show-ProjectSelection {
    <#
    Interactive checkbox menu: Up/Down to move, Enter to toggle an item
    (or toggle all via "Select All"), Enter on "Confirm & Run" to submit.
    Returns an array of selected items (all, if none checked).
    #>
    param(
        [string[]]$Items,
        [string[]]$PreSelected = @()
    )

    $menuItems = @("Select All") + $Items + @("Confirm & Run")
    $confirmIndex = $menuItems.Count - 1
    $checked = New-Object bool[] ($menuItems.Count)

    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($PreSelected -contains $Items[$i]) { $checked[$i + 1] = $true }
    }
    if ($PreSelected.Count -gt 0) {
        $allChecked = $true
        for ($i = 1; $i -lt $confirmIndex; $i++) { if (-not $checked[$i]) { $allChecked = $false; break } }
        $checked[0] = $allChecked
    }

    $cursor = if ($PreSelected.Count -gt 0) { $confirmIndex } else { 0 }

    function Draw-Menu {
        param($Top)
        [Console]::SetCursorPosition(0, $Top)
        for ($i = 0; $i -lt $menuItems.Count; $i++) {
            $pointer = if ($i -eq $cursor) { ">" } else { " " }
            if ($i -eq $confirmIndex) {
                $line = "$pointer     $($menuItems[$i])".PadRight(60)
            } else {
                $mark = if ($checked[$i]) { "[x]" } else { "[ ]" }
                $line = "$pointer $mark $($menuItems[$i])".PadRight(60)
            }
            if ($i -eq $cursor) {
                Write-Host $line -ForegroundColor $MenuTheme.Cursor
            } elseif ($i -ne $confirmIndex -and $checked[$i]) {
                Write-Host $line -ForegroundColor $MenuTheme.Checked
            } else {
                Write-Host $line -ForegroundColor $MenuTheme.Normal
            }
        }
    }

    Write-Host "Select projects (Up/Down: move, Enter: toggle / confirm, Tab: jump to confirm, Esc: cancel - none checked = all):" -ForegroundColor $MenuTheme.Hint

    # Reserve the exact rows the menu needs before computing $top. On terminals
    # without real scrollback exposed via the Console API (Windows Terminal / VS
    # Code's integrated terminal both use ConPTY, where BufferHeight == WindowHeight),
    # any auto-scroll that happens *after* $top is captured leaves it pointing at the
    # wrong row, which is what breaks Up/Down redraws once the menu is taller than
    # the visible window. Writing blank lines first forces that scroll to happen now.
    1..$menuItems.Count | ForEach-Object { Write-Host "" }
    $top = [Console]::CursorTop - $menuItems.Count
    [Console]::CursorVisible = $false
    Draw-Menu -Top $top

    $confirmed = $false
    $cancelled = $false
    while (-not $confirmed -and -not $cancelled) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { $cursor = ($cursor - 1 + $menuItems.Count) % $menuItems.Count }
            'DownArrow' { $cursor = ($cursor + 1) % $menuItems.Count }
            'Tab'       { $cursor = $confirmIndex }
            'Enter' {
                if ($cursor -eq $confirmIndex) {
                    $confirmed = $true
                } elseif ($cursor -eq 0) {
                    $newState = -not $checked[0]
                    for ($i = 0; $i -lt $confirmIndex; $i++) { $checked[$i] = $newState }
                    if ($newState) { $cursor = $confirmIndex }
                } else {
                    $checked[$cursor] = -not $checked[$cursor]
                    $allChecked = $true
                    for ($i = 1; $i -lt $confirmIndex; $i++) { if (-not $checked[$i]) { $allChecked = $false; break } }
                    $checked[0] = $allChecked
                    if ($checked[$cursor]) { $cursor = [Math]::Min($cursor + 1, $confirmIndex) }
                }
            }
            'Escape' { $cancelled = $true }
        }
        Draw-Menu -Top $top
    }
    [Console]::CursorVisible = $true

    if ($cancelled) {
        Write-Host "Cancelled." -ForegroundColor $MenuTheme.Error
        exit 0
    }

    $selected = @()
    for ($i = 1; $i -lt $confirmIndex; $i++) {
        if ($checked[$i]) { $selected += $Items[$i - 1] }
    }

    if ($selected.Count -eq 0) { return $Items }
    return $selected
}

function Show-Menu {
    <#
    Single-select arrow-key menu (no checkboxes). Returns the selected index,
    or -1 if the user pressed Escape.
    #>
    param(
        [Parameter(Mandatory)][string[]]$Labels,
        [string]$Prompt = "Select an option"
    )

    $count = $Labels.Count
    $cursor = 0

    function Draw-Menu {
        param($Top)
        [Console]::SetCursorPosition(0, $Top)
        for ($i = 0; $i -lt $count; $i++) {
            $pointer = if ($i -eq $cursor) { ">" } else { " " }
            $line = "$pointer $($Labels[$i])".PadRight(70)
            if ($i -eq $cursor) {
                Write-Host $line -ForegroundColor $MenuTheme.Cursor
            } else {
                Write-Host $line -ForegroundColor $MenuTheme.Normal
            }
        }
    }

    Write-Host "$Prompt (Up/Down: move, Enter: select, Esc: quit):" -ForegroundColor $MenuTheme.Hint

    # See the comment in Show-ProjectSelection — reserve rows before computing
    # $top so ConPTY-based terminals (Windows Terminal / VS Code) don't desync
    # the cursor position once the list is taller than the visible window.
    1..$count | ForEach-Object { Write-Host "" }
    $top = [Console]::CursorTop - $count
    [Console]::CursorVisible = $false
    Draw-Menu -Top $top

    $selectedIndex = $null
    while ($null -eq $selectedIndex) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { $cursor = ($cursor - 1 + $count) % $count; Draw-Menu -Top $top }
            'DownArrow' { $cursor = ($cursor + 1) % $count; Draw-Menu -Top $top }
            'Enter'     { $selectedIndex = $cursor }
            'Escape'    { $selectedIndex = -1 }
        }
    }
    [Console]::CursorVisible = $true
    return $selectedIndex
}

function Show-GroupedMenu {
    <#
    Single-select arrow-key menu, expanded and flattened across groups.
    Each group's Name is rendered as a non-selectable header, numbered
    (1-9) so pressing that digit key jumps the cursor straight to the
    group's first entry; Up/Down skip over headers so only actual entries
    can be highlighted.

    Typing searches: the query is matched against names, group names and
    each entry's Desc — which is search-only, never shown (Find-MenuEntries in MenuSearch.psm1 — synonyms, English +
    Vietnamese, accents optional) and the list turns into a flat, best-first
    result list. Backspace edits the query, Escape clears it (a second
    Escape quits); digits jump to groups only while the query is empty.
    Returns the selected entry object (from Group.Entries), or $null on
    Escape.

    -SearchOnly (ztms.ps1 --spotlight, the hotkey window): no grouped list —
    just the search line, and as many results as fit the (short) window.
    #>
    param(
        [Parameter(Mandatory)]$Groups,
        [string]$Prompt = "Select an option",
        [switch]$SearchOnly
    )

    $rows = @()
    $groupHeaderIndex = @{}
    $groupNumber = 0
    foreach ($group in $Groups) {
        $groupNumber++
        $headerLabel = if ($groupNumber -le 9) { "[$groupNumber] $($group.Name)" } else { $group.Name }
        $rows += [ordered]@{ IsHeader = $true; Label = $headerLabel; Entry = $null }
        $groupHeaderIndex[$groupNumber] = $rows.Count - 1
        foreach ($entry in $group.Entries) {
            $rows += [ordered]@{ IsHeader = $false; Label = $entry.DisplayName; Entry = $entry }
        }
    }

    $selectableIndices = @()
    for ($i = 0; $i -lt $rows.Count; $i++) { if (-not $rows[$i].IsHeader) { $selectableIndices += $i } }

    if ($selectableIndices.Count -eq 0) {
        Write-Host "No entries to show." -ForegroundColor $MenuTheme.Error
        return $null
    }

    # Map each group number to the first selectable row in that group, so a
    # digit keypress can jump straight there.
    $groupJumpTarget = @{}
    foreach ($num in $groupHeaderIndex.Keys) {
        $headerIdx = $groupHeaderIndex[$num]
        $target = $selectableIndices | Where-Object { $_ -gt $headerIdx } | Select-Object -First 1
        if ($null -ne $target) { $groupJumpTarget[$num] = $target }
    }

    $groupWidth = (($Groups | ForEach-Object { $_.Name.Length }) | Measure-Object -Maximum).Maximum + 2
    # Every row is cut to the window width — a row that wrapped would push
    # all rows below it down a line and break the in-place redraw.
    $width = [Math]::Max(40, [Console]::WindowWidth - 1)

    $cursor = $selectableIndices[0]
    $query = ""
    $results = @()
    $resultCursor = 0

    function Write-MenuRow {
        # One full-width row: $Text, then $Tail in its own color, cut/padded to $width.
        param([string]$Text, $Color, [string]$Tail = "", $TailColor = $Color)
        if ($Text.Length -gt $width) { $Text = $Text.Substring(0, $width) }
        $room = $width - $Text.Length
        if ($Tail.Length -gt $room) { $Tail = $Tail.Substring(0, $room) }
        Write-Host $Text -ForegroundColor $Color -NoNewline
        Write-Host $Tail.PadRight($room) -ForegroundColor $TailColor
    }

    function Draw-Menu {
        param($Top)
        # Hide the real cursor while the rows are written, then park it right
        # after the query on the search line and show it again — so the search
        # box gets the terminal's own blinking caret, like a normal text box.
        [Console]::CursorVisible = $false
        Write-MenuBody -Top $Top
        [Console]::SetCursorPosition([Math]::Min($width - 1, "Search: ".Length + $query.Length), $Top)
        [Console]::CursorVisible = $true
    }

    function Write-MenuBody {
        param($Top)
        [Console]::SetCursorPosition(0, $Top)

        if ($query) {
            $note = if ($results.Count -gt 0 -and $results[0].Partial) { "   (no exact match - closest results)" } else { "" }
            Write-MenuRow "Search: $query" $MenuTheme.Search $note $MenuTheme.Desc
            $drawn = 0
            if ($results.Count -eq 0) { Write-MenuRow "    No matches." $MenuTheme.Error; $drawn++ }
            for ($i = 0; $i -lt $results.Count; $i++) {
                $r = $results[$i]
                $pointer = if ($i -eq $resultCursor) { "▸" } else { " " }
                $text = "$pointer   " + $r.Group.PadRight($groupWidth) + $r.Entry.DisplayName
                $color = if ($i -eq $resultCursor) { $MenuTheme.Cursor } else { $MenuTheme.Normal }
                Write-MenuRow $text $color
                $drawn++
            }
            # Blank out the rest of the reserved area (the full list, or in
            # -SearchOnly the results area)
            for (; $drawn -lt $listRows; $drawn++) { Write-MenuRow "" $MenuTheme.Normal }
            return
        }

        if ($SearchOnly) {
            Write-MenuRow "Search: " $MenuTheme.Search
            for ($i = 0; $i -lt $listRows; $i++) { Write-MenuRow "" $MenuTheme.Normal }
            return
        }

        Write-MenuRow "Search: " $MenuTheme.Hint "type to filter by name or description" $MenuTheme.Desc
        $activeHeaderIndex = 0
        for ($i = 0; $i -lt $rows.Count; $i++) { if ($rows[$i].IsHeader -and $i -le $cursor) { $activeHeaderIndex = $i } }
        for ($i = 0; $i -lt $rows.Count; $i++) {
            if ($rows[$i].IsHeader) {
                $headerColor = if ($i -eq $activeHeaderIndex) { $MenuTheme.HeaderActive } else { $MenuTheme.HeaderInactive }
                Write-MenuRow $rows[$i].Label $headerColor
            } else {
                $pointer = if ($i -eq $cursor) { "▸" } else { " " }
                $color = if ($i -eq $cursor) { $MenuTheme.Cursor } else { $MenuTheme.Normal }
                Write-MenuRow "$pointer   $($rows[$i].Label)" $color
            }
        }
    }

    if ($SearchOnly) {
        # No prompt/hint line — the search box is the whole UI (keys: Up/Down,
        # Enter, Esc). Results get whatever rows the window has left (it's
        # sized small on purpose).
        $listRows = [Math]::Min(15, [Math]::Max(3, [Console]::WindowHeight - [Console]::CursorTop - 2))
    } else {
        Write-Host "$Prompt (type to search, Up/Down: move, 1-9: jump to group, Enter: select, Esc: clear search / quit):" -ForegroundColor $MenuTheme.Hint
        $listRows = $rows.Count
    }

    # See the comment in Show-ProjectSelection — reserve rows before computing
    # $top so ConPTY-based terminals (Windows Terminal / VS Code) don't desync
    # the cursor position once the list is taller than the visible window.
    # +1 for the search line above the list.
    $height = $listRows + 1
    1..$height | ForEach-Object { Write-Host "" }
    $top = [Console]::CursorTop - $height
    [Console]::CursorVisible = $false
    Draw-Menu -Top $top
    # Warm the search up (synonym table + per-entry cache, ~100ms) now that
    # the menu is on screen and before the first key — so the first
    # keystroke isn't the slow one. Keys typed meanwhile just queue up.
    $null = Find-MenuEntries -Groups $Groups -Query "a"

    $selectedEntry = $null
    $done = $false
    while (-not $done) {
        $key = [Console]::ReadKey($true)
        $searching = $query.Length -gt 0
        $ctrl = ($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0
        # Ctrl+W = Ctrl+Backspace (delete word), the usual terminal alias
        $keyName = if ($ctrl -and $key.Key -eq [ConsoleKey]::W) { 'Backspace' } else { "$($key.Key)" }
        switch ($keyName) {
            'UpArrow' {
                if ($searching) {
                    if ($results.Count -gt 0) { $resultCursor = ($resultCursor - 1 + $results.Count) % $results.Count }
                } elseif (-not $SearchOnly) {
                    $pos = [array]::IndexOf($selectableIndices, $cursor)
                    $cursor = $selectableIndices[($pos - 1 + $selectableIndices.Count) % $selectableIndices.Count]
                }
                Draw-Menu -Top $top
            }
            'DownArrow' {
                if ($searching) {
                    if ($results.Count -gt 0) { $resultCursor = ($resultCursor + 1) % $results.Count }
                } elseif (-not $SearchOnly) {
                    $pos = [array]::IndexOf($selectableIndices, $cursor)
                    $cursor = $selectableIndices[($pos + 1) % $selectableIndices.Count]
                }
                Draw-Menu -Top $top
            }
            'Enter' {
                if ($searching) {
                    if ($results.Count -gt 0) { $selectedEntry = $results[$resultCursor].Entry; $done = $true }
                } elseif (-not $SearchOnly) {
                    $selectedEntry = $rows[$cursor].Entry
                    $done = $true
                }
            }
            'Escape' {
                if ($searching) {
                    $query = ""
                    Draw-Menu -Top $top
                } else {
                    $selectedEntry = $null
                    $done = $true
                }
            }
            'Backspace' {
                if ($searching) {
                    # Ctrl+Backspace: drop the last word and the spaces after it,
                    # like a normal text box ("pull db " -> "pull ")
                    $query = if ($ctrl) { $query -replace '\S*\s*$', '' } else { $query.Substring(0, $query.Length - 1) }
                    $results = @(Find-MenuEntries -Groups $Groups -Query $query | Select-Object -First $listRows)
                    $resultCursor = 0
                    Draw-Menu -Top $top
                }
            }
            default {
                $ch = $key.KeyChar
                if (-not $searching -and -not $SearchOnly -and $ch -match '^[1-9]$') {
                    $num = [int]"$ch"
                    if ($groupJumpTarget.ContainsKey($num)) {
                        $cursor = $groupJumpTarget[$num]
                        Draw-Menu -Top $top
                    }
                } elseif (-not [char]::IsControl($ch) -and ($searching -or $ch -ne ' ')) {
                    $query += $ch
                    $results = @(Find-MenuEntries -Groups $Groups -Query $query | Select-Object -First $listRows)
                    $resultCursor = 0
                    Draw-Menu -Top $top
                }
            }
        }
    }
    # A search result list is shorter than the reserved area (the rest is
    # blanked) — park the cursor right under the last result so whatever runs
    # next prints there, not below a gap of empty rows.
    $usedRows = if ($query) { 1 + [Math]::Max(1, $results.Count) } elseif ($SearchOnly) { 1 } else { $height }
    [Console]::SetCursorPosition(0, $top + $usedRows)
    [Console]::CursorVisible = $true
    return $selectedEntry
}

function Confirm-Prompt {
    param(
        [string]$Message,
        [bool]$DefaultYes = $true
    )
    $hint = if ($DefaultYes) { "[Y/n] (Default: Y)" } else { "[y/N] (Default: N)" }
    Write-Host "# $Message $hint : " -ForegroundColor $MenuTheme.Prompt -NoNewline
    $ans = Read-Host
    if ([string]::IsNullOrWhiteSpace($ans)) { return $DefaultYes }
    return ($ans -match '^[yY]')
}

Export-ModuleMember -Function Show-ProjectSelection, Show-Menu, Show-GroupedMenu, Confirm-Prompt
