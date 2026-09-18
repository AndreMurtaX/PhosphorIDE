# Build PhosphorIDE and prove the build is worth having, on Windows.
#
#   powershell -NoProfile -File scripts\build.ps1            debug build + checks
#   powershell -NoProfile -File scripts\build.ps1 -Release   optimised, stripped
#   powershell -NoProfile -File scripts\build.ps1 -NoChecks  build only
#
# The checks are the point. A GUI program that links is not a GUI program that
# works: the three failures this script exists to catch all produced a binary that
# lazbuild was perfectly happy with.
#
#   * a .lfm naming a property its .pas does not publish. The form streams fine
#     until it is constructed, and then LCL shows "Press OK to ignore and risk
#     data corruption" and WAITS. --selftest constructs every form, with LCL's
#     exception dialogs disarmed, and answers with an exit code.
#   * a unit-level regression in the diagnostic parser, the highlighter or the
#     protocol codec -- none of which has a visible failure mode. bin\phosphoridetest.
#   * the generated language tables drifting from the Phosphor sources they were
#     extracted from. gen-keywords.py --check.
#
# --selftest runs under a TIMEOUT rather than a plain wait, because a modal dialog
# is not a failure the exit code can report: it is a process that never exits.
# Measured 2026-09-10, twice, from two different causes.

[CmdletBinding()]
param(
    [switch]$Release,
    [switch]$NoChecks,
    # Where a Phosphor checkout lives, for the generated-tables check. Skipped
    # when it is not there -- a contributor need not have both repositories.
    [string]$PhosphorRepo = '',
    # Forbid the host contract check from SKIPPING. In CI the phosphor binary is
    # built a step earlier, so a skip there can only mean that step lied -- and a
    # check that quietly does not run reads as a pass.
    [switch]$RequireHost,
    [int]$SelfTestTimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $root 'bin'

function Fail($message) {
    Write-Host ''
    Write-Host "BUILD FAILED: $message" -ForegroundColor Red
    exit 1
}

function Find-LazBuild {
    $onPath = Get-Command lazbuild.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    foreach ($candidate in @(
        'C:\Lazarus\lazbuild.exe',
        'C:\lazarus\lazbuild.exe',
        "${env:ProgramFiles}\Lazarus\lazbuild.exe",
        "${env:ProgramFiles(x86)}\Lazarus\lazbuild.exe")) {
        if (Test-Path $candidate) { return $candidate }
    }
    Fail 'lazbuild.exe not found. Install Lazarus, or put lazbuild on PATH.'
}

$lazbuild = Find-LazBuild
$mode = if ($Release) { 'Release' } else { 'Default' }

Write-Host "lazbuild: $lazbuild"
Write-Host "mode:     $mode"
Write-Host ''

# ---------------------------------------------------------------- the build --

function Invoke-LazBuild($project, $buildMode) {
    Write-Host "building $project ($buildMode)"
    # -B rebuilds everything. Without it a changed .lfm can keep an old resource,
    # and the mismatch this script exists to catch is exactly the one that hides
    # behind a stale .lfm resource.
    $output = & $lazbuild -B "--build-mode=$buildMode" $project 2>&1
    $failed = $LASTEXITCODE -ne 0

    # lazbuild answers 0 in cases where the compiler did not, so the text is read
    # as well as the code.
    $bad = $output | Where-Object { $_ -match '^\s*(\S+\s+)?(Error|Fatal|Warning|Note):' }
    if ($bad) {
        $bad | ForEach-Object { Write-Host "  $_" }
    }
    if ($failed -or $bad) {
        Fail "$project did not build cleanly (zero errors, warnings and notes is the bar)."
    }
    Write-Host "  ok"
}

Invoke-LazBuild (Join-Path $root 'src\phosphoride.lpi') $mode
Invoke-LazBuild (Join-Path $root 'tests\phosphoridetest.lpi') 'Default'
Invoke-LazBuild (Join-Path $root 'tests\phosphorcontract.lpi') 'Default'

$exe = Join-Path $bin 'phosphoride.exe'
$testExe = Join-Path $bin 'phosphoridetest.exe'
$contractExe = Join-Path $bin 'phosphorcontract.exe'
if (-not (Test-Path $exe)) { Fail "no binary at $exe" }

if ($NoChecks) {
    Write-Host ''
    Write-Host "built $exe (checks skipped)"
    exit 0
}

# --------------------------------------------------------------- the checks --

Write-Host ''
Write-Host 'unit checks'
& $testExe
if ($LASTEXITCODE -ne 0) { Fail "$LASTEXITCODE unit check(s) failed." }

# THE ONE COUPLING BETWEEN THE TWO REPOSITORIES THAT HAD NO CHECK. Everything
# above tests uphosphormsg.pas against strings THIS repository wrote down; this
# runs the actual binary and asserts the shapes it really emits. Exit 77 is its
# skip, announced by the program itself so it exists however it was invoked.
Write-Host ''
Write-Host 'host contract'
if ($RequireHost) { & $contractExe --require-host } else { & $contractExe }
$rc = $LASTEXITCODE            # on its own line: a pipeline measures the pipe
if ($rc -eq 77) {
    # Already announced itself, in its own words. Nothing to add.
} elseif ($rc -ne 0) {
    Fail "$rc shape(s) no longer match the phosphor binary."
}

Write-Host ''
Write-Host 'form streaming (--selftest)'
$report = Join-Path $env:TEMP 'phosphoride-selftest.txt'
if (Test-Path $report) { Remove-Item $report -Force }

$proc = Start-Process -FilePath $exe -ArgumentList '--selftest', $report `
    -PassThru -WindowStyle Hidden
if (-not $proc.WaitForExit($SelfTestTimeoutSeconds * 1000)) {
    $proc.Kill()
    Write-Host '  the selftest never exited.' -ForegroundColor Red
    Write-Host '  A GUI binary that hangs instead of answering is almost always a dialog'
    Write-Host '  nobody can dismiss: an .lfm/.pas mismatch, or a WriteLn to a console this'
    Write-Host '  subsystem does not have. Run it from a console to see.'
    Fail 'selftest timed out.'
}
if (Test-Path $report) {
    Get-Content $report | ForEach-Object { Write-Host "  $_" }
}
if ($proc.ExitCode -ne 0) { Fail "selftest exit code $($proc.ExitCode)." }
Write-Host '  ok'

# The generated tables are a copy of facts that live in another repository, so
# the check is only meaningful where that repository is.
if ($PhosphorRepo -eq '') {
    foreach ($guess in @(
        (Join-Path (Split-Path -Parent $root) 'Phosphor'),
        (Join-Path $root '..\Phosphor'))) {
        if (Test-Path (Join-Path $guess 'engine\libs')) { $PhosphorRepo = $guess; break }
    }
}

Write-Host ''
Write-Host 'generated language tables'
if ($PhosphorRepo -eq '' -or -not (Test-Path (Join-Path $PhosphorRepo 'engine\libs'))) {
    Write-Host '  SKIPPED: no Phosphor checkout found.'
    Write-Host '  Pass -PhosphorRepo <path> to check that src\core\uphosphorlang.pas still'
    Write-Host '  matches the sources it was generated from.'
} else {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        Write-Host '  SKIPPED: python not found.'
    } else {
        & python (Join-Path $root 'tools\gen-keywords.py') $PhosphorRepo --check
        if ($LASTEXITCODE -ne 0) {
            Fail 'uphosphorlang.pas is stale -- rerun tools\gen-keywords.py.'
        }
    }
}

# THE OTHER GENERATED UNIT, and it needs no second repository -- the icons are
# drawn by the script that writes them, so this can always run. Without it a
# hand-edit of uphosphoricons.pas survives until somebody regenerates and
# wonders why their icon came back.
Write-Host ''
Write-Host 'generated icons'
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Host '  SKIPPED: python not found.'
} else {
    & python (Join-Path $root 'tools\gen-icons.py') --check
    if ($LASTEXITCODE -ne 0) {
        Fail 'uphosphoricons.pas is not what tools\gen-icons.py writes.'
    }
}

Write-Host ''
Write-Host 'citations'
if (-not $python) {
    Write-Host '  SKIPPED: python not found.'
} else {
    & python (Join-Path $root 'tools\check-citations.py')
    if ($LASTEXITCODE -ne 0) {
        Fail 'a file:line citation no longer points at what it claimed.'
    }
}

Write-Host ''
Write-Host "built and checked: $exe" -ForegroundColor Green
