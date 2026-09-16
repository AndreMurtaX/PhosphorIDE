# The debugger lane — what is built, what is next

**Written 2026-09-15, from the engine side.** Two layers landed here today and the
ground under this repository moved; this file is the handoff. Read it before the
Debug menu, because four documents in this repo described an engine that no longer
exists and three of them are the first thing anyone reads.

---

## What changed underneath, and why it matters on the first turn

`README.md`, `CLAUDE.md`, `docs/architecture.md` §6, `docs/building.md` and
`docs/debug-protocol.md` all stated, in the present tense, that a step debugger was
impossible: the `BREAKPOINT` seam must never block, the VM has no step API, the frame
stack is private, the console host installs no seam. **All four were true when written
and none is true now.** They are corrected or struck as of this commit, but an agent
that had already read them would have gone off to solve a problem nobody has.

What Phosphor has today, all of it exercised by a 43-assertion contract test in that
repository (`tests/debug_protocol_test.py`):

| | |
| --- | --- |
| a seam that **returns an action** and may block | `TPhosphorDebugProc` → `TPhosphorDebugAction` |
| arm a breakpoint set, and re-arm it **while stopped** | `ArmDebug`; fixed 2026-09-15 — it used to reach every VM except the running one |
| the four step actions | `daStepInto`, `daStepOver`, `daStepOut`, `daRun` |
| frame and variable reads | `DbgFrameDepth`, `DbgFrameFunc`, `DbgLocal`, `DbgGlobal` |
| **pause a running program** | works as of 2026-09-15; it was advertised `true` and could not fire for a year |
| `setBreakpoints` answers the set it **installed** | a line with no statement comes back absent, which is the verified/unverified marker |
| a malformed frame does not kill the debuggee | a missing `lines` key, a string, a null or a nested array are all survived |

---

## What is built on this side

Both are tested headless — no widgetset, no display, no `phosphor` binary — and both
are in the 183 checks `bin/phosphoridetest` runs.

**`src/core/udebugtransport.pas`** — the loopback listener. Binds `127.0.0.1:0`, reads
the ephemeral port back, accepts one connection on its own thread, reads on another,
and hands whole lines to the main thread through `Poll`.

**`src/core/udebugsession.pas`** — the session. Sequence numbers matched to requests,
the six states actually driven, protocol-version refusal, desync → report and
disconnect, socket close → end of session. Commands refuse locally when the state
forbids them.

**How they fit together, in the order the caller uses them:**

```pascal
Port := Session.BeginListen(FilePath, Lines, StopAtEntry);   // 0 means it failed
// spawn `phosphor debug --port <Port> <FilePath>` through TPhosphorRunner
// then call Session.Poll() on a timer; the handshake runs itself
```

`BeginListen` does **not** spawn anything, deliberately: this repository's rule is that
every interaction with the host is a process and asynchronous ones go through
`TPhosphorRunner`, so a unit that spawned its own would be a second way in. It also
keeps both units testable with no display, which is what let the state machine be
pinned before any menu existed.

Verified end to end against a real host through exactly these units: handshake, only
the stoppable line installed out of three asked for, stopped at the armed line with
reason `breakpoint`, `Pause` correctly refused while stopped, variables read, three
passes, exit 0, back to idle.

---

## What happened — all five steps, 2026-09-16

Every step below is built and was **driven against the real `phosphor debug --port`
host on Windows**, not reasoned about. The five bar conditions hold: `lazbuild -B`
clean at `-vewn`, `bin\phosphoridetest` 183 checks green, `--selftest` exit 0 under a
timeout, `gen-keywords.py --check` clean. Linux is the gap, and it is named at the end.

| step | verified by |
| --- | --- |
| 1. Start Debugging, one breakpoint, one stop | stop on line 10 of a 14-line fixture, navy stripe, `GotoSource`, status bar `debug lane345.bas ...` |
| 2. The variables pane | `a=5 b=10 s=0` local, `total=5` global, locals above globals, four columns streamed |
| 3. Hollow marks | a breakpoint on a blank line came back absent from the installed set and is drawn **grey**; the armed one stays maroon |
| 4. Step over / into / out | 10 → 11 → 12 by F8, into `add` at line 5 by F7, back out by Shift+F8 |
| 5. Leaving a session honestly | `> stopped at line 4 (exception): division by zero`, then one ending line, no listening socket and no orphan child left behind |

The prediction in step 4 held exactly: stepping does land on the `function add(a, b)
local s` header line, and it is not a bug.

### What the first cut got wrong, and a critic found

Four adversarial reviews of step 1 ran before step 3 was verified; three of the four
independently named the same defect, and it was the worst one on the list.

- **The stripe was a memory, not a state.** `FDebugLine` was written on every stop and
  cleared only when the session ended, so from the moment the user pressed Continue the
  editor painted "execution is here" on a line the program had already left —
  indefinitely, on a program blocked at `line input`, and after *every step* once step 4
  landed. It now clears in `DebugStateChanged` whenever the state is not `dsStopped`,
  and the screenshot of a program blocked at `input` with no stripe anywhere is the
  proof.
- **Tools > Preferences > OK stranded the debuggee.** Accepting the dialog re-resolves
  the host, which called `TDebugSession.Probe`, every path of which ends at `dsIdle` —
  so the editor declared there was no session while the child was still alive and
  stopped. `Probe` now refuses while a session is in flight and says so.
- **The session ended in three places and none of them knew about the others.**
  `EndDebugSession` is now idempotent and driven from the state; `RunnerFinished` reads
  a `FDebugLive` flag instead of asking whether a timer is enabled.
- **The loopback listener leaked** — one bound port and one parked accept thread per
  session, for programs that merely finished. `HandleDisconnect` now asks for the
  teardown, and `TDebugSession.Poll` performs it, because both callbacks run inside the
  transport's own `Drain`. The same deferral fixes a use-after-free in `Desync`.
- **A breakpoint set during a session was never re-sent**, though both ends support
  re-arming. The same defect as `TrackEdit` having no caller, found the same way.
- **The stop was announced above the output that produced it.** Two timers, no ordering.
  The debug tick now drains the child's pipes before it reads the socket.
- **`Continue` had no shortcut and its mnemonic collided with Step Over's.** It is
  `&Continue` on **F6** — not F9, which runs without the debugger here, and one key
  cannot do two things.
- **"Why is stepping unavailable?" answered with an empty dialog** on a host where it
  *is* available. The menu item is hidden when the answer would be nothing.

Two more were found by driving rather than by reading, and are recorded as traps in
`CLAUDE.md`: a toolbar button's caption is a real Alt accelerator that shadowed the
menu bar (**Alt+T killed the running program** instead of opening Tools), and
`Process.MainWindowHandle` is not the form.

### What the host still owes

Measured on 2026-09-16 by speaking PDBP to `phosphor debug --port` directly, with no
editor involved:

- **A breakpoint on the first statement is reported installed and never fires.**
  `setBreakpoints lines:[1]` answers `lines:[1]`; the program runs to completion. This
  undercuts step 3 in the one case the editor cannot detect — the installed set is the
  only marker the protocol has, so line 1 is drawn armed and behaves dead.
- **An exception stop does not linger.** The `stopped/exception` event and the socket
  close arrive together, so the editor's read-only gating around a terminal stop is
  correct and unobservable. It was also, before this commit, being thrown away:
  `RunnerFinished` tore the session down before the last frame was read, and the editor
  never said the program had stopped at all. It now polls once more first.

### Still unmeasured

**Linux.** Nothing in this lane has been run under gtk2. The transport is `fpSocket`
and portable, the timers are LCL, and the one platform-specific thing in the new code
is `CompareFilenames` — which is there precisely because it knows the difference. That
is an argument, not a measurement, and this file does not treat the two as the same.

---

## What is next, in order

### 1. Start Debugging, one breakpoint, one stop

`umainform.pas`, `umainform.lfm:476-503`. Six Debug actions carry `Enabled = False`
and **no `OnExecute` at all** — `ActDebugStart` (Shift+F9), `ActStepOver` (F8),
`ActStepInto` (F7), `ActStepOut` (Shift+F8), `ActContinue`, `ActDebugStop`. Flipping
`Enabled` today gives live shortcuts that do nothing.

`ActDebugStart` gets the first handler: save if configured, `BeginListen`, spawn
through the existing `StartHost` / `TPhosphorRunner` with
`['debug','--port',N,path]` (`umainform.pas:868-905`), then drive `Poll` from a
40 ms `TTimer`. On `stopped`, paint the line through `EditorSpecialLineMarkup`
(`:1383-1400`) and navigate with `GotoSource`.

Two things to decide in five lines: a line that is both a breakpoint and the current
stop reads as the **stop**; and `RefreshDebugActions` (`:1287-1308`) has to key on
`State` as well as `Available`, and clear the stale hints it never clears today.
`ActionList1Update` (`:1507-1539`) deliberately does not touch these six, so nothing
will fight it.

**Reuse `TPhosphorRunner` for the pipes**, not just the spawn. An editor that holds the
socket but not the child's stdout stalls the debuggee behind a full pipe buffer, with
no protocol symptom at all — the session simply stops progressing.

### 2. The variables pane — the first usable moment

A third tab in `PagesOutput`. No codec work needed: `ParseVariables` already decodes
name / value / kind / scope.

**The editor formats nothing** — the host renders each value as `PRINT` would. Keep
locals above globals and labelled: in this language an undeclared name inside a
function **is** a global, so blurring the two teaches the user something false. Key the
pane by a frame index even though it is always 0 today; that one integer is what stops
this pane being rewritten when the stack pane lands.

After this step a person can set a breakpoint, press Debug, stop on it and read their
variables. Everything before it is scaffolding; everything after is refinement.

### 3. Hollow marks for breakpoints that will never fire

`ubreakpoints.pas` holds a sorted line array and nothing else. The installed set now
arrives on `OnLinesInstalled`; a mark not in it should be drawn hollow. **Keep the
flags out of `TBreakpointSet`** — a parallel array in the form — so that unit stays
LCL-free and headless.

Ask for a set containing a `rem`, a blank line and an `endfunction` and watch all of
them come back absent; today the gutter would paint five solid marks where one fires.

### 4. Step over / into / out

They work on the host already. Expect one report that is not a bug: stepping lands on
a `function f(n) local r` header line, because the compiler's jump over the function
body sits there.

### 5. Leaving a session honestly

`Continue` only in `dsStopped`. On `stopped{reason:'exception'}` show the event's own
`text` — that path **does** carry it, e.g. `division by zero` — and send nothing
further: a terminal state is read-only. `Stop` is a process kill through
`TPhosphorRunner`, deliberately, because `disconnect` while the program runs is never
answered.

---

## Traps, each one measured rather than reasoned about

- **A `TTimer` needs a widgetset.** `phosphoridetest` links the LCL and deliberately
  never creates one. Putting a timer inside `udebugtransport` killed that program the
  moment the transport was first exercised — the group header printed, nothing after
  it, exit 0, no summary. The timer belongs to the form.

- **Never emit an unterminated tail.** `uphosphorrun.pas:509-520` flushes a partial
  line after ~80 ms of quiet so a program ending in `PRINT` does not lose it. Copying
  that here hands half a frame to a JSON parser and ends the session as "not JSON".

- **A bare `#10`, never `LineEnding`.** CRLF on output is forbidden by the
  specification and is the single easiest way to break a conformant host.

- **fcl-net's `TInetServer` cannot serve this design.** `Bind` never calls
  `fpGetSockName`, so a bind on port 0 leaves `Port` reading 0 and the number the child
  needs is unobtainable; and `Accept` closes the socket it just accepted unless
  `StartAccepting` was called. Unit `Sockets` directly, which also does the Winsock
  startup in its own initialization.

- **A one-line loop body is a test shape, not a curiosity.** A regression on the engine
  side made a three-pass loop report two stops, and only when the body was a single
  line — 39 protocol assertions, both byte-exact suites and ten gates went straight
  through it, because every fixture's loop body had more than one line. If you write a
  fixture, write that one.

- **Do not copy `tests/debug_protocol_test.py:141`.** It compares the reply to the
  *request*, which is exactly why the requested-versus-installed defect survived a green
  suite for a year.

---

## What is deliberately not in scope

**`evaluate`.** The capability arrives `false`, the host refuses the command, and the
editor should grey the box rather than build one. It needs a side-effect-free
expression entry point that does not exist in the engine at all — roughly 750 lines
there — and none of the five steps above wants it. A watch window is the step after a
working debugger, not part of one.
