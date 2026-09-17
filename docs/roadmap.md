# Roadmap

What is next for PhosphorIDE, in the order it should happen, written so that an agent can
pick one item up, know what "done" means, and know which files it touches.

There are no dates and no version numbers in this file, because there are none in the
repository. An item is finished when its checkable condition holds, not when a week ends.

## What the ordering is for

It is a **dependency order plus a lead-time order**, not a schedule.

Two constraints produced it. First, nothing later may be invalidated by something earlier:
the transport comes before the panes that talk over it, and the change to the generated
tables comes before the two features that read the new columns. Second, the debugger's
Phosphor half has a lead time this repository cannot compress -- a change there has to
land, be released, and then be discovered by the `--help` probe in
`src/core/udebugsession.pas:142` -- so items 3 to 6 are the ones to start first and items
11 to 17 are what an agent picks up while they are out of reach. The two groups interleave
in wall-clock time. They do not interleave in dependency.

Cheapness is the tie-break, not the organising principle. Item 13 is a morning's work and
sits low because nothing depends on it; item 17 sits last because it has a cost the rest of
the list does not, named where it is described.

**That ordering is spent**, and the Phosphor lead time it was built around turned out to be
a day rather than a season. Two things on the first list never closed, and neither is
forgotten:

- **Item 2a**, the contract test against the real binary, which has not moved at all.
- **Two clauses of item 1**: `xvfb-run -a bash scripts/build.sh` has still never been run
  by anyone here, and neither has a `--release` build on Linux. The rest of item 1 -- the
  editor DRIVEN under gtk2 rather than merely constructed -- was answered many times over
  by `tools/lane/`, which is why the item reads as finished and is not.

The ordering of the SECOND list, from 18 on, is a different one and is stated where it
starts.

## The bar, for every item on this list

The sibling repository's rule holds here: nothing is done on a claim.

- `powershell -NoProfile -File scripts\build.ps1` green, which means `lazbuild -B` with
  **zero errors, zero warnings and zero notes** -- the script greps lazbuild's text as well
  as its exit code, because lazbuild has answered 0 where the compiler did not.
- `bin\phosphoridetest` green: every check, exit code 0. The run prints its own
  count; the literal lives in `CLAUDE.md`'s gate alone, where the number is there so a
  DROP is visible.
- `bin\phosphoride --selftest <file>` exit 0, **under a timeout**. A GUI-subsystem binary
  that hangs instead of answering is almost always a modal dialog nobody can dismiss; that
  happened twice on 2026-09-10, from two different causes.
- Green on Linux too, once item 1 has actually been run there.
- Any new logic that can be wrong invisibly -- a parser, a scanner, a codec -- gets checks
  in `tests/phosphoridetest.lpr`, which runs headless by naming `InterfaceBase` and the
  widgetset unit directly instead of `Interfaces` (`tests/phosphoridetest.lpr:24-40`). Do
  not break that: it is what lets a highlighter be tested without a window.

---

## 1. Drive the editor by hand under gtk2

**What.** `scripts/build.sh` has been run on Ubuntu with Lazarus 4.8: both projects build
with zero errors, warnings and notes, `bin/phosphoridetest` is green, `gen-keywords.py
--check` is clean, and `phosphoride --selftest` constructs all three forms **under gtk2**
when a display is reachable. The window has been opened there and photographed: menu,
toolbar, tab, gutter, splitter, output tabs and input row all land where they should.

What has NOT happened is anyone USING it under gtk2 -- opening a file, running it,
feeding its stdin, stopping it, dragging the splitter, resizing the window.

**Why.** Construction and layout are the cheap half. The expensive half is behaviour that
differs by widgetset: gtk2 fires `OnResize` and `OnChangeBounds` at different moments than
win32, `TStatusBar` panel sizing differs, `TSplitter` minimum sizes differ, and modal
dialog parenting differs. None of that shows up in a form that is merely built.

It is also the half that found the last defect. The status bar looked empty in a gtk2
screenshot; counting its panels showed `SimplePanel = True`, an LCL default that is the
opposite of Delphi's, and the same bar was blank on Windows. **Looking at it on the other
platform is what produced the question.**

**Done when.**

- A file is opened, run with F9, and its output appears; a diagnostic is double-clicked
  and the caret lands on the right line in the right file.
- A program that reads `LINE INPUT` is answered from the input row, and its prompt is
  seen BEFORE the answer -- the idle-flush path in `DrainTimer`.
- A runaway program is stopped with Ctrl+F2 while the window stays responsive.
- The splitter is dragged and the window resized, without the output pane collapsing or
  the editor losing its gutter.
- `xvfb-run -a bash scripts/build.sh` runs the selftest rather than skipping it. This is
  still unwatched: the measurement above used a real Xwayland session, and a virtual
  framebuffer is not quite the same thing.
- `--release` produces a Release build there.

**Touches.** Whatever it proves wrong. Nothing is expected; that is why it is worth doing.

---

## 2. Continuous integration on both platforms

**DONE, 2026-09-10.** `.github/workflows/build.yml` runs two jobs -- `windows-latest`
and `ubuntu-latest` -- each checking out `AndreMurtaX/Phosphor` beside this repository,
installing Lazarus, and running that platform's build script, with xvfb on Linux so the
selftest is not skipped. Both are green.

The open question it answered was the Lazarus version. `gcarreno/setup-lazarus@v3.3.1`
was asked for `stable` and installed **Lazarus 3.6 with FPC 3.2.2** on both platforms --
not the 4.8 this was written against. It built with zero errors, warnings and notes,
passed all 147 checks, and constructed all three forms on both widgetsets. So the
supported range is wider than the machine it was written on: **Lazarus 3.6 and 4.8**.
That is a measured fact now rather than a hope, and it is the kind that quietly stops
being true, which is what the CI is for.

**Why.** Three of the nine traps recorded on 2026-09-10 produced a binary `lazbuild` was
perfectly happy with. Only a script catches those, and a script that runs on one machine
catches them on one machine.

The table check is the one that pays for itself over years. `tools/gen-keywords.py:36`
asserts `{'core': 534, 'package': 181, 'gui': 426}`, so a Phosphor release that adds a
built-in turns this repository red instead of silently leaving the editor ignorant of the
new name. That only works if something runs it on every push.

**What is done.**

- A push runs both jobs and both are green.
- The Linux selftest runs under xvfb rather than being skipped, and its log carries the
  report lines, including `status bar: 4 panels, simple=False, 1 tabs`.
- The Lazarus version is visible in the log, and the difference from 4.8 was looked at
  rather than assumed away.

**What is still owed on this item.**

- **The gate has not been watched failing.** Delete one word from a list in
  `src/core/uphosphorlang.pas`, push, confirm the job turns red at the table step with
  the file named, then revert. A gate nobody has watched fail is not known to be able to
  fail -- that rule is the sibling repository's and it applies here.
- The artefact upload is the Default build: tens of megabytes, because it carries debug
  info. Decide whether that is wanted, or build `--release` for it. What must not happen
  is a 40 MB debug binary offered as a release.
- The `actions/checkout@v4`, `upload-artifact@v4` and `setup-lazarus@v3.3.1` steps all
  raise a Node 20 deprecation annotation on every run. Harmless today, a failure later.

**Touches.** `.github/workflows/build.yml`.

---

## 2a. A contract test against the real phosphor binary

**What.** A check that runs the ACTUAL `phosphor` binary against a handful of deliberately
broken `.bas` files and asserts the shapes this editor parses: the four diagnostic forms,
the four exit codes, that diagnostics go to stderr one per failed run, and that `--help`
still carries the usage block `udebugsession.pas` reads.

**Why.** `src/core/uphosphormsg.pas` is tested by 40-odd checks -- against strings THIS
repository wrote down, not against the binary. If Phosphor reworded a message, renumbered
an exit code or moved a diagnostic to stdout, every test here would still pass and
jump-to-error would silently stop working. That is the one coupling between the two
repositories with no automatic check behind it; the other three
(`docs/phosphor-engine-work-order.md`, "Keeping the two repositories in step") already
have one.

It also cuts the other way, which is the better half: it would have caught the wording of
`phosphor: file not found:` changing under us, and it is the only thing that can tell the
engine's authors that a message they improved broke a consumer.

**Done when.**

- A new `tests/` target runs the real binary and asserts every shape
  `uphosphormsg.pas` claims to handle, with the .bas fixtures committed.
- It SKIPS with a printed announcement when no host is found, the way
  `scripts/build.sh` announces a skipped selftest -- a check that quietly does not run
  reads as a pass.
- CI runs it: the workflow already checks out `AndreMurtaX/Phosphor` beside this
  repository, so the binary has to be built there first or the step has to build it.
- A deliberate temporary edit to one expected shape turns it red, and the log names
  which shape moved. Then revert.

**Touches.** `tests/` (new fixtures and a target), `.github/workflows/build.yml`,
`scripts/build.ps1` and `scripts/build.sh`.

---

## The debugger, first half: the Phosphor repository

Items 3 to 6 are work in `C:/Dev/Phosphor`, not here. They are on this roadmap because
without them items 7 to 10 cannot start, and because the editor already says so out loud to
the user: `src/core/udebugsession.pas:111-121` explains the gap in the Debug menu, and
`docs/debug-protocol.md` specifies the protocol that closes it.

**`docs/phosphor-engine-work-order.md` is the version of this to hand to an agent working
over there.** It carries what this roadmap cannot: the reproduction for each defect, the
timings, the `file:line` for every insertion point, and the list of tempting changes that
would break a packed executable. It also corrects two things the protocol document got
wrong -- the step rule and the missing variable-name table -- which were found by measuring
the engine rather than by reading this side's description of it.

Nothing in this repository can shorten them. **Never describe stepping as working, or as
coming soon, without saying that it needs work in the Phosphor repository first.**

## 3. Phosphor: a debug seam that is allowed to block

**DONE in the Phosphor repository on 2026-09-15**, and the lead time this item was placed for turned out to be a day. The handoff is `docs/debugger-lane.md`.

**What.** A second seam beside `OnBreakpoint` whose installed procedure may block, nil by
default, and a return value that tells the VM what to do next.

`OnBreakpoint` cannot be reused, and this is not a preference. Its contract is written into
the type's own comment: the seam "MUST NOT block: the engine treats it as a report, never a
wait, so no confirm-answer is returned" (`engine/PhosphorValue.pas:73-74`), and it returns
void, so there is nothing for a debugger to answer with. Redefining it in place would change
what `BREAKPOINT` means for every existing host, including the three with recorded
exemptions in `scripts/check-seams.py` -- among them `phosphor.lpr:OnBreakpoint`,
"BREAKPOINT is report-and-continue; there is nowhere for a host to pause to". A new seam
leaves all of that exactly as it is.

The **waiting happens in the host, never in the engine**. The engine stays free of sockets
and of any notion of a debugger; that boundary is checked, and the check must keep passing.

**Why.** Nothing else on the debugger list can begin. Every other item is downstream of a VM
that can be told to stop.

**Done when.**

- `TPhosphorEngine` exposes a seam that may block, documented in the same voice as
  `OnBreakpoint`'s, nil by default.
- A host that installs nothing behaves byte-identically: the whole `tests/suite` corpus
  green on both OSes, including the case that pins `BREAKPOINT` as a no-op.
- The boundary check still passes -- `engine/` names no host or GUI unit.
- A test host installs the seam, counts its calls for a fixed program, and asserts the
  count; and `-ProveFailure` has been seen catching a corrupted expectation of that count.

**Touches (Phosphor).** `engine/PhosphorValue.pas`, the VM, the engine facade,
`scripts/check-seams.py`, `tests/`.

---

## 4. Phosphor: a step/resume state machine

**DONE in the Phosphor repository on 2026-09-15**, and the lead time this item was placed for turned out to be a day. The handoff is `docs/debugger-lane.md`.

**What.** `stepOver`, `stepInto` and `stepOut` are not three traps. They are one trap plus a
comparison against the frame depth recorded when the step was requested: step into stops at
the next statement whatever the depth; step over stops at the next statement whose depth is
at most the depth at the request; step out stops at the next statement whose depth is below
it. Which is why item 5 is needed even for plain stepping, and not only for a pane -- the
depth is the quantity being compared, and the frame stack is private today.

`pause` needs a flag the host can set from its protocol reader thread and the VM checks at
the next trap.

**The cost to name rather than hide.** A program spinning in a tight loop reaches the trap
once per statement, so pause interrupts it. A program blocked inside `INPUT` does not, and
pause will not reach it. `TPdbpCapabilities` carries a `Pause` field
(`src/core/udebugproto.pas:90`) precisely so that a host can decline rather than accept a
request it cannot honour.

**Done when.**

- For a fixed program that includes recursion, a scripted sequence of step commands produces
  an asserted sequence of (line, depth) pairs, byte-exact, on both OSes -- so step-over
  across a recursive call is pinned, which is the case that goes wrong.
- The trap is off unless armed, and a normal `phosphor run` is unchanged in output and in
  exit code.

**Touches (Phosphor).** The VM, the engine facade, `tests/`.

---

## 5. Phosphor: accessors for globals and frames

**DONE in the Phosphor repository on 2026-09-15**, and the lead time this item was placed for turned out to be a day. The handoff is `docs/debugger-lane.md`.

**What.** Read-only access to the current frame stack -- a count, and per frame the
function's name, the source line, and the local slot names with their values -- and to the
globals. Today the frame stack is private with no accessor, which is recorded in
`src/core/udebugsession.pas:22-24` as one of the four reasons stepping cannot be offered.

Three Phosphor facts shape the shape of it, and none may be papered over:

- **An undeclared variable inside a function resolves to a GLOBAL.** Only names in the
  `local` list are frame slots. A pane that showed every name a function mentions as a local
  would be lying, which is why `TPdbpVariable` carries `Scope` as `'local' | 'global'`
  (`src/core/udebugproto.pas:106`).
- **The type suffix is part of the name.** `count%`, `name$`, `list@`. The accessor reports
  the suffixed name and the editor shows it unchanged (`src/core/udebugproto.pas:104`).
- **The host renders the value, "as PRINT would render it"**
  (`src/core/udebugproto.pas:105`). The editor must never format a number itself.
  Duplicating `PRINT`'s formatting here would be a second copy of a fact that lives in
  another repository -- the exact mistake `uphosphorlang.pas` exists to prevent.

**Done when.**

- An accessor returns frames for a program stopped inside two nested user functions, and the
  names reported as local match that function's `local` list -- no undeclared name appears
  as a local.
- A handle value renders as whatever `PRINT` gives for it.
- The engine boundary check still passes; the goldens are green on both OSes.

**Touches (Phosphor).** The VM, the engine facade, `tests/`.

---

## 6. Phosphor: a `phosphor debug` subcommand speaking PDBP

**DONE in the Phosphor repository on 2026-09-15**, and the lead time this item was placed for turned out to be a day. The handoff is `docs/debugger-lane.md`.

**What.** The subcommand. It listens on a loopback socket, accepts one client, speaks the
line-delimited JSON specified in `docs/debug-protocol.md`, and runs the program under items
3 to 5.

**Why a socket and not the child's stdout.** `src/core/udebugproto.pas:28-33` gives the
reason and it is not stylistic: for a language whose entire observable behaviour is `PRINT`,
a frame-shaped line on stdout is a frame the program under test can forge. One `PRINTLN` of
a fake `exited` event would end the session from inside the program being debugged. The
program's streams stay the program's.

**Why the editor will find it.** `TDebugSession.Probe` asks the binary for `--help` and
looks for a line beginning `phosphor debug` (`DebugSubcommandMarker`,
`src/core/udebugsession.pas:105`). A host that implements everything and does not print that
line will still be reported as unable to step. The usage block must gain a line in that
shape.

**Done when.**

- `phosphor --help` prints a line starting `phosphor debug`.
- A scripted client completes `initialize` -> `setBreakpoints` -> `launch` -> `stopped` ->
  `stackTrace` -> `variables` -> `continue` -> `exited` against a fixed program, and the
  transcript is byte-exact green.
- The handshake refuses a mismatch: a client sending `protocol: 999` is refused with an
  error rather than half-connected. `src/core/udebugproto.pas:43-46` is why -- a debugger
  that half-works is harder to diagnose than one that will not start.
- The `capabilities` object names only what is implemented. The editor defaults every
  capability to `False` (`src/core/udebugproto.pas:344-346`), so an omission is safe; a
  false claim is not.
- A run **without** the subcommand is unchanged: exit codes 0, 1, 2, 3 keep their meanings,
  and stderr still carries exactly one diagnostic per failed run, in the shape
  `phosphor: <path>:<line>: <message>`.

**Touches (Phosphor).** `host/console/phosphor.lpr`, a new host unit for the protocol,
`scripts/check-seams.py` if a seam is installed there, docs, `tests/`.

---

## The debugger, second half: this repository

## 7. The socket transport and the handshake

**DONE 2026-09-16**, driven against the real host on BOTH platforms (Windows 11, and gtk2 on Ubuntu under a real Xwayland session) and recorded in `docs/debugger-lane.md` — including what the first cut got wrong. The tooling that does the driving is `tools/lane/`.

**What.** The piece `src/core/udebugsession.pas:211` names as "the next piece of work":
connect to the socket a `phosphor debug` child is listening on, send the frame
`EncodeInitialize` already builds, and keep the capabilities the response carries.

**Reuse the runner's shape; do not invent a second one.** The rule in
`src/umainform.pas:6-10` is that nothing waits, and the reason `uphosphorrun` looks the way
it does applies unchanged to a socket: a reader thread, a guarded buffer, and a drain timer
turning bytes into whole lines on the main thread. A protocol frame is exactly one line --
`TJSONObject.AsJSON` is compact and JSON escaping turns any newline inside a value into
`\n`, "which is the property the framing rests on"
(`src/core/udebugproto.pas:199-202`) -- so the existing partial-tail logic is the right
logic. A decoder fed half a frame returns `Valid=False`, and that is a desync to report and
disconnect over, not a crash (`src/core/udebugproto.pas:165-167`).

Two things must be right or the session will fail in ways that look like host bugs:

- **The child is still a child.** `TPhosphorRunner` already owns process lifetime, kill and
  pipe draining, and the debug child's stdout and stderr are still the program's output and
  still belong in the output pane. Do not open a second process abstraction beside it.
- **A refused connection is a normal outcome** -- the child died at startup, the port was
  taken -- and must become a line in the output pane and a return to `dsIdle`. Never a modal
  dialog, and never a wait without a deadline. `ProbeHost` is the precedent: a bounded wait,
  made knowingly by the caller rather than behind their back.

**Done when.**

- `TDebugSession.Available` becomes `True` only after a handshake completes, and
  `Capabilities` reflects what the response carried. Today `Probe` deliberately reports
  unavailable even for a host that advertises the subcommand
  (`src/core/udebugsession.pas:206-212`); that stub is what this item replaces, and the
  sentence it prints must be replaced, not left to become false.
- A protocol mismatch disconnects with a message naming both versions.
- Killing the child mid-session leaves the editor in `dsIdle` with the menu re-enabled, and
  a second session starts cleanly.
- `tests/phosphoridetest.lpr` gains headless checks for the framing: a frame split across
  two reads, two frames arriving in one read, a trailing partial.

**Touches.** `src/core/udebugsession.pas`, a new transport unit under `src/core/`,
`tests/phosphoridetest.lpr`, `src/phosphoride.lpi`.

---

## 8. The session state machine, the step actions, and the current-line marker

**DONE 2026-09-16**, driven against the real host on BOTH platforms (Windows 11, and gtk2 on Ubuntu under a real Xwayland session) and recorded in `docs/debugger-lane.md` — including what the first cut got wrong. The tooling that does the driving is `tools/lane/`.

**What.** Drive `TDebugState` (`src/core/udebugsession.pas:52-59`) from the inbound events;
wire the six actions that already exist and are greyed out -- `ActDebugStart`, `ActStepOver`,
`ActStepInto`, `ActStepOut`, `ActContinue`, `ActDebugStop`, all handled in
`RefreshDebugActions` at `src/umainform.pas:1141`; send the breakpoint set on launch and on
every change; and paint the line execution is stopped on.

**The marker is nearly free.** `EditorSpecialLineMarkup` (`src/umainform.pas:1237`) already
colours breakpoint lines by looking a number up in a short sorted array, and the same handler
answers for the stopped line. The precedence matters: a line that is both a breakpoint and
the stopped line must read as **stopped**, or the user cannot see where they are. Keep the
handler cheap -- SynEdit asks it for every visible line.

**Breakpoints go over the wire as a whole set per file, never as add/remove.**
`EncodeSetBreakpoints` replaces, and says why: the editor's list moves every time a line is
inserted above a mark, so the two ends will not agree on what is currently set
(`src/core/udebugproto.pas:241-244`). `TBreakpointSet.TrackEdit`
(`src/core/ubreakpoints.pas`) is what moves them, driven by `TEditorDoc.LinesChanged`
off SynEdit's `senrLineCount` notification, so a re-send after an edit while stopped is
mandatory rather than an optimisation.

**Keep telling the truth.** An action stays greyed with a reason attached whenever the
capability is absent. A host reporting `stepOut: false` gets a greyed Step Out whose hint
says so -- not a request the other end will refuse. That is the entire reason
`TPdbpCapabilities` exists (`src/core/udebugproto.pas:84-87`).

**Done when.**

- Starting a debug session on a program with a breakpoint stops there, the line is marked,
  and the marker moves on each step.
- The greyed-out state is driven by `Capabilities`, not by a constant.
- Stop terminates: `disconnect` with `terminate: true`, the child is gone, the marker is
  cleared, the editor is in `dsIdle`.
- **The honest path survives the happy one.** `ActDebugWhy` (`src/umainform.pas:3247`) still
  shows a correct sentence against a host with no debug subcommand.
- Inserting a line above a breakpoint while stopped re-sends the set, and the host stops on
  the statement the user chose rather than the one below it.

**Touches.** `src/umainform.pas`, `src/umainform.lfm`, `src/core/udebugsession.pas`,
`src/core/ueditordoc.pas`.

---

## 9. A variables pane

**DONE 2026-09-16**, driven against the real host on BOTH platforms (Windows 11, and gtk2 on Ubuntu under a real Xwayland session) and recorded in `docs/debugger-lane.md` — including what the first cut got wrong. The tooling that does the driving is `tools/lane/`.

**What.** A tab beside Output and Problems in `PagesOutput`: Name, Value, Scope, filled from
the `variables` response for the selected frame.

**Why.** It is the reason people want a debugger. A marker and a stack say where you are,
not why.

Locals first, then globals, visibly separated -- because an undeclared name inside a
function **is** a global, and a pane that mixes the two hides the one Phosphor rule most
likely to surprise someone reading their own program. The pane displays the string the host
gave it; see item 5 for why it must not format anything itself.

**Done when.** Stopped inside a function, the pane shows that function's locals with their
suffixes intact and the globals below; selecting a different frame in the call-stack pane
refills it; a handle shows what `PRINT` shows; the pane is empty and disabled when not
stopped; no code path in the pane formats a number.

**Touches.** `src/umainform.lfm`, `src/umainform.pas`, optionally a small pane unit.

---

## 10. A call-stack pane

**DONE 2026-09-16**, driven on both platforms and recorded in
`docs/debugger-lane.md`. Three-deep recursion shows five rows including `(main)`,
double-click moves the caret, selecting a frame drives the variables pane by index,
and both panes empty when the program resumes. The one thing the item asked for that
the host could not do -- a line on every frame, so a caller can be jumped to -- was
reported to Phosphor and fixed there the same day, and needed no change here.

**Was: next, and reachable today** — items 3 to 9 are done, so nothing is waiting on the
other repository any more. Two things found on 2026-09-16 belong with it:

- ~~Phosphor owes a fix: a breakpoint on the first statement is answered as installed
  and never fires.~~ **Fixed 2026-09-16** in Phosphor `fce3db1`. It was the first
  EXECUTED statement rather than line 1, which is why it survived a year: every
  fixture anyone writes opens with a comment. Reproduce the before-state with
  `tools/lane/first-statement-probe.py`.
- ~~A hollow gutter icon for an un-armable breakpoint is still a grey row instead.~~
  **DONE 2026-09-16**, once item 13 gave it an image list: solid dot for a breakpoint
  the host bound, hollow ring for one it could not, and the full-row colours retired.
  Both drawn by `tools/gen-icons.py`, at 16 and 24, in a second image list of their
  own.
- ~~Phosphor owes a second fix: `stackTrace` answers every frame but the innermost
  with `line: 0`.~~ **Fixed 2026-09-16** in the same commit. The data was already on
  the frame; the repair was one accessor and an off-by-one. Both are written up in
  [`phosphor-debugger-debts.md`](phosphor-debugger-debts.md), which is kept because
  the mechanism of each is worth more than the fact that they are gone.


**What.** A list of frames. The decoding is already written and tested: `TPdbpFrames`
carries `Index`, `Name` (the function's name, or `(main)`), `Path` and `Line`
(`src/core/udebugproto.pas:94-100`, parsed at `:354-377`).

Double-click jumps through `GotoSource` (`src/umainform.pas:1047`) rather than a second
navigator, because that is the one place that clamps a line past the end of a file -- and a
line number genuinely can exceed the file's line count: an unterminated block in a
three-line file reports line 4.

**Done when.** Three-deep recursion shows four rows including `(main)`; double-click moves
the caret and switches tab; selecting a frame drives the variables pane; the pane clears on
continue.

**Touches.** `src/umainform.lfm`, `src/umainform.pas`.

---

## The editor's own gaps

Items 11 to 17 depend on nothing in the Phosphor repository. They are what an agent picks up
while items 3 to 6 are out of reach.

## 11. Code completion from the generated tables

**DONE 2026-09-16.** Ctrl+Space over all 1198 names, tier-aware and suffix-aware,
silent inside a string or a comment, case-preserving on insertion. The rules are
`src/core/uphosphorcomplete.pas`, which has no LCL in it and is pinned by 37
headless checks; the popup is `TSynCompletion`. A preference sets the tier
ceiling and every row shows its own.

Driven on both platforms. The one thing worth adding to what the item asked for:
`OnCodeCompletion` replaces the range THIS unit measured rather than the one
`TSynCompletion` derives from SynEdit's identifier characters — they agree
today, and a completion that depends on two scanners agreeing is one change away
from writing `left$$`.

**Was:**

**What.** A completion box over all 1198 names -- 53 keywords, 538 core built-ins, 181 from
host packages, 426 GUI -- served from `uphosphorlang`, which was built for this. The lists
are sorted, lower case, suffixes included, and the header says so: "for a completion box or
a documentation lookup" (`src/core/uphosphorlang.pas:44-45`). `TPhosphorTier` is ordered by
availability "so a completion list can be filtered with a single `<=` test"
(`src/core/uphosphorlang.pas:30-31`).

Three things must be right:

- **Tier-aware.** Core is always present. Package names exist only because the console host
  links every package -- another host need not. GUI names exist only where a graphical
  session was reachable when the program started. Offering `form@` with the same weight as
  `println` invites a program that runs on the author's desktop and fails on a server. Show
  the tier per row, and let a preference restrict the list.
- **Suffix-aware.** The suffix is part of the name: `left$` is one word, not `left`
  followed by an operator (`src/core/uphosphorlang.pas:21-22`). The partial word under the
  caret must be scanned by the same rule the highlighter uses, or typing `lef` and accepting
  `left$` inserts a second `$`.
- **Case-insensitive lookup, case-preserving insertion.** Phosphor lowercases every
  identifier as it is scanned (`engine/PhosphorLexer.pas:452`), so `PrintLn` and `println`
  are one word; the insertion should follow what the user typed rather than forcing lower
  case on their file.

**What it must not do.** Infer anything from a colour. `src/core/usynphosphor.pas:24-31`
records that the highlighter colours keywords by word and not by position, deliberately and
wrongly -- `next = 5` is a legal assignment in Phosphor -- and states that "nothing
downstream (folding, indentation) may be built on the assumption that a coloured keyword IS
a keyword". Completion is downstream.

**Done when.**

- Ctrl+Space in a `.bas` tab offers a filtered list, typing narrows it, Enter inserts the
  whole suffixed name.
- A tier filter is honoured and the tier is visible per row.
- Completion does not fire inside a string literal or a comment. Both are decidable from the
  current line alone, which is exactly what `usynphosphor` guarantees by having no range
  state (`src/core/usynphosphor.pas:5-12`).
- `tests/phosphoridetest.lpr` gains headless checks for the prefix rule: `lef` yields
  `left$`; `x$` is a complete identifier; a `'` comment yields no candidates.

**Touches.** `src/core/usynphosphor.pas` (a token-at-caret helper) or a new small unit,
`src/umainform.pas`, `src/phosphoride.lpi`, `tests/phosphoridetest.lpr`. Use SynEdit's
`SynCompletion` rather than a hand-drawn popup.

---

## 12. Signature help from the registry's `:`-signature strings

**DONE 2026-09-16.** `gen-keywords.py` keeps the codes, `uphosphorlang` carries
**1226 signatures over 1136 names**, and a hint under the caret shows every arity
of the call being typed with the current argument in brackets. Both counts are
asserted the way the tier counts are, so a Phosphor release that changes a
registration is a red build here.

Three answers the item asked for, and one it did not:

- `mid$` has two arities and both show. Sorted shortest first, because the short
  one is what is being typed when the hint first appears.
- **Absent and empty are different answers.** `dirseparator$:` is a registration
  and means "takes nothing"; `callfunc` means "nothing known", because its
  arities are assembled in a loop at run time and the literal in the source says
  `$` while the truth is nine things. Taking the literal would have been a WRONG
  fact rather than a missing one, so those names carry none at all.
- The four compiler special forms carry none either, and the generator says why:
  there is nothing in a registry to extract, and writing one by hand is the
  second copy of another repository's fact that `uphosphorlang` exists to
  prevent.
- Not asked for and worth having: the hint is a `THintWindow` and not a second
  completion list. Nothing is being chosen, so a widget that took the keyboard
  would be in the way of the typing it is meant to help, and there is nothing to
  dismiss — closing the call moves the caret out of it.

**Was:**

**What.** Show the argument kinds while the caret is inside a call's parentheses.

**The material already exists and is currently thrown away.** Phosphor registers as
`Reg.Add('name:sig', @fn)`, where the codes are `n` numeric, `%` an exact `int%` that does
not widen, `$` string, `@` handle, `?` bool, repeated per argument, and a zero-argument
function is `'name:'`. `tools/gen-keywords.py:46` matches the whole literal and keeps only
the part before the colon. Keeping the codes is a change to one regex group and one emitted
array -- and it keeps the fact in the generated file, where it belongs, rather than in the
editor where it would go stale.

Two facts make this less simple than it looks, and both belong in the generator:

- **One name has several signatures.** `Reg.Add` overwrites **by signature**, so `mid$:$n`
  and `mid$:$nn` are two slots, not a conflict. The table must map a name to a *list* of
  code strings, and the popup must show them all. An editor that shows one arity for a name
  that has three is worse than one that shows none.
- **The codes are not parameter names, and there are none to extract.** The registry stores
  kinds. So the popup renders kinds -- `mid$(string, number[, number])` derived
  mechanically. Do not write parameter names by hand: that is a second copy of a fact from
  another repository, which is the mistake `uphosphorlang` exists to prevent.

The counts stay assertions. Whatever the new arrays hold, `gen-keywords.py` must assert
their size the way it asserts 534/181/426 today, so that a Phosphor release which changes a
signature is a red build here rather than silence.

**Done when.**

- `python tools/gen-keywords.py ../Phosphor --check` passes against a regenerated
  `uphosphorlang.pas` that carries signatures.
- The unit exposes a lookup returning every signature for a name, and
  `tests/phosphoridetest.lpr` asserts a known multi-arity one.
- Typing `mid$(` shows every arity; the popup dismisses on the closing parenthesis and never
  appears inside a string.
- The four compiler special forms that are in no registry -- `eof`, `input$`, `loc`, `lof`
  (`tools/gen-keywords.py:135`) -- either carry a signature the generator marks as
  hand-written, or carry none. They must not silently look like registry facts.

**Touches.** `tools/gen-keywords.py`, `src/core/uphosphorlang.pas` (regenerated, never
hand-edited), `src/umainform.pas`, `tests/phosphoridetest.lpr`.

---

## 13. Icons and a toolbar image list

**DONE 2026-09-16.** Nine icons at 16 and 24, drawn by `tools/gen-icons.py`, decoded
into an empty `TImageList` at `FormCreate`, with `List = True` so every caption sits
beside its icon rather than under it — which is also what keeps the toolbar one row
tall. `--selftest` reports `toolbar icons: 9 images at 16+24 px`, and both build
scripts fail on a hand-edited `uphosphoricons.pas` or a stale `icons-preview.png`.

The trap below was designed for and not discovered; what WAS discovered is that
`AddMultipleResolutions` is overloaded on `array of TCustomBitmap` and
`array of TRasterImage`, and a `TPortableNetworkGraphic` is both, so a bare open array
is a compile error until the array is given a name and a type.

**Was:**

**What.** `ToolBar1` has `ShowCaptions = True` and no `Images` property
(`src/umainform.lfm:14-21`): every button is text. Add an image list and icons for New,
Open, Save, Run, Stop, Check Syntax, Toggle Breakpoint, Step Over and Step Into.

**Why here.** Low value per hour, which is why it is not higher, and completely independent,
which is why it is a good thing to pick up when something else is blocked.

**The trap, to be designed for rather than discovered: register both 16x16 and 24x24.** A
single-resolution image list is scaled by the widgetset, and the two widgetsets scale
differently -- one gives a blurred mark and the other gives a missing one, and neither is a
build failure, so nobody finds out until a screenshot arrives from the other platform.
`Application.Scaled` is `True` (`src/phosphoride.lpr:114`), so this is live on the first run
on a high-DPI Windows machine.

**Done when.** The toolbar renders sharp at 100% and 150% scaling on Windows and on gtk2;
every button keeps a caption or a hint, because an icon-only toolbar with no hints is a
puzzle; and `--selftest` still exits 0 -- an image list is a component the `.lfm` names, and
trap 3 of 2026-09-10 is exactly an `.lfm` naming something its `.pas` does not publish,
which is a modal dialog rather than a failure.

**Touches.** `src/umainform.lfm`, `src/umainform.pas`, an icon resource.

---

## 14. A find-in-files pane

**DONE 2026-09-16.** `Ctrl+Shift+F`, or **Edit > Find in Files**, and the results
are the fifth tab of the output pane. `src/core/ufindinfiles.pas` is the search
and has no LCL in it, with 36 headless checks of its own.

Four answers the item asked for:

- **The jump is `GotoSource`, unchanged.** The row shows a leaf name and the
  line, because a list box full of absolute paths is one nobody can read at a
  glance; the full path rides beside it in a parallel `line|path` list, which is
  exactly the shape the Problems pane already uses and for exactly the same
  reason.
- **A binary file produces no rows** -- and the sniff happens BEFORE the rest of
  the file is read, which is the part that was not in the plan. Reading an
  executable whole in order to discover from its first four kilobytes that it is
  not text is megabytes per file skipped: on the Windows lane a walk of `C:\Dev`
  reached 268 files in the second and a half before Stop was pressed, and 702 in
  the same window once the order was fixed.
- **Cancelling is an ending and it says so.** `stopped after 702 files, 0
  matches`, in the status bar and in the list. A results list that merely stopped
  growing does not say whether the search finished or was stopped, and those are
  different answers to "did you look everywhere".
- **Match case yes, whole word no**, decided here rather than inherited: both
  dialogs are created with `frHideWholeWord`, so that box has never been shown,
  and this pane is not going to be the one search in the program that can do
  something the others cannot.

Measured on BOTH machines rather than one, with `tools/lane/steps-find.txt` and
`tools/lane/steps-find-linux.txt`, which drive the same six cases:

| | Windows | gtk2 |
| --- | --- | --- |
| the sibling checkout, no mask, run to the end | 387 matches in 1006 files | 351 in 925 |
| `LooksBinary` over this checkout, no mask | 7 rows from 150 files, none from a binary | 10 from 150, none from a binary |
| a walk nobody would wait for, stopped | after 702 files | after 2413 files, 2649 matches |

The gtk2 run also re-earned its own lesson: the window came up 725 pixels high on
one run and 775 on the next, so every click in the Linux script is measured UP
FROM THE BOTTOM EDGE (`bot DX DYUP`). An offset from the top would have landed in
a different pane on the second run.

**Was:**

**What.** A pane beside Problems that searches a directory tree and lists `path:line:text`,
with double-click to jump.

**Why.** Find, Find Next and Replace are all scoped to the active buffer
(`src/umainform.pas:642-698`). A program that spans files, or a search of the Phosphor
examples, has no answer today short of leaving the editor.

**The jump is already built.** `ListProblemsDblClick` (`src/umainform.pas:1029`) resolves a
path and calls `GotoSource` (`:1047`). Reuse `GotoSource`; do not write a second navigator.

**Do not walk a tree on the main thread.** The one rule `umainform` exists to keep is that
nothing here waits (`src/umainform.pas:6-10`), and a search over a network share waits for a
long time. A worker that posts results in batches, and a stop button, matching every other
long operation in this editor.

**Done when.** A search across a directory of a thousand files stays responsive and can be
cancelled mid-run; rows carry path, line and the matching text; double-click opens the file
at the line, opening a tab if it is not already open; a match-case option matches the one
`FindDialog1` offers -- whole word is *not* one of them, because both dialogs are created
with `frHideWholeWord` even though their handlers test for it, so decide that here rather
than inherit it; a binary file does not produce garbage rows.

**Touches.** `src/umainform.pas`, `src/umainform.lfm`, and a search unit under `src/core/`
so the matching is testable headless.

---

## 15. An outline pane and go-to-definition for user functions

**DONE 2026-09-16.** The **Outline** tab is the sixth in the output pane and
`F12` is Go to Definition; `src/core/uphosphoroutline.pas` is the scanner and has
no LCL in it, with 106 headless checks of its own.

The item's own warning is the whole of it, so it is answered first. A scanner
that treats a word as structural IS wrong about some legal program, because
Phosphor has no keyword table -- and the unit's header says so, names the trade
in `usynphosphor`'s terms, and then forbids its own use in any code path that
changes a buffer. Folding is referred to item 17 rather than decided there.

Within that limit it was measured rather than assumed, and the obvious scanner
is wrong about all five. Every line below was compiled and run against
`bin/phosphor.exe`:

| legal Phosphor | what a first-word scanner does |
| --- | --- |
| `x = 1 : function f()` | misses it; a definition begins a STATEMENT, not a line |
| `if x > 0 then function f()`, `... else function f()` | misses it |
| `head: function a%() return 1 : end function : function b%() return 2 : end function` | finds at most one of the TWO |
| `10 function h()` | misses it; a leading integer is a label |
| `end function` as two words, adjacent | never sees a terminator, so every file using it reads as unterminated |

And two more that decide behaviour rather than parsing: the type suffix is part
of the name, so `g$ m% n? o@` are four different functions and the suffix is the
only return type the language declares; and `FUNCTION Upper()` ... `END FUNCTION`
is legal, so names are matched FOLDED and shown AS TYPED.

**The finding that changed the design is arity.** `function len(a, b)` beside
`println len("abcd")` does NOT shadow the built-in: the host resolves by name AND
argument count, so that call prints 4 and `len(1, 2)` prints 99. Measured. A
go-to-definition matching on the name alone would send the caret, confidently,
into a body the call never enters -- so F12 counts the arguments at the call site
first, and `FindOutlineFunc` takes an arity.

Four answers to the done-when's clauses, and one it did not ask for:

- Ten functions, ten rows, in source order, and the three ghosts -- `function`
  inside a `rem`, inside a `'` comment and inside a string -- produce none.
- **Clicking a row moves the caret AND LEAVES THE KEYBOARD IN THE LIST**, so
  arrowing down the outline walks the file; a double-click hands the keyboard
  back. `GotoSource` grew an optional column and an optional focus for it rather
  than being copied, and the column is load-bearing: two definitions can share a
  line, and column 1 would be the wrong one of them.
- F12 on a name nothing defines writes one line to the status bar. A call to an
  undefined name COMPILES in Phosphor and fails only when it runs, so finding
  nothing is an ordinary answer and not a diagnostic.
- F12 on a built-in OFFERS the function reference, in the `MessageDlg` shape
  `ActDebugWhyExecute` already uses, and never opens a browser unasked. A word
  that is a statement keyword (`println`) says that instead, which is a truer
  answer than either of the other two.
- Not asked for: the selection follows the caret, so the pane also answers "which
  function am I in"; and the rebuild is debounced at **250 ms** rather than the
  40 ms this program uses everywhere else -- that one is a DRAIN cadence for
  things arriving from outside, and this is a debounce on the user's own typing,
  which is a different quantity.

Labels and `gosub` targets are deliberately absent, and that is the one place
this went smaller than it could have: they are a second table in the compiler
that never consults the function table, and they would need a reserved-word test
this repository does not extract. An absence that is written down beats a jump
that is wrong and looks right.

Driven on both platforms with `tools/lane/steps-outline.txt` and
`tools/lane/outline.bas`, a fixture that compiles and runs.

**Was:**

**What.** A list of the `function` definitions in the active buffer, and F12 on a call
jumping to its definition.

**What makes it tractable, and what makes it a trap.** `function` and `endfunction` are
keywords by **position**, not by lexing: Phosphor's lexer has no keyword table at all, and
every keyword reaches the parser as an ordinary identifier
(`src/core/usynphosphor.pas:24-31`, citing `engine/PhosphorLexer.pas:444-470`). A scanner
that treats the first word of a line as structural is therefore right for every ordinary
program and wrong for a legal one.

That is an acceptable trade **for navigation**, where being wrong costs a spurious row in a
list -- and it is not acceptable for anything that edits text. Say so in the new unit's
header, in the same terms `usynphosphor` says it, and keep the scanner out of every code
path that changes a buffer.

The outline is rebuilt from the buffer rather than the file on disk, because the user is
typing into it; and it must not rebuild on every keystroke -- coalesce on a timer.

**Done when.** A file with ten functions shows ten entries in source order; clicking one
moves the caret; F12 on a call defined in the same file jumps to it, and on a name it cannot
find writes to the status bar rather than opening a dialog; F12 on a built-in offers the
function-reference link instead (`UrlFunctionReference`, `src/umainform.pas:270`); and the
scanner is checked headless against a file containing the word `function` inside a string
literal and inside a `'` comment, neither of which may produce an entry.

**Touches.** A new unit under `src/core/`, `src/umainform.pas`, `src/umainform.lfm`,
`tests/phosphoridetest.lpr`, ~~`src/phosphoride.lpi`~~ -- struck because it was wrong:
that project's `<Units>` list stops at `udebugsession` and names none of
`uphosphorcomplete`, `ufindinfiles`, `udebugtransport` or `uphosphoricons` either. They
all resolve through `<OtherUnitFiles Value="core"/>`, and adding one entry would turn a
visibly partial list into one that reads as complete and is not.

---

## 16. An integrated REPL pane

**DONE 2026-09-16.** `Ctrl+Shift+R`, or **Run > REPL**, and the transcript below was
read back out of the pane rather than imagined:

```
phosphor> println 6*7
42
phosphor> x = 1
phosphor> println x
1
phosphor> for i = 1 to 3
     ...> println i
     ...> next
1
2
3
phosphor> nosuchthing(
error: unexpected token in expression
phosphor>
> end of input
> the REPL ended, exit code 0
```

`docs/architecture.md` said this should not be built, and ended "a proper REPL pane is a
second execution model and it should be built as one, or not at all". That was the right
instruction and it is the shape here: a second `TPhosphorRunner` in its own field, bound
to three new handlers, so **the binding is the discrimination** -- `FRunner` is untouched,
nothing on the Run path learns a new question, and `ActionList1Update`'s
`Busy := FRunner.Running` is deliberately left alone so Run stays available for the whole
life of a prompt.

**The item's two named hazards, and a third it did not know about.**

- *The prompt arrives but is not a line.* Correct, and it worked first time -- the two-tick
  threshold in `uphosphorrun.pas` had been a reasoned number since 2026-09-10 and this is
  the first thing that ever exercised it. What the item did not predict is that a line
  printing NOTHING puts two prompts on one line (`phosphor> phosphor> 1`), so
  `uphosphorrepl.SplitReplPrompts` gives each its own, with the invariant that the segments
  rebuild the input byte for byte.
- *A REPL nobody closes never exits.* Correct, and worse than stated: **`CloseInput` closed
  nothing**. It called `RequestClose` on the writer thread, which ends that thread's loop
  and touches no handle, so the one way a REPL is meant to end did not work. Repaired in
  `cadfe7e`, and the repair has to wait a tick because the writer blocks inside
  `WriteBuffer`. **And the pipes were inherited by the next child** on Unix -- so with a
  REPL live, any Run forked afterwards held its stdin write end open and end-of-input
  never arrived at all. `MakeHandlePrivate` is `MakeSocketPrivate` on a different kind of
  descriptor.
- *Not predicted, and the host's rather than ours:* **a REPL error is buffered on Unix** and
  does not arrive until the process exits, so on Linux the diagnostic for a line lands
  underneath whatever happened since. Measured on both platforms with no editor involved
  (`tools/lane/repl-probe.py`), written up with the one-line ask in
  [`phosphor-repl-debt.md`](phosphor-repl-debt.md). Nothing here compensates for it: the
  runner shows lines in the order the bytes arrive, and inventing an order would be this
  side guessing at something only the host knows.

**The done-when, clause by clause.** `println 6*7` shows 42; `x = 1` then `println x`
shows 1; a block shows `     ...> `; closing the pane leaves no `phosphor` behind, checked
by process name on both platforms and printed by both lane drivers; and the Run path's
checks pass unchanged, with a run driven beside a live prompt to prove the two children
coexist.

One clause is answered NO and it is better said than papered over: **`error:` lines are
not STYLED as diagnostics.** A `TMemo` has one colour, and the alternatives were to mutate
the host's text with a prefix or to replace the widget -- the first puts characters in the
transcript that the host did not write, and the second is a feature of its own. They are
verbatim, in the place they happened, and never offered as a jump target, which is the
half of that clause that could do harm.

**Two things the pane does that the item did not ask for.** The typed line is echoed onto
the prompt's own line, so the record afterwards reads the way the session happened rather
than the way the bytes arrived; and Up and Down walk what was typed, with the first Up
stashing the half-finished line so Down brings it back -- one keystroke may not silently
destroy what somebody was writing.

Driven on both platforms with `tools/lane/steps-repl.txt` and `steps-repl-linux.txt`. The
Windows script also covers the window being closed with a live REPL, which asks about it by
name; the gtk2 script cannot read text back -- that VM has no text reader, only XTest and
`xwd` -- so its assertions are screenshots plus the process check.

**Was:**

**What.** A pane that runs `phosphor` with no arguments and feeds it a line at a time. A bare
`phosphor` is a REPL whose variables and functions persist across lines, which is the one
thing Run cannot offer: Run hands the host a **file**
(`EnsureSavedForRun`, `src/umainform.pas:1141`) and every run starts from nothing.

**Most of it exists.** `TPhosphorRunner` already spawns, reads both pipes on their own
threads, and writes to the child's stdin (`SendInput`, `src/core/uphosphorrun.pas:773`); the
input box beside the output pane already feeds `INPUT` and `LINE INPUT`; and `uphosphormsg`
already recognises the REPL's own diagnostic shape -- `error: <msg>`, no prefix, no path, no
line -- as `pmkReplError`, and correctly refuses to treat it as a jump target.

**Two things will bite, and both are known now rather than after the fact.**

- **The prompt arrives, but it is not a line, and the pane must know that.** The REPL
  writes `phosphor> ` with no newline (`Phosphor host/console/phosphor.lpr:3746`), and the
  runner already handles that case: `DrainTimer` counts drains in which a stream produced
  nothing and `FlushPrompt` emits the unterminated tail after two of them
  (`src/core/uphosphorrun.pas:667-681`), marked `ACompleteLine=False`; `RunnerOutput`
  (`src/umainform.pas:1345`) already appends such a fragment to the pane and already
  refuses to hand it to `uphosphormsg`, because a parser fed half of
  `phosphor: x.bas:2: unexpected token` finds no error at all. So the prompt will arrive,
  about 80 ms late, which is invisible. What is untested is the whole path: no check and
  no run has yet driven a child that prompts, so the two-tick threshold is a reasoned
  number rather than a measured one, and this item is where it first gets exercised.
- **A REPL nobody closes never exits**, and on Windows it holds a lock on its own
  executable. That is a recorded trap in the Phosphor repository, and it weighs more here
  because the editor starts the process on the user's behalf. The pane must `CloseInput` and
  then terminate the child when the pane closes, when the editor closes, and when the host
  path changes -- and `FormCloseQuery` (`src/umainform.pas:693`) must count a REPL child the
  way it already counts a run.

  **AND `CloseInput` DID NOT CLOSE ANYTHING.** Found on 2026-09-16 while reading for this
  item: it called `TPipeWriterThread.RequestClose`, which ends that thread's LOOP and
  nothing else -- the child's stdin handle stayed open for the life of the runner. So the
  one way a REPL is meant to end did not work, and nothing noticed because no feature had
  ever asked for end-of-input. Repaired in the same increment, and the repair has to wait a
  tick: the writer thread blocks inside `WriteBuffer` and does not look at its flag again
  until that write returns, so the handle is closed from `DrainTimer` once the thread is
  `Finished` -- the same question that method already asks of the two readers.

  **AND THE PIPES WERE INHERITED BY THE NEXT CHILD.** The second hazard this item created
  rather than found: with a REPL live, every Run, Check, Compile, Pack and debuggee forked
  afterwards inherited the REPL's stdin WRITE end on Unix, because FPC opens a pipe with a
  bare `AssignPipe` -- `pipe()`, no `FD_CLOEXEC` (`fcl-process unix/pipes.inc:20-24`) --
  and `TProcess` forks with `InheritHandles` True (`processbody.inc:258`). Closing this
  process's copy then delivers no end-of-input at all, for as long as that child lives.
  `MakeHandlePrivate` is the repair and it is `MakeSocketPrivate` under another name, on a
  different kind of descriptor.

**Done when.** `println 6*7` shows 42; `x = 1` then `println x` shows 1, which is the
persistence that justifies the pane; a multi-line block shows the `     ...> ` continuation
prompt; `error:` lines are styled as diagnostics and are not offered as jump targets;
closing the pane leaves no `phosphor` process behind, verified by process name on both
platforms; and the ordinary Run path's line handling is unchanged with its checks still
passing.

**Touches.** `src/core/uphosphorrun.pas`, `src/umainform.pas`, `src/umainform.lfm`,
`tests/phosphoridetest.lpr` -- and, not listed and all of them necessary: a new
`src/core/uphosphorrepl.pas`, `src/phosphoride.lpr` for the selftest line,
`docs/architecture.md` for the paragraph this item struck, `tools/lane/` for the two step
scripts and the probe without which "verified by process name on both platforms" cannot be
satisfied, and `tools/lane/win.ps1` -- a second `TMemo` in the window would otherwise have
silently redirected every existing `memo` step.

---

## 17. Folding

**DONE 2026-09-16, and one clause of its own done-when is answered NO.** Seven block
kinds fold from the gutter, not the five this item named: `do while ... loop` and
`repeat ... until` are blocks too, both measured.

**This item argued it might not be worth doing, and it was right about the danger and
wrong about only one thing.** Both of its costs were real:

- *It changes the highlighter's base class and its cost model.* Unavoidable, and paid.
  `TSynEditFoldedView` refuses a highlighter that is not a `TSynCustomFoldHighlighter`
  (`syneditfoldedview.pp:3570-3576`) and there is no seam that accepts fold ranges from
  outside, so the instruction "build it on the structural scanner rather than by
  promoting the highlighter" cannot be followed as written. What CAN be followed, and
  was, is the half that matters: the base class is promoted and the DECISIONS are still
  the structural scanner's.
- *It rests on the assumption the highlighter refuses to make.* This was the right
  warning and it understated the case. Six legal Phosphor programs were compiled and run
  that an obvious folder hides code in, and every one of them is now a check in
  `src/core/uphosphorfold.pas`:

| legal Phosphor | what an obvious folder does |
| --- | --- |
| `for i = 1 to 2 println i next` | opens a fold that never closes -- a WHOLE BLOCK ON ONE LINE with no colon, and six of the seven kinds do it |
| `function f(n) return n + 1 endfunction` | the same |
| `while i < 2 i = i + 1 wend` | the same |
| `if x = 1 then println then` | `then` is a legal VARIABLE, so the line ends with the word `then` and is the inline form, which takes no endif |
| `else if n = 2 then ... endif` | `else if` is ONE token, so the chain needs exactly one endif; treating that `if` as an opener leaves the first unclosed |
| `if n = 1 then / ... / end if` | the two-word terminator is judged where the `end` is, not where the `if` is |

The rule that makes them safe is an asymmetry: **a terminator is recognised wherever it
appears and an opener only where a statement may begin.** A missed close hides text just
as surely as a wrong open -- the block then runs to the end of the file -- and the
language makes the asymmetry safe, because a terminator word used as a variable while its
block is open is a compile error.

**The done-when, clause by clause.** The block kinds fold and unfold, driven from the
gutter on both platforms; a `function` inside a string literal and a `for` inside a
comment produce no fold, and so do four more cases the item did not think to ask for;
fold state survives an edit, which SynEdit maintains itself; and the highlighter's
existing headless checks pass unchanged -- 545 in total now, 89 of them new.

**And the performance clause is answered NO, which is the reason it demanded a
measurement.** `MeasureHighlighter` prints three numbers on every run and they were taken
on both sides of the change:

| | before | after |
| --- | --- | --- |
| scanning the whole buffer, 5000 lines | 64.0 ms | 67.3 ms |
| scanning one line | 0.0130 ms | 0.0130 ms |
| an edit at the top that does not change the block structure | 0.040 ms | 0.040 ms |
| an edit at the top that OPENS OR CLOSES a block | 0.040 ms | **66.2 ms** |

`PerformScan` rescans forward until a line's range matches the stored one; before the
promotion no range ever differed, so every edit stopped one line later. It is ONE
keystroke and not every keystroke -- `fun`, `func`, `funct` are identifiers and cost
nothing -- but "not measurably slower" is false for the keystroke that completes or
breaks a block word, and the honest thing is to say so rather than quote the two numbers
that did not move.

**The three things a reader should know that are not in the item.** The fold gutter part
was already there: SynEdit creates five parts by default and the fold column is the
fifth, so the form needed no change at all and what turned folding on was the class test
alone. `select`'s ARMS are deliberately not folded, because `case` is a legal assignment
target wherever a select is not the innermost block. And **a breakpoint inside a
collapsed block is invisible while still armed and still firing** -- `TSynGutterMarks`
paints visible rows only -- which is recorded here and in `SyncGutterMarks` rather than
fixed, because the debugger's own stop unfolds to reach the line and the alternative is
an editor that refuses to collapse over a mark.

**Was:**

**What.** Collapsible `if`/`endif`, `for`/`next`, `while`/`wend`, `select`/`endselect`,
`function`/`endfunction`.

**Why it is last, and why it may not be worth doing at all.** Two costs, both real, both
already written down in `docs/architecture.md` and in the highlighter's own header.

- **It changes the highlighter's base class and its cost model.** `TSynPhosphorSyn` derives
  from `TSynCustomHighlighter` and carries **no range state on purpose**: Phosphor has no
  block comment and no multi-line string -- a string literal reaching a newline is the hard
  lexical error `unterminated string` (`engine/PhosphorLexer.pas:420-435`) -- so every line
  can be coloured by looking at that line alone, `GetRange`/`SetRange` stay the base class's
  no-ops, and editing line 10 never repaints line 400
  (`src/core/usynphosphor.pas:5-12`). SynEdit's fold support lives in a different base class
  that keeps per-line fold state. Adopting it reintroduces exactly the cross-line dependency
  this highlighter was designed to avoid, and the repaint behaviour of a large file changes
  with it.
- **It rests on the assumption the highlighter refuses to make.** Fold ranges are computed
  from keywords, and `src/core/usynphosphor.pas:24-31` says in as many words that nothing
  downstream may assume a coloured keyword is a keyword, because Phosphor decides keywords
  by position and `next = 5` is a legal assignment. A fold engine built on the colouring
  will mis-fold a legal program, and the failure mode is **text hidden from the user**,
  which is worse than a wrong colour.

If it is done anyway: build it on the structural scanner from item 15 -- which exists now,
`src/core/uphosphoroutline.pas` -- rather than by promoting the highlighter, and accept
that it will be wrong on the same rare programs the outline is wrong on, with the same
justification, that a fold is visible and reversible. That unit's header refuses to decide
this either way on its own; it names this item instead.

**Done when.** The five block kinds fold and unfold; a file with `function` inside a string
literal and `for` inside a comment produces no fold for either; fold state survives an edit
above it; typing in a 5000-line file is not measurably slower than it is today, **measured
before and after rather than assumed**; and the highlighter's existing headless checks pass
unchanged.

**Touches.** `src/core/usynphosphor.pas`, the structural scanner unit from item 15,
`src/umainform.pas`, `tests/phosphoridetest.lpr`.

---

---

# What is next

Items 1 to 17 are done. This is the list that replaces them, and its ordering is not the
first list's.

**Corrections come before features.** Items 18 to 20 are things this repository already
knows are wrong or unmeasured; every one of them was found by building something else, and
every one is cheaper to fix now than after the next thing is built on top of it. A known
defect that survives one more increment stops being a defect and becomes a property.

**Then what the editor is still missing**, 21 to 24, ordered by how often a person would
reach for the absence.

**Then what only the other repository can unlock**, 25 and 26, which are the last two
things `docs/architecture.md` still lists as absent and which have a lead time this
repository cannot compress.

**And 27 and 28 are about keeping the answers honest**, which is where this project's
defects have actually come from: not from code that was wrong when it was written, but
from prose that stopped being true while nobody was reading it.

**Item 2a is still open** and still worth doing; it has not moved, and it is the only gate
on the first list that never closed.

---

## 18. One statement-position rule, not two

**DONE 2026-09-17.** The rule is `uphosphorfold.TLineWalk` -- a public record and five
procedures -- and `uphosphoroutline` is one of its two consumers rather than a second copy.
`ScanFoldLine` and `ScanOutline` are both written on it, and so is `CallArgCount`.

The divergence this item was filed for is gone, and it was wider than the one line above:
EVERY opener after a label after `then` opened a fold the outline listed nothing for --
`if x > 0 then 20 for i = 1 to 3`, `... 20 while`, `... 20 repeat`, all seven kinds.

**The extraction was measured rather than asserted**, which is the part worth keeping. A
harness linked the units from before the change and from after it into one program and ran
both over 4524 inputs -- every block word in every statement position, every spelling of
every terminator, the half-typed and illegal shapes an editor actually sees, and the 176
real `.bas` programs in this repository and in `../Phosphor`. **About 920000 field
comparisons. On the 176 real programs: no difference in any field, anywhere.** Every
remaining difference is on illegal or half-typed input and falls into eight classes:

| input | before | after |
| --- | --- | --- |
| `if x > 0 then 20 <opener>` | folded, outline listed nothing | neither |
| `function f("x, y")` | 2 parameters | 1 -- the comma is inside a string |
| `function f(g(1, 2))` | 2 | 1 -- the commas are a level down |
| `function f(a, b` | 2 | unknown, which is what -1 already meant everywhere |
| `function f('a')` | one parameter named `'a'` | unknown -- `'` is a COMMENT |
| `f(,)` | 0 arguments | 2, which is the rule the old comment stated |
| `f([])` | 0 arguments | 1 -- a nested group is a thing, and that program runs |
| `10 20 function f()` | folded and listed | neither: a second numeric label is refused |
| `max(1, end function)` | closed the block | nothing: inside brackets it is a variable |

In five of them the two copies had ALREADY disagreed with each other inside the one unit:
`CallArgCount` knew about comments and counted separators a level at a time, and the
outline's own parameter reader did neither. Nothing chose which of the two was right; the
merge did. Each is now a check, as is the walk itself -- `TestWalk` asks the rule directly,
without a consumer, which is what neither copy ever had. 545 checks before, 626 after, and
the 545 pass unchanged.

**AND THE HARNESS MISSED TWO REGRESSIONS, which is the more useful half of this item.** The
first cut of the shared walk was wrong twice ON LEGAL PROGRAMS, and all 4229 cases of the
first corpus ran straight past both, because a corpus built by varying the WORDS cannot
find a defect about their NEIGHBOURS. A word read ahead for a two-word merge was handed
forward as a decided token instead of being put back, so it got neither the `rem` test nor
a lookahead of its own:

* `end end function` lost its terminator -- the lexer's merge pass advances by ONE when a
  pair does not merge and retries at the second `end` -- so the fold ran to the end of the
  file and collapsing it hid everything below, which is the exact failure `uphosphorfold`
  exists to prevent.
* `end rem a note` walked the COMMENT as code, so a `:` inside one opened a program-level
  statement position and a `function` inside one was listed in the outline pane, unclosed,
  claiming every line below it.

Both were found the same day by an adversarial review that generated adjacency rather than
vocabulary, `WalkNext` now rewinds, and the shapes are checks on both sides. The rule
carried into `CLAUDE.md` is the one that generalises: a differential harness answers "did
the answers move", never "are these the inputs that would move them".

**What.** `src/core/uphosphoroutline.pas` and `src/core/uphosphorfold.pas` each carry their
own copy of "where may a statement begin". One of them should own it and the other should
call it.

**Why, and it is not tidiness.** THEY ALREADY DISAGREE. The outline tracks whether a
statement position is a PROGRAM-LEVEL one, because an integer label is legal at program
level and not after `then` -- `x = 1 : 20 function h()` runs and `if x > 0 then 20 function
f()` is refused. The folder does not track it, so that second line opens a fold the outline
does not list a function for.

Today that costs nothing: the program does not compile, so the cost is a fold marker in a
file that is already red. What it costs later is the thing that has bitten this repository
twice. Phosphor's compound-keyword table (`engine/PhosphorLexer.pas:189-224`) is a moving
part, `tools/gen-keywords.py --check` does not extract it, and a change there will be fixed
in ONE of the two copies. From then on the outline pane and the fold gutter disagree about
where the same `function` ends, in the same window, on the same buffer -- one jumps to a
line and the other hides down to a different one.

`uphosphorcomplete`'s header already names this shape: "two scanners that agree until they
do not". `uphosphorfold`'s header currently CLAIMS to be the one copy. It is not, and that
sentence is either made true or deleted.

**Done when.** One unit owns the rule and the other calls it; the outline's checks and the
fold unit's pass unchanged, which is the proof that the extraction was faithful rather than
a rewrite; and the program-level difference above is a check on both sides rather than a
difference nobody wrote down.

**Touches.** `src/core/uphosphorfold.pas`, `src/core/uphosphoroutline.pas`,
`tests/phosphoridetest.lpr`.

---

## 19. The keystroke that costs 66 ms

**DONE 2026-09-17, and the answer is that nothing needs doing.** The number was measured in
the editor, through the path a key takes, and it is **12.70 ms on the largest Phosphor
program that exists**.

**The threshold, written down before the answer was known:** one frame at 60 Hz -- **16.7 ms
of synchronous work for the worst keystroke on any program in either repository**, with
100 ms as a hard ceiling for any buffer at all. A character appearing under a caret is
display-loop feedback rather than command response, so the frame budget is the figure that
applies and not the 100 ms instantaneity limit. **The bar is in MILLISECONDS ON A NAMED
MACHINE and deliberately not in lines**, because the per-line cost is driven by what is ON
the line: an identifier costs more to classify than a comment, and the rate across the real
corpus spans 1.7 to 34.5 us per line.

**How it is measured now.** `bin/phosphoride --measure-typing <report> [file.bas]` builds
buffers of 100 to 5000 lines plus, optionally, a real program; puts the caret on a word one
character short of a definition; and times `TCustomSynEdit.CommandProcessor(ecChar, ...)` --
the call `KeyDown` itself makes -- with `uphosphorclock`, reporting the MINIMUM and the
median of 21 passes. It reports the fold depth of a line in the middle of the buffer before
and after, because a cascade that is not happening looks exactly like folding being free.

Measured on Windows 11, the shipping Default build, QueryPerformanceCounter at 10 MHz:

| what | 100 | 500 | 1000 | 2000 | 5000 | **the real 874-line program** |
| --- | --- | --- | --- | --- | --- | --- |
| a quiet keystroke | 2.13 | 2.07 | 2.07 | 2.02 | 2.10 | **1.65 ms** |
| the cascading one | 3.45 | 8.63 | 15.17 | 27.57 | 64.33 | **12.70 ms** |
| the same, every fold collapsed | 4.13 | 12.66 | 22.77 | 42.41 | 102.33 | **12.90 ms** |

**The three unknowns the item listed, answered:**

- **When.** On the keystroke, with the message loop blocked. `ScanChangedLines` calls
  `ScanRanges` synchronously (`synedit.pp:5612`); the chunked idle path
  (`IdleScanRanges`, 2500 lines at a time) is guarded by `WaitingForInitialSize` and is
  reached only before the window has a handle. What IS deferred is the repaint, which is a
  flat 3-6 ms whatever the buffer size, because it draws the visible window and nothing
  else.
- **How much is ours.** The cascade costs **12.45 us per line, of which `ScanFoldLine` is
  0.48 us -- four per cent**. Folding did not make a line dearer; it made the number of
  lines large. A cleverer fold scanner would buy nothing measurable.
- **Which sizes.** 176 real `.bas` files across this repository and `../Phosphor`: median
  58 lines, p90 252, largest 872. **Nothing anybody has written reaches 1000.** On this
  machine the bar is crossed at roughly 1150 lines of code of this density.

**Two things found on the way that were not in the item:**

- **Typing the word `function` is ONE cascade, not eight.** `f`, `fu`, `func` are
  identifiers and open nothing; only the eighth keystroke completes the word. Measured as a
  counter rather than a stopwatch: of 160 keystrokes, exactly 20 -- one per pass -- exceeded
  four times the quiet cost. But *writing* a function near the top is **two** cascades, not
  one: the `endfunction` that closes it reverts every line below to the outer depth and
  cascades in its turn, which is why the table above reports open and close separately and
  they are the same size.
- **Collapsing every fold makes the same keystroke 1.6x dearer -- on a synthetic buffer.**
  `TSynEditFoldedView.FixFolding` re-queries every collapsed node and each query scans one
  more line. The fixture here has a fold node every three lines; a real program does not,
  and on the 874-line one the collapsed cost is **1.02x**. Worth knowing, not worth fixing.

**The mitigation the item proposed does not apply, and the reason is worth keeping.**
`PerformScan` stops when a line's range pointer equals the stored one, and those pointers
are interned by equality (`synedithighlighterfoldbase.pas:1739-1745`), so an ordinary edit
settles within a few lines -- measured, and that is the 2 ms row. But an opener with no
terminator below it changes the fold depth of EVERY line under it, so no line's range can
match again. **The cascade is inherent, not an artefact of our representation, and there is
no early stop to reach for.** `usynphosphor` does nothing that defeats interning.

**And the lever, if a threshold is ever missed, is not in this item's code.** An identifier
in no table -- which is what most words in a program are -- costs **3.5 us to classify**,
through six sorted `TStringList.Find` calls over case-insensitive indexes
(`uphosphorlang`). Two of those per line is most of the 12.45 us. That is item 29.

**Two ways of timing this from OUTSIDE the process were tried and both lie**, recorded in
`tools/lane/steps-typing.txt` so the next reader does not pay for them again: a posted key
followed by a sent `WM_NULL` measures the probe's own head start, because Windows delivers
sent messages before posted ones; and `OnProcessCommand`/`OnCommandProcessed` bracket
`ExecuteCommand` but not the rescan, which runs later in `DecPaintLock`. The lane case
remains as a DRIVEN, visible confirmation -- real keys, real queue, the fold marker
arriving -- with the number coming from inside.

**What.** Find out what folding actually costs a person typing, rather than what it costs a
loop in the test program, and then decide.

**Why.** Item 17 answered its own performance clause with NO and printed the numbers:
scanning one line is unchanged, an ordinary edit is unchanged, and an edit that OPENS OR
CLOSES a block in a 5000-line file went from 0.040 ms to 66 ms. That is honest but it is
not yet useful, because it was measured in `MeasureHighlighter` -- a bare
`ScanRanges` over an attached line store -- and three things about the real case are
unknown:

- **When SynEdit does it.** On the keystroke, or on idle before the next paint? A cost paid
  where nobody is waiting is a different cost.
- **How much of it is ours.** The rescan runs the highlighter over every line below the
  edit; `ScanFoldLine` is a second pass over each of those lines, and its share has never
  been separated from the base cost.
- **Whether the file sizes that matter are affected at all.** 5000 lines was chosen because
  the item said so. A Phosphor program of 300 lines would pay 4 ms, which is nothing.

**The cheap mitigation, if one is needed**, is not a cleverer scanner: it is to stop
scanning. `TSynCustomHighlighter` rescans until a line's range MATCHES the stored one, and
two ranges match structurally -- so a fold stack that reaches the same depth by a different
path still compares equal, and most edits at the top of a file settle within a few lines.
Whether they do here is a question about `TSynCustomCodeFoldBlock`'s interning and has not
been asked.

**Done when.** The number is measured IN THE EDITOR -- a driven case that types `function`
at the top of a large buffer and times what the user waits for -- and either it is under a
threshold written down in this item, or something is done and re-measured. "It felt fine"
does not close this.

**Touches.** `tools/lane/`, `tests/phosphoridetest.lpr`, possibly
`src/core/usynphosphor.pas`.

---

## 20. A breakpoint a fold hides

**DONE 2026-09-17, and the answer is the third one PLUS a rule the item did not
decide.** The collapsed header carries a new gutter mark that says a breakpoint is
hidden inside it, and a gutter click on that row OPENS THE BLOCK instead of toggling.

**Why the third.** The first two were argued out rather than dismissed. Refusing the
collapse is a `[-]` that a person clicks and watches do nothing -- the same class as the
status bar with four panels and no text. Unfolding when a breakpoint MOVES is worse than
it sounds, because breakpoints move on every edit above them: typing at the top of a file
would keep tearing folds open. The badge is the only one that does not take away a state
somebody can legitimately want -- a breakpoint inside a function they deliberately folded
shut -- and its failure mode is the mildest: if the glyph is not understood, the user
clicks it and finds out.

**And the click rule is what makes it a fix rather than a decoration.** Without it the
badge is a nicer way to watch the same duplicate get created; with it the duplicate cannot
be created at all. It is the ONLY row in the gutter where a click does anything else, and
only while it is badged: a collapsed header hiding nothing toggles like every other line.
Nothing is refused, the caret does not move, and the status bar says which of the two
happened.

**What it cost to find out, measured before anything was built:**

* Performing the item's sequence against the editor as it was gave an EMPTY gutter and
  then two breakpoints where one was meant. Against the real host those two stop the run
  **three times**, and the extra stop lands on a line with no mark on it.
* **Exactly one mark is drawn per line at 96 PPI**, and WHICH of two on the same line
  survives is decided by their heap addresses -- it changes between runs. `Application.Scaled`
  is on, and at 150% the ratio becomes 2 and both appear: a design that stacked two marks
  would have differed by MONITOR. So a badged header shows the badge and nothing else,
  including when it carries a breakpoint of its own.
* `CollapsedLineForFoldAtLine` is the call that answers "which visible row", and with
  nesting it gives the OUTERMOST collapsed header -- the one the user can actually see.
  `ExpandedLineForBlockAtLine` answers the innermost enclosing block whether or not
  anything is folded, and would point at a row that is itself hidden.
* `FoldedAtTextIndex` and `UnFoldAtTextIndex` are **0-based**, and SynEdit's own comments
  beside both say "1-based". Do not cite those comments.
* The fold notification is `senrLineMappingChanged`. `OnChange` never fires for a fold and
  `TSynStatusChange` has no member for one.
* Nothing in this repository saves or restores a fold state, so no breakpoint can be
  hidden at startup -- which is the worse version of this problem, and it does not exist.

**What the badge deliberately does not say** is how many, or whether the host armed them.
One glyph stands for N breakpoints and loses solid-versus-hollow, which is the one piece of
protocol information this gutter carries. That is a real loss and the click is why it is
acceptable: one click and every hidden mark is drawn exactly as it always was, one per
line. The badge is a door, not a summary.

**Driven on both platforms**: `tools/lane/steps-hidden.txt` and `steps-hidden-linux.txt`
perform the item's sequence and then the control case -- a collapsed header hiding nothing,
which still toggles.

**What.** Decide what the editor does when a fold hides a line that carries a breakpoint.

**Why.** Today it does nothing, and that is recorded in `SyncGutterMarks` rather than
fixed. `TSynGutterMarks` paints visible screen rows only, so the mark is simply not drawn;
the breakpoint is still in the set, still armed and still fires, and the debugger's own
stop calls `GotoSource`, which moves the caret and makes SynEdit unfold to reach it. So
nothing is broken.

What is unpleasant is the sequence a person actually performs: collapse a function, see no
mark, conclude the breakpoint is gone, click the gutter on the collapsed header to set it
again -- and get a SECOND breakpoint, on the header line, which then stops the run twice,
once at a line with no mark on it.

**The three answers, and none of them is obviously right.** Refuse to collapse a block that
hides a breakpoint, which is a fold marker that argues with the user. Unfold when a
breakpoint is set or moved, which is a caret that jumps for a reason nobody asked for. Or
draw something in the gutter of the COLLAPSED header to say a mark is hidden inside it,
which is the most informative and needs a mark image that means "not here, below".

**Done when.** One of the three is chosen, the reason is written where the code is, and a
lane case on both platforms performs the sequence above and shows what happens. The
"present but blank" class of defect is what `--selftest` reports panel counts for; this is
the same class, and a screenshot is what settles it.

**Touches.** `src/umainform.pas`, possibly `tools/gen-icons.py` and
`src/core/uphosphoricons.pas`, `tools/lane/`.

---

## 21. Replace in files

**DONE 2026-09-17.** The Find in Files pane has a Replace row, and it changes the lines the
search listed and nothing else.

**IT NEEDED A DEFECT FIXED FIRST, and finding it was most of the work.** The item says the
write must go through `TEditorDoc.SaveToFile`, and that no file may change its line endings
-- and those two could not both be true, because `SaveToFile` wrote `FEdit.Lines.Text`.
`TStrings.Text` joins with `TextLineBreakStyle`, which defaults to the machine's own
convention and which `TSynEditStringList` does not override. Measured through the real
editor: **Ctrl+S on a file of `rem a\nx = 1\n` returned CRLF throughout, and a file with no
closing newline gained one.** A program written on Linux and saved on Windows came back as a
whole-file diff for a one-character edit. `src/core/utextfile.pas` now owns the rules and
`SaveToFile` is its caller; see the commit before this one.

**The two rules the feature rests on**, both checked against the bytes of a fixture
directory rather than against a screenshot:

* **No line the search did not list is touched.** The search deposits ONE hit per line, so
  a row means "this line matches"; every occurrence ON that line is replaced, and a file
  that matched nothing is never opened.
* **A file keeps the endings and the closing newline it arrived with.**

**Two routes, decided by the tab strip.** A file OPEN in a tab is changed through its buffer
inside one `BeginUndoBlock` using `TextBetweenPoints` -- so **one Ctrl+Z takes the whole
replace back**, the tab shows modified, and its bytes on disk do not move until the user
saves. Writing such a file behind its own editor would leave the buffer holding the old text
and the next save would put it back. A file that is NOT open goes through
`ufindinfiles.ReplaceInFile`, which goes through `utextfile`.

**A file that cannot be written is reported and skipped**, never a reason to stop: a run
that has already rewritten four files and then meets a read-only fifth must finish the other
six. `phosphoridetest` checks the read-only case, the vanished case, a line number past the
end of a file, and a line that no longer matches -- each of which leaves the file exactly as
it was and the run going.

**Nothing is written until the user has seen the list**: the button is dead until a search
has produced rows, dead again the moment a new search starts, and the confirmation carries
the counts. Afterwards the rows are cleared, because a second Replace over lines already
changed is how `a` becomes `bb`.

**One rule was decided here rather than inherited**: `ReplaceInLine` never looks at what it
just wrote. Replacing `foo` with `xfoox` in a scanner that rescans from the start of the
replacement does not terminate; this one advances past it, so that case is `xfoox` and not a
hang. It is a check.

**Driven on both platforms** by `tools/lane/replace-tree.ps1` and `replace-tree.sh`, which
build a four-file tree in the temp directory, run the real editor over it and compare the
bytes. They are scripts rather than `steps-*.txt` because this case CHANGES files, and a
fixture under `tools/lane` that is rewritten on every run leaves the repository dirty. Both
report `REPLACE TREE OK` and both agree byte for byte: `a.bas` intact on disk (open in a
tab), `b.bas` rewritten with its CRLF, `sub/c.bas` rewritten with no closing newline gained,
`d.bas` untouched.

**What.** The Find in Files pane can search a tree. It cannot change one.

**Why.** Replace exists already (`ActReplace`, `ReplaceDialog1`) and is scoped to the
active buffer, exactly as Find was before item 14. The asymmetry is the whole argument: a
person who has just found eleven occurrences across six files is one dialog away from the
thing they were going to do next, and the editor asks them to open six tabs.

**And it is the first feature on this list that CHANGES TEXT**, which is why it is not
cheap. Everything built in items 14 to 17 is allowed to be wrong about a rare legal
program, because being wrong costs a row in a list or a fold nobody wanted. A replace that
is wrong costs somebody their file. So: no scanner is involved, the match is the same
literal `FindInLine` the search already uses, and the write goes through
`TEditorDoc.SaveToFile` -- the one writer, which is the only thing that knows about the
BOM rule -- or through an open buffer's own undo stack, never through a stream of its own.

**Done when.** A replace across a tree changes exactly the occurrences the search listed
and nothing else, verified by a before-and-after of a fixture directory; a file that is
OPEN is changed through its buffer so that Undo works and the tab shows modified; a file
that is read-only or vanished between the search and the write is reported and skipped
rather than failing the whole run; nothing is written until the user has seen the list;
and no file gains a BOM or changes its line endings.

**Touches.** `src/core/ufindinfiles.pas`, `src/umainform.pas`, `src/umainform.lfm`,
`tests/phosphoridetest.lpr`, `tools/lane/`.

---

## 22. The matching block, and jumping to it

**DONE 2026-09-17.** With the caret on a block keyword its partner is outlined in the text,
**Ctrl+Shift+M** moves the caret to it, and the three words that only LOOK like block
keywords each get a sentence in the status bar instead of a jump to nowhere.

**HALF OF IT COST ONE LINE, AND FINDING THAT LINE WAS THE WORK.** SynEdit already creates a
`TSynEditMarkupWordGroup` for every editor and hands it whatever highlighter the editor is
given (`synedit.pp:2367`, `:6790`). It finds the partner through the fold NODE INFO the
base class emits -- but it filters on nodes carrying `sfaMarkup`, and that action comes from
the fold config's Modes: `if fmMarkup in AValue then FFoldActions := FFoldActions +
[sfaMarkup]` (`synedithighlighterfoldbase.pas:2660`). The default is `[fmFold]` alone, and
Modes is filtered through SupportedModes on the way in (`:2654`), so asking for it without
widening the supported set does nothing. Measured before the line existed: with the caret
inside `function`, nothing was painted anywhere. `usynphosphor.CreateFoldConfigInstance`
now creates the config with `[fmFold, fmMarkup]`, and the painting -- recomputed on every
caret move and every edit, by SynEdit, in its own colours -- arrives with no markup code in
this repository at all.

**The other half is ours, because SynEdit's markup cannot say why there is no partner.**
`uphosphorfold.MatchBlockAt` walks the buffer and answers one of four things: matched,
unterminated, unopened, or nothing at all. `ActMatchBlock` moves the caret on the first and
writes a sentence for the other three.

**NOTHING IS REMEMBERED**, which is how the answer survives an edit: the whole buffer is
walked on every call, there is no cached structure to go stale, and roadmap item 19 measured
the corpus at under nine hundred lines.

**`ScanFoldLineRaw` is new, and it is why a one-line pair still matches.** Folding drops a
block that opens and closes on the same line because it hides nothing (rule 6); matching
wants it, because in `for i = 1 to 2 println i next` the `for` and the `next` ARE partners.
So the rule is applied in one place, by `ScanFoldLine`, over what the raw scan returns.

**The three refusals, each a check and each driven:**

| the line | what it looks like | what it answers |
| --- | --- | --- |
| `next = 5` | a terminator | `this closes a for, and none is open` |
| `y = function + 1` | an opener | `no block keyword under the caret` |
| `println "for i = 1 to 3 endfunction"` | both | `no block keyword under the caret` |

and an opener nothing closes says `this while is never closed`.

**Driven on both platforms** by `tools/lane/steps-matching.txt` and
`steps-matching-linux.txt` over `matching.bas`, which holds all four answers.

**What.** With the caret on `if`, show where its `endif` is -- and jump there.

**Why it is cheap now and was not before.** `uphosphorfold` already answers, for every
line, what it opens and what it closes; the fold stack already knows which block the caret
is inside. The feature is a reading of a structure that exists, and it changes no text,
which puts it on the safe side of the line item 21 has to cross.

**Why it is worth doing at all.** Phosphor has no braces. The eye has nothing to match on,
and a `next` eleven lines down is not visibly the partner of a `for` -- which is the same
argument the outline pane won on, one level smaller.

**Done when.** With the caret on a block keyword, its partner is marked in the text and a
shortcut moves the caret to it; on a keyword that opens nothing -- `next = 5`, `function`
as a variable, a word inside a literal -- nothing is marked and the status bar says so
rather than the editor doing nothing; an unterminated block marks nothing and says which;
and the marking survives the buffer being edited, because it is recomputed and not
remembered.

**Touches.** `src/core/uphosphorfold.pas`, `src/umainform.pas`, `src/umainform.lfm`,
`tests/phosphoridetest.lpr`.

---

## 23. Send the selection to the REPL

**DONE 2026-09-17.** **Ctrl+Shift+Enter** takes the selected lines -- or, with no selection,
the one the caret is on -- and feeds them to the prompt.

**ONE LINE PER PROMPT, AND THAT IS THE WHOLE DESIGN.** The REPL reads one line at a time
and answers each with a prompt. Sending five lines the moment they are queued would put five
echoes in the transcript before the first prompt arrived, and the record would read nothing
like the same five lines typed by hand -- which this item's done-when asks for in as many
words. So the lines go into a queue and one leaves only when a prompt is showing:
`PumpReplQueue` is called from `ReplOutput`, which is where a prompt lands.

**A line that opens a block needs no special case at all.** The host answers it with
`     ...> ` instead of `phosphor> `, and a continuation prompt is a prompt: the rest of the
definition follows it because the queue is waiting for a prompt and not for a particular
one. `IsAllPrompt` is the test, on an OPEN fragment -- a prompt is written before a read and
never terminated, so a complete line that happens to read like one is something the program
printed.

**Measured by driving it**: the five lines of a definition arrive as

```
phosphor> function twice(n) local r
   ...>   r = n * 2
   ...>   println "inside twice"
   ...>   return r
   ...> endfunction
phosphor> println twice(21)
inside twice
42
```

and `twice` is callable from the prompt afterwards, which is the clause that proves the five
lines were a definition and not five strings.

**Two rules that are not in the item and were worth deciding.** A selection that ends at
column 1 does NOT include that line -- dragging from 4 to the start of 9 selects four lines,
which is what every editor draws and what stops a stray `endfunction` being sent that nobody
highlighted. And what is sent goes into the **history** as though it had been typed, because
Up should walk what was sent as well.

**Sending with no REPL running starts one first**, and sends nothing until its prompt
arrives -- the queue is what makes that safe rather than a race.

**Driven on both platforms** by `tools/lane/steps-sendrepl.txt` and
`steps-sendrepl-linux.txt` over `sendrepl.bas`.

**What.** A shortcut that takes the selected lines -- or the current one -- and feeds them
to the prompt.

**Why.** The REPL keeps its variables across lines and Run starts from nothing; that is the
whole of item 16's argument. The missing half is that a person editing a function has no
way to try it without retyping it into the prompt, which is exactly the retyping the pane
was built to remove.

**The one thing to get right** is that a multi-line selection is several lines and the REPL
reads one at a time: they are sent in order, the transcript echoes each, and a line that
opens a block leaves the prompt on `     ...> ` exactly as typing it would. Nothing is
special-cased and nothing is joined.

**Done when.** A selected `function` definition of five lines reaches the prompt as five
lines and the function is then callable from it; sending with no REPL running starts one
first; sending while the prompt is mid-block continues that block; and the transcript
afterwards is indistinguishable from the same lines typed by hand.

**Touches.** `src/umainform.pas`, `src/umainform.lfm`, `tools/lane/`.

---

## 24. A diagnostic you can see in the text

**DONE 2026-09-17.** A run that fails tints the line it blamed, in the document that
diagnostic names and in no other.

**A WASH, NOT A BAND.** The debug stop keeps its opaque navy because it is where you ARE and
it moves as you step; this one stays put while somebody reads and edits around it, so it
keeps the text's own colours and tints only the background. That is the same argument that
retired the full-width maroon the breakpoint used to have: a line of code is a thing you
read, and a diagnostic is a thing you read it BECAUSE of.

**The stop still wins**, and the arrangement is one `Exit`: `EditorSpecialLineMarkup`
answers the debug line first and returns, so "you are here" outranks "this was wrong last
time" without a rule being written for it.

**THE FIRST DIAGNOSTIC OF THE RUN, NOT THE LAST.** A failure cascades; the line a person
acts on is the one the host blamed first, and a mark that jumped to the final complaint
would point at consequences rather than at the cause.

**Cleared unconditionally when a run starts**, which is the one place the item told us not
to copy the existing behaviour: the Problems pane empties only when `Clear output on run` is
set, because a pane is a LOG and may legitimately keep two runs side by side. A band behind
a line of code is a claim about THIS text right now, and a claim that outlived the run that
produced it is a lie whatever the preference says.

**And it is dropped the moment its line is typed into.** That needed a second notification:
`senrLineCount` is what moves a breakpoint when lines are added above it, and typing INSIDE
a line changes no count at all -- so `TEditorDoc` now also listens to `senrLineChange`, which
is the one that fires for the line under the caret.

**One rule, two consumers.** The arithmetic that follows an insertion was
`TBreakpointSet.TrackEdit`'s alone; it is now `ubreakpoints.TrackLine`, which TrackEdit
applies to a set and item 24 applies to the single line it remembers. A second copy of a
three-branch rule is how the two would come to disagree about where a line went, and this
repository has spent two items on exactly that. `phosphoridetest` checks the rule without a
set around it -- including that **0 stays 0**, because otherwise every edit in a session
would shift "no blame" into a line number.

**A diagnostic with no location marks nothing**, and that costs no code: `HasSourceLocation`
already chooses the branch, and `file not found:` and a `--check` warning take the other one.

**Driven on both platforms** by `tools/lane/steps-blame.txt` and `steps-blame-linux.txt` over
`blame.bas`. **The edit comes last in those scripts and that order is deliberate**: F9 saves
before it runs, so an edit followed by another run would write the change into a checked-in
fixture and leave the repository dirty after every pass. Editing last means nothing saves
it. The first attempt did it the other way round and did leave the file changed; undoing at
the end did not restore it, because by then the focus was not in the editor.

**What.** The line a failed run blamed is marked IN THE EDITOR, not only in the Problems
pane.

**Why.** `uphosphormsg` parses the location, `AddProblem` lists it, and
`ListProblemsDblClick` jumps to it -- and then the editor shows a caret on an ordinary
line. The information is in the window and not where the eye is. `EditorSpecialLineMarkup`
already paints the current debug statement, so the seam exists and is one line wide.

**What it must not become.** Not a live checker: nothing here compiles anything, and a mark
that appears while somebody is typing is a mark that is wrong most of the time. It marks
what the LAST run said, it is cleared when the next run starts, and a line that has since
been edited loses its mark rather than keeping a claim about text that has changed.

Note that the existing clear is not a model to copy: `StartHost` empties the Problems pane
only when the `Clear output on run` preference is on (`src/umainform.pas:1319-1323`), and a
mark in the TEXT that outlived the run that produced it would be a lie whatever that
preference says. This one clears unconditionally.

**Done when.** A run that fails marks the line it blamed in the active document and only
there; the mark survives scrolling and is cleared by the next run; editing the marked line
clears its mark; a diagnostic with no location (`file not found:`, a `--check` warning)
marks nothing; and the debug current-statement band still wins over it, because "you are
here" outranks "this was wrong last time".

**Touches.** `src/umainform.pas`, `tests/phosphoridetest.lpr`, `tools/lane/`.

---

## 25. Phosphor: an expression the debugger can evaluate

**DONE 2026-09-17**, in `C:/Dev/Phosphor` (`aae86e6`). The host answers `evaluate`
for a global, a local in a named frame and an expression that faults;
`capabilities.evaluate` is true; and **this repository needed no change to discover
it** -- `DecodeCapabilities` already read the key and `EncodeEvaluate` already wrote
the request, both written before the other end existed. Third time that contract has
been proved right by one end moving and the other not.

**IT REUSES THE COMPILER RATHER THAN WRITING A SECOND LANGUAGE.** The whole source is
compiled again with one line appended -- `<hidden> = (<expr>)` -- so the precedence
is the language's own, including the two irregularities a re-implementation gets
wrong: `-2 ^ 2` is -4 because `^` takes a PRIMARY base, and `a < b < c` does not
chain because the comparison rung is an `if` and not a `while`. Appending can only
ADD names and instructions, so every global index of the running program is where it
was -- the property `ReplRun` has rested on since the REPL existed, checked over 154
real programs rather than assumed. One compile costs 0,9 ms on the mean of 7558 `.bas`
files across both repositories, 15,7 ms on the worst. A second expression reader was
built and differentially checked against the engine over 77 expressions before this
was chosen; it worked, and it was a second copy of a language this pair of
repositories has spent three items de-duplicating.

**THE GATE READS THE EMITTED INSTRUCTIONS, NEVER THE TEXT**, and that is the whole
safety argument. `expr` is the one field of this protocol an editor sends verbatim,
so it is where a hostile string arrives: `total) : total = 99 : println (1` is a
legal line whose middle statement writes a global. The compiler refuses most such
smuggles -- **but by accident**, on the trailing fragment failing to be a statement
rather than on the payload, so balancing the tail gets all of them past it; and a
comment defeats any scheme that neutralises the tail by appending a terminator. None
of that is visible to a text rule and all of it is plain in the bytecode, which may
hold only opcodes that compute and exactly one store: the last instruction, into the
slot the host itself named. 39 hostile strings were measured against it.

**No call the user writes is performed**, said on the wire by a new
`evaluateCalls: false` capability -- the handshake carries six keys now, and
`docs/debug-protocol.md` specifies both. `a@[i]`, `s$[n]` and `s$[[n]]` do answer,
through the three names the compiler's own bracket lowering emits and only where the
program defines no function of that name and arity. Refusing them would have meant a
debugger that renders an array as `@1` in its variables pane and then declines to
look inside it.

**A fresh VM per request** -- no output seam, no input seam, no debug seam, its own
ceilings -- seeded with every global and then the frame's locals over the globals of
the same name, which IS the shadowing rule rather than a second copy of it. It has
nothing to save and restore; the alternative needed fifteen fields put back, a list
with no test that is not a second copy of itself. The handle registry is the one
thing a fresh VM does not isolate, so `LiveHandleCount` is read either side of every
request and a request that moved it gets no answer at all.

**And it found an engine defect.** `TPhosphorVM.Create` never initialised
`FErrHandler`, and 0 is a valid pc, so every freshly created VM carried an `ON ERROR`
handler at instruction 0. `Run` resets it and `RunFrom` deliberately does not, so the
hole was exactly a VM created and then driven by `RunFrom` -- which nothing did until
this. It was invisible because what happened next depended on the program's own text:
one containing `end` reached that halt, so `RunFrom` returned **True for a run that
had faulted**, with `LastError` empty. Fixed in the constructor and pinned with
`end` and without, because a check on the second half alone passes with the defect in
place.

Phosphor's own bar, all of it: `fpc -B -vewn` clean, every suite byte-exact,
`-ProveFailure` seen catching a corrupted expectation, the boundary check green,
`tests/debug_protocol_test.py` from 58 assertions across four sessions to **97 across
seven**, and green on Linux -- suite, classic, examples, packages and the protocol.

**What is NOT done, said out loud.** `len(x$)` is refused, along with all 1145
registered names, because the registry carries no notion of an effect and this host
will not guess. Widening that needs a purity bit beside `Reg.Add` across seventeen
library units, which is a different piece of work and is not scoped. And the attack
plan's ask for a `probe_sweep` leg evaluating at every stop is unmet by design: that
is an ENGINE probe and this evaluator is host-side, so the leg could only exist as a
second copy of the gate. The concern behind it -- an `on error` shape in the corpus --
is answered at the right level instead, in the protocol suite's seventh session.

**Here: nothing, as the item said.** Item 26 is the pane that will read
`TDebugCaps.Evaluate`, which nothing consumes yet.

**What.** Work in `C:/Dev/Phosphor`. A PDBP `evaluate` request that answers the value of an
expression in a chosen frame, and `capabilities.evaluate` set true when it exists.

**Why it is not this repository's to do.** `docs/debug-protocol.md` specifies the request
and `src/core/udebugproto.pas` can already encode it; `capabilities.evaluate` is false on
every host today and the editor honours that. The reason the editor must not close the gap
itself is the invariant at the top of `CLAUDE.md`: an expression evaluator here would be an
interpreter here, and the one design decision the rest of the program is not allowed to
trade away is that the engine is never linked.

**The shape to ask for**, in the terms the two debts in `docs/phosphor-debugger-debts.md`
were asked in: an expression, a frame index, and an answer that is a VALUE and an error
string, never a formatted line -- because the formatting belongs to whoever displays it and
a host that formats has to guess at a pane it cannot see.

**Done when.** The host answers `evaluate` for a global, a local in a named frame, and an
expression that faults; `capabilities.evaluate` is true; and this repository needs no
change to discover it, because the capability probe already exists -- which is the test of
whether the contract was drawn in the right place, exactly as it was for the two debts that
came before.

**Touches.** The Phosphor repository. Here: nothing, until it lands.

---

## 26. Watches, and a breakpoint with a condition

**DONE 2026-09-17**, across both repositories (Phosphor `1b38e9e`).

**THE WATCH PANE IS THE EIGHTH TAB**, and `uwatchlist.TWatchList` is where the
thinking is -- LCL-free, so `phosphoridetest` pins every case without a window. A
watch has THREE states and the third is the whole point: unknown, a value, or an
error. `Invalidate` empties every answer the instant the program stops standing
still, so the pane shows a BLANK rather than the number from the last stop. That is
this item's own sentence, and it is worth restating as a general one: a reading that
might be from now and might be from a minute ago is a reading nobody can act on, and
nothing about it looks different. The EXPRESSIONS survive, because they belong to the
person and not to the session.

**AN ID, NOT A ROW.** The `evaluate` reply carries a value and nothing else -- not
the expression, not the frame -- so this side has to remember which question it
answers. A row index would hand a late answer to whatever slid up when a watch was
deleted, which is the same stale value wearing a different hat. Ids come from a
counter and are never reused; an answer for a watch that is gone lands nowhere.

**THE CONDITION IS EVALUATED IN THE HOST, and that was measured rather than
assumed.** Faking it here -- stop, ask `evaluate`, continue when false -- works, and
costs 11,6 to 23 ms per hit against 0,04 to 2,3 ms over there. A 10 000-hit loop is
231 seconds against 58; it writes one Output line and one band flash per refused
hit; and this editor already loses between 1 and 13 stops in ten thousand, each of
which would be a condition never evaluated. The host side is one evaluator with two
callers, so a condition and a watch cannot come to disagree about what an expression
means -- the failure this pair of repositories has now spent five items avoiding.

**FOUR GUTTER GLYPHS, not a badge.** Armed and inert cross with plain and
conditional; a conditional one is the same disc with a bite out of its right side.
SynEdit CAN paint two marks on one line -- `MaxExtraMarksColums` is published and
setting it to 1 makes both appear -- but at this gutter's width they share 24 px and
read as a smudge. Drawn and looked at, not reasoned about.

**A REFUSED CONDITION BECOMES A PROBLEMS ROW ON ITS OWN LINE**, which is the one
channel in this window that carries a line and can be jumped to -- what "reported
where it was typed" has to mean when the thing typed is not in the text. The
breakpoint is then installed unconditional and the row says so. A condition whose
NAMES are wrong cannot be caught at that moment, because scope is a frame and there
is not one yet; it arrives later as a stop carrying `text`.

**AND ToItems FINALLY HAS CALLERS.** `ToArray`'s comment had said "for handing to a
debug adapter" since it was written and nothing ever did: both sites that build the
frame wrote their own loop over the document's facade. That cost nothing while a
breakpoint was one integer and would have cost this whole feature the moment one
carried a condition, because a hand-written loop that copies the line and forgets the
condition compiles, runs, and sends a mark that fires on every hit.

**The claims that had expired, corrected as the item asks.** The toolbar hint that
still said "Nothing stops at it yet"; `architecture.md` calling the call-stack pane a
fourth tab (it is the fifth, and it WAS the fourth when written -- Find and Outline
landed either side and nobody counted again); "only frame 0 has a line", fixed in
Phosphor on 2026-09-16; and `capabilities.evaluate` being false on every host, which
stopped being true the day before this. Plus a count that lived as a literal in five
places across three files and was wrong in all five.

**Proven:** 747 checks -> 822, clean at `-vewn`, `--selftest` 0 with the new pane and
five gutter marks counted, both generators current, and green on Linux. On the host
side, 97 protocol assertions across seven sessions -> 117 across eight.

**What is NOT done, and is not hidden.** The chunk a condition compiles to is not
cached, so a condition on a hot line in a LARGE program costs 2,3 ms a hit -- 2000
hits in 4,5 s. A cache keyed on the expression takes that to microseconds and the
technique is proven (`TProgram.Patch` re-points the prologue so the kept program does
not grow, measured at zero growth over 10 000 correct evaluations). It is a known
piece of work and it is written down in `../Phosphor/docs/debugging.md` rather than
left to be discovered.

**What.** The editor half of item 25, plus conditional breakpoints.

**Why they are one item.** Both are the same request with a different caller: a watch
evaluates an expression when the program stops, and a conditional breakpoint evaluates one
to decide whether to stop. Neither is reachable without 25, and once 25 exists both are
panes and a dialog rather than protocol work.

**Done when.** A watch list shows expressions evaluated at each stop and says plainly when
one cannot be evaluated rather than showing a stale value; a breakpoint carries an optional
condition, the gutter shows that it has one, and a condition the host refuses is reported
where it was typed; and `Debug > Why is stepping unavailable?` and the paragraph in
`CLAUDE.md` about what is NOT built are both corrected in the same increment, because a
limitation recorded in the present tense is a claim with an expiry date nobody set.

**Touches.** `src/core/udebugsession.pas`, `src/core/udebugproto.pas`,
`src/umainform.pas`, `src/umainform.lfm`, `CLAUDE.md`, `docs/architecture.md`.

---

## 27. A citation that cannot rot quietly

**DONE 2026-09-17.** `tools/check-citations.py`, run by both build scripts beside the
two `--check` gates.

**IT WAS IN FLIGHT, AND I SAID IT WAS NOT.** The note below told the next person to
check `tools/` before starting. I did, saw only the two generators, and wrote in this
very entry that the session had produced nothing. That was false, and the tool I had
just written found it: a citation it flagged led to
`.claude/worktrees/distracted-williams-53ecc1/`, where **commit `ad5a1ea` on the branch
`claude/distracted-williams-53ecc1`** holds a 655-line `check-citations.py`, a
`citations.tsv`, both build scripts wired, and a pass of citation corrections -- 879
insertions across 15 files, committed on 2026-09-16 and never merged.

Checking `tools/` was the wrong check. `git log --all --not main` was the right one, and
it takes a second. **A branch is not a place work goes to be finished**; this one sat for
a day while the entry describing it said it might be done, and then I wrote that it was
not. Both halves of that are the item's own subject: a claim nobody could verify
cheaply, left standing.

**What I did about it, and what I did not.** I kept the tool written here, because the
branch is two weeks stale against a tree that has since absorbed items 18 to 26 and its
build-script changes now conflict with three other gates. I took its best idea outright
-- the `citations-frozen` marker, which lets a file that DISCUSSES citations opt out,
and which its author hit on the first run exactly as I did. **It is read in the first
forty lines only**, and that was not the first rule: anywhere in the file was, and it
was wrong within the hour, because this very entry explains the marker and thereby
froze the roadmap -- forty-three citations stopped being checked and the run said so
only as a smaller total. A gate that switches itself off quietly is worse than no gate.
A declaration belongs where a reader looks for one. **What I did NOT do is mine
its citation corrections**, and that is the honest gap: it fixed ranges like
`PhosphorCompiler.pas:601-645` to `:623-632` against the Phosphor of 2026-09-16, and
Phosphor has changed since -- items 25 and 26 edited `PhosphorVM.pas` and
`phosphor.lpr` in this session alone. Applying those numbers unread would be
re-introducing rot with a straight face. They are worth a read against today's tree and
they are not in this commit.

**A BOUNDS CHECK WOULD HAVE BEEN GREEN THROUGH THE WHOLE DEFECT.** All sixteen rotted
line numbers were still INSIDE their files; what changed was what the lines SAID. So
`tools/citations.lock` remembers a fingerprint of each cited range plus its first real
line, and a citation whose target no longer matches is a red build.

**THE REPORT IS THE FEATURE.** It names every file carrying that citation -- the
original defect had one of them in SEVEN places -- and searches the target for the
remembered text, so it says "that text is now at line 190" rather than only "it moved".
One inserted line in `PhosphorLexer.pas` turns twelve citations red and each one says
where its text went.

**IT FOUND ROTTED CITATIONS ON ITS FIRST RUN**, and they are fixed in the same commit:
`phosphor.lpr` line 3017, cited for the REPL prompt, had become frame-label printing in
the debug state dump. The prompt is `:3746`.

**I counted those wrong twice.** A grep before writing the checker found three; I wrote
"three". The tool found a fourth, in `docs/roadmap.md`, worded differently from the
others. I wrote "four". A wider search then found a FIFTH, in
`tests/phosphoridetest.lpr`. That is the item's own argument happening to the person
making it, twice in ten minutes: a count in prose is a claim, and the only reliable
counter is one that runs.

`umainform.pas`
line 1132 for `ActDebugWhy` had become `ActSaveAsExecute`'s `var` (it is `:3247`); and
the same claim
about the UI thread was cited as `6-9` in one place and `6-10` in three others.

**AND IT CHECKS THIS REPOSITORY'S OWN CITATIONS TOO**, 60 of the 118. They rot faster
than the sibling's, because they point at code somebody is editing today.

**What it does NOT catch, which is why the item is worth more than its mechanism.** It
checks that a citation points at the text it pointed at before. It cannot check that
the text supports the SENTENCE beside it, and it cannot see a claim with no citation in
it at all -- which is exactly the second defect of 2026-09-16: `CLAUDE.md` explained the
no-BOM rule by saying a BOM is a lexical error on line one, which the console host has
stripped since its first commit. The rule was right, the reason had never been true of
that path, and there was no number in it to go stale. No mechanism finds that one.

**AND THE BASELINE RECORDS THE TREE AS IT IS, WHICH IS THIS TOOL'S REAL LIMITATION.**
A first `--update` fingerprints whatever is there, including citations that were ALREADY
wrong -- so the gate now defends the current numbers whether or not they were ever right.
It stops the NEXT drift; it blesses the last one.

That is not theoretical. The unmerged branch above corrected ranges this baseline has
just frozen, and the lockfile's own weak anchors say where to look: twenty-one citations
point at lines reading `var`, `begin`, `end;` or `uses`, which are not lines anybody
cites on purpose. They are not known to be wrong. They are known to be unrecognisable,
and that list is the cheapest possible worklist for whoever reads them:

    awk -F'\t' '!/^#/ && length($3)<12' tools/citations.lock

**What.** A checker that fails the build when a `file:line` into `../Phosphor` no longer
points at what it claimed.

**Why.** `CLAUDE.md`'s rule is that a fact about Phosphor is extracted, never retyped, and
that where extraction is impossible the source is cited with a line number. On 2026-09-16
sixteen of those citations, in eight files, pointed at the wrong lines: the sibling file had
grown by about sixty lines and nothing in either repository could notice. The worst of them,
cited in seven places for "the lexer has no keyword table", had become the backslash-escape
table inside a string literal. They were found by accident.

**And the same day produced a second instance of the same shape** with no line numbers in
it at all: `CLAUDE.md` explained the no-BOM rule by saying a BOM is a lexical error on line
one, which the console host has stripped since its first commit. The rule was right and the
reason had never been true of that path. A checker cannot catch that one -- but it is why
the item is worth more than its mechanism, and why the commit that closes it should say
what class of thing it does NOT catch.

**Done when.** The checker is green on the current tree, red when a citation is made stale,
skipped cleanly when `../Phosphor` is not there, and run by both build scripts beside the
two `--check` gates that already exist.

**Touches.** `tools/`, `scripts/build.ps1`, `scripts/build.sh`, `docs/building.md`,
`CLAUDE.md`.

---

## 28. Reading text back, on the machine that cannot

**FIRST HALF DONE 2026-09-17. SECOND HALF BLOCKED, and it is not mine to unblock.**

**Reading text back: done, through AT-SPI, and it needed no new package.** The item
said the route must not want anything the VM does not have without Andre's say-so.
It did not have to: `gi` with the `Atspi` typelib was already installed, and
`/usr/lib/x86_64-linux-gnu/gtk-2.0/modules/` already held `libgail.so` and
`libatk-bridge.so`, which are the two halves a GTK2 program needs to describe
itself. The answer was installed and nothing had asked it. `xdotool`, `xclip`,
`xsel` and `python3-xlib` are all absent, so every route that suggests itself first
was the wrong one.

`tools/lane/readtext.py` reads any control's text; `lane-linux.sh` gains `text
<needle>` and `say <name>`, and `steps-readtext-linux.txt` + `readtext.bas` are the
case. It asserts on the Output pane's actual transcript -- `lane-readtext-ok` and
`total=42`, the program's own words -- which is the question Windows has asked
through `WM_GETTEXT` since 2026-09-16 and this side could not.

**THE FAILURES ARE COUNTED AND THE SCRIPT EXITS NON-ZERO**, which is the part that
makes it a test rather than a printout. Proven by failing: the first run spelled the
key `{F9}` in the Windows way, `xdrive` said `no keysym called {F9}`, nothing ran,
and the two output assertions went red -- the first time anything in this directory
could say so without a person looking at a picture.

**AND IT CLOSED A GAP THE ITEM DID NOT ASK FOR.** `CLAUDE.md` has said since
2026-09-16 that the gtk2 menu bar "answers neither a synthetic click nor F10
navigation from XTest and so could not be driven at all". True of XTest, and not of
AT-SPI: a menu item exposes one action and doing it opens what a click would open.
`menu <name>` is the verb, and the case proves it by invoking Help > About and then
reading the dialog that opened, by its words. The obstacle was never the editor.

**The `xvfb-run` half is blocked on a package and a password.** `xvfb-run` is not
installed on the VM (`apt-cache policy xvfb`: `Installed: (none)`), and `sudo -n`
there fails, so it cannot be installed without Andre. That clause is one of the two
item 1 never closed and it is still open; so is its sibling, a `--release` build on
Linux. Until then, "green on Linux" means green in a real Xwayland session, which is
not quite the same claim -- which is the sentence `CLAUDE.md` has carried since
2026-09-10 and which this item exists to settle.

**What.** A way for the Linux lane to read what a control SAYS, and a single run of
`scripts/build.sh` under `xvfb-run`.

**Why.** `tools/lane/lane-windows.ps1` asserts on TEXT -- it sends `WM_GETTEXT` and reads
the transcript back, which is how the REPL's whole conversation was checked. The gtk2 side
has no equivalent: keys go in through XTest and frames come out through `xwd`, so every
assertion there is a screenshot a person has to look at. That is why the Linux half of the
REPL case checks the process table and the Windows half checks the words.

The second half is the last thing on the five-gate bar that has never been watched. Both
build scripts have run green on both machines, and the `xvfb-run` branch of `build.sh` --
the one CI uses -- has been read and never executed by anyone here. A virtual framebuffer
and a real session are not quite the same thing, and that sentence has been in `CLAUDE.md`
since 2026-09-10 without being settled.

**Done when.** One lane case on Linux asserts on the TEXT of a control rather than on a
picture of it -- through AT-SPI, or by reading the X selection after a select-all and copy,
or by any route that does not need a package the VM does not have without Andre's say-so --
and `xvfb-run -a bash scripts/build.sh` has been run once, with its output recorded here or
in `docs/building.md`, green or not. That second half is one of the two clauses item 1
never closed; the other, a `--release` build on Linux, belongs with it.

**Touches.** `tools/lane/`, `docs/building.md`, `CLAUDE.md`.

---

## 29. The 3.5 microsecond identifier

**What.** `uphosphorlang` classifies a word by asking six sorted `TStringList.Find` indexes
in turn -- operator, literal, keyword, then each of the three built-in tiers. A word that is
in none of them, which is what a user's own names are and therefore what most words in a
program are, visits all six. Measured 2026-09-17 at `-O3`: **3.5 us for a miss, 0.9 us for a
hit**, against 0.04 us for the `LowerCase(Copy(...))` that precedes it.

**Why it matters, and it is not folding.** Item 19 measured a keystroke at the top of a long
file at 12.45 us per line and found `ScanFoldLine` to be 4% of it. Most of the rest is this:
two identifiers on a line, most of them misses, is roughly 7 us. It is paid on every line of
every rescan, on every file open, and on every scroll -- not only on the cascading keystroke
item 19 was about. Nothing today misses item 19's threshold, so this is a lever and not a
defect.

**The shape of the fix, and its hazard.** One index instead of six, holding the kind
alongside the word; and a cheaper compare than `AnsiCompareText`, which is what makes each
of the ten probes in a binary search cost about 100 ns. Both belong in
`tools/gen-keywords.py`, because `uphosphorlang.pas` is GENERATED and hand-editing it is
forbidden. **The hazard is that a classification regression is invisible**: a keyword that
stops being found is painted as an identifier, which no build catches and no screenshot
shows. So the done-when has to include a check that every word in every table still
classifies as its own kind -- all 1198 of them, from the tables themselves, not a sample.

**Done when.** The generator emits the new index, `--check` still passes, every word in
every table is verified to classify correctly by `phosphoridetest`, and
`phosphoride --measure-typing` is re-run and the per-line number is quoted here before and
after.

**Touches.** `tools/gen-keywords.py`, `src/core/uphosphorlang.pas` (generated),
`tests/phosphoridetest.lpr`.

---

## What is deliberately not on this list

**Linking the Phosphor engine into the editor.** Never. `src/phosphoride.lpr:5-10` states
the requirement: a script that loops forever, exhausts memory or faults the interpreter must
take its own process down and leave the editor holding the user's unsaved work. It is "the
one design decision the rest of the program is not allowed to trade away for convenience",
and no item above may be implemented by relaxing it.

**Heaptrc in the Default build mode.** Removed on 2026-09-10, and it stays removed: `-gh`
writes its leak report to stdout at exit, a Windows GUI-subsystem binary has no stdout, and
the process hangs on exit instead of reporting. A leak-checking build is a console build run
from a console. That is a procedure, not a roadmap item.

**DAP.** Not a rejection. `src/core/udebugproto.pas:18-26` says why PDBP is first -- DAP's
framing is HTTP-style headers, its message set is large, and the half that has to be written
in Free Pascal inside the phosphor host is the half that pays for that -- and it says that
PDBP's message names are DAP's, so a bridge later is a rename rather than a redesign. It
becomes worth doing the day PhosphorIDE is not the only client. Nothing above should make it
harder.

**A copy of the language reference in this repository.** Help points at the Phosphor
repository's documents on purpose: "a copy of a reference for a language that is still
moving is a copy that lies" (`src/umainform.pas:266-270`).
