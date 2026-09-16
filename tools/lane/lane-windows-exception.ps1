# Lane step 5's other half: an exception stop is terminal and read-only, and the
# engine's own message has to reach the user because nothing else carries it.
#
# Also the line-1 question: a breakpoint on the first statement is reported as
# INSTALLED and then never fires, which is a claim step 3 leans on.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$s = $PSScriptRoot
. "$s\win.ps1"
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Txt3 {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern int SendMessageW(IntPtr h, int msg, IntPtr wp, StringBuilder lp);
  [DllImport("user32.dll", EntryPoint="SendMessageW")]
  public static extern IntPtr SendMessageP(IntPtr h, int msg, IntPtr wp, IntPtr lp);
  public static string Get(IntPtr h) {
    int n = (int)SendMessageP(h, 0x000E, IntPtr.Zero, IntPtr.Zero);
    var sb = new StringBuilder(n + 2);
    SendMessageW(h, 0x000D, (IntPtr)(n + 1), sb);
    return sb.ToString();
  }
}
"@

$shot = Join-Path $PSScriptRoot "shots"
New-Item -ItemType Directory -Force -Path $shot | Out-Null
Get-ChildItem $shot -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

$p = Start-Process -FilePath "C:\Dev\PhosphorIDE\bin\phosphoride.exe" `
     -WorkingDirectory "C:\Dev\PhosphorIDE" -ArgumentList "$s\boom.bas" -PassThru
Start-Sleep -Seconds 5
$form = [Wnd]::TopLevel($p.Id)
Write-Output "pid=$($p.Id) form=$form"

function Focus() { [Wnd]::SetForegroundWindow($form) | Out-Null; Start-Sleep -Milliseconds 400 }
function Send($k, $w) { [System.Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds $w }
function Grab($name) {
  $r = New-Object Wnd+R
  [Wnd]::GetWindowRect($form, [ref]$r) | Out-Null
  $bmp = New-Object System.Drawing.Bitmap ($r.Rr - $r.L), ($r.B - $r.T)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
  $g.Dispose()
  $bmp.Save("$shot\$name.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output "  shot $name"
}
function Memo() {
  foreach ($row in [Wnd]::Kids($form)) {
    $f = $row -split "`t"
    if ($f[1] -eq 'Edit') {
      $t = [Txt3]::Get([IntPtr][long]$f[0])
      if ($t.Length -gt 0) { return $t }
    }
  }
  return '(no memo text)'
}

Focus
# line 1 is the first statement. The question is whether anything stops there.
Send "^g" 700
Send "1{ENTER}" 500
Send "{F5}" 400
Send "+{F9}" 5000
Grab "01-line-1-breakpoint"
Write-Output "--- after start, breakpoint on line 1 ---"
Memo
Write-Output "--- end ---"

# whatever happened above, drive on to the division by zero
Send "{F6}" 3000
Grab "02-after-continue"
Send "{F6}" 3000
Grab "03-exception"
Write-Output "--- final transcript ---"
Memo
Write-Output "--- end ---"

Focus
Send "%d" 800
Grab "04-debug-menu-at-exception"
Send "{ESC}" 500

Write-Output "listening sockets held by pid $($p.Id):"
$n = netstat -ano | Select-String "LISTENING" | Select-String "\s$($p.Id)\s*$"
if ($n) { $n | ForEach-Object { "  $_" } } else { Write-Output "  none" }
Write-Output "phosphor children still alive:"
$c = Get-Process phosphor -ErrorAction SilentlyContinue
if ($c) { $c | ForEach-Object { "  pid $($_.Id)" } } else { Write-Output "  none" }
Write-Output "done; pid $($p.Id) still up"
