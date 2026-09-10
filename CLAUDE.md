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
2. `bin/phosphoridetest` is **all green** -- today 147 checks, exit 0. The count is
   printed; if it went down, something was deleted.
3. `phosphoride --selftest <report>` exits **0 under a timeout**. It constructs every
   form and writes what it found to the report file. The timeout is not optional; see
   trap 3.
4. `python tools/gen-keywords.py ../Phosphor --check` is **clean**. It prints
   `uphosphorlang.pas is current (538 core, 181 package, 426 gui)` and exits 0.
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

Measured on 2026-09-10 on Ubuntu with Lazarus 4.8: `bash scripts/build.sh` builds both
projects clean, `bin/phosphoridetest` is green, and the selftest constructs all three
forms under **gtk2** when a display is reachable -- there, through a real Xwayland
session (`DISPLAY=:0` with the mutter Xwayland cookie in `XAUTHORITY`) rather than
xvfb. The `xvfb-run` form above is still the one CI uses and is still the one nobody
has watched; a session and a virtual framebuffer are not quite the same thing.

`src/phosphoride.lpr:40-41` says `scripts/build.ps1` runs the selftest after
`lazbuild`, and it does. Both scripts exist and both have been run: `build.ps1` on
Windows and `build.sh` on Ubuntu, each green end to end. What remains unmeasured is
narrower than it was -- the `xvfb-run` branch of `build.sh`, and the editor DRIVEN by
hand under gtk2 rather than merely constructed there.

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
- **`src/core/uphosphorlang.pas` is GENERATED. Never hand-edit it.** Rewrite it with
  `python tools/gen-keywords.py ../Phosphor`. Its 53 keywords, 538 core, 181 package
  and 426 GUI built-ins are facts about the *other* repository; a hand edit puts them
  in two places and the edited copy is the one that goes stale. The script asserts
  `EXPECTED = {'core': 534, 'package': 181, 'gui': 426}` (534 registrations plus the
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

All nine were paid for on **2026-09-10**, building this repository.

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
- **A changed `.lfm` needs `lazbuild -B`.** Without it the old form resource is kept
  and the binary streams the previous version of the form -- so the fix above appeared
  not to work, twice, until the rebuild was made a clean one. Both build scripts pass
  `-B` for exactly this reason. **Never diagnose an .lfm change from an incremental
  build.**

---

## What is NOT built, and must never be described as built

**There is no step debugging, and it cannot be added from this repository alone.**
Breakpoints can be set from the gutter or with F5 and are kept in the document; the
Debug menu's Step items are **greyed out with an explanation attached**, and
`Debug > Why is stepping unavailable?` shows it in full. That is deliberate: an
explained absence beats a hidden menu, and beats a Step button that silently does
nothing.

The reason is a property of the engine, not an oversight a flag would fix
(`udebugsession.pas:12-30`):

- the `BREAKPOINT` seam "must not block: the engine treats it as a report, never a
  wait" (`Phosphor engine/PhosphorValue.pas:73-74`), and it returns **void**, so there
  is nothing for a debugger to answer with;
- `TPhosphorEngine` has **no step API at all** -- no `Step`, `OnStep`, `OnLine` or
  `Continue`, and no opcode-level trap;
- the frame stack is **private with no accessor**, so there is no call stack to report
  and no way to name a variable and read it;
- the console host **does not install the seam**, with a recorded exemption in
  `Phosphor scripts/check-seams.py`.

`docs/debug-protocol.md` specifies **PDBP**, the line-delimited JSON protocol that
would close the gap, and `src/core/udebugproto.pas` is its editor end -- written first
on purpose, because the wire format is the half two implementations must agree on.
Two decisions there are load-bearing: it is **not DAP** (whose header framing and large
message set would be paid for in Free Pascal inside the host; PDBP borrows DAP's
message names so a bridge is a rename), and it is **not carried on the child's
stdout** -- a language whose entire observable behaviour is `PRINT` can forge a frame,
and one `println` of an exited-event would end the session from inside the program
being debugged. The protocol gets its own socket.

Never write "coming soon" or "supported" about stepping without saying, in the same
sentence, that it requires work in the **Phosphor** repository.

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
already do (`PhosphorLexer.pas:361-366` for unterminated strings, `:385-408` for
keywords-by-position, `:392` for case folding, `:399` for `mod`). Then a change over
there is findable from here. Do not paraphrase a Phosphor rule from memory; open the
file.

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
