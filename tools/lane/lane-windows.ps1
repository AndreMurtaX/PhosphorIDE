# The lane on Windows, driven from a step script -- the counterpart of
# lane-linux.sh, with which it shares SIX verbs of eight.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\lane\lane-windows.ps1 `
#              -Fixture tools\lane\deep.bas -Steps tools\lane\steps-stack.txt
#
# Commands, one per line: key <chord>, type <text>, wait <ms>, shot <name>,
# at <dx> <dy> (click, relative to the window's top-left), memo (print the Output
# pane's text), dblclick <dx> <dy>, says (dump what the accessibility layer sees),
# text <needle> (ASSERT that some control says it).
#
# `text` AND `says` ARRIVED ON 2026-09-17, with the stdin row's TextHint, because
# `memo` PRINTS and a lane that only prints is a lane somebody has to read. The
# Linux driver has counted its `text` assertions since roadmap item 28; this one
# had nothing of the kind, which is the same weaker question that side used to ask.
#
# TWO MEASUREMENTS PAID FOR THEM, and the first one was a wrong turn worth writing
# down. A TextHint looked like a string no message could reach: `Wnd::Kids` reported
# EditInput's text as EMPTY while the hint was plainly drawn in the screenshot
# beside it. That sent this file to EM_GETCUEBANNER, which DOES NOT ANSWER ACROSS A
# PROCESS BOUNDARY -- measured rather than assumed, with a buffer allocated in the
# editor by VirtualAllocEx and poisoned with 0x5A first: SendMessage returned FALSE,
# set no error, and left every poison byte untouched. Then to UI Automation, which
# did answer, and would have shipped a dependency and a paragraph of theory for a
# problem that was not there.
#
# THE PROBLEM THAT WAS THERE: `GetWindowTextLengthW` does not cross a process
# boundary for a control either. `Kids` calls it, gets 0, and skips the read -- so
# its text column is empty for exactly the controls a lane wants to assert on.
# Measured on EditInput the same day: GetWindowTextLengthW says 0 and an explicit
# WM_GETTEXTLENGTH says 45, which is the length of the hint. That is the trap at the
# bottom of win.ps1 met one API earlier, and nothing in this directory reads the
# column -- every caller already sends WM_GETTEXT for itself, and so does `text`.
#
# SO THE HINT IS ORDINARY WINDOW TEXT, ON BOTH PLATFORMS, and that is a fact about
# THIS binary rather than about Windows. The LCL answers lcTextHint YES on win32
# only for ComCtl IE6 and newer (win32object.inc:599-605); phosphoride ships no
# comctl32 v6 manifest, so the answer is NO and the LCL emulates the hint by writing
# it into the widget's real text (customedit.inc:707-721) -- the same path gtk2 takes
# for a different reason. IF SOMEBODY ADDS A MANIFEST, this case goes red here and
# stays green on Linux, and the reason will not be obvious: EM_SETCUEBANNER would
# then hold the hint where no cross-process message gives it back, and `text` would
# need UI Automation after all. That is the paragraph above, kept for that day.
#
# A CASE IS WRITTEN TWICE, NOT ONCE. This header said "the same commands so a
# case can be written once" until 2026-09-17, and it was wrong twice over.
#
# The VERBS only mostly match. Shared: `key`, `type`, `wait`, `raise`, `shot`,
# `at`. Here and not there: `dblclick`, `memo`. There and not here: `at2` (which
# is what `dblclick` is called on that side), `bot` and `bot2` (a click measured
# UP from the bottom edge, because mutter gives the window a different height on
# different runs), `outtab`, `rootshot` and `popshot`.
#
# And the KEY NAMES do not match at all: `key` here is SendKeys -- `^g`,
# `{ENTER}`, `{F5}`, `+{F9}` -- and on Linux it is an X keysym -- `ctrl+g`,
# `Return`, `F5`, `shift+F9`. Feeding one
# driver the other's script does not fail: SendKeys renders every token it does
# not recognise as LITERAL TEXT, so `steps-lane.txt` run here typed
# `ctrlGctrlA3ReturnF5...` into the fixture and drove nothing. It cost a run, and
# the only reason it cost no more is that this script kills the editor without
# saving.
#
# Hence the file names: `steps-NAME.txt` is this driver's and
# `steps-NAME-linux.txt` is lane-linux.sh's. FOUR FILES PREDATE THAT RULE and are
# Linux-only despite carrying no suffix -- `steps-lane.txt`, `steps-blocked.txt`,
# `steps-exception.txt` and `steps-stop.txt`. Their Windows counterparts are not
# missing; they are the earlier single-purpose drivers beside this one, with the
# steps baked into the PowerShell: lane-windows-steps.ps1, -session.ps1 and
# -exception.ps1.
#
# TRAP: Process.MainWindowHandle is NOT the form -- the LCL keeps a hidden
# top-level window holding Application.Title and Windows hands that one back, so
# GetWindowRect describes something invisible. win.ps1 enumerates the process's
# VISIBLE top-level windows instead.

[CmdletBinding()]
param(
    [string]$Fixture = '',
    [string]$Steps = '',
    [int]$StartupSeconds = 5,
    [switch]$KeepOpen
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot 'win.ps1')

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class LaneWin {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern int SendMessageW(IntPtr h, int msg, IntPtr wp, StringBuilder lp);
  [DllImport("user32.dll", EntryPoint="SendMessageW")]
  public static extern IntPtr SendMessageP(IntPtr h, int msg, IntPtr wp, IntPtr lp);
  public static string Text(IntPtr h) {
    int n = (int)SendMessageP(h, 0x000E, IntPtr.Zero, IntPtr.Zero);  // WM_GETTEXTLENGTH
    var sb = new StringBuilder(n + 2);
    SendMessageW(h, 0x000D, (IntPtr)(n + 1), sb);                    // WM_GETTEXT
    return sb.ToString();
  }
}
"@

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe = if ($env:PHOSPHORIDE) { $env:PHOSPHORIDE } else { Join-Path $root 'bin\phosphoride.exe' }
if (-not $Fixture) { $Fixture = Join-Path $PSScriptRoot 'lane345.bas' }
if (-not $Steps)   { $Steps   = Join-Path $PSScriptRoot 'steps-lane.txt' }
$Fixture = (Resolve-Path $Fixture).Path
$Steps = (Resolve-Path $Steps).Path

$shot = Join-Path $PSScriptRoot 'shots'
New-Item -ItemType Directory -Force -Path $shot | Out-Null
Get-ChildItem $shot -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

$p = Start-Process -FilePath $exe -WorkingDirectory $root -ArgumentList $Fixture -PassThru
Start-Sleep -Seconds $StartupSeconds
$form = [Wnd]::TopLevel($p.Id)
if ($form -eq [IntPtr]::Zero) { Write-Error 'no visible PhosphorIDE window'; exit 1 }
Write-Output "pid=$($p.Id) form=$form"

function Rect() {
    $r = New-Object Wnd+R
    [Wnd]::GetWindowRect($form, [ref]$r) | Out-Null
    return $r
}

function Focus() { [Wnd]::SetForegroundWindow($form) | Out-Null; Start-Sleep -Milliseconds 350 }

# SENDKEYS HAS NO TARGET WINDOW. It types into whatever holds the focus at the
# instant it fires, so every `key` and `type` below is an unaddressed letter --
# and on 2026-09-18 a whole case's worth of them was delivered into a chat window
# that happened to be in front, silently, while the screenshots photographed an
# editor that had received nothing.
#
# TRIES TO FIX IT FIRST, then refuses. A desktop can steal focus for a moment --
# a notification, a window finishing its paint -- and killing a run over that
# would make the driver useless. Three attempts at a third of a second, and if
# the editor still is not in front, the case goes RED and says which window took
# it. Anything is better than typing the test's own words into it.
function RequireFocus($what) {
    for ($i = 0; $i -lt 3; $i++) {
        if ([LaneWin]::GetForegroundWindow() -eq $form) { return $true }
        [Wnd]::SetForegroundWindow($form) | Out-Null
        Start-Sleep -Milliseconds 350
    }
    if ([LaneWin]::GetForegroundWindow() -eq $form) { return $true }
    $fg = [LaneWin]::GetForegroundWindow()
    $title = [LaneWin]::Text($fg)
    # WRITE-HOST, NOT WRITE-OUTPUT, and the difference is the whole function.
    # PowerShell makes a function's uncaptured output part of its RETURN VALUE,
    # so five Write-Output lines here came back to `if (RequireFocus ...)` as a
    # non-empty array -- which is true. The guard counted its own failure, printed
    # nothing, and let the keys through: a refusal that refused nothing. Measured
    # 2026-09-18 by pointing the comparison at a handle nothing can ever be and
    # watching the case type anyway.
    Write-Host "FOCUS FAIL  refusing to send '$what' -- the editor is not in front"
    Write-Host "            the foreground window is $fg '$title'"
    Write-Host "            SendKeys would have typed this into it. A Windows lane"
    Write-Host "            run owns the desktop for its duration; nothing else may"
    Write-Host "            use this machine while it is going."
    $script:Failures++
    $script:Assertions++
    return $false
}

function Grab($name) {
    $r = Rect
    $bmp = New-Object System.Drawing.Bitmap ($r.Rr - $r.L), ($r.B - $r.T)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
    $g.Dispose()
    $bmp.Save((Join-Path $shot "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "  shot $name"
}

function ClickAt($dx, $dy, $double) {
    $r = Rect
    [LaneWin]::SetCursorPos($r.L + $dx, $r.T + $dy) | Out-Null
    Start-Sleep -Milliseconds 150
    [LaneWin]::mouse_event(0x02, 0, 0, 0, [IntPtr]::Zero)
    [LaneWin]::mouse_event(0x04, 0, 0, 0, [IntPtr]::Zero)
    if ($double) {
        Start-Sleep -Milliseconds 80
        [LaneWin]::mouse_event(0x02, 0, 0, 0, [IntPtr]::Zero)
        [LaneWin]::mouse_event(0x04, 0, 0, 0, [IntPtr]::Zero)
    }
    Start-Sleep -Milliseconds 400
}

# The TMemo of whichever output tab is SHOWING: the longest VISIBLE Edit-class
# child with text in it.
#
# VISIBLE is the word that earns its keep. There are two TMemos in this window
# now -- MemoOutput on the Output tab and MemoRepl on the REPL tab -- and a
# helper that took the longest of ALL Edit-class children would quietly start
# reading the REPL transcript the moment it grew past the run's, in every
# existing `memo` step, with no error anywhere. Only the active tab's controls
# are visible, so visibility is the discriminator the LCL already provides; the
# component names do not cross the process boundary.
#
# GetWindowText does not cross that boundary for a control either -- it is
# documented and it fails by returning "" -- so WM_GETTEXT is sent explicitly.
function Memo() {
    $best = ''
    foreach ($row in [Wnd]::Kids($form)) {
        $f = $row -split "`t"
        if (($f[1] -eq 'Edit') -and ($f[3] -eq '1')) {
            $t = [LaneWin]::Text([IntPtr][long]$f[0])
            if ($t.Length -gt $best.Length) { $best = $t }
        }
    }
    if ($best) { Write-Output $best } else { Write-Output '(the pane is empty)' }
}

# EVERY VISIBLE CONTROL AND WHAT IT SAYS, for writing a case and for the report.
#
# VISIBLE, because only the active output tab's controls are, and the other seven
# tabs' are not -- the same discriminator `memo` uses, and for the same reason: the
# component names do not cross the process boundary but visibility does.
function Says() {
    $rows = @()
    foreach ($row in [Wnd]::Kids($form)) {
        $f = $row -split "`t"
        if ($f[3] -ne '1') { continue }
        $t = [LaneWin]::Text([IntPtr][long]$f[0])
        if ($t) { $rows += ("{0}`t{1}" -f $f[1], ($t -replace "`r`n", ' | ')) }
    }
    return $rows
}

$script:Failures = 0
# HOW MANY QUESTIONS THIS CASE ACTUALLY ASKED. Audited 2026-09-18: twenty-two of
# the twenty-three cases on this side asked NONE. Every one printed
# `text assertions: all passed` and exited 0, because a failure counter that is
# never incremented is zero -- so re-running them proved the program starts and
# does not crash while keys are sent at it, and nothing else.
$script:Assertions = 0

# `text <needle>` -- the assertion, named for the Linux driver's verb because it
# asks the same question: does some control in this window SAY this to the person
# in front of it. WM_GETTEXT is sent explicitly to each one; see the header for
# why the text `Kids` already carries cannot be used for it.
function Text($needle) {
    $script:Assertions++
    foreach ($row in [Wnd]::Kids($form)) {
        $f = $row -split "`t"
        if ($f[3] -ne '1') { continue }
        if ([LaneWin]::Text([IntPtr][long]$f[0]).Contains($needle)) {
            Write-Output "TEXT OK   $needle"
            return
        }
    }
    Write-Output "TEXT FAIL no control says: $needle"
    $script:Failures++
}

Focus
foreach ($line in Get-Content -LiteralPath $Steps) {
    $line = $line.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    $verb, $rest = $line -split '\s+', 2
    switch ($verb) {
        # <space> is spelled out because every line is trimmed, and SendKeys has
        # no {SPACE} of its own -- so "key ^ " would arrive as "key ^".
        'key'      { if (RequireFocus $rest) { [System.Windows.Forms.SendKeys]::SendWait(($rest -replace '<space>', ' ')); Start-Sleep -Milliseconds 120 } }
        # TYPE IS LITERAL TEXT AND KEY IS A CHORD, so this escapes what SendKeys
        # would otherwise read as syntax: + ^ % ~ ( ) { } [ ] each go in braces.
        # Paid for on 2026-09-16 -- "type s = mid$(" opened a modifier group and
        # ate the characters after it, and the line came out as "s = mid$ bc",".
        #
        # AND IT BROKE FIVE SCRIPTS THAT WERE ALREADY WRITTEN, silently, for a
        # day. `type 10{ENTER}` was the idiom before this escaping existed, and
        # afterwards it typed the eight characters `10{ENTER}` into the Go to
        # line box and pressed nothing -- so the dialog stayed up, every step
        # after it went into a modal nobody closed, and the run still produced
        # its screenshots and reported no error. Found on 2026-09-17 by writing
        # a sixth script with the same idiom and looking at the picture.
        # `steps-gutter`, `-gutter-edit`, `-stack`, `-stack-jump` and
        # `-stack-running` now say `type 10` then `key {ENTER}`, which is what
        # the split between these two verbs was always for. A step file written
        # against one version of its driver is not a fixture; it is a caller.
        'type'     {
            $lit = -join ($rest.ToCharArray() | ForEach-Object {
                if ('+^%~(){}[]'.Contains($_)) { '{' + $_ + '}' } else { $_ } })
            if (RequireFocus $rest) { [System.Windows.Forms.SendKeys]::SendWait($lit); Start-Sleep -Milliseconds 120 }
        }
        'wait'     { Start-Sleep -Milliseconds ([int]$rest) }
        'shot'     { Grab $rest }
        'raise'    { Focus }
        'memo'     { Write-Output "--- output pane ---"; Memo; Write-Output "--- end ---" }
        'says'     { Write-Output "--- what this window says ---"
                     Says | ForEach-Object { Write-Output "  $_" }
                     Write-Output "--- end ---" }
        # <space> as in `key`, because every line is trimmed: `text a  b` would
        # otherwise lose the run of spaces a transcript actually contains.
        'text'     { Text ($rest -replace '<space>', ' ') }
        'at'       { $c = $rest -split '\s+'; ClickAt ([int]$c[0]) ([int]$c[1]) $false }
        'dblclick' { $c = $rest -split '\s+'; ClickAt ([int]$c[0]) ([int]$c[1]) $true }
        default    { Write-Error "unknown command: $verb"; }
    }
}

$r = Rect
Write-Output "window $($r.L),$($r.T) $($r.Rr - $r.L)x$($r.B - $r.T)"
Write-Output "--- phosphor children ---"
$c = Get-Process phosphor -ErrorAction SilentlyContinue
if ($c) { $c | ForEach-Object { "  pid $($_.Id)" } } else { Write-Output "  none" }

if ($KeepOpen) {
    Write-Output "pid $($p.Id) left running"
} else {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    # AND THE CHILD. Killing the editor does not kill the program it was
    # debugging: a phosphor stopped at a breakpoint, or blocked on input, simply
    # loses the only thing that was going to tell it to continue. Leaving one of
    # those on someone's desktop is how this project learned to check.
    Start-Sleep -Milliseconds 400
    $orphans = Get-Process phosphor -ErrorAction SilentlyContinue
    if ($orphans) {
        $orphans | ForEach-Object {
            Write-Output "  killing orphaned phosphor pid $($_.Id)"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Output "closed"
}

# The verdict LAST and in the exit code, so a run can be scripted rather than
# watched -- and after the teardown above, because a case that fails its
# assertions must still not leave a phosphoride holding bin\phosphoride.exe open
# for the next build.
if ($script:Assertions -eq 0) {
    # NOT A PASS. This case drove the editor and photographed it, which is
    # evidence exactly once -- on the day somebody looked at the pictures. As a
    # gate it asked nothing, so it cannot go red.
    Write-Output ''
    Write-Output 'THIS CASE ASSERTS NOTHING: 0 text checks.'
    Write-Output 'Screenshots and `memo` dumps are evidence when a person reads them,'
    Write-Output 'and a gate only when something compares them. Give it a `text` line,'
    Write-Output 'or run it knowing it can only fail by crashing.'
    exit 1
}
if ($script:Failures -gt 0) {
    Write-Output "TEXT ASSERTIONS FAILED: $($script:Failures) of $($script:Assertions)"
    exit 1
}
Write-Output "$($script:Assertions) assertion(s), all passed"
exit 0
