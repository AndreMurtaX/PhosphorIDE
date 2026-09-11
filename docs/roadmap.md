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
- `bin\phosphoridetest` green: 147 checks, exit code 0.
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
  identifier as it is scanned (`engine/PhosphorLexer.pas:392`), so `PrintLn` and `println`
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

**What.** A list of the `function` definitions in the active buffer, and F12 on a call
jumping to its definition.

**What makes it tractable, and what makes it a trap.** `function` and `endfunction` are
keywords by **position**, not by lexing: Phosphor's lexer has no keyword table at all, and
every keyword reaches the parser as an ordinary identifier
(`src/core/usynphosphor.pas:24-31`, citing `engine/PhosphorLexer.pas:385-408`). A scanner
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
`tests/phosphoridetest.lpr`, `src/phosphoride.lpi`.

---

## 16. An integrated REPL pane

**What.** A pane that runs `phosphor` with no arguments and feeds it a line at a time. A bare
`phosphor` is a REPL whose variables and functions persist across lines, which is the one
thing Run cannot offer: Run hands the host a **file**
(`EnsureSavedForRun`, `src/umainform.pas:715`) and every run starts from nothing.

**Most of it exists.** `TPhosphorRunner` already spawns, reads both pipes on their own
threads, and writes to the child's stdin (`SendInput`, `src/core/uphosphorrun.pas:418`); the
input box beside the output pane already feeds `INPUT` and `LINE INPUT`; and `uphosphormsg`
already recognises the REPL's own diagnostic shape -- `error: <msg>`, no prefix, no path, no
line -- as `pmkReplError`, and correctly refuses to treat it as a jump target.

**Two things will bite, and both are known now rather than after the fact.**

- **The prompt arrives, but it is not a line, and the pane must know that.** The REPL
  writes `phosphor> ` with no newline (`Phosphor host/console/phosphor.lpr:1143`), and the
  runner already handles that case: `DrainTimer` counts drains in which a stream produced
  nothing and `FlushPrompt` emits the unterminated tail after two of them
  (`src/core/uphosphorrun.pas:354-365`), marked `ACompleteLine=False`; `RunnerOutput`
  (`src/umainform.pas:906`) already appends such a fragment to the pane and already
  refuses to hand it to `uphosphormsg`, because a parser fed half of
  `phosphor: x.bas:2: unexpected token` finds no error at all. So the prompt will arrive,
  about 80 ms late, which is invisible. What is untested is the whole path: no check and
  no run has yet driven a child that prompts, so the two-tick threshold is a reasoned
  number rather than a measured one, and this item is where it first gets exercised.
- **A REPL nobody closes never exits**, and on Windows it holds a lock on its own
  executable. That is a recorded trap in the Phosphor repository, and it weighs more here
  because the editor starts the process on the user's behalf. The pane must `CloseInput` and
  then terminate the child when the pane closes, when the editor closes, and when the host
  path changes -- and `FormCloseQuery` (`src/umainform.pas:359`) must count a REPL child the
  way it already counts a run.

**Done when.** `println 6*7` shows 42; `x = 1` then `println x` shows 1, which is the
persistence that justifies the pane; a multi-line block shows the `     ...> ` continuation
prompt; `error:` lines are styled as diagnostics and are not offered as jump targets;
closing the pane leaves no `phosphor` process behind, verified by process name on both
platforms; and the ordinary Run path's line handling is unchanged with its checks still
passing.

**Touches.** `src/core/uphosphorrun.pas`, `src/umainform.pas`, `src/umainform.lfm`,
`tests/phosphoridetest.lpr`.

---

## 17. Folding

**What.** Collapsible `if`/`endif`, `for`/`next`, `while`/`wend`, `select`/`endselect`,
`function`/`endfunction`.

**Why it is last, and why it may not be worth doing at all.** Two costs, both real, both
already written down in `docs/architecture.md` and in the highlighter's own header.

- **It changes the highlighter's base class and its cost model.** `TSynPhosphorSyn` derives
  from `TSynCustomHighlighter` and carries **no range state on purpose**: Phosphor has no
  block comment and no multi-line string -- a string literal reaching a newline is the hard
  lexical error `unterminated string` (`engine/PhosphorLexer.pas:361-366`) -- so every line
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

If it is done anyway: build it on the structural scanner from item 15 rather than by
promoting the highlighter, and accept that it will be wrong on the same rare programs the
outline is wrong on -- with the same justification, that a fold is visible and reversible.

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
