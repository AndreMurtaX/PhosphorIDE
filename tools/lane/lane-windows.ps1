# The lane on Windows, driven from a step script -- the counterpart of
# lane-linux.sh, taking the same commands so a case can be written once.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\lane\lane-windows.ps1 `
#              -Fixture tools\lane\deep.bas -Steps tools\lane\steps-stack.txt
#
# Commands, one per line: key <chord>, type <text>, wait <ms>, shot <name>,
# at <dx> <dy> (click, relative to the window's top-left), memo (print the Output
# pane's text), dblclick <dx> <dy>.
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

Focus
foreach ($line in Get-Content -LiteralPath $Steps) {
    $line = $line.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    $verb, $rest = $line -split '\s+', 2
    switch ($verb) {
        # <space> is spelled out because every line is trimmed, and SendKeys has
        # no {SPACE} of its own -- so "key ^ " would arrive as "key ^".
        'key'      { [System.Windows.Forms.SendKeys]::SendWait(($rest -replace '<space>', ' ')); Start-Sleep -Milliseconds 120 }
        # TYPE IS LITERAL TEXT AND KEY IS A CHORD, so this escapes what SendKeys
        # would otherwise read as syntax: + ^ % ~ ( ) { } [ ] each go in braces.
        # Paid for on 2026-09-16 -- "type s = mid$(" opened a modifier group and
        # ate the characters after it, and the line came out as "s = mid$ bc",".
        'type'     {
            $lit = -join ($rest.ToCharArray() | ForEach-Object {
                if ('+^%~(){}[]'.Contains($_)) { '{' + $_ + '}' } else { $_ } })
            [System.Windows.Forms.SendKeys]::SendWait($lit); Start-Sleep -Milliseconds 120
        }
        'wait'     { Start-Sleep -Milliseconds ([int]$rest) }
        'shot'     { Grab $rest }
        'raise'    { Focus }
        'memo'     { Write-Output "--- output pane ---"; Memo; Write-Output "--- end ---" }
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
