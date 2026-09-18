# What this window says, through UI Automation -- the Windows answer to
# tools/lane/readtext.py.
#
# WHY THIS EXISTS. `Says` in lane-windows.ps1 sends WM_GETTEXT to every visible
# child, and on 2026-09-18 that was MEASURED against the whole editor with a file
# open and nothing running. It sees four things:
#
#     Edit                 An answer for the running program, then Enter
#     Button               Send
#     msctls_statusbar32   1: 1
#     Window               ToolBar1
#
# That is the entire readable surface, and it explains a fact this repository had
# recorded as a mystery: eighteen of the nineteen Windows cases assert nothing.
# It is not that nobody wrote the assertions -- it is that `text` could not reach
# a single thing those cases are about. WM_GETTEXT is a window message about a
# window's OWN caption. A SysListView32 keeps its rows in items, a SysTreeView32
# in nodes, and both answer it with nothing; the Problems rows, the call stack,
# the variables, the watches, the outline and the find-in-files hits are all one
# of those two. SynEdit is a custom control with no caption at all. And the status
# bar answers with the FIRST panel only, which is why `1: 1` is the one string
# every Linux case kept accidentally matching.
#
# UI Automation is the instrument that reaches them, and it is the same shape of
# answer AT-SPI gives on the other side: a tree of elements, each with a control
# type, a name and sometimes a value. The LCL's win32 widgetset uses the real
# common controls, so UIA's built-in providers describe them without the editor
# knowing anything about it -- no accessibility flag to set, no module to load,
# which is the one way this differs from gtk2 (where GTK_MODULES=gail:atk-bridge
# is required or the program describes nothing).
#
# WHAT IT STILL WILL NOT REACH, measured rather than assumed -- see the dump the
# `uia` verb writes. A custom control that implements no UIA provider appears as
# a bare pane with a class name and no text, exactly as it does to WM_GETTEXT.
#
# TWO SURFACES, ASKED SEPARATELY AND ON PURPOSE. `text` keeps its WM_GETTEXT
# question and `uia` is its own verb. Folding one into the other would make a
# failure ambiguous -- "no control says this" would stop meaning anything precise
# -- and this session has already spent a day on an instrument that was trusted
# before it was measured.

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# THE MANAGED UIA CLIENT DOES NOT LOAD THE WIN32 PROXIES BY ITSELF, and without
# this line the instrument is a more expensive WM_GETTEXT. Measured 2026-09-18:
# the first cut of this file described the whole editor as
#
#     Pane [SysTabControl32]
#     Pane [msctls_statusbar32]  1: 1
#     Pane [Edit]
#
# -- every element a `Pane`, every name a window caption, which is the HWND
# fallback provider answering for controls that have real UIA representations.
# A SysTabControl32 is a Tab with TabItem children, a msctls_statusbar32 is a
# StatusBar with one element PER PANEL rather than the first one's text, and a
# SysListView32 has its rows. Those live in UIAutomationClientsideProviders.dll
# and the CLIENT has to ask for them; the unmanaged client loads them and the
# managed one, which is what PowerShell gets from Add-Type, does not.
#
# It is worth knowing which half of this an assertion rests on: nothing here is
# a change to the editor, and a control's UIA shape is the proxy's opinion of a
# common control, not something PhosphorIDE implements or could break.
#
# REGISTERED BY TABLE, NOT BY ASSEMBLY NAME. The documented
# `RegisterClientSideProviderAssembly(AssemblyName)` throws a
# NullReferenceException here -- it reflects for a type it then does not find in
# the shape it wants -- while the table the assembly publishes is a public static
# field and handing it to `RegisterClientSideProviders` does the same job with
# nothing to go wrong. Measured, both ways, 2026-09-18.
#
# AND THE ROOT ELEMENT IS TOUCHED FIRST, which is the whole of the third attempt.
# Registering into a client that has not initialised throws the SAME
# NullReferenceException as the assembly-name form, from inside the framework,
# with no inner stack -- so the two failures are indistinguishable and the first
# one sends you looking for a missing type that is present. Reading
# `AutomationElement.RootElement` is what starts the client; after that the
# registration takes. The table has forty entries, which is the number to check
# if this ever silently becomes a no-op.
Add-Type -AssemblyName UIAutomationClientsideProviders
$null = [System.Windows.Automation.AutomationElement]::RootElement
[System.Windows.Automation.ClientSettings]::RegisterClientSideProviders(
    [UIAutomationClientsideProviders.UIAutomationClientSideProviders]::ClientSideProviderDescriptionTable)

# The tree under a window handle, one row per element.
#
# ControlViewWalker rather than RawViewWalker: the raw view carries every
# implementation detail the provider chose to expose and is three times the rows
# for nothing a person would assert on. Depth is capped because a provider that
# returns itself as its own child is a hang, not an error.
function UiaRows($h, $maxDepth = 14) {
    $rows = New-Object System.Collections.Generic.List[object]
    $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$h)
    if (-not $root) { return $rows }
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker

    function Visit($el, $d) {
        if ($d -gt $maxDepth) { return }
        try {
            $c = $el.Current
            $v = ''
            $pat = $null
            if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pat)) {
                $v = $pat.Current.Value
            }
            $rows.Add([pscustomobject]@{
                Depth = $d
                Type  = ($c.ControlType.ProgrammaticName -replace 'ControlType\.', '')
                Class = $c.ClassName
                Name  = ($c.Name -replace "`r`n", ' | ')
                Value = ($v -replace "`r`n", ' | ')
                Off   = $c.IsOffscreen
                El    = $el
            })
        } catch {
            # An element that went away between the walk and the read is not a
            # failure of the walk. It is reported so a dump nobody can explain
            # does not look like a complete one.
            $rows.Add([pscustomobject]@{
                Depth = $d; Type = '(gone)'; Class = ''; Name = "$_"; Value = ''; Off = $true; El = $null
            })
            return
        }
        $kid = $walker.GetFirstChild($el)
        while ($kid) {
            Visit $kid ($d + 1)
            $kid = $walker.GetNextSibling($kid)
        }
    }

    Visit $root 0
    return $rows
}

# EVERY element that says anything, for writing a case and for the report.
#
# `uiasays all` keeps the silent ones too, which is how you find out whether a
# pane is absent from the tree or merely nameless -- two very different answers
# that look identical once they are filtered out.
function UiaSays($h, $all = $false) {
    foreach ($r in UiaRows $h) {
        if (-not $all -and -not $r.Name -and -not $r.Value) { continue }
        $mark = if ($r.Off) { 'off' } else { '   ' }
        '{0} {1}{2} [{3}] {4}{5}' -f $mark, (' ' * $r.Depth), $r.Type, $r.Class, $r.Name,
            $(if ($r.Value) { " = $($r.Value)" } else { '' })
    }
}

# Does anything ON SCREEN say this?
#
# OFFSCREEN IS NOT A MATCH, and that is the same rule the Linux side had to learn
# about its notebook: gtk2 leaves SHOWING on the page you just left, and UIA
# leaves a whole hidden tab page in the tree with IsOffscreen set. A verb that
# ignored the flag would assert that the Watches pane says something while the
# Problems pane is the one in front of the person.
function UiaFind($h, $needle) {
    foreach ($r in UiaRows $h) {
        if ($r.Off) { continue }
        if (($r.Name -and $r.Name.Contains($needle)) -or
            ($r.Value -and $r.Value.Contains($needle))) {
            return $r
        }
    }
    return $null
}

# `uiatab <name>` -- select an output tab BY ITS NAME, and then check that it is
# the selected one.
#
# THE WINDOWS TWIN OF THE LINUX `tab` VERB, and it exists for the same reason and
# was written after the same mistake. Every pane in this window except Output is
# reached in the existing cases by clicking a pixel, and those pixels were right
# on the day they were written: the eight tabs share one row whose widths depend
# on the font, so `at 300 588` selects Problems on one machine and Find in Files
# on another, and nothing says which one it got.
#
# SELECTION IS ASKED OF THE TAB CONTROL, not of the tab's state. On the gtk2 side
# a page tab carries no SELECTED state at all and the notebook's Selection
# interface is the only thing that answers -- and here SelectionItemPattern does
# both halves, so the verb selects and then reads back what is selected rather
# than assuming the click took.
function UiaTab($h, $name) {
    # EXACT, THEN UNIQUE PREFIX -- because a tab's caption is not a constant.
    # Measured 2026-09-18: while the program is stopped the captions read
    # `Call Stack (5)` and `Variables (3)`, so an exact match finds nothing at
    # precisely the moment every case that wants those panes is looking. The
    # prefix has to be UNIQUE or this is the locator-drift defect again.
    $rows = UiaRows $h
    $tabs = @($rows | Where-Object { $_.Type -eq 'TabItem' })
    $hits = @($tabs | Where-Object { $_.Name -eq $name })
    if ($hits.Count -eq 0) {
        $hits = @($tabs | Where-Object { $_.Name.StartsWith($name) })
    }
    if ($hits.Count -ne 1) {
        return "TAB FAIL  $($hits.Count) tabs named: $name  [$(($tabs | ForEach-Object { $_.Name }) -join ', ')]"
    }
    $name = $hits[0].Name
    $pat = $null
    if (-not $hits[0].El.TryGetCurrentPattern(
            [System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pat)) {
        return "TAB FAIL  tab cannot be selected: $name"
    }
    $pat.Select()
    Start-Sleep -Milliseconds 400
    # READ IT BACK. A Select() that silently did nothing looks exactly like one
    # that worked, which is the whole of what the Linux side got wrong first.
    $pat2 = $null
    $back = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$h)
    foreach ($r in UiaRows $h) {
        if ($r.Type -ne 'TabItem' -or $r.Name -ne $name) { continue }
        if ($r.El.TryGetCurrentPattern(
                [System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pat2)) {
            if ($pat2.Current.IsSelected) { return "TAB OK    $name" }
        }
    }
    return "TAB FAIL  selected nothing: $name"
}

# `uiamenu <top> <item>` -- open a menu and invoke an item in it, by name.
#
# The menu bar is the one part of this window a synthetic click has never been
# able to reach reliably on either platform: on gtk2 neither a click nor F10
# answers and the AT-SPI action does, and here the Alt accelerators are shadowed
# by the toolbar's own captions -- the trap this repository paid for on
# 2026-09-16, where `S&top` on the toolbar answered Alt+T and killed the debuggee
# instead of opening Preferences. Invoking the item is the question a person's
# click asks, without the keyboard in the way.
function UiaMenu($h, $top, $item) {
    $rows = UiaRows $h
    $m = @($rows | Where-Object { $_.Type -eq 'MenuItem' -and $_.Name -eq $top })
    if ($m.Count -ne 1) { return "MENU FAIL $($m.Count) top-level menus named: $top" }
    $ex = $null
    if ($m[0].El.TryGetCurrentPattern(
            [System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$ex)) {
        $ex.Expand()
    } else {
        $iv = $null
        if (-not $m[0].El.TryGetCurrentPattern(
                [System.Windows.Automation.InvokePattern]::Pattern, [ref]$iv)) {
            return "MENU FAIL cannot open: $top"
        }
        $iv.Invoke()
    }
    Start-Sleep -Milliseconds 500
    if (-not $item) { return "MENU OK   $top (opened)" }
    # THE POPUP IS NOT UNDER THE WINDOW. A menu opens as its own top-level
    # window, so the item is looked for from the desktop root rather than from
    # the editor's handle -- searching the editor's subtree finds the bar and
    # never the popup.
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::MenuItem)),
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, $item)))
    $found = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if (-not $found) { return "MENU FAIL no item named: $item" }
    $iv2 = $null
    if (-not $found.TryGetCurrentPattern(
            [System.Windows.Automation.InvokePattern]::Pattern, [ref]$iv2)) {
        return "MENU FAIL item cannot be invoked: $item"
    }
    $iv2.Invoke()
    Start-Sleep -Milliseconds 600
    return "MENU OK   $top > $item"
}
