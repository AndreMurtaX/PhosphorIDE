# Drive the editor through lane steps 3 and 4 against the real host, and grab a
# frame at each point where the claim is visible.
#
# Keys are the product's own: Ctrl+G go to line, F5 toggle breakpoint,
# Shift+F9 start debugging, F8 step over, F7 step into, Shift+F8 step out,
# F6 continue.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$shot = Join-Path $PSScriptRoot "shots"
New-Item -ItemType Directory -Force -Path $shot | Out-Null
Get-ChildItem $shot -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

$fix = Join-Path $PSScriptRoot "lane345.bas"

# The repository root is two levels up, so this runs from a checkout
# rather than from wherever it was written. $env:PHOSPHORIDE overrides
# for a binary built somewhere else.
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe = if ($env:PHOSPHORIDE) { $env:PHOSPHORIDE } else { Join-Path $root "bin\phosphoride.exe" }

$p = Start-Process -FilePath $exe `
     -WorkingDirectory $root -ArgumentList $fix -PassThru
Start-Sleep -Seconds 5
$p.Refresh()
Write-Output "pid=$($p.Id)"

function Focus() {
  [Microsoft.VisualBasic.Interaction]::AppActivate($p.Id)
  Start-Sleep -Milliseconds 400
}

function Grab($name) {
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
  $g.Dispose()
  $bmp.Save("$shot\$name.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output "  shot $name"
}

function Send($keys, $waitMs) {
  [System.Windows.Forms.SendKeys]::SendWait($keys)
  Start-Sleep -Milliseconds $waitMs
}

function BreakAt($line) {
  Send "^g" 700
  Send "$line{ENTER}" 500
  Send "{F5}" 400
  Write-Output "  breakpoint toggled on line $line"
}

Focus
# line 3 is blank: the host cannot arm it. line 10 is a statement.
BreakAt 3
BreakAt 10
Grab "01-two-marks-before-debug"

Send "+{F9}" 4000
Grab "02-stopped-at-10"

Send "{F8}" 1500
Grab "03-step-over-to-11"

Send "{F8}" 1500
Grab "04-step-over-to-12"

Send "{F7}" 1500
Grab "05-step-into-add"

Send "+{F8}" 1500
Grab "06-step-out"

Send "{F6}" 2500
Grab "07-after-continue"

netstat -ano | Select-String "  $($p.Id)$" | Select-Object -First 20 | ForEach-Object { "  net: $_" }

$p.Id | Out-File "$shot\pid.txt" -Encoding ascii
Write-Output "done; pid $($p.Id) still up"
