# Replace in files, end to end, against a fixture directory -- roadmap item 21.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\lane\replace-tree.ps1
#
# WHY THIS IS A SCRIPT AND NOT A steps-*.txt. Every other lane case drives a
# fixture that is checked in and read; this one CHANGES files, and a case that
# rewrites something under tools/lane leaves the repository dirty after every
# run. So the tree is built in the temp directory, the lane is pointed at it, and
# the bytes are compared before and after -- which is also the only way to check
# the half of item 21 that no screenshot can show: that the files nobody listed
# were not touched, and that the ones that were kept their line endings.
#
# WHAT THE FOUR FILES ARE FOR:
#
#   a.bas      OPEN in the editor, so it takes the BUFFER route. Its bytes ON
#              DISK must NOT change: the replace lives in the buffer, one Ctrl+Z
#              undoes all of it, and the tab shows modified until it is saved.
#   b.bas      CRLF, not open. Rewritten in place, and CRLF must survive.
#   sub\c.bas  LF with NO closing newline, in a subdirectory. Rewritten, and it
#              must not gain one.
#   d.bas      matches nothing. Must be byte-identical, and is never opened.
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent (Split-Path -Parent $here)
$root = Join-Path $env:TEMP 'phosphoride-replace-tree'
if (Test-Path $root) { Remove-Item $root -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $root 'sub') -Force | Out-Null

function Put($rel, $text) {
  [System.IO.File]::WriteAllBytes((Join-Path $root $rel),
                                  [System.Text.Encoding]::UTF8.GetBytes($text))
}
function Hex($rel) {
  (([System.IO.File]::ReadAllBytes((Join-Path $root $rel)) |
      ForEach-Object { $_.ToString('X2') }) -join ' ')
}

Put 'a.bas'     "rem alpha one`nx = alpha`nrem three`n"
Put 'b.bas'     "rem alpha`r`ny = 2`r`n"
Put 'sub\c.bas' "z = alpha"
Put 'd.bas'     "nothing here`n"

$files = @('a.bas', 'b.bas', 'sub\c.bas', 'd.bas')
$before = @{}
foreach ($f in $files) { $before[$f] = Hex $f }

# The coordinates are the find pane's three rows, measured from
# shots/300-find-pane-with-replace.png: Find at y=589, In at y=616, Replace at
# y=645, and the Replace button at x=475 on that row.
$steps = @"
raise
key ^+f
wait 800
type alpha
wait 300
at 200 616
wait 400
key ^a
type $root
wait 400
at 200 589
wait 400
key {ENTER}
wait 2000
shot 330-the-rows-the-search-listed
at 200 645
wait 400
type beta
wait 400
at 475 645
wait 900
shot 331-the-question-with-the-counts
key {ENTER}
wait 1500
raise
wait 500
shot 332-replaced-and-the-tab-is-modified
at 300 130
wait 500
key ^z
wait 900
raise
wait 400
shot 333-one-undo-took-it-all-back
"@
$stepFile = Join-Path $root 'steps.txt'
Set-Content $stepFile $steps -Encoding ascii

Push-Location $repo
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'lane-windows.ps1') `
  -Fixture (Join-Path $root 'a.bas') -Steps $stepFile 2>&1 |
  Select-String -Pattern 'pid=|window ' | ForEach-Object { $_.Line }
Pop-Location

$expect = @{
  'a.bas'     = 'INTACTO'   # open in a tab: the change is in the buffer
  'b.bas'     = 'MUDOU'
  'sub\c.bas' = 'MUDOU'
  'd.bas'     = 'INTACTO'
}
$bad = 0
''
'{0,-12} {1,-9} {2,-9} {3}' -f 'file', 'expected', 'got', 'bytes now'
foreach ($f in $files) {
  $after = Hex $f
  $got = if ($after -eq $before[$f]) { 'INTACTO' } else { 'MUDOU' }
  if ($got -ne $expect[$f]) { $bad++ }
  '{0,-12} {1,-9} {2,-9} {3}' -f $f, $expect[$f], $got, $after
}
''
if ($bad -eq 0) { 'REPLACE TREE OK' } else { "REPLACE TREE FAILED: $bad file(s) wrong"; exit 1 }
