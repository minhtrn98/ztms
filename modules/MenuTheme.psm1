# Central color palette for the interactive console menus in ProjectMenu.psm1.
# Change a color here once instead of hunting through every Draw-Menu.

$MenuTheme = [ordered]@{
    Cursor         = "Yellow"     # currently highlighted row
    Checked        = "Green"    # checkbox item toggled on
    Normal         = "DarkGray"     # unselected / unchecked item
    HeaderActive   = "DarkYellow" # group header the cursor is currently inside
    HeaderInactive = "Gray" # other, non-active group headers
    Hint           = "Cyan" # instructional line under the prompt
    Prompt         = "Cyan"     # Confirm-Prompt question text
    Error          = "Red"      # cancelled / no-entries messages
}

Export-ModuleMember -Variable MenuTheme
