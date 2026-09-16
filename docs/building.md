# Building PhosphorIDE

Two commands build it, two more check it, and the rest of this file is the reasons --
which matter here more than usual, because several of the failures this project has
already paid for do not look like build failures. They look like a build that never
finishes.

Everything below is Lazarus 4.8 with FPC 3.2.2 on Windows 11 and on Linux/gtk2. CI
additionally builds and checks it on **Lazarus 3.6**, so the supported range is both.
Those
are the versions this was built and verified with, not a supported-matrix claim.

---

## What you need

**Lazarus 3.6 or 4.8, FPC 3.2.2.** Confirm before blaming anything else:

```
lazbuild --version      # 4.8
fpc -iV                 # 3.2.2
```

On Windows the Lazarus installer puts FPC under `C:\lazarus\fpc\3.2.2\bin\x86_64-win64`
and `lazbuild.exe` at `C:\lazarus`. On Linux you need the gtk2 widgetset units as well
as the IDE -- on Debian-derived systems that is `lazarus` plus `lcl-gtk2`; distribution
packages are usually older than 4.8, so 4.8 in practice means the release `.deb`/`.rpm`
or a source install. qt5 is not what this was checked against.

The build scripts look for `lazbuild` on PATH first and then at the conventional install
location. If yours lives somewhere else, put it on PATH.

**SynEdit, LazUtils and LCL.** All three ship with Lazarus; there is nothing to install
and no package to open. `src/phosphoride.lpi` names them in `RequiredPackages` and
`lazbuild` resolves them out of the Lazarus installation, which is also why the `.lpi`
contains no path to them.

**Python 3 -- for one script only.** `tools/gen-keywords.py` regenerates
`src/core/uphosphorlang.pas`. That unit is committed generated output, so a plain build
needs no Python at all. You need Python to regenerate the tables or to run the `--check`
gate, and for nothing else in this repository.

**A Phosphor checkout, or at least a `phosphor` binary.** The editor builds, starts and
edits text with no Phosphor anywhere on the machine -- it never links the engine -- but
Run, Check Syntax, Compile and Pack all spawn the `phosphor` binary, and without one they
have nothing to spawn. `src/core/uphosphorhost.pas` searches in a deliberate order:
the Preferences setting, `$PHOSPHOR_HOST`, beside `phosphoride` itself, `../Phosphor/bin`,
PATH, then the usual install directories. The fourth entry is the one that matters to a
contributor: check the two repositories out side by side --

```
C:\Dev\Phosphor
C:\Dev\PhosphorIDE
```

-- and the editor finds the host with nothing configured. Build the host from its own
repository (<https://github.com/AndreMurtaX/Phosphor>), whose quickstart is the same
shape as this one.

---

## Build it

Windows:

```
powershell -NoProfile -File scripts\build.ps1
```

Linux:

```
bash scripts/build.sh
```

`-NoProfile` is not decoration. A user profile that prints a banner, sets
`$ErrorActionPreference`, or changes the console encoding lands in the middle of a build
log and changes what the script sees; the CI form and the local form should differ in
nothing.

Each script does the same six things in the same order:

1. **Build the editor** -- `lazbuild -B src/phosphoride.lpi`, build mode Default, into
   `bin/phosphoride` (`.exe` on Windows). Units go to `lib/$(TargetCPU)-$(TargetOS)`.
2. **Build the checks** -- `lazbuild -B tests/phosphoridetest.lpi` into
   `bin/phosphoridetest`, units to `lib/test-$(TargetCPU)-$(TargetOS)`, so the two
   projects can never link each other's leftovers.
3. **Refuse to trust the exit code.** A build step can succeed having produced nothing.
   The script checks that the binary exists and is executable before it says a word about
   success. This is Phosphor's rule and it is here for the same reason.
4. **Run the unit checks** -- `bin/phosphoridetest`, which prints
   `291 checks, all green.` and exits 0. A non-zero exit is the number of failures, each
   already printed with what it expected and what it got.
5. **Run `--selftest`, under a timeout.** `bin/phosphoride --selftest <report>` builds
   every form once and exits 0 or 1. The timeout is not caution, it is the fix for a
   defect; see "The checks" below.
6. **Check the generated tables** -- `tools/gen-keywords.py <phosphor> --check`, against
   a sibling `../Phosphor` if the script can find one. Skipped, out loud, when there is
   no checkout or no Python: a contributor need not have both repositories, but a check
   that quietly does not run reads as a pass.

A clean checkout has neither `bin/` nor `lib/` -- both are gitignored -- so the first run
creates them.

The Default binary is around 40 MB, nearly all of which is DWARF debug information.
That is a debug build doing its job, not a bloated one.

---

## Building by hand

The scripts are a convenience over three `lazbuild` calls:

```
lazbuild -B src/phosphoride.lpi
lazbuild -B tests/phosphoridetest.lpi
lazbuild -B --build-mode=Release src/phosphoride.lpi
```

**Why `-B`.** `lazbuild` decides what to recompile from `.ppu` timestamps, and timestamps
do not encode the things that actually invalidate a unit: a switched build mode, an
upgraded Lazarus, a different set of compiler options. The two build modes write their
units to different directories but produce the same target file, so an incremental build
after a mode switch is exactly the situation where a mixture links cleanly and then
misbehaves at runtime. `-B` costs about a minute. The alternative is a class of failure
that does not present as a build failure at all, which is the most expensive kind.

**Why the committed `.lpi`, and not IDE session state.** `src/phosphoride.lpi` sets
`SessionStorage` to `None`, so Lazarus writes no `.lps` at all and the project file is
the whole project by construction. That is deliberate: the build is reproducible from
what git holds, and `lazbuild` against the `.lpi` is bit-for-bit the same build a
contributor gets and a CI job gets. Session files hold per-user, per-machine state --
open tabs, cursor positions, absolute paths -- which is why `.lps`, `.lpo` and the
`packagefiles.xml` that `lazbuild` drops in whatever directory it was run from are all
gitignored. If a build works in the IDE and not from `lazbuild`, the `.lpi` is missing
something and the `.lpi` is what needs fixing.

---

## The two build modes

**Default** (`lazbuild -B src/phosphoride.lpi`) -- DWARF 3 debug info, assertions
compiled in, `-vewn`, no optimisation, units in `lib/$(TargetCPU)-$(TargetOS)`. This is
what you develop against and what the build scripts run.

**Release** (`lazbuild -B --build-mode=Release src/phosphoride.lpi`) -- `-O3`,
smart-linked (`SmartLinkUnit` and `LinkSmart` both on), no debug info, symbols stripped,
units in `lib/$(TargetCPU)-$(TargetOS)-release`. Same `-vewn`, same output path for the
binary, so a Release build overwrites a Default one and vice versa. Build with `-B` when
you switch.

**heaptrc (`-gh`) is deliberately absent from both, and must stay absent.** On 2026-09-10
a Default mode carrying `-gh` produced an editor that would not exit: the window closed,
the process did not. heaptrc writes its leak report to stdout during unit finalisation,
and a Windows GUI-subsystem binary has no stdout to write it to, so the write hits an
invalid handle and the RTL's I/O error handling takes it from there. That is trap 2 of
this repository, and it is the same root cause as trap 1 (see below) arriving at exit
instead of at startup.

Leak-checking is therefore a deliberate, separate act, and the thing it needs is a real
console -- not merely being launched from one. On Windows a GUI-subsystem process does
not inherit the console it was started from, so `-gh` on `phosphoride` needs the
subsystem changed too (`GraphicApplication` off) before it will report anything. The
cheaper route is to add `-gh` to `tests/phosphoridetest.lpi`, which is already a console
program and already exercises the units where a leak would be worth finding.

---

## The checks

Three of them. They cover different things and none of them covers what the other two do.

### `bin/phosphoridetest` -- 291 checks

```
bin\phosphoridetest.exe          # Windows
bin/phosphoridetest              # Linux
```

Exit 0 means every check passed; anything else is the failure count.

What it covers is the logic that can be wrong without anyone noticing: the diagnostic
parser (every input string was captured from a real `phosphor` run, not invented -- that
is why `phosphor: C:\Dev\x\dz.bas:4: division by zero` is in there, since a drive-letter
colon is precisely what breaks a parser that splits on the last one), the generated word
tables against their own declared counts, the highlighter's token stream, and the PDBP
encode/decode path.

What it cannot catch: anything about a window. It creates none. It links the LCL but
names `InterfaceBase` and `Win32Int`/`Gtk2Int` directly instead of `Interfaces`, because
`Interfaces` calls `CreateWidgetset` in its initialization section and on gtk2 that opens
the X display before `main` -- which kills a process that merely listed the unit on a
machine with no session. Naming the widgetset unit directly links the same code and
leaves the call unmade, so this program runs identically on a desktop, over a pipe and on
a headless CI machine. The technique is Phosphor's; it is trap 5 here.

### `phosphoride --selftest` -- and it must be run under a timeout

```
bin\phosphoride.exe --selftest selftest.txt
bin/phosphoride --selftest /tmp/selftest.txt
```

It constructs `TFrmMain`, `TFrmAbout` and `TFrmPreferences` once each, writes a report
naming the component count of each plus the four language-table counts, and exits 0 if
all three built or 1 if one did not.

What it catches is the failure mode that has no compiler error: an `.lfm` naming a
property or a component its `.pas` does not publish. That streams fine right up until the
form is created. On 2026-09-10 the result was not a red build -- it was LCL's
`TApplication.ShowException` (`lcl/include/application.inc:1598`) drawing *"Press OK to
ignore and risk data corruption"* on whatever machine happened to run the build, and
waiting. `--selftest` sets `Application.Flags + [AppNoExceptionMessages]` so
`ShowException` returns without drawing anything and the exception reaches a `try/except`
that turns it into an exit code.

**Run it under a timeout anyway.** The flag only covers the dialogs LCL knows it is
showing; a widgetset dialog, a driver message box or a font-cache stall is still a
process that stops with nobody to answer it, and a build that hangs reports nothing at
all. The scripts do this:

```powershell
$p = Start-Process bin\phosphoride.exe -ArgumentList '--selftest','selftest.txt' -PassThru
if (-not $p.WaitForExit(60000)) { $p.Kill(); throw '--selftest did not finish' }
```

```bash
timeout 60 bin/phosphoride --selftest /tmp/selftest.txt; echo "exit $?"
```

**And note that it reports through a file, not stdout.** That is trap 1, the one the
`.lpr`'s header comment is about: a Windows GUI-subsystem binary has no console, so
`WriteLn` hits an invalid handle and the RTL's I/O error surfaces as a modal dialog
nobody is there to dismiss -- a hang, not a message. Measured on 2026-09-10 with a
`--selftest` that merely wrote its result to stdout: it hung until it was killed. The
report path and the exit code are the entire output channel, on purpose.

What `--selftest` cannot catch: whether any of those forms is usable. It builds them; it
does not look at them. A control anchored to the wrong parent, an unreadable colour, a
menu item wired to the wrong handler all pass.

### `gen-keywords.py --check` -- the tables have not drifted

```
python tools\gen-keywords.py ..\Phosphor --check
python3 tools/gen-keywords.py ../Phosphor --check
```

This one needs a Phosphor *checkout*, not a binary: it reads `.pas` sources. It
regenerates `src/core/uphosphorlang.pas` into memory and diffs, printing
`uphosphorlang.pas is current (538 core, 181 package, 426 gui)` or exiting non-zero with
`... is stale -- rerun tools/gen-keywords.py`.

Before it generates anything it asserts the counts it extracted: 534 from `engine/libs`,
181 from `host/packages`, 426 from `host/gui/libs`. The unit ships 538 core names because
the script adds the four compiler special forms -- `eof`, `input$`, `loc`, `lof` -- which
are in no registry and so cannot be extracted. If a Phosphor release moves one of those
numbers the script refuses to run and says so, and a human decides what the new number is
in a commit message. That refusal is the point: a new Phosphor release should show up
here as a red build, not as an editor that has quietly stopped knowing about a built-in.

What `--check` cannot catch: **the keywords.** Phosphor's lexer has no keyword table at
all -- it emits every one of them as a plain identifier and the parser decides from
position (`engine/PhosphorLexer.pas:444-470`), so there is nothing to extract. The 53
keywords are held by hand in `gen-keywords.py` and checked against
`TPhosphorCompiler.IsReservedWord` by a person. `--check` proves the committed unit
matches the script; it does not prove the script matches Phosphor. A Phosphor release
that adds a keyword is invisible to every gate in this repository until somebody reads
`IsReservedWord`.

### The generated units

Two, and both are checked by `scripts/build.ps1` and `scripts/build.sh`:
`src/core/uphosphorlang.pas` (the language tables, extracted from a Phosphor checkout)
and `src/core/uphosphoricons.pas` (the toolbar icons, drawn by `tools/gen-icons.py`).
Neither may be hand-edited; `--check` on either is a red build. The icon generator also
writes `tools/icons-preview.png`, a magnified sheet of all nine at both sizes on a light
band and a dark one, because PNG bytes in a diff are not something a person can review.

---

### What none of the three covers

No check here runs a BASIC program. Run, Check Syntax, Compile to `.pbc`, Pack, Stop, the
stdin box and the output pane are exercised by driving the editor against a real
`phosphor` binary by hand. **And no check here debugs one.** The Debug menu works as of 2026-09-16 -- start,
breakpoints, the three steps, continue, the variables pane -- and every one of those is
a conversation with a live `phosphor debug --port` child over a socket, which none of
the three gates can stand in for. The protocol CODEC is pinned headless in
`bin/phosphoridetest`; the session is not. It was verified by driving the editor from a
script against the real host on both platforms, with the transcripts read out of the
Output pane as TEXT rather than photographed; `tools/lane/` is that script, with its
own README, and `docs/debugger-lane.md` says what each step was checked against.
Roadmap item 2a is the contract test that would turn part of it into a gate.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\lane\lane-windows-steps.ps1
```

```bash
cd tools/lane && fpc -O2 -k-lXtst xdrive.lpr && ./lane-linux.sh ./lane345.bas ./steps-lane.txt
```

Neither is part of `build.ps1` or `build.sh`, and neither should be: they need a
window, a display and a `phosphor` that can debug. They are what a person would do,
written down so the answer is repeatable rather than remembered.

---

## The hint that is not a gate

Both projects compile with `-vewn`: errors, warnings and notes. Hints are deliberately
not in that set, and the reason is `Sender`.

An LCL event handler's signature is fixed -- `procedure(Sender: TObject) of object` --
so a handler that has no use for the parameter must still declare it, and `-vh` answers
with `Hint: Parameter "Sender" not used` for code that is correct and cannot be written
any other way. Turning hints on would mean either a permanently dirty log or suppression
pragmas scattered through every form unit, and both of those are worse than not asking.

So the bar is **zero warnings and zero notes**. That is a lower bar than the Phosphor
engine's, which is the price of writing LCL code. Within it the rule is unchanged: a note
is a defect until proven cosmetic, and the fix is the cause, never the switch.

---

## Cross-platform rules for contributors

Five of these are one-line habits that cost nothing to keep and a debugging session to
discover. The sixth needs a person and a second machine.

**Lowercase source filenames.** FPC turns a unit name into a file name, and on Linux that
lookup is case-sensitive: `uses UMainForm` finds `umainform.pas` on Windows and fails on
Linux with `Can't find unit UMainForm`. Every file in `src/` and `src/core/` is
lowercase and every `uses` clause spells it the same way. This one only ever bites the
contributor who is not on Linux, which is why it is first.

**No absolute paths in the `.lpi`.** The target is `../bin/phosphoride`, unit output is
`../lib/$(TargetCPU)-$(TargetOS)`, the extra unit directory is `core` -- all relative to
the project file, all valid on both platforms. Packages resolve through the Lazarus
installation rather than through a path. An absolute path in a `.lpi` is the classic way
a project comes to build on exactly one machine.

**`cthreads` first in the `.lpr`, inside `{$IFDEF UNIX}`.** It is the first unit named by
both `phosphoride.lpr` and `phosphoridetest.lpr`. `TProcess` reads its pipes on a thread,
and without `cthreads` the Unix RTL has no thread manager, so those reads deadlock the
UI. It must be first because the thread manager has to be installed before any other
unit's initialization section can start a thread.

**`CompareFilenames`, never `=` or `SameText`, for paths.** The LazUtils function already
knows that Windows is case-insensitive and Linux is not. Two behaviours depend on getting
this right: "is this file already open in a tab" (`src/umainform.pas:503`) and the
recent-files list (`src/core/uphosphorsettings.pas:278`). Compare with `=` and Windows
opens one file into two tabs; compare with `SameText` and Linux merges two genuinely
different files.

**`TProcessUTF8` (LazUtils' `UTF8Process`), never `TProcess`.** `TProcess.Executable` is
an AnsiString converted through the Windows system code page, so a path containing a
non-ASCII character is mangled before the OS ever sees it and the child fails to start
for a file that is plainly there. Trap 6, and both spawn sites obey it:
`src/core/uphosphorrun.pas:259` for the run itself and `src/core/uphosphorhost.pas:118`
for the `--version` probe.

**Look at both widgetsets before shipping.** A layout that is right on win32 can collapse
on gtk2: the metrics differ, fonts are taller, and anything positioned by a hard-coded
pixel offset moves. Nothing automated here catches it -- `--selftest` proves a form
*constructs*, the test binary opens no window at all -- so it takes a person on each
platform, or one person and a VM. Budget for it rather than discovering it from a
screenshot.

---

## Two more traps worth knowing before you edit

Not build steps, but they are what the build steps are shaped around, and both were paid
for on 2026-09-10.

**`SetFocus` on a control whose form is not on screen yet raises `Can not focus`.** The
main window creates its first tab from `FormCreate`, before it is shown, so the file
named on the command line was reported as unopenable with the focus error as its stated
reason. `TFrmMain.FocusEditor` now checks `Showing` and `CanFocus` first and `FormShow`
focuses the startup tab. Focus is something to ask for once there is somewhere to put it.

**One thread reading both of a child's pipes deadlocks.** A blocking read on stdout does
not return while the child is filling stderr, and once the stderr buffer fills the child
blocks on its write -- neither side moves again, and the program that provokes it is an
ordinary one that prints a lot and then fails. `uphosphorrun.pas` runs one reader thread
per pipe plus a timer that drains their buffers on the main thread. If you touch that
unit, that shape is the whole point of it.
