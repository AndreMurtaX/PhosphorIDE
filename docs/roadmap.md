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

## The bar, for every item on this list

The sibling repository's rule holds here: nothing is done on a claim.

- `powershell -NoProfile -File scripts\build.ps1` green, which means `lazbuild -B` with
  **zero errors, zero warnings and zero notes** -- the script greps lazbuild's text as well
  as its exit code, because lazbuild has answered 0 where the compiler did not.
- `bin\phosphoridetest` green: 545 checks, exit code 0.
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
- **The honest path survives the happy one.** `ActDebugWhy` (`src/umainform.pas:1132`) still
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
  writes `phosphor> ` with no newline (`Phosphor host/console/phosphor.lpr:3017`), and the
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
