# Lane step 5, plus the two findings that only show in the transcript:
#   * a breakpoint set DURING a session is re-armed and does stop the program
#   * the stop is announced BELOW the output that produced it
#   * the session ends once, saying why, and leaves no listening socket behind
#
# The window is moved to a known rectangle so the Output tab can be clicked
# without guessing where it ended up.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int t, bool repaint);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
}
"@

$shot = Join-Path $PSScriptRoot "shots"
New-Item -ItemType Directory -Force -Path $shot | Out-Null
Get-ChildItem $shot -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

$fix = Join-Path $PSScriptRoot "lane345.bas"

$p = Start-Process -FilePath "C:\Dev\PhosphorIDE\bin\phosphoride.exe" `
     -WorkingDirectory "C:\Dev\PhosphorIDE" -ArgumentList $fix -PassThru
Start-Sleep -Seconds 5
$p.Refresh()
Write-Output "pid=$($p.Id)"

[Win]::MoveWindow($p.MainWindowHandle, 0, 0, 1420, 960, $true) | Out-Null
Start-Sleep -Milliseconds 700

function Focus() {
  [Microsoft.VisualBasic.Interaction]::AppActivate($p.Id)
  Start-Sleep -Milliseconds 400
}

function Grab($name) {
  $bmp = New-Object System.Drawing.Bitmap 1420, 960
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
  $g.Dispose()
  $bmp.Save("$shot\$name.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output "  shot $name"
}

function Send($keys, $waitMs) {
  [System.Windows.Forms.SendKeys]::SendWait($keys)
  Start-Sleep -Milliseconds $waitMs
}

function Click($x, $y) {
  [Win]::SetCursorPos($x, $y)
  Start-Sleep -Milliseconds 150
  [Win]::mouse_event(0x02, 0, 0, 0, [IntPtr]::Zero)
  [Win]::mouse_event(0x04, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 400
}

function BreakAt($line) {
  Send "^g" 700
  Send "$line{ENTER}" 500
  Send "{F5}" 400
  Write-Output "  breakpoint on line $line"
}

Focus
BreakAt 10
Send "+{F9}" 4000
Grab "01-stopped-at-10"

# a breakpoint the host has never heard of, set while the program is paused
BreakAt 13
Send "{F6}" 3000
Grab "02-continued-to-13"

# the Output tab: 25 across, 189 up from the bottom edge of the window
Click 25 (960 - 189)
Grab "03-output-at-13"

Send "{F6}" 3000
Grab "04-finished"

Write-Output "listening sockets held by pid $($p.Id):"
$n = netstat -ano | Select-String "LISTENING" | Select-String "\s$($p.Id)\s*$"
if ($n) { $n | ForEach-Object { "  $_" } } else { Write-Output "  none" }

Write-Output "phosphor children still alive:"
$c = Get-Process phosphor -ErrorAction SilentlyContinue
if ($c) { $c | ForEach-Object { "  pid $($_.Id)" } } else { Write-Output "  none" }

$p.Id | Out-File "$shot\pid.txt" -Encoding ascii
Write-Output "done; pid $($p.Id) still up"
