# Shared interactive checkbox menu, deduplicated from the original per-script copies.

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
            $color = if ($i -eq $cursor) { "Yellow" } elseif ($i -ne $confirmIndex -and $checked[$i]) { "Green" } else { "White" }
            if ($i -eq $confirmIndex) {
                Write-Host ("$pointer     $($menuItems[$i])".PadRight(60)) -ForegroundColor $color
            } else {
                $mark = if ($checked[$i]) { "[x]" } else { "[ ]" }
                Write-Host ("$pointer $mark $($menuItems[$i])".PadRight(60)) -ForegroundColor $color
            }
        }
    }

    Write-Host "Select projects (Up/Down: move, Enter: toggle / confirm, Tab: jump to confirm, Esc: cancel - none checked = all):" -ForegroundColor Cyan

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
        Write-Host "Cancelled." -ForegroundColor DarkYellow
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
            $color = if ($i -eq $cursor) { "Yellow" } else { "White" }
            Write-Host ("$pointer $($Labels[$i])".PadRight(70)) -ForegroundColor $color
        }
    }

    Write-Host "$Prompt (Up/Down: move, Enter: select, Esc: quit):" -ForegroundColor Cyan

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
    Each group's Name is rendered as a non-selectable header; Up/Down skip
    over headers so only actual entries can be highlighted. Returns the
    selected entry object (from Group.Entries), or $null on Escape.
    #>
    param(
        [Parameter(Mandatory)]$Groups,
        [string]$Prompt = "Select an option"
    )

    $rows = @()
    foreach ($group in $Groups) {
        $rows += [ordered]@{ IsHeader = $true; Label = $group.Name; Entry = $null }
        foreach ($entry in $group.Entries) {
            $label = "{0,-32} {1}" -f $entry.DisplayName, $entry.Desc
            $rows += [ordered]@{ IsHeader = $false; Label = $label; Entry = $entry }
        }
    }

    $selectableIndices = @()
    for ($i = 0; $i -lt $rows.Count; $i++) { if (-not $rows[$i].IsHeader) { $selectableIndices += $i } }

    if ($selectableIndices.Count -eq 0) {
        Write-Host "No entries to show." -ForegroundColor Red
        return $null
    }

    $cursor = $selectableIndices[0]

    function Draw-Menu {
        param($Top)
        [Console]::SetCursorPosition(0, $Top)
        for ($i = 0; $i -lt $rows.Count; $i++) {
            if ($rows[$i].IsHeader) {
                Write-Host ("🔘 $($rows[$i].Label)".PadRight(70)) -ForegroundColor Magenta
            } else {
                $pointer = if ($i -eq $cursor) { ">" } else { " " }
                $color = if ($i -eq $cursor) { "Yellow" } else { "White" }
                Write-Host ("$pointer   $($rows[$i].Label)".PadRight(70)) -ForegroundColor $color
            }
        }
    }

    Write-Host "$Prompt (Up/Down: move, Enter: select, Esc: quit):" -ForegroundColor Cyan

    # See the comment in Show-ProjectSelection — reserve rows before computing
    # $top so ConPTY-based terminals (Windows Terminal / VS Code) don't desync
    # the cursor position once the list is taller than the visible window.
    1..$rows.Count | ForEach-Object { Write-Host "" }
    $top = [Console]::CursorTop - $rows.Count
    [Console]::CursorVisible = $false
    Draw-Menu -Top $top

    $selectedEntry = $null
    $done = $false
    while (-not $done) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow' {
                $pos = [array]::IndexOf($selectableIndices, $cursor)
                $pos = ($pos - 1 + $selectableIndices.Count) % $selectableIndices.Count
                $cursor = $selectableIndices[$pos]
                Draw-Menu -Top $top
            }
            'DownArrow' {
                $pos = [array]::IndexOf($selectableIndices, $cursor)
                $pos = ($pos + 1) % $selectableIndices.Count
                $cursor = $selectableIndices[$pos]
                Draw-Menu -Top $top
            }
            'Enter' {
                $selectedEntry = $rows[$cursor].Entry
                $done = $true
            }
            'Escape' {
                $selectedEntry = $null
                $done = $true
            }
        }
    }
    [Console]::CursorVisible = $true
    return $selectedEntry
}

function Confirm-Prompt {
    param(
        [string]$Message,
        [bool]$DefaultYes = $true
    )
    $hint = if ($DefaultYes) { "[Y/n] (Default: Y)" } else { "[y/N] (Default: N)" }
    Write-Host "# $Message $hint : " -ForegroundColor Cyan -NoNewline
    $ans = Read-Host
    if ([string]::IsNullOrWhiteSpace($ans)) { return $DefaultYes }
    return ($ans -match '^[yY]')
}

Export-ModuleMember -Function Show-ProjectSelection, Show-Menu, Show-GroupedMenu, Confirm-Prompt
