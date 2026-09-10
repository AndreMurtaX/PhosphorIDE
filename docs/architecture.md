# Architecture

How PhosphorIDE is put together, and why each piece is shaped the way it is.

PhosphorIDE is a Lazarus 4.8 / FPC 3.2.2 LCL application: a tabbed SynEdit editor
with a purpose-built Phosphor BASIC highlighter, an output pane, and a set of
actions that hand the file on screen to the `phosphor` binary. It links SynEdit
and the LCL. It does not link the Phosphor engine, and the rest of this document
is largely about what follows from that.

Read this alongside the unit headers. Every unit under `src/core/` carries a long
comment saying why it is the shape it is; this file is the map that makes those
comments navigable, not a replacement for them.

---

## 1. The process boundary

**The editor never links the interpreter. It spawns it.**

This is the founding decision and the one the rest of the program is not allowed
to trade away for convenience. It is written at the top of `src/phosphoride.lpr`
in those terms, and it is worth stating the reason in full, because every
awkwardness further down this document is a bill this decision runs up.

A BASIC program under development is, by definition, wrong. It loops forever. It
allocates until the machine swaps. It recurses until the stack goes. It hits an
interpreter defect and faults inside the VM. If the interpreter is a library
inside the editor's process, then every one of those takes the editor down with
it, and takes the user's unsaved work in three other tabs with it. An editor that
loses your file because the program you were writing had a `while` with no exit
is not an editor anyone can use to write a program with a `while` in it.

So the interpreter runs in a child process, and the worst a runaway script can do
is kill itself. The editor is still on screen, still holding the buffer, still
able to save it, and the Stop button still works.

### What crosses the boundary

Five things, and no more:

```
  phosphoride (LCL, GUI subsystem)              phosphor (console subsystem)
  --------------------------------              ---------------------------
   TProcessUTF8.Execute  ---- argv ---------->   run | compile | pack | flags
   SendInput             ---- stdin --------->   INPUT, LINE INPUT, INPUT$
   reader thread         <--- stdout --------    PRINT, PRINTLN, the program
   reader thread         <--- stderr --------    phosphor: x.bas:12: <message>
   FProcess.ExitStatus   <--- exit code -----    0 | 1 | 2 | 3
   Kill                  ---- TerminateProcess / SIGKILL -->
```

**argv.** `TPhosphorRunner.Start` takes the executable, an array of arguments and
a working directory, and nothing else. The arguments are the host's documented
CLI and nothing invented on top of it:

```
phosphor [run] <file> [--out <path>] [--sandbox <dir>] [--no-console]
phosphor compile [--check] <in.bas> <out.pbc>
phosphor pack [--no-console] <in.pbc> <out>
phosphor --version | --help | --diag
phosphor                                   (no arguments: a REPL)
```

Run is `['run', path]`, or `['--sandbox', root, 'run', path]` when the sandbox
preference is on -- the root defaults to the directory the script itself is in,
which is the only default that is not a surprise. Check Syntax is `['compile',
'--check', path, temp]` into a temporary `.pbc` the editor then ignores; the
point of that call is the diagnostics, not the artefact. Pack is *two* runs,
because `phosphor pack` takes compiled bytecode and never source: the first
compiles to a temporary `.pbc` and the second is started from `RunnerFinished`
only if the first actually produced one.

The working directory is the directory of the file being run. That is what makes
a script's own relative paths mean what the author meant.

**stdin.** The input box under the output pane writes one line, with a
terminator, into the child's standard input; that is what a program blocked in
`INPUT`, `LINE INPUT` or `INPUT$` reads. `CloseInput` closes the pipe, which the
program sees as end of input. The line is echoed into the output pane, because a
console shows what was typed and a program that does not echo leaves the user
looking at a transcript with holes in it.

**stdout and stderr.** Both are read, separately, live -- see section 3. stdout is
the program's own output. stderr is where diagnostics arrive, exactly one per
failed run, because the engine stops at the first error and there is no error
list to collect.

**The exit code.** Four values, and they are a real taxonomy worth keeping
straight (`PhosphorExitCodeText` in `uphosphormsg.pas` turns each into one line
for the status bar):

| code | meaning |
| ---- | ------- |
| 0 | it ran and finished |
| 1 | the BASIC program failed -- a compile or runtime error |
| 2 | the host refused to run: nothing executed |
| 3 | the interpreter itself faulted |

Anything else came from the operating system or from whoever killed the process.

### What does not cross it

There is no shared memory, no API, no callback, no handle to a value, no way for
the editor to ask what a variable holds, no way to install a hook. The editor
knows what a text stream told it and what an integer said at the end. That is the
whole of it.

In particular: **the editor cannot pause the child, and cannot bound it.**

Phosphor's execution ceilings -- `MaxSteps`, `TimeoutMs`, `MaxOutputBytes` and
`MaxMemoryBytes` -- are the *embedder's* to set. They are set in Pascal, by the
program that links the engine, before it runs anything. The console `phosphor`
host sets none of them: that is deliberate on its side, documented in Phosphor's
`docs/embedding.md`, and it means an ordinary `phosphor run x.bas` is unbounded
by design. An editor driving that binary from outside has no way to reach in and
set a ceiling the host declined to set. There is no `--max-steps` flag to pass,
and inventing one here would be inventing it in the wrong repository.

**So killing the process is the only lever, and Stop (Ctrl+F2) is that lever.**
On Windows it is `TerminateProcess`, which does not walk a process tree. The
`phosphor` host spawns nothing, so today there is no tree -- but a packed
executable that shells out would leave its own children behind, and that is a
known and recorded limit rather than something to discover later.

Two honest consequences of having no ceilings:

- A program that prints without stopping grows the output pane without bound.
  `TFrmMain.AddOutput` appends to a `TMemo` and nothing trims it, so the memory
  belongs to the editor even though the loop belongs to the child. Stop ends it.
  A line cap on the pane is the obvious fix and is not written.
- A program that allocates without stopping is the operating system's problem,
  and the editor's only involvement is that Stop still works while it happens.
  That is exactly the property the process boundary was bought for.

### The cost of the boundary, stated plainly

- **The host reads a file, so the buffer must be on disk.** `EnsureSavedForRun`
  saves first, or asks whether to run the version on disk. A temporary copy would
  run the right text under the wrong name, and every diagnostic would then point
  at a path in the temp directory.
- **Everything is asynchronous, or the UI freezes.** Nothing in `umainform.pas`
  waits on the child. The two places that do block on a process -- `ProbeHost`
  and the debug probe, both `phosphor --help`/`--version` -- are separate,
  deliberate calls with a deadline (`RunAndCapture`, 5 s default), because the
  path they run comes from a *setting* and a setting can point at anything. The
  day it points at something that waits for input, an editor without that timeout
  never finishes starting and there is nothing on screen to say why.
- **Diagnostics are text, and text has to be parsed.** Section 5 of
  `uphosphormsg.pas`'s header is the list of ways that goes wrong.

---

## 2. The unit map

```
                          src/phosphoride.lpr
                    Application, --selftest, Halt code
                                  |
        +-------------------------+-------------------------+
        |                         |                         |
   umainform.pas            uaboutform.pas          upreferencesform.pas
   tabs, actions, output pane, problems list, status bar
        |
        |  owns one of each, for the life of the window
        |
        +-- core/ueditordoc.pas ......... one open file: its SynEdit, its path,
        |         |                       its breakpoints
        |         +-- core/ubreakpoints.pas .. the marks, and the arithmetic that
        |                                      keeps them on their statement
        +-- core/uphosphorrun.pas ....... the child process: two reader threads
        |                                 and a drain timer
        +-- core/uphosphorsettings.pas .. the INI under the per-user config dir
        +-- core/usynphosphor.pas ....... the SynEdit highlighter
        +-- core/udebugsession.pas ...... can this host be stepped? (today: no)
        |         |
        |         +-- core/udebugproto.pas .. PDBP encode/decode
        |
        |  asks; owns nothing
        |
        +-- core/uphosphorhost.pas ...... where is the phosphor binary
        +-- core/uphosphormsg.pas ....... what did that stderr line mean
        +-- core/uphosphorlang.pas ...... GENERATED word tables
                        ^
                        |  tools/gen-keywords.py [--check]
                        |
              ../Phosphor/engine/libs
              ../Phosphor/host/packages
              ../Phosphor/host/gui/libs
```

Dependencies run downward only. No unit under `core/` uses `umainform`, and none
of them knows that a menu exists.

**`src/phosphoride.lpr`** owns the process: `Application.Initialize`, the one
form that is created at startup, and `--selftest`. It also owns the two
Windows-subsystem facts in section 6.

**`src/umainform.pas`** owns the window and every action -- the tab control, the
output pane, the problems list, the status bar, the menus. Its single rule is
that *nothing here waits*. It knows about all of `core/`; nothing in `core/`
knows about it. Its second rule is that it does not decide anything a core unit
has already decided: it does not parse a diagnostic, it does not guess where the
host is, and it does not colour a token.

**`core/ueditordoc.pas`** owns one open file. The SynEdit control is created here
rather than dropped on a form, because there is one per tab and the number of
tabs is not known until someone opens something. It owns a `TBreakpointSet` and
the wiring that keeps it honest: a handler on SynEdit's own `senrLineCount`
notification, so a breakpoint follows its statement when text above it moves. It
must never know what a breakpoint is *for*: today, nothing can stop at one.

That wiring is worth its own sentence, because it was missing. The arithmetic was
written first and nothing called it, so for several hours the editor had
breakpoints that stayed on their line numbers while the text slid underneath them
-- a defect with no visible symptom, found on 2026-09-10 by grepping for callers
of a method that had none. The fix moved the set into `core/ubreakpoints.pas`,
where `tests/phosphoridetest.lpr` exercises every boundary case without a window,
and subscribed to the notification SynEdit was already sending.

Reaching that notification needs `ViewedTextBuffer`, which Lazarus keeps
protected, so the unit declares a one-line descendant to see it. The alternative
-- inferring the delta from `Lines.Count` in `OnChange` -- is wrong for the case
that matters: pasting six lines into the middle of a file says the count went up
by six but not *where*.

`ueditordoc` writes UTF-8 with **no** byte-order mark, and that is
not a preference -- the Phosphor lexer has no BOM handling at all, and a leading
BOM is the lexical error `unexpected character` on line 1 of an otherwise perfect
program.

**`core/uphosphorrun.pas`** owns the child process and everything about reading
it. It must never know what the arguments mean: it is handed an executable, an
array of strings and a working directory. It has no idea what `compile --check`
is, and adding that knowledge here would put the CLI contract in two places.

**`core/uphosphorhost.pas`** owns the search for the binary, in a fixed order --
the Preferences setting, then `$PHOSPHOR_HOST`, then beside the executable, then
a sibling `../Phosphor/bin/` checkout, then PATH, then the usual install
directories. It goes from the most deliberate answer to the most incidental, so a
person who has *said* which binary to use is never overruled by one that merely
happens to be on PATH. It must never *run* anything while searching: running an
unknown executable to find out whether it is the right one is how a file dropped
in the working directory gets executed, and the editor already spawns quite
enough processes on the user's behalf. `ProbeHost` is the one call that runs a
candidate, with `--version`, against a path the caller has already settled on.

**`core/uphosphorsettings.pas`** owns what is remembered between runs: an INI
under `%APPDATA%\phosphoride\` or `~/.config/phosphoride/`. Not the registry, and
not a file beside the executable -- a portable-looking editor that writes next to
itself fails the moment it is installed into Program Files, and that failure is
silent. `Load` never throws; a corrupt settings file leaves the defaults
standing. `HostPath` empty means "search on every start", and a discovered path
is deliberately **not** written back: that would freeze a lucky guess into a
decision the user never made, and the first thing that moved would then be wrong
forever.

The config directory is named from the *executable*, because `GetAppConfigDir`
asks `ApplicationName`, which defaults to the binary's own name -- not from
`Application.Title`. Renaming the binary moves the settings. Recorded because it
is the kind of thing that is discovered by losing a settings file.

**`core/usynphosphor.pas`** owns colour. Section 4.

**`core/uphosphormsg.pas`** owns the meaning of a line of the host's stderr, and
nothing else. **Pure**: no LCL, no file access, no state. Text in, record out.

**`core/uphosphorlang.pas`** owns the word lists. **Pure**, and **generated** --
section 5.

**`core/udebugproto.pas`** owns the PDBP wire format. **Pure**: `fpjson` and
strings. It speaks to nothing yet, on purpose -- section 6.

**`core/udebugsession.pas`** owns one question: can the host in front of us be
stepped? Today the answer is always no, and the value of the unit is the sentence
it hands the UI to explain why.

### Purity, and why it is worth naming

`uphosphormsg`, `uphosphorlang` and `udebugproto` reach no LCL unit at all.
`usynphosphor` reaches only `Graphics`, because a highlighter's colours are
`TColor`, and it never touches a canvas or a window.

That is what makes `tests/phosphoridetest.lpr` possible: 147 checks over the
diagnostic parser, the generated tables, the highlighter's token stream and the
protocol codec, in a console program that runs identically on a desktop, over a
pipe, and on a headless CI machine. These are exactly the parts that can be wrong
without anyone noticing -- a parser that silently stops matching, a highlighter
that quietly paints a bad escape as ordinary text, an encoder that emits a frame
the other end will not accept. A form that fails to build is caught by
`--selftest`; a colour that is slightly wrong is caught by looking. These are
neither.

The test program links LCL units but **never `Interfaces`**. `Interfaces`
contains one thing that matters: a `CreateWidgetset` call in its *initialization*
section, and on gtk2 that call opens the X display before `main` -- so a binary
that merely listed the unit died on a machine with no session. Naming the
widgetset unit directly (`InterfaceBase` plus `Win32Int` or `Gtk2Int`) links the
same code, satisfying the `WSRegister*` symbols the LCL's registration tables
reference, while leaving the call unmade. The technique is Phosphor's, taken from
the host that decides at startup whether a graphical session is reachable.

---

## 3. The async runner

`TPhosphorRunner` is **one thread per pipe, plus a timer on the main thread that
drains what they collected.** Three alternatives were considered and each is
rejected for a specific, reproducible reason.

### Why not one thread reading both pipes

It deadlocks. A blocking read on stdout does not return while the child is
writing to stderr, and once the stderr pipe's buffer fills, the child blocks on
its write -- so neither side moves again, and the editor sits there with a
half-finished transcript and a child that is not dead.

The program that provokes this is not exotic. It is *a program that prints a lot
and then fails*: plenty of stdout, then a diagnostic on stderr, with the reader
still draining stdout. That is the single most common shape a failing BASIC
program has.

Two threads, each blocked on its own pipe, cannot get into that state.

### Why not poll `NumBytesAvailable`

Polling works, and it lies about when the child is done. It also spends the
interval asleep, so output arrives in visible jerks rather than as the child
produces it. A blocking read delivers the moment the child writes, which is what
makes watching a slow program feel like watching a program rather than watching a
progress indicator.

### Why a drain timer rather than `TThread.Synchronize`

The LCL rule is that the UI is touched from one thread. `Synchronize` and `Queue`
both satisfy it, and both put the ordering of the program partly in the RTL's
hands: a `Synchronize` from the stdout thread and one from the stderr thread
interleave with each other and with whatever the user is doing, and re-entrancy
becomes something to reason about at every call site.

Instead, the reader threads never touch the LCL at all. They append bytes to a
buffer guarded by a `TCriticalSection`, and `DrainTimer` -- on the main thread,
every 40 ms -- takes the whole buffer under the lock, releases it, and turns the
bytes into lines and events. One obvious order of operations, no re-entrancy, and
the lock is held for a swap of two strings rather than for the duration of a
repaint.

40 ms is the compromise: small enough that output feels live, large enough that a
program printing in a tight loop does not spend the UI's whole budget on repaints.

The same timer decides when the run is over, and it needs *both* conditions --
readers finished **and** process not running. The child can have exited while a
reader still has buffered bytes to hand over, and a reader can finish while the
child is still winding down. Either condition alone drops output on some runs and
not others, which is the worst kind of defect to look for.

### Why lines and not bytes

A pipe read returns whatever happened to be in the buffer. A single read can end
mid-line, and a diagnostic can arrive in two pieces.

Every consumer wants whole lines: the output pane appends them, the diagnostic
parser matches them whole. A parser fed half of `phosphor: x.bas:2: unexpected
token` finds no error at all -- not a partial one, *none*, and the jump-to-error
that the user was waiting for silently does not happen. So `EmitLines` holds the
partial tail until its newline arrives, and flushes it unterminated when the
stream ends. That last flush matters: `phosphor --version` ends with a newline,
but a program whose last statement is `PRINT` rather than `PRINTLN` does not, and
dropping its final line would be a silent loss.

There is one exception, and it is a prompt. A child that writes `phosphor> ` or
`INPUT`'s `? ` and then waits has an unterminated line whose newline is never
coming, so holding it forever would leave the user staring at a blank pane and
answering a question they cannot see. `DrainTimer` counts the drains in which a
stream produced nothing, and `FlushPrompt` emits the tail after two of them --
about 80 ms. That emission carries `ACompleteLine=False`, which is how the output
pane knows to keep appending to the same visual line and how everything
downstream knows this is not yet a line to parse.

A trailing CR is stripped there too, so a CRLF pipe on Windows and an LF pipe on
Linux present the same string to everything downstream.

### Why no encoding conversion

The host emits UTF-8. The LCL wants UTF-8. The bytes are passed through
untouched.

This is a decision, not an omission. Any "helpful" conversion here -- `SysToUTF8`,
a CP1252 round-trip -- would corrupt exactly the strings Phosphor is careful
about, in a language that counts characters with `len` and bytes with `bytelen`
and means the difference.

The one place an encoding conversion *is* required is the other direction, and it
is a trap that cost real time on **2026-09-10**: `TProcess.Executable` is an
`AnsiString` that fcl-process converts for `CreateProcessW` through the Windows
**system code page** -- 1252 here, not UTF-8. A path holding a non-ASCII
character is therefore mangled before the OS ever sees it, and the answer is
`file not found` for a file that is plainly there. `TProcessUTF8` (LazUtils) does
the conversion the LCL's way; on Linux it is a pass-through. The runner uses
`TProcessUTF8` and `uphosphorhost.RunAndCapture` uses it too.

On Windows the child is started with `poNoConsole` and `swoHide`, so running a
console child from a GUI parent does not flash a console window. The output comes
down the pipes either way. On Linux a GUI parent has no console to give away, so
neither option has anything to do.

`Start` distinguishes two failures that are easy to conflate. A child that could
not be started *at all* -- a missing binary, a directory, no permission -- fires
`OnStartFailed` and answers `False`. A child that starts and then fails is not a
start failure: that is an exit code, and it arrives through `OnFinished`.

---

## 4. The highlighter

`TSynPhosphorSyn` is a `TSynCustomHighlighter` with **no range state**, which is
unusual enough to explain.

### Why no range state is needed

A SynEdit highlighter normally has to carry state from line to line, because a
block comment or a multi-line string opened on line 10 changes how line 400 is
coloured. That machinery -- `GetRange`, `SetRange`, `ResetRange` -- is where a
highlighter's bugs live, and it is why editing one line can repaint the rest of
the file.

Phosphor has neither construct:

- `'` and `rem` run to end of line, and nothing else starts a comment. There is
  no `/* */`.
- A string literal that reaches a newline is not a continuation. It is the hard
  lexical error `unterminated string` (`engine/PhosphorLexer.pas:361-366`).

So every line can be coloured by looking at that line alone. `GetRange` and
`SetRange` stay the base class's no-ops, editing line 10 never repaints line 400,
and there is no state to get wrong.

`FInString` exists but is *within* a line only -- it is reset by `SetLine`, and it
says whether this call is opening a literal or resuming one.

### Why one string literal can emit several tokens

Two of Phosphor's rules are exactly the kind a beginner loses an hour to, and
both are visible at lexing time, so the highlighter paints them as errors rather
than waiting for the compiler to say so:

- **An unknown backslash escape.** `"C:\temp"` is not a path, it is a tab.
  `"\x"` is not a literal backslash-x, it is the compile error `unknown escape
  sequence`. The valid set is `n t r 0 a b f v \ "`
  (`engine/PhosphorLexer.pas:329-359`) and anything else is a defect.
- **An unterminated string**, which runs to end of line.

For the first of these, colouring the *whole* literal red would be wrong: the
string is mostly fine and the mistake is two characters wide. So `ScanString`
returns several tokens for one literal. It scans forward until it finds the bad
escape; if there is text before it, that text is emitted as `ptkString` and the
scan resumes on the next call, which emits the two offending characters as
`ptkError` and then carries on in the literal. The result is a green string with
two red characters in the middle of it, pointing at the thing that is actually
wrong.

`""` is handled on the way past: it is one embedded quote and does not close the
literal. A backslash as the last byte of a line closes nothing and is an error,
because the literal cannot then close either.

### What it deliberately gets wrong

**Phosphor's lexer has no keyword table.** Every keyword arrives at the parser as
an ordinary identifier, and the parser decides from POSITION whether the word is
a keyword (`engine/PhosphorLexer.pas:385-408`). `next = 5` and `elseif += 3` are
legal assignments to legal variables.

Colouring those words as keywords everywhere is therefore *wrong*, in a way no
highlighter can fix without being the parser. It is the right trade -- the
alternative mis-colours every ordinary program in order to be correct about a
rare one -- but it is a trade, and it is recorded as one:

> nothing downstream (folding, indentation) may be built on the assumption that a
> coloured keyword IS a keyword.

The two exceptions are `rem` and `mod`, which the lexer itself owns and which can
never be variables. Those are treated as absolute.

A type suffix is part of the name: `left$` is one token, never `left` followed by
a symbol. `GetIdentChars` includes `$ % @ ?` so that double-clicking `count%`
selects the whole name and a word-boundary search for `left$` behaves.

Built-ins are painted in three tiers with three different colours -- core,
package, GUI -- because they are not interchangeable. A program that calls a GUI
name is portable in a way `print` is not, and seeing that at a glance is worth a
colour.

Both themes live in `ApplyTheme` in this unit rather than in the form, so a
second window, a print preview or a future embedded viewer gets the same colours
without anyone copying a table.

---

## 5. The generated word tables

### The two-repository problem

The words this editor highlights are **facts about another repository**: 53
keywords from `TPhosphorCompiler.IsReservedWord`, and 1141 built-in names from
the `Reg.Add` registrations under `engine/libs`, `host/packages` and
`host/gui/libs`.

Typing them into `uphosphorlang.pas` by hand would put those facts in two places,
and the copy that gets edited is the copy that goes stale. Worse, it goes stale
*silently*: a Phosphor release adds twelve built-ins, the editor quietly does not
know about them, and nobody finds out until a user asks why `zip_open@` is not
coloured.

`tools/gen-keywords.py` is the only place that knows how to extract the built-ins:

```
python tools/gen-keywords.py ../Phosphor            # rewrite the unit
python tools/gen-keywords.py ../Phosphor --check    # fail if it would change
```

`--check` regenerates into memory and diffs. It is what `scripts/build.ps1` runs,
skipping only when no Phosphor checkout is present, since a contributor need not
have both repositories. **A Phosphor release that adds a built-in shows up here
as a red build.** That is the point: silence would mean the editor had quietly
stopped knowing the language.

The counts are asserted rather than assumed -- 534 engine names, 181 package, 426
GUI -- and if a release moves any of them the script refuses to generate and says
so:

```
refusing to generate: core tier has 546 names, expected 534.
Phosphor changed. Decide what the new number is, update EXPECTED in this
script, and say so in the commit message.
```

Refusing is the right failure. A generator that happily writes whatever it found
turns "Phosphor changed under us" into a diff nobody reads.

The unit's public counts are `PhosphorKeywordCount = 53`,
`PhosphorBuiltinCoreCount = 538`, `PhosphorBuiltinPackageCount = 181`,
`PhosphorBuiltinGuiCount = 426`. Core is 538 rather than 534 because four names
are not in any registry at all: `eof`, `input$`, `loc` and `lof` are special
forms the compiler handles directly, and a user function may not shadow them
(`engine/PhosphorCompiler.pas:461-469, 800-832`).

### The two extraction traps, both already paid for

**1. A naive grep for `Reg.Add('name:sig')` undercounts the engine by 23.**

Two libraries register from a `const` array in a loop, so the names never appear
next to a `Reg.Add` call at all: `PhosphorCallLib` (`callfunc` and its four
suffixed forms across nine arities) and `PhosphorSysLib` (18 mobile shared-path
names). A regex over call sites finds none of them, and the count comes out 23
short with nothing to indicate anything is missing.

The script matches the *array reference* -- `Reg.Add(SomeArray[i] + ':...', @fn)`
-- and then reads the elements of `SomeArray` out of the same unit's `const`
section. Matching the reference rather than a list of known file names is what
makes this general: a loop registration added to some other library tomorrow is
found the same way, instead of going missing until a count assertion fires.

**2. A stale agent worktree under Phosphor's `.claude/` doubles every count.**

`.claude/worktrees/` holds a full duplicate copy of `engine/libs`. A generator
that walks the repository *root* looking for `.pas` files finds every library
twice, and since the extraction collects into a set, the result is not obviously
doubled -- it is subtly wrong in whichever direction the stale copy differs.
Scanning the root once was enough to learn this.

The script therefore scans exactly three directories, named explicitly in
`TIER_DIRS`, and exits if any of them is missing:

```python
TIER_DIRS = [
    ('core',    'engine/libs'),
    ('package', 'host/packages'),
    ('gui',     'host/gui/libs'),
]
```

### What the generated unit does at runtime

It builds six sorted, case-insensitive `TStringList` indexes at unit load, and
`IsPhosphorKeyword` / `PhosphorBuiltinTier` are binary searches over them. The
built-in tables hold 1145 names between them, and the highlighter asks which tier
a word belongs to once per identifier token on every visible line; a linear scan
over that would be felt while scrolling.

Lookup is case-insensitive because Phosphor lowercases every identifier as it is
scanned (`engine/PhosphorLexer.pas:392`), so `PrintLn` and `println` are one word.

---

## 6. The debug seam

### What exists

- **Breakpoints.** Set from the gutter or F5, stored per document in a
  `TBreakpointSet`, sorted and deduplicated, and moved in step with edits above
  them by a handler on SynEdit's `senrLineCount` notification. A breakpoint whose
  line was deleted is dropped rather than slid onto its neighbour.
- **`udebugproto.pas`**: the complete PDBP codec -- twelve commands, five events,
  five stop reasons, capabilities, frames, variables -- with an encoder and a
  decoder that never raises. A line that is not JSON, or is JSON of the wrong
  shape, comes back `Valid=False` with `ParseError` set, because a desync is a
  thing to report and disconnect over, not a thing to crash on.
- **`udebugsession.pas`**: the availability probe and the state machine.
- **`docs/debug-protocol.md`**: the specification, written so the *other* end can
  be implemented from the document alone without reading this code.
- **A Debug menu whose Step items are greyed out**, each carrying the reason as
  its hint, plus **Debug > Why is stepping unavailable?** which shows it in full.

### What does not exist

**Step debugging.** There is no session, no stopping, no stack, no variable
inspection, and no way to add one from this repository.

The obstruction is in Phosphor, and it is structural rather than a missing flag:

- The engine's `BREAKPOINT` seam is documented as report-and-continue and **"must
  never block"** (`Phosphor engine/PhosphorValue.pas:73-74`). It returns void, so
  there is nothing for a debugger to answer it with.
- The VM has **no step API** -- no `Step`, `OnStep`, `OnLine` or `Continue` on
  `TPhosphorEngine`, and no opcode-level trap.
- The frame stack is **private with no accessor**, so there is no call stack to
  report and no way to name a variable and read it.
- The console host **does not install the seam at all**, with a recorded
  exemption in Phosphor's `scripts/check-seams.py`: "BREAKPOINT is
  report-and-continue; there is nowhere for a host to pause to".

A step debugger therefore needs work **in the Phosphor repository**, and
`docs/debug-protocol.md` says what work, in the order it has to happen. Nothing
in this editor is one release away from stepping, and nothing here should be
described as "coming soon" without that sentence attached.

### Where the line is drawn

This repository owns the **editor half**: the wire format, the encoder, the
decoder, the breakpoint list, the state machine and the UI. Phosphor owns the
**engine half**: a pausable seam, a step API, a frame-stack accessor and a
`phosphor debug` subcommand.

The editor half was written first on purpose. The wire format is what the two
ends have to agree on, and pinning it down while it is cheap -- before either end
exists to argue with -- is less work than discovering the disagreement afterwards
with two implementations already written. It is also the half that can be *tested*
today: the protocol checks in `tests/phosphoridetest.lpr` exercise a codec whose
counterpart does not exist.

Availability is detected by asking the binary for its own `--help` and looking
for a `phosphor debug` subcommand -- **not** by comparing version numbers. A
version comparison would require this editor to know which Phosphor version first
shipped the feature, which is a fact about the future. Asking the binary what it
can do is a fact about the binary in front of us, and it costs one process start
at the same moment `ProbeHost` is already starting one. The probe re-runs whenever
the host changes, which is what makes "install a newer phosphor, then reopen
Preferences" work.

A host that advertises the subcommand is still not trusted: `Capabilities` stays
empty until a handshake completes, and every capability defaults to `False`, so a
partial implementation cannot be over-trusted into a request it will refuse.

### Two design choices in PDBP worth recording here

**Why not DAP.** The Debug Adapter Protocol brings an editor-agnostic ecosystem
and is the right answer the moment PhosphorIDE is not the only client. It is the
wrong answer for the *first* implementation: DAP's framing is HTTP-style headers
over a byte stream and its message set is large, and the half that has to be
written in Free Pascal inside the `phosphor` host is precisely the half that pays
for that. PDBP is deliberately small enough that a host-side implementation is a
day's work rather than a project, and its message names are DAP's, so a bridge
later is a rename rather than a redesign.

**Why not the child's stdout.** The obvious transport -- protocol frames on the
child's own stdout, distinguished by a prefix -- is unusable for a language whose
entire observable behaviour is `PRINT`. A program that prints a line shaped like
a frame would drive the debugger; one `PRINTLN` of a forged `exited` event ends
the session from inside the program being debugged. The program's streams stay
the program's, and the protocol gets its own socket.

---

## 7. The GUI subsystem, and what it cost

Four traps, all found on **2026-09-10**, all specific to a Windows GUI-subsystem
binary, and all of which shaped `src/phosphoride.lpr` and `scripts/build.ps1`.

**A GUI binary has no console, so `WriteLn` is a hang.** The handle is invalid,
the RTL raises an I/O error, and the LCL surfaces it as a **modal dialog** with
nobody there to dismiss it. That is not a message, it is a process that never
exits. A `--selftest` that merely wrote its result to stdout hung until it was
killed. So `--selftest` reports through a **file** whose path is its second
argument, and the verdict is carried by the **exit code**; the program writes to
a console stream nowhere.

**`-gh` (heaptrc) in that same binary hangs on exit.** The leak report is written
to the same missing stdout, at exit, with the same result. It is removed from the
Default build mode. A leak-checking build has to be run from a console, and that
is a deliberate, recorded limitation rather than an oversight.

**An `.lfm` naming a property its `.pas` does not publish does not fail.** The
form streams fine right up until it is constructed, and then
`TApplication.ShowException` (`lcl/include/application.inc:1598`) answers with a
`PromptUser` box -- *"Press OK to ignore and risk data corruption. Press Abort to
kill the program."* -- and waits, on whatever machine happened to run the build.
`--selftest` sets `Application.Flags + [AppNoExceptionMessages]`, which makes
`ShowException` return without drawing anything (`application.inc:1604`), so the
mismatch reaches a `try/except` and becomes an exit code. `scripts/build.ps1`
**also** runs it under a timeout, because a flag only covers the dialogs the LCL
knows it is showing.

That is why `--selftest` exists at all: it constructs every form -- main, about,
preferences -- from the command line, reports the component count of each and the
four language-table counts, and halts 0 or 1. A GUI program that links is not a
GUI program that works, and all three failures `build.ps1` exists to catch
produced a binary `lazbuild` was perfectly happy with.

**`SetFocus` on a control whose form is not shown yet raises "Can not focus".**
The first thing the window does is create a tab, from `FormCreate`, before it is
on screen. The file named on the command line was reported as *unopenable*, with
the focus error given as the reason -- a correct error message about entirely the
wrong thing. `FocusEditor` now checks `Showing and CanFocus`, and `FormShow` asks
for focus once there is somewhere to put it.

---

## 8. Deliberately not in v1

Each of these is a decision, not a backlog entry.

**Code folding.** It needs `TSynCustomFoldHighlighter` as an ancestor -- a
different base class, with range state and fold-node bookkeeping -- and, more
importantly, a parser good enough to be *trusted* about block structure. Phosphor
makes that expensive in a specific way: the grammar decides keywords by position,
so `next` and `endif` are ordinary identifiers until the parser says otherwise
(section 4). A folding highlighter that assumed a coloured `if` was a real `if`
would mis-fold any program that used `if` as a variable, and mis-folded code
*hides lines*, which is a far worse failure than mis-coloured code. Getting it
right means writing enough of Phosphor's parser to be sure -- in this repository,
in a second implementation, kept in step with the first. That is a large piece of
work whose payoff is a triangle in the gutter, so it is not v1.

**Code completion.** The word tables are already here, tiered and indexed, so a
list of candidates is cheap. A *useful* completion is not: it needs to know
whether the caret is in a string, in a comment, after a `.`, in an argument
position, and which of the 1145 tabled names are plausible there -- and again the answer
depends on a parser this repository does not have. A completion box that offers
`endfunction` inside a string literal is worse than no completion box. The tables
are exposed (`PhosphorBuiltins(ATier)`, sorted, with suffixes) so that whoever
builds this starts from facts rather than from a hand-typed list.

**Project files.** There is no `.phosphorproj`, no build configuration, no
dependency graph. A Phosphor program is a file; the host takes a file; `pack`
takes one `.pbc`. Inventing a project format here would invent a build model that
Phosphor itself does not have, and the editor would then be the authority on a
concept the language has never heard of. Recent files and per-file state are what
is actually needed today, and that is what exists.

**An integrated REPL.** `phosphor` with no arguments is a REPL, and it would be
easy to spawn it into the output pane. It is left out for one concrete reason:
a REPL never exits. It has no end-of-run event, `Running` stays true forever, and
the single-child model in `TPhosphorRunner` -- one process at a time, Stop kills
it, Run refuses while one is live -- would have to become a session model with
its own lifecycle, its own prompt handling and its own "is this output or is this
a prompt" problem. Phosphor's own working rules already warn that starting
`phosphor.exe` with no arguments and no piped stdin opens a REPL that never exits
and locks its own executable. The input box under the output pane feeds `INPUT`
and `LINE INPUT`, which is what programs under development actually need; a
proper REPL pane is a second execution model and it should be built as one, or
not at all.

---

## 9. Build shape

| | |
| --- | --- |
| Toolchain | Lazarus 4.8, FPC 3.2.2, LCL + SynEdit |
| Platforms | Windows and Linux |
| Project | `src/phosphoride.lpi`, build modes `Default` and `Release` |
| Compiler options | `-vewn` -- zero errors, warnings and notes is the bar |
| Windows subsystem | GUI (`GraphicApplication`), which is section 7 |
| Tests | `tests/phosphoridetest.lpi` -- console, headless, 147 checks |
| Build script | `scripts/build.ps1`, `scripts/build.sh` |
| Licence | MIT, by AndreMurtaX |
| Sibling repository | https://github.com/AndreMurtaX/Phosphor |

`scripts/build.ps1` builds both projects with `-B` (a stale `.lfm` resource hides
exactly the mismatch the selftest exists to catch), reads lazbuild's *text* as
well as its exit code because lazbuild answers 0 in cases where the compiler did
not, then runs three checks: the unit tests, `--selftest` under a timeout, and
`gen-keywords.py --check` against a Phosphor checkout when one can be found.
