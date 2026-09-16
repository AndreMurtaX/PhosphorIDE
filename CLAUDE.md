# PhosphorIDE -- working rules

PhosphorIDE is a small desktop editor for **Phosphor BASIC**, written in Free Pascal
against Lazarus 3.6 or 4.8 with FPC 3.2.2, and the LCL and SynEdit. Windows and Linux, MIT, by
AndreMurtaX. It edits `.bas` files in tabs with a purpose-built highlighter, and it
drives the `phosphor` binary from the sibling repository
(<https://github.com/AndreMurtaX/Phosphor>) to run, check, compile and pack them. It is
an editor for an interpreter it does not contain, and every rule below follows from
that sentence.

---

## The one invariant: the editor never links the engine

`phosphoride` spawns `phosphor` as a **child process**. It does not link the engine, it
does not evaluate BASIC in-process, and it never will. The reason is stated in
`src/phosphoride.lpr:5-10`: a script that loops forever, exhausts memory or faults the
interpreter must take its own process down and leave the editor holding the user's
unsaved work. An in-process interpreter turns every bad script into a lost file.

Concretely, this forbids:

- **No `uses PhosphorEngine`,** and no other unit from `../Phosphor/engine` or
  `../Phosphor/host`. Nothing in `src/` compiles a `.bas`, tokenises one for anything
  but colour, or executes one.
- **No in-process evaluation** of any kind -- not for a watch window, not for a
  "quick evaluate" box, not for constant folding in the editor.
- **Every interaction with the host is a process.** Asynchronous work goes through
  `TPhosphorRunner` (`src/core/uphosphorrun.pas`); the two synchronous questions the
  editor asks a binary about *itself* (`--version`, `--help`) go through
  `RunAndCapture` (`src/core/uphosphorhost.pas:98`), which blocks and therefore carries
  a 5000 ms deadline. There is no third way in.

If a feature seems to need the engine linked, it needs a protocol instead. See PDBP
below.

---

## Done means proven, on both machines

Nothing is done on a claim. An increment is complete when all five hold:

1. `lazbuild` builds with **zero errors, zero warnings, zero notes**. Both `.lpi` files
   pass `-vewn` in `CustomOptions`; a note is a defect until proven cosmetic, and it is
   never suppressed.
2. `bin/phosphoridetest` is **all green** -- today 409 checks, exit 0. The count is
   printed; if it went down, something was deleted.
3. `phosphoride --selftest <report>` exits **0 under a timeout**. It constructs every
   form and writes what it found to the report file. The timeout is not optional; see
   trap 3.
4. **Both generated units are current.**
   `python tools/gen-keywords.py ../Phosphor --check` prints
   `uphosphorlang.pas is current (538 core, 181 package, 426 gui)`, and
   `python tools/gen-icons.py --check` prints
   `uphosphoricons.pas is current (9 icons, 16 and 24 px)`. Both exit 0, and both
   build scripts run them.
5. **Green on Linux too.** Windows-green has shipped Linux-broken defects in the
   sibling repository (SIGPIPE, soname, cert generation), and this repository has two
   Linux-only hazards of its own: `cthreads` and the gtk2 widgetset.

Windows:

```powershell
lazbuild --build-mode=Default src\phosphoride.lpi
lazbuild tests\phosphoridetest.lpi
bin\phosphoridetest.exe
$code = $LASTEXITCODE           # on its own line: a pipeline measures the pipe
$p = Start-Process bin\phosphoride.exe -PassThru `
       -ArgumentList '--selftest', "$env:TEMP\phosphoride-selftest.txt"
if (-not $p.WaitForExit(30000)) { $p.Kill(); throw '--selftest hung' }
$p.ExitCode
python tools\gen-keywords.py ..\Phosphor --check
```

Linux:

```bash
lazbuild --build-mode=Default src/phosphoride.lpi
lazbuild tests/phosphoridetest.lpi
bin/phosphoridetest; echo $?
xvfb-run -a timeout 30 bin/phosphoride --selftest /tmp/phosphoride-selftest.txt; echo $?
python3 tools/gen-keywords.py ../Phosphor --check
```

`xvfb-run` is there because `phosphoride.lpr` names `Interfaces`, whose initialisation
calls `CreateWidgetset`, which on gtk2 opens the X display **before `main`** -- so the
selftest of a GUI program cannot run on a bare headless box the way
`bin/phosphoridetest` can. That is the same fact `tests/phosphoridetest.lpr:26-38`
exploits in the other direction: the test program names `InterfaceBase` plus
`Win32Int`/`Gtk2Int` directly and never `Interfaces`, so it links the LCL without
connecting to anything.

Measured again on 2026-09-16, same VM: all five gates green with the debugger in,
and the editor **driven** under gtk2 rather than merely constructed -- breakpoints,
stepping, the variables pane and a clean end, through `tools/lane/`. What is still
unwatched is narrower than it has ever been: the `xvfb-run` branch of `build.sh`, and
the gtk2 MENU BAR, which answers neither a synthetic click nor F10 navigation from
XTest and so could not be driven at all.

Measured on 2026-09-10 on Ubuntu with Lazarus 4.8: `bash scripts/build.sh` builds both
projects clean, `bin/phosphoridetest` is green, and the selftest constructs all three
forms under **gtk2** when a display is reachable -- there, through a real Xwayland
session (`DISPLAY=:0` with the mutter Xwayland cookie in `XAUTHORITY`) rather than
xvfb. The `xvfb-run` form above is still the one CI uses and is still the one nobody
has watched; a session and a virtual framebuffer are not quite the same thing.

`src/phosphoride.lpr:40-41` says `scripts/build.ps1` runs the selftest after
`lazbuild`, and it does. Both scripts exist and both have been run: `build.ps1` on
Windows and `build.sh` on Ubuntu, each green end to end. What remains unmeasured is
narrower again: the **`xvfb-run` branch** of `build.sh`, and nothing else. The other
half of that sentence -- the editor DRIVEN under gtk2 rather than merely constructed
there -- stopped being true on 2026-09-16 and is now `tools/lane/`: keys through
XTest, frames through `xwd` decoded by PIL, and a `steps-*-linux.txt` per case,
covering a debug session, the gutter marks, completion, signature help and find in
files. One fact from it is worth carrying here, because it cost two runs that read
as broken panes: **mutter gives this window a different height on different runs**
-- 700, 725, 750 and 775 all seen -- so every click in a Linux script is measured UP
from the bottom edge, where the output panel is anchored.

If one of the five cannot be met you are **blocked**. Say so precisely; do not lower
the bar.

---

## Architecture invariants

- **The UI thread never blocks.** `umainform.pas:6-9`: nothing here waits. A run that
  never returns must still leave the user able to stop it, save around it and edit
  while it spins -- which is the whole point of the child process. The only sanctioned
  blocking call is `RunAndCapture`, and only because it has a deadline.
- **One thread per pipe: two readers and a writer.** Not one thread reading both: a
  blocking read on stdout does not return while the child is filling stderr, and once
  the stderr buffer fills the child blocks on its write, so neither side moves again.
  The provoking program is entirely ordinary -- one that prints a lot and then fails.
  The readers deposit into a lock-guarded buffer and a timer on the main thread drains
  it into whole lines. No `Synchronize`, no `Queue`, and no thread touches the LCL.
  **Stdin is a thread for the mirror-image reason**: a pipe write blocks when its
  1 KB buffer is full, which is what a couple of dozen sends to a program that is not
  reading produce, and that write on the main thread is a frozen editor with Stop
  included. `SendInput` queues and returns. `Cleanup` closes the child's input BEFORE
  waiting on the writer, or a writer parked in a blocking write never sees `Terminate`
  and `WaitFor` reproduces the hang one place along. (`uphosphorrun.pas`.)
- **Lines, not bytes, cross the boundary.** A pipe read can end mid-line, and a parser
  fed half of `phosphor: x.bas:2: unexpected token` finds no error at all. The partial
  tail is held until its newline, and flushed unterminated at end of stream -- or,
  while the child is still running, after two idle drain ticks, because an unterminated
  line that has gone quiet is a prompt. The `ACompleteLine` flag says which of the two
  it is, and a partial is never handed to the diagnostic parser.
- **`src/core/uphosphoricons.pas` is GENERATED. Never hand-edit it.** The toolbar's
  nine icons are DRAWN by `tools/gen-icons.py` — a few hundred bytes of PNG each,
  at 16 and at 24, decoded into an empty `TImageList` at `FormCreate`. They are not in
  the `.lfm` because a `TImageList` streams its pictures as one binary blob, and a blob
  in a form file people edit by hand cannot be reviewed or diffed. `tools/icons-preview.png`
  is written by the same run and checked by the same `--check`: it is the only form
  these icons have that a person can review, and a set that has drifted from the picture
  of it is worse than no picture.

  **Two resolutions, drawn twice, never scaled once.** A single-resolution image list is
  scaled by the widgetset, the two widgetsets scale differently, one gives a blurred
  mark and the other a missing one, and neither is a build failure — so nobody finds
  out until a screenshot arrives from the other platform. The geometry is written in
  EIGHTHS of the box, because 16 and 24 are both divisible by 8 and every coordinate
  then lands on a whole pixel at both sizes. `--selftest` reports the widths, not just
  the count: two resolutions of 16 would count as two.

  **The toolbar is light on Windows and dark under gtk2.** One icon set has to read on
  both, so nothing is drawn in near-black or near-white alone and outlines are mid grey.
  A dark outline on a dark toolbar is an icon nobody can see, and that is not a build
  failure either.
- **`src/core/uphosphorlang.pas` is GENERATED. Never hand-edit it.** Rewrite it with
  `python tools/gen-keywords.py ../Phosphor`. Its 53 keywords, 538 core, 181 package
  and 426 GUI built-ins are facts about the *other* repository; a hand edit puts them
  in two places and the edited copy is the one that goes stale. The script asserts
  `EXPECTED = {'core': 534, 'package': 181, 'gui': 426}`, and
  `EXPECTED_SIG_NAMES` / `EXPECTED_SIG_PAIRS` for the signatures (534 registrations plus the
  four special forms `eof input$ loc lof` makes the unit's 538) and **refuses to
  generate** when Phosphor has moved, so a new Phosphor release is a red build rather
  than silence. Decide the new numbers deliberately, update `EXPECTED`, and say so in
  the commit message.
- **The diagnostic parser handles four shapes, and a refusal is not a location.**
  `phosphor: <path>:<line>: <msg>` is the only one that can be jumped to. A packed
  executable omits the path (`phosphor: <line>: <msg>`); the REPL says `error: <msg>`;
  and a host refusal (`file not found:`, `usage:`, a `--check` warning) carries no
  location at all. A parser that assumes the first shape turns `file not found:
  nope.bas` into a jump to line 0 of a file called `file not`. Messages contain colons
  (`no function nosuchfunc$:%`), so the separator is found by searching for
  `:<digits>: ` past any drive letter -- never by splitting on the first or last colon.
  There is never a column, and the line number **can exceed the file's line count** (an
  unterminated block in a three-line file reports line 4), so clamp before scrolling.
- **A `.bas` is saved as UTF-8 with NO byte-order mark.** Not a preference: Phosphor's
  lexer has no BOM handling, so a leading BOM is the lexical error `unexpected
  character` on line 1 of an otherwise perfect program. Every Windows editor and
  `Set-Content -Encoding utf8` writes one. `TEditorDoc.SaveToFile` is the only writer;
  keep it that way.
- **Bytes from the child are passed through untouched.** The host emits UTF-8 and the
  LCL wants UTF-8. Any "helpful" conversion -- `SysToUTF8`, a CP1252 round trip --
  corrupts exactly the strings Phosphor is careful about.
- **The gutter mark is a SECOND copy of the breakpoint set, and it is rebuilt, never
  patched.** `TFrmMain.SyncGutterMarks` removes every `TPhosphorBreakMark` and adds one
  per breakpoint, solid or hollow from `BreakpointIsArmed`. It is a subclass with
  nothing in it so that `is` can answer "did this window put this here": SynEdit's mark
  list is shared, and clearing all of it would delete somebody else's.

  **TWO HANDLERS ON ONE NOTIFICATION, AND THE ORDER IS NOT OURS.** SynEdit adjusts its
  own marks for an insertion through a handler on `senrLineCount`, and
  `TEditorDoc.LinesChanged` is another handler on the same one. Rebuilding from inside
  it puts the new marks in BEFORE that adjustment runs, and the adjustment then shifts
  them a second time: on 2026-09-16 one line typed above a breakpoint on line 10 left
  the mark on **12** while the statement went to 11. So `OnBreakpointsChanged` carries
  an `AFromEdit` flag, an edit only raises `FMarksDirty`, and `EditorChange` — which
  SynEdit fires once the change is finished — does the rebuild. A toggle is not an
  edit and is rebuilt on the spot.
- **Breakpoints are line numbers, and they must follow edits.** A mark that stays put
  while text is inserted above it points at a statement the user did not choose.
  `TBreakpointSet.TrackEdit` (`core/ubreakpoints.pas`) is the arithmetic, and it drops
  a breakpoint whose line was deleted rather than sliding it onto the neighbour;
  `TEditorDoc.LinesChanged` is the wiring, subscribed to SynEdit's `senrLineCount`
  notification. **Both halves, always.** The arithmetic was written first and nothing
  called it, and the result was breakpoints that silently did not move -- a defect with
  no symptom, found on 2026-09-10 by grepping for callers of a method that had none.
  The set lives in its own LCL-free unit precisely so that `phosphoridetest.lpr` can
  pin every boundary case without a window.
- **No socket of ours travels into a child.** The editor opens the debug
  listener and THEN spawns the debuggee, so a descriptor that is merely open at
  that moment is inherited by the very program being debugged. Measured on
  2026-09-16 with `ss -ltnp`, session live:
  `users:(("phosphor",pid=5381,fd=18),("phosphoride",pid=5343,fd=18))` -- the
  debuggee holding a listener it was only meant to connect to, and could have
  accepted on. `MakeSocketPrivate` (`core/udebugtransport.pas`) clears it on the
  listener and on the accepted peer: `FD_CLOEXEC` on Unix,
  `SetHandleInformation` on Windows, where `TProcess` sets `InheritHandles :=
  True` (`processbody.inc:258`) and `netstat` cannot show the problem because it
  reports one owning PID. `TDebugTransport.HandlesArePrivate` is the invariant
  as a boolean, and `phosphoridetest` pins it -- because deleting one line in
  `Listen` is otherwise a silent regression with a symptom only `ss` can see.
- **A SIGNATURE IS ABSENT OR IT IS EMPTY, AND THOSE ARE DIFFERENT ANSWERS.**
  `PhosphorSignatures` gives a one-element list holding `''` for a name that
  takes no arguments, and a zero-element list for a name nothing is known about.
  A caller that treats them alike tells somebody that `callfunc` takes nothing.
  `callfunc` and its four suffixed forms register one slot per arity from a loop,
  so the literal in the Phosphor source says `$` and the truth is nine things;
  the generator drops them rather than keep the literal, because an editor
  showing one arity for a name that has nine is worse than one showing none. The
  four compiler special forms carry none for the same kind of reason: there is no
  registry entry to extract, and a hand-written one would be a second copy of
  another repository's fact.
- **Completion reads the word tables, never the highlighter.** `usynphosphor`
  colours keywords by word and not by position, deliberately and wrongly, and its
  own header says nothing downstream may assume a coloured keyword IS a keyword.
  `uphosphorcomplete` therefore reads `uphosphorlang` directly. It has **no LCL in
  it**, for the same reason `ubreakpoints` does not: every decision it makes is
  about a string and a column, and `phosphoridetest` pins all of them without a
  window. The popup, the shortcut and the painting are the form's.

  Three rules in it are load-bearing. **A type suffix is part of the name**, so the
  prefix under the caret is scanned by the highlighter's own character sets and
  `OnCodeCompletion` replaces the range THAT measured rather than the one
  `TSynCompletion` derives from SynEdit's identifier characters — the two agree
  today, and depending on that is one change away from writing `left$$`.
  **Nothing is offered inside a string or a comment**, which is decidable from the
  current line alone because `'` and `rem` run to end of line and an unterminated
  string is a hard error rather than a continuation. And **the tier is a cut**: a
  core-only list may not contain a package or GUI name, or the editor is
  recommending a program that works on its author's desktop and stops on a server.
- **Every path comparison goes through `CompareFilenames`** (`LazFileUtils`). It
  already knows that Windows is case-insensitive and Linux is not, which is one fewer
  platform rule spelled out by hand. Three sites depend on it:
  `uphosphorhost.pas:196` (de-duplicating host candidates),
  `uphosphorsettings.pas:278` (the recent list) and `umainform.pas:503` (is this file
  already open -- get it wrong and two tabs of one file quietly diverge).
- **A discovered host path is never written back to the settings.** Empty `HostPath`
  means "search on every start". Writing a lucky guess back freezes a decision the user
  never made, and the first thing that moves is then wrong forever.
- **Nothing is executed while searching for the host.** `LocateHostCandidates` reports
  paths; only `ProbeHost` runs one, against a path the caller has already settled on.
  Running an unknown executable to find out what it is is how a file dropped in the
  working directory gets run.

---

## Traps that have already cost real time

The first nine were paid for on **2026-09-10**, building this repository; the three
marked 2026-09-16 were paid for driving it.

- **A Windows GUI-subsystem binary has no console.** `WriteLn` hits an invalid handle,
  and the RTL's I/O error surfaces as a **modal dialog with nobody there to dismiss
  it** -- a hang, not a message. A `--selftest` that merely wrote its result to stdout
  hung until it was killed. That is why the selftest reports through a **file** and its
  **exit code**, and why nothing in `phosphoride` writes to a console stream.
- **`-gh` (heaptrc) in that same GUI binary hangs the process on exit,** because the
  leak report goes to the same missing stdout. It is not in the Default build mode and
  must not be added back. A leak-checking build is run from a console, deliberately,
  by someone watching.
- **An `.lfm` naming a property its `.pas` does not publish does not fail -- it
  prompts.** LCL's `TApplication.ShowException` (`lcl/include/application.inc:1598`)
  answers with "Press OK to ignore and risk data corruption", and waits, on whichever
  machine happened to run the build. `--selftest` sets
  `Application.Flags + [AppNoExceptionMessages]` so `ShowException` returns without
  drawing (`application.inc:1604`) and the mismatch becomes an exit code -- **and the
  build script runs it under a timeout anyway**, because a flag only covers the dialogs
  LCL knows it is showing.
- **`SetFocus` on a control whose form is not shown yet RAISES "Can not focus".** The
  window creates its first tab from `FormCreate`, before it is on screen, so the file
  named on the command line was reported as unopenable with the focus error as its
  reason. Focus is asked for once there is somewhere to put it: `FormShow` does it.
  (`umainform.pas:438-450`.)
- **A test program that links the LCL but must run headless names the widgetset unit
  directly.** `InterfaceBase` plus `Win32Int`/`Gtk2Int`, never `Interfaces`, whose
  initialisation opens the display before `main`. The technique is Phosphor's and the
  reason is the same: identical behaviour on a desktop, over a pipe, and in CI.
- **`TProcess.Executable` is converted through the Windows system code page,** so a
  non-ASCII path is mangled before the OS sees it. Use `TProcessUTF8` (`UTF8Process`,
  LazUtils) everywhere. Both `uphosphorrun` and `uphosphorhost` do.
- **One thread reading both of a child's pipes deadlocks.** Stated as an invariant
  above because it is one; repeated here because it is the trap that is most tempting
  to undo -- the single-threaded `while Running do if NumBytesAvailable > 0` version
  looks simpler, and it both lies about when the child is done and delivers output in
  visible jerks.
- **`TStatusBar.SimplePanel` defaults to TRUE in the LCL** (`lcl/comctrls.pp:198`,
  `default True`), which is the opposite of Delphi. A status bar whose `.lfm` defines
  four panels and does not say `SimplePanel = False` streams all four, sizes itself,
  draws its bevel and its resize grip, and then renders **`SimpleText`** -- which is
  empty. The result is a status bar that is plainly there and says nothing, on BOTH
  platforms, with no error anywhere. It survived a screenshot on each OS before
  anyone counted the panels; `--selftest` now reports the count and the flag, because
  "present but blank" is not a thing a screenshot can diagnose.
- **A toolbar button's caption is a REAL Alt accelerator, and it shadows the menu
  bar.** A `TToolButton` takes its caption from its action, ampersand included, so
  `S&top` on the toolbar answered **Alt+T** -- the Tools menu's key -- and killed the
  program being debugged instead of opening Preferences. `&Run` did the same to the Run
  menu. Found on 2026-09-16 by driving the editor from a script, which is the only way
  it could be found: the accelerator is invisible unless Alt is held. Every toolbar
  button now carries its own `Caption` **after** its `Action` in the `.lfm`, with no
  mark in it. A button is clicked, not typed.
- **`Process.MainWindowHandle` is not the form.** The LCL creates a hidden top-level
  window holding `Application.Title`, and Windows hands that one back as the main
  window. `MoveWindow` moved something invisible, `GetWindowRect` described it, and
  `EnumChildWindows` found it childless -- and every one of those succeeded. Any script
  that drives this program has to enumerate the process's **visible** top-level windows
  instead. (`scratchpad win.ps1` does; the technique is worth keeping.)
- **`GetWindowText` does not cross a process boundary for a control.** It is documented
  and it fails quietly: the Output memo reads back as the empty string from outside, so
  a pane full of text looks blank to a test. `SendMessage(WM_GETTEXT)` sent explicitly
  does marshal the string, and reading the transcript as TEXT is a far better witness to
  the ORDER of its lines than a photograph of it.
- **A changed `.lfm` needs `lazbuild -B`.** Without it the old form resource is kept
  and the binary streams the previous version of the form -- so the fix above appeared
  not to work, twice, until the rebuild was made a clean one. Both build scripts pass
  `-B` for exactly this reason. **Never diagnose an .lfm change from an incremental
  build.**

---

## Stepping: what is built, and the two things that are not

**Step debugging works.** As of 2026-09-16 the editor starts a session, stops at
breakpoints, steps over, into and out, shows the variables in scope, and ends the
session honestly -- driven against the real `phosphor debug --port` host **on both
platforms**: Windows 11, and gtk2 on Ubuntu under a real Xwayland session. The tooling
that does the driving is `tools/lane/`, and `docs/debugger-lane.md` records the five
steps, what each one was verified against, and the one thing gtk2 would not let a
script reach.

This paragraph replaces one that said, for a year and in the present tense, that
stepping was impossible. It was true when written -- the `BREAKPOINT` seam could not
block and returned void, the VM had no step API, the frame stack was private, the
console host installed no seam -- and every one of those four facts stopped being true
on 2026-09-15, in the **Phosphor** repository. The lesson worth keeping is not about
debugging: **a limitation recorded in the present tense is a claim with an expiry date
nobody set.** When one of these files says something cannot be done, say who would have
to change it, so the reader knows where to check.

What is still absent, and must not be described otherwise:

- **No watches and no evaluate.** `capabilities.evaluate` is `false` on every host
  today, and the editor must never close that gap in-process: an expression evaluator
  here would be an interpreter here. See the invariant at the top.
- **No conditional breakpoints.** A breakpoint the host could not arm IS drawn, as a
  **hollow ring in the gutter** beside the solid dot of one that will fire — the
  convention every debugger uses, and what roadmap item 13's image list was for. The
  full-row maroon and grey it replaced were a stand-in the code said so about at the
  time: a band of colour behind a line of code is a line of code that is harder to
  read, and a breakpoint is a thing you set and then read around. The one band that
  stays is the navy one for the current statement, because "you are here" IS a band.

The **call stack pane** landed on 2026-09-16 and is driven on both platforms. Two
rules in it are worth keeping: every `variables` request goes **by frame index**, which
is what made the pane a selection rather than a rewrite; and both panes are **emptied
whenever the state is not `dsStopped`**, because a stack and a set of locals describe a
program standing still, and the host refuses to answer about either while one runs.

Two debts this repository found by DRIVING the host, reported with their mechanism
in [`docs/phosphor-debugger-debts.md`](docs/phosphor-debugger-debts.md), and **both
fixed in Phosphor on 2026-09-16** (`fce3db1`):

- ~~A breakpoint on the first statement is reported installed and never fires.~~ It
  was never "line 1" -- it was the first EXECUTED statement, and a file opening with a
  `rem` lost line 2 instead, which is why it survived a year: every fixture anyone
  writes has a comment at the top. Three sites each right alone composed into it.
- ~~Only the innermost frame carries a line.~~ The data was already recorded --
  `TCallFrame.CallerStmtPC` -- and the repair was one accessor plus an off-by-one.

Both are left struck rather than deleted, because **the editor needed no change for
either fix**: the Line cells filled themselves and the once-per-session note about
callers having no line simply stopped appearing. That is the test of whether a
two-repository contract was drawn in the right place, and it is worth being able to
point at.

The code that handled the absent answers **stays**. A frame reporting `line: 0` is
still a legal answer from a conformant host, and `BreakpointIsArmed` still believes
the installed set. Neither is dead code; both are the editor being right about a
protocol rather than about one implementation of it.

One engine-side fact that remains, measured the same way:

- **An exception stop does not linger.** The host emits
  `{"event":"stopped","reason":"exception","line":4,"text":"division by zero"}` and
  closes the socket in the same breath, so the read-only gating around a terminal stop
  is correct but never observable for more than a tick. It is kept because the protocol
  permits a host that waits.

`docs/debug-protocol.md` specifies **PDBP** and `src/core/udebugproto.pas` is its editor
end -- written before the host end existed, on purpose, because the wire format is the
half two implementations must agree on. Two decisions there are load-bearing: it is
**not DAP** (whose header framing and large message set would be paid for in Free Pascal
inside the host; PDBP borrows DAP's message names so a bridge is a rename), and it is
**not carried on the child's stdout** -- a language whose entire observable behaviour is
`PRINT` can forge a frame, and one `println` of an exited-event would end the session
from inside the program being debugged. The protocol gets its own socket.

---

## The Phosphor repository, and facts that are not ours to retype

The sibling checkout lives at `../Phosphor` (`C:/Dev/Phosphor` here), and the host
search knows that layout -- `../Phosphor/bin/phosphor` is search position 4, after the
Preferences setting, `$PHOSPHOR_HOST` and a binary beside `phosphoride` itself.

These facts live **there**, and this repository holds them only as extracted copies or
as citations with a `file:line`:

- **the language** -- keywords, operators, literals, lexical rules;
- **the CLI contract** -- `phosphor [run] <file> [--out p] [--sandbox d]
  [--no-console]`, `phosphor compile [--check] <in.bas> <out.pbc>`,
  `phosphor pack [--no-console] <in.pbc> <out>`, `phosphor --version|--help|--diag`,
  and a bare `phosphor` is a REPL. Exit codes: **0** fine, **1** the BASIC program
  failed, **2** the host refused to run so nothing executed, **3** the interpreter
  itself faulted;
- **the function catalogue** -- which names exist, in which of the three tiers.

**A fact about Phosphor is EXTRACTED, never retyped.** `tools/gen-keywords.py` is the
one place allowed to know how, and its two extraction traps are already paid for: a
naive grep for `Reg.Add('name:sig')` **undercounts the engine by 23 names**, because
`PhosphorCallLib` and `PhosphorSysLib` register from const arrays in a loop, and a
stale agent worktree under `.claude/worktrees/` holds a duplicate copy of
`engine/libs` that **doubles every count** if the repository root is scanned instead of
the three known directories.

Where extraction is not possible -- an exit code, a seam's contract, a lexer rule the
highlighter depends on -- **cite the source with a line number**, as the unit headers
already do (`PhosphorLexer.pas:420-435` for unterminated strings, `:444-470` for
keywords-by-position, `:452` for case folding, `:459-460` for `mod`). Then a change
over there is findable from here. Do not paraphrase a Phosphor rule from memory; open
the file.

**AND A CITATION ROTS SILENTLY.** Every one of those four numbers was wrong on
2026-09-16 -- `:361-366` had become the `strClosed` reasoning, and `:385-408`, cited
in seven places here for "the lexer has no keyword table", had become the
backslash-escape table inside a string literal. The CLAIMS were all still true; the
line numbers had drifted by roughly sixty as the sibling file grew, and nothing in
either repository could notice. They were found only because roadmap item 15 was
about to copy one of them into an eighth place. So: when you touch a unit whose
header cites `../Phosphor`, OPEN THE CITED LINES and fix them if they have moved --
a citation nobody re-reads is a comment that lies with a reference attached, which is
worse than no reference at all.

One consequence worth keeping in mind while touching the highlighter: Phosphor's lexer
has **no keyword table**. Every keyword reaches the parser as an ordinary identifier
and is decided by position, so `next = 5` is a legal assignment. Colouring those words
as keywords is a deliberate, documented trade -- and nothing (folding, indentation,
completion) may be built on the assumption that a coloured keyword *is* a keyword.
`rem` and `mod` are the exception: the lexer itself owns those.

---

## Conventions

- **Commit as** `--author="AndreMurtaX <andre.murta@fhinck.com>"`, and end the message
  with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. A green uncommitted
  increment is not shipped.
- **Adapt the header comments with the code.** The long `WHY` blocks at the top of each
  unit are the design record; a change that makes one of them false is unfinished.
- **Record what a mistake cost, with the date, in the prose** -- the way the seven
  traps above are recorded. A rule with no defect behind it gets argued away.
- **Pascal: empty parens mark a CALL.** `a := Pop();` at the call site; none on the
  declaration, on a `property`, or after `@`.
- **objfpc mode has no `case`-of-string.** Use an `if` / `else if` chain.
- **Never write a patch script through a bash heredoc; use the Write tool.** A quoted
  heredoc still ate a backslash on 2026-09-10 in the sibling repository, and the
  failure surfaced as an anchor that did not match rather than as anything mentioning
  quoting.
