# PhosphorIDE

[![build](https://github.com/AndreMurtaX/PhosphorIDE/actions/workflows/build.yml/badge.svg)](https://github.com/AndreMurtaX/PhosphorIDE/actions/workflows/build.yml)

An editor for [Phosphor BASIC](https://github.com/AndreMurtaX/Phosphor), written in
Free Pascal against Lazarus/LCL and SynEdit. Desktop only -- Windows and Linux, the
same source on both. MIT licensed.

**The editor never links the Phosphor engine.** It edits text and it spawns the
`phosphor` binary as a child process; every run, syntax check, compile and pack is
an argument vector handed to that binary, and everything the editor knows about the
result it learned from the child's exit code and its two pipes. That is not an
implementation detail that could be optimised away later -- it is the requirement the
rest of the program is built around. A BASIC program that loops forever, exhausts
memory or faults the interpreter takes down its own process and leaves the editor
holding the user's unsaved work; an in-process interpreter would take the window,
the tabs and the unsaved buffers with it. The cost is real and is paid in full: no
in-process introspection, no shared heap, no cheap variable inspection, and a
debugger that has to be a protocol rather than a function call. See
[Debugging](#debugging) for what that costs today.

## Quickstart

Requires **Lazarus 3.6 or 4.8** with FPC 3.2.2 and the LCL, SynEdit and LazUtils
packages, all three of which ship with Lazarus, so a stock install is enough. Both
versions are measured rather than assumed: 4.8 is what it was written and driven by
hand against, 3.6 is what CI builds and checks it with.

```powershell
powershell -NoProfile -File scripts\build.ps1        # Windows
```

```bash
bash scripts/build.sh                                # Linux
```

Each script drives `lazbuild` over `src/phosphoride.lpi` and then runs the built
binary's `--selftest` under a timeout; the timeout is not decoration, see
[Testing](#testing). The binary lands in `bin/` -- `bin\phosphoride.exe` on Windows,
`bin/phosphoride` on Linux -- and unit output goes to `lib/$(TargetCPU)-$(TargetOS)`,
both of which are `.gitignore`d. To build by hand:

```
lazbuild src/phosphoride.lpi            # bin/phosphoride
lazbuild tests/phosphoridetest.lpi      # bin/phosphoridetest
```

A `Release` build mode exists (`-O3`, smart-linked, stripped) and writes to the same
`bin/phosphoride`. Both modes compile with `-vewn` and the project's bar is zero
warnings and zero notes.

**Finding a host.** The editor has no interpreter of its own, so "where is
`phosphor`" is a question it answers on every start, on two operating systems,
without a registry key or an installer to lean on. `uphosphorhost.LocateHostCandidates`
walks this order, most deliberate answer first, so that a person who has *said* which
binary to use is never overruled by one that merely happens to be on `PATH`:

1. the path set in **Tools > Preferences**;
2. **`$PHOSPHOR_HOST`**, for a shell or a CI job that wants to pin one;
3. **beside the executable** -- `./phosphor`, `./bin/phosphor`;
4. **a `../Phosphor` checkout** -- `../Phosphor/bin/phosphor` and one level further
   up, which covers both `PhosphorIDE/bin/phosphoride` and `PhosphorIDE/phosphoride`
   as the editor's own location;
5. **`PATH`**;
6. the usual install directories -- `%ProgramFiles%\Phosphor\`,
   `%LOCALAPPDATA%\Programs\Phosphor\` on Windows; `/usr/local/bin`, `/usr/bin`,
   `~/.local/bin` on Linux.

Nothing on that list is *executed* while searching. A path that exists is reported as
a candidate and the caller decides; running an unknown executable to find out whether
it is the right one is how a file dropped in the working directory gets run, and this
program already spawns quite enough processes on the user's behalf. `ProbeHost` is
the one place that does run it -- `phosphor --version`, against a path already settled
on, with a five-second deadline, because the path came from a *setting* and a setting
can name anything. The day it names something that waits for input, an editor without
that deadline never finishes starting and there is nothing on screen to say why.

A discovered path is never written back into the settings file. Empty means "search
every time"; freezing a lucky guess into a decision the user never made means the
first thing that moves is wrong forever. The Preferences host page shows what the
search *would* find, live, as the box is typed in.

The child is spawned through `TProcessUTF8` (LazUtils), not `TProcess`. `TProcess`
converts `Executable` through the Windows system code page, so a non-ASCII path is
mangled before the OS ever sees it -- found on 2026-09-10, and the failure looks like
a missing binary rather than an encoding fault, which is what makes it expensive.

## What works

Multi-tab editing, one `TSynEdit` per tab, with the highlighter below. Files are read
and written as UTF-8 **with no byte-order mark** -- that is not a preference: the
Phosphor lexer has no BOM handling at all, so a leading BOM is `unexpected character`
on line 1 of an otherwise perfect program, and every Windows editor and
`Set-Content -Encoding utf8` writes one.

| keystroke  | action                                                          |
| ---------- | --------------------------------------------------------------- |
| `F9`       | Run -- `phosphor run <file>`                                    |
| `Ctrl+F9`  | Check Syntax -- `phosphor compile --check <file> <temp>.pbc`     |
| `Ctrl+F2`  | Stop -- kills the child                                          |
| `F5`       | Toggle Breakpoint on the caret line                              |
| gutter click | the same toggle, where every other editor puts it              |
| `Ctrl+G`   | Go to Line; `Ctrl+F` / `F3` / `Ctrl+R` find, find next, replace  |
| `Ctrl+N` `Ctrl+O` `Ctrl+S` `Ctrl+Shift+S` `Ctrl+W` `Ctrl+Q` | new, open, save, save as, close tab, exit |

Compile to Bytecode and Pack Executable sit in the Run menu without shortcuts. Pack
is **two** runs of the host, because `phosphor pack` takes compiled bytecode and never
source: the editor compiles to a temporary `.pbc` and starts the `pack` only if that
first run exited 0. When the Sandbox preference is on, Run becomes
`phosphor --sandbox <root> run <file>`, defaulting the root to the directory the
script is in. The child's working directory is the file's own directory.

The host reads a *file*, so an unsaved buffer is not a program it can run. An
untitled or modified document is saved first (or, with Save-before-run off, the editor
asks whether to run the version on disk). Running a temporary copy would run the right
text under the wrong name and every diagnostic would then point into the temp
directory.

**Output streams live.** The child's stdout and stderr arrive in the Output pane as
the child writes them, not when it exits, and the input box below feeds its stdin for
`INPUT`, `LINE INPUT` and `INPUT$`. The shape behind that is one reader thread per
pipe plus a timer that drains their buffers on the main thread, and it is that shape
for a reason paid for on 2026-09-10: **one thread reading both pipes deadlocks.** A
blocking read on stdout does not return while the child is filling stderr, and once
the stderr pipe's buffer fills the child blocks on its write -- neither side moves
again. The program that provokes it is utterly ordinary: one that prints a lot and
then fails. Polling `NumBytesAvailable` from a single thread avoids the deadlock but
spends the interval asleep, so output arrives in visible jerks and the "is it done"
answer is a guess. The reader threads never touch the LCL; they append bytes to a
guarded buffer and the timer turns those into whole lines, because a parser handed
half of `phosphor: x.bas:2: unexpected token` finds no error at all.

**Diagnostics are parsed, not just printed.** The host emits exactly one diagnostic
per failed run -- the engine stops at the first error -- shaped
`phosphor: <path>:<line>: <message>`, and `uphosphormsg` knows the three other shapes
too: a packed executable omits the path, the REPL says `error: <msg>`, and a host-level
refusal such as `file not found:` carries no location at all. The separator is found
by looking for `:<digits>: ` past any Windows drive letter, because messages contain
colons of their own (`no function nosuchfunc$:%`, `cannot open "cafe.txt" for input:
no such file`) and splitting on the first or the last one produces garbage either way.
Anything with a location goes to the Problems tab and double-clicks to its line; a run
that produced exactly one such diagnostic jumps there by itself. Line numbers are
clamped before scrolling -- an unterminated block in a three-line file is reported at
line 4. The status bar renders the host's exit code as what it means: 0 fine, 1 the
BASIC program failed, 2 the host refused to run and nothing executed, 3 the interpreter
itself faulted.

**Breakpoints** can be set from the gutter or with `F5`, are painted on the line, and
follow the text: `core/ubreakpoints.pas` holds the set and `core/ueditordoc.pas`
subscribes to SynEdit's own line-count notification, so inserting a line above a mark
moves it to the statement the user chose rather than leaving it on a line number. A
breakpoint whose line is deleted is dropped rather than slid onto its neighbour, because
a mark that moves somewhere the user did not choose is worse than one that disappears.
What they do *not* do is stop anything -- see below.

Also here: preferences (host path, sandbox, font, tab width, line numbers,
current-line highlight, right margin, dark theme, save-before-run,
clear-output-on-run), a recent
files list, window geometry restored on start, and Help entries that open the Phosphor
language and function references on GitHub rather than shipping a copy of a reference
for a language that is still moving. Settings live in an INI file under
`%APPDATA%\phosphoride\` or `~/.config/phosphoride/` -- named after the *executable*,
not the application title, because `GetAppConfigDir` asks `ApplicationName`, so
renaming the binary moves the settings.

One more trap, cheap to describe and expensive to find: `SetFocus` on a control whose
form is not on screen yet **raises** `Can not focus`. The window creates its first tab
from `FormCreate`, before it is shown, so on 2026-09-10 a file named on the command
line was reported as unopenable with the focus error given as the reason. Focus is now
asked for only once there is somewhere to put it.

## The highlighter

`src/core/usynphosphor.pas` is a purpose-built SynEdit highlighter, and its word lists
are not typed by hand. `src/core/uphosphorlang.pas` is **generated** from a Phosphor
checkout by `tools/gen-keywords.py`, which reads every `Reg.Add` registration in
`engine/libs`, `host/packages` and `host/gui/libs`:

```
python tools/gen-keywords.py ../Phosphor            # rewrite the unit
python tools/gen-keywords.py ../Phosphor --check    # CI: fail if it would change
```

The word lists are facts about *another repository*, and typing them here would put
those facts in two places -- the second copy being the one that goes stale. The
generator asserts its counts (534 core registrations, 181 package, 426 GUI) and
**refuses to generate** if Phosphor has moved, so a new Phosphor release that adds a
built-in arrives as a red build rather than as silence. `--check` regenerates into
memory and diffs.

The keywords are the exception, and they are not generated at all: Phosphor's lexer has
no keyword table, so there is nothing to extract. The 53 of them are held by hand in
`gen-keywords.py` and checked against `TPhosphorCompiler.IsReservedWord` by a person,
which means a Phosphor release that adds a keyword passes every gate here in silence.

What the editor therefore knows: **53 keywords** and **1145 built-in names** in three
availability tiers -- 538 core (the 534 registrations plus `eof`, `input$`, `loc` and
`lof`, four special forms the compiler handles itself and no registry lists), 181 from
the opt-in host packages, 426 GUI. The tiers are three lists rather than one because
they are not interchangeable: core is always there, package names exist only because
the console host links every package, and GUI names exist only where a graphical
session was reachable when the program started. A program calling one is portable in a
way `print` is not, and it is coloured differently for that reason. Lookup is
case-insensitive because Phosphor lowercases every identifier as it scans, and a type
suffix is part of the name -- `left$` is the word, and `left` alone is not a built-in.

There is **no range state**. A SynEdit highlighter normally carries state across lines
for block comments and multi-line strings; Phosphor has neither -- `'` and `rem` run to
end of line, and a string literal that reaches a newline is the hard lexical error
`unterminated string`. So every line is coloured by looking at that line alone, and
editing line 10 never repaints line 400.

Two things get painted that a keyword list cannot reach, and they were chosen because
Phosphor's own documentation names them as what beginners hit most:

- **An unknown backslash escape.** `"C:\temp"` is not a path, it is a tab; `"\x"` is
  not a literal backslash-x, it is the compile error `unknown escape sequence`. The two
  offending characters take the error colour while the rest of the run stays a string,
  which is why one literal can emit several tokens.
- **An unterminated string**, red to end of line.

**And one thing is deliberately wrong.** Phosphor's lexer has no keyword table at all:
every keyword reaches the parser as an ordinary identifier and is decided by
**position** (`engine/PhosphorLexer.pas:385-408`). `next = 5` and `elseif += 3` are
legal assignments, and this editor will colour both words as keywords anyway. That is
a trade, not an oversight. Being right about the rare program means being the parser;
the alternative -- colouring nothing until it is certain -- mis-colours every ordinary
program to be correct about a strange one. What the trade *costs* is that nothing
downstream may assume a coloured keyword is a keyword, so no folding and no
auto-indentation are built on top of it. The two words the lexer itself owns, `rem`
and `mod`, are the exception and are treated as absolute.

## Debugging

**Stepping works.** Set a breakpoint in the gutter or with F5, press **Shift+F9**,
and the program stops there with the line highlighted and its variables listed. Then
**F8** steps over, **F7** steps into, **Shift+F8** steps out and **F6** continues.
A breakpoint the host could not arm -- on a blank line, a comment, an `endfunction` --
is drawn grey instead of red, because the host answers `setBreakpoints` with the set it
actually installed and a mark that will never fire should not look like one that will.

The editor still does not contain an interpreter. A debug session is
`phosphor debug --port <n> <file.bas>` as a child process, talking back over a loopback
socket in a line-delimited JSON protocol called PDBP; the program's own stdout, stderr
and stdin stay on the ordinary pipes where the output pane already reads them.

Three sentences of history, because they are the reason the design is shaped this way.
Until 2026-09-15 the Debug menu's Step items were greyed out with an explanation
attached, and that explanation had four citations: the engine's `BREAKPOINT` seam had
to be report-and-continue, the VM had no step API, the frame stack was private, and the
console host installed no seam. All four were true when written and none is true now.
Phosphor gained `TPhosphorDebugProc`, `ArmDebug`, four step actions and the `Dbg*`
accessors; this editor's end of the protocol had been written first, on purpose, and
the menu followed on 2026-09-16.

The **Call Stack** pane lists the frames the program is standing in -- four `down`
calls and `(main)`, in a three-deep recursion -- and selecting one shows that frame's
variables, so the locals of the outermost call are one click away from the innermost.
Double-click a frame to go to it. Both panes empty themselves the moment the program
resumes: they describe a program standing still, and a photograph presented as a live
view is the same defect as a current-line marker that outlives its stop.

One limitation that is the host's and not the editor's: **only the innermost frame
carries a line**, because the engine does not record a call site per frame. The callers
are listed without one and cannot be jumped to, which the pane says rather than
guessing at a location.

What is **not** built: no watches and no evaluate -- `capabilities.evaluate` is false on
every host, and an expression evaluator in here would be an interpreter in here.
`docs/debugger-lane.md` records what each step was verified against, and what the first
cut got wrong.

Two decisions in that specification are worth stating here because they constrain the
Phosphor side. It is **not DAP**: the Debug Adapter Protocol is the right answer if
PhosphorIDE is ever not the only client, but its framing is HTTP-style headers over a
byte stream and its message set is large, and the half that has to be written in Free
Pascal inside the host is the half that pays for that -- so PDBP is small enough to be
a day's work, and its message names are DAP's, making a bridge later a rename rather
than a redesign. And it is **not on stdout**: protocol frames on the child's own stdout
are unusable for a language whose entire observable behaviour is `PRINT`, since one
`PRINTLN` of a forged `exited` event would end the session from inside the program
being debugged.

Availability is asked of the binary rather than computed from a version number --
which version first shipped the subcommand is a fact about the future, whereas what the
binary in front of us can do is a fact about the binary in front of us. `--help` is the
cheap pre-filter, and it is only that: the usage block advertises `phosphor debug` and
says nothing about `--port`, so a host with only the terminal debugger looks identical
there. **Available means the handshake succeeded**, which is the only thing that
actually proves it.

Everything else meanwhile is unaffected. Breakpoints are kept and tracked because the
editor side is the half that can be built and tested now, and a breakpoint list that
already survives editing is what the other half will need the day the host can answer.

## Layout

| path                | what                                                                |
| ------------------- | ------------------------------------------------------------------- |
| `src/`              | `phosphoride.lpr` (the program and `--selftest`), the three forms.  |
| `src/umainform.pas` | the editor window and every action. Nothing here waits.             |
| `src/core/`         | the units: `usynphosphor` (highlighter), `uphosphorrun` (the async child), `uphosphormsg` (diagnostics), `uphosphorhost` (finding the binary), `uphosphorsettings`, `ueditordoc` + `ubreakpoints`, `udebugproto` + `udebugsession` (PDBP), `uphosphorlang` (**generated**). |
| `tools/`            | `gen-keywords.py` -- regenerates `uphosphorlang.pas` from a Phosphor checkout. |
| `tests/`            | `phosphoridetest.lpr`, the headless unit checks.                     |
| `scripts/`          | `build.ps1` / `build.sh`: lazbuild, then `--selftest` under a timeout. |
| `docs/`             | `architecture.md`, `building.md`, `roadmap.md`, `debug-protocol.md` -- the PDBP specification -- and `debugger-lane.md`, which says what is built on each side and what is next. |
| `bin/`, `lib/`      | build output. Both ignored.                                          |

## Testing

Two harnesses, and between them they leave a gap that is worth naming.

**`bin/phosphoridetest`** -- 185 checks, all green -- covers the logic that can be
wrong without anyone noticing: the diagnostic parser (every input string in it was
captured from a real `phosphor` run, not invented), the exit-code taxonomy, the
generated word lists against their asserted counts, what the highlighter's scanner
emits token by token, and every PDBP frame both ends must agree on, including that
garbage is a report and never a crash. It is a console program that links SynEdit and
the LCL but **never `Interfaces`**, so no widgetset is created and it runs identically
on a desktop, over a pipe and on a headless CI machine. Linking the LCL is not what
connects to a display: `Interfaces` is, via the `CreateWidgetset` call in its
initialization section, which on gtk2 opens the X display before `main`. Naming the
widgetset unit directly (`InterfaceBase` plus `Win32Int`/`Gtk2Int`) links the same code
and leaves the call unmade. The technique is Phosphor's.

**`phosphoride --selftest <report>`** constructs all three forms from the command line
and writes what happened to `<report>`, exiting 0 if every form built and 1 if one did
not. It exists because an `.lfm` that names a property its `.pas` does not publish does
not fail: LCL's `TApplication.ShowException` answers the streaming error with "Press OK
to ignore and risk data corruption" and *waits*. In a build script that is not a red
test, it is a hang, with the dialog sitting on whatever machine happened to run it.
`--selftest` sets `Application.Flags + [AppNoExceptionMessages]` so the mismatch becomes
an exit code, and `scripts/build.ps1` **also** runs it under a timeout, because a flag
only covers the dialogs LCL knows it is showing.

Two Windows-specific hazards found on 2026-09-10 shaped that design, both of them
hangs rather than errors:

- A **GUI-subsystem binary has no console**, so `WriteLn` hits an invalid handle and
  the RTL's I/O error surfaces as a modal dialog nobody is there to dismiss. A
  `--selftest` that merely wrote its result to stdout hung until it was killed. Hence a
  report *file* and an exit code, and no console stream anywhere in this program.
- **`-gh` (heaptrc) in that same binary writes its leak report to that same missing
  stdout at exit**, so the process hangs on the way out. It is removed from the Default
  build mode; a leak-checking build has to be run from a console.

What neither covers: the forms are constructed but never driven, so nothing here clicks
a menu, and no test spawns a real `phosphor`. Every claim about the host's output shapes
and exit codes is pinned by strings captured from the real binary rather than by a live
run. There is no end-to-end test and the gap is known.

## Licence

MIT -- see [LICENSE](LICENSE). By AndreMurtaX.

The interpreter this editor drives lives in the sibling repository:
**https://github.com/AndreMurtaX/Phosphor**. Its
[language reference](https://github.com/AndreMurtaX/Phosphor/blob/main/docs/language-reference.md)
and
[function reference](https://github.com/AndreMurtaX/Phosphor/blob/main/docs/function-reference.md)
are what the Help menu opens, and they are the authority on everything the highlighter
merely colours.
