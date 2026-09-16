# Two debts the Phosphor debugger owes, measured 2026-09-16

**This document describes work in the OTHER repository** — `AndreMurtaX/Phosphor`, the
engine — and it lives here for the reason
[`phosphor-engine-work-order.md`](phosphor-engine-work-order.md) gives: the ask is the
editor's half of a two-repository contract, and a contract kept only in the repository
that must satisfy it tends to be edited into agreement with whatever was built.

Both were found while building PhosphorIDE's debugger, both were **measured by speaking
PDBP to the host with no editor involved** (`tools/lane/pdbp-probe.py`), and the
mechanism of each was then read in the Phosphor sources rather than guessed. Neither
changes the wire format: PDBP is unchanged and both ends stay conformant.

**BOTH FIXED on 2026-09-16, in Phosphor `fce3db1`**, the same day they were written
up, and measured from this side afterwards: a breakpoint on the first executed
statement fires once, and a three-deep recursion reports `4, 7, 7, 7, 11` where it
used to report `4, 0, 0, 0, 0`. The editor needed no change for either.

The document is kept because the MECHANISM of each is worth more than the fact that
they are gone, and because two of the three things it got right are the kind that
recur: a mechanism manufactured for internal bookkeeping quietly consuming something
user-visible, and a limitation recorded in prose outliving the reason for it by a
year. The ask below is unedited.

---

## Debt 1 — a breakpoint on the first executed statement is answered installed, and never fires

### What happens

`setBreakpoints` answers `lines: [N]`, so the editor draws the mark as armed; the
program then runs past it to completion. Every other line in the same file works.

Measured against `bin/phosphor.exe` on 2026-09-16, `stopAtEntry` false unless noted:

| fixture | first executed statement | asked | installed | stops reported |
| --- | --- | --- | --- | --- |
| `boom.bas` | line 1 | `[1]` | `[1]` | `exception@4` |
| `boom.bas` | | `[2]` | `[2]` | `breakpoint@2`, `exception@4` |
| `boom.bas` | | `[1, 2]` | `[1, 2]` | `breakpoint@2`, `exception@4` |
| `boom.bas`, `stopAtEntry: true` | | `[1]` | `[1]` | `entry@1`, `exception@4` |
| `lane345.bas` | **line 2** (line 1 is a `rem`) | `[2]` | `[2]` | *(none)* |
| `lane345.bas` | | `[9]` | `[9]` | `breakpoint@9` |
| `lane345.bas` | | `[2, 9]` | `[2, 9]` | `breakpoint@9` |

**It is not line 1. It is the first executed statement, whatever line carries it** —
`lane345.bas` opens with a `rem` and loses line 2 instead. The `stopAtEntry: true` row
is the tell: that boundary *is* reached and *is* polled.

### Why, read rather than guessed

Three sites, in the order they act:

1. `host/console/phosphor.lpr:1774-1775` — the `launch` handler keeps what the editor
   asked in `FEditorEntry` and then sets `FStopAtEntry := True` **unconditionally**.
   Its own comment says why: arming with stop-at-entry is how the socket thread gets a
   safe moment to take `FRunVM`, because the engine offers no thread-safe way to find
   the running VM from outside.
2. `engine/PhosphorVM.pas:4127-4162` — inside `DebugPoll` the entry test runs first and
   sets `stop := True`; the breakpoint test that follows is guarded by
   `if (not stop) and (Length(FDbgLines) > 0) and DebugLineArmed(ALine)`. At the first
   boundary the reason is therefore **always** `srEntry`, and the armed line set is
   never consulted there.
3. `host/console/phosphor.lpr:1884-1891` — seeing `srEntry` with `FEditorEntry` false,
   the host takes the VM pointer, sets `FState := dbgRunning` and `Exit(daRun)`:
   it resumes without a word. The user's breakpoint went with it.

Each of the three is right on its own. The defect is that the entry stop the host
invented for its own bookkeeping is allowed to consume a boundary the user asked to
stop at.

### The fix this asks for

**In the host, at the silent resume.** Before `Exit(daRun)`, ask whether `ALine` is in
the armed set the editor sent (`FBreaks`, the same array `Arm` copies from); if it is,
do not resume — fall through and report `stopped` with reason `breakpoint` at that
line, exactly as any other boundary would.

That keeps the fix where the problem was created. The alternative — making the
breakpoint test in `DebugPoll` independent of the entry test, and preferring
`srBreakpoint` when both are true — changes a documented precedence for **every** host,
including the terminal debugger, to repair something only the socket host does. If it
is taken anyway, `engine/docs` and the seam's contract have to say the new precedence,
and the terminal debugger's `--stop-at-entry --break N` on the same line has to be
re-checked.

One case the fix must get right, and it is the reason `stopAtEntry` is in the table
above: when the editor **did** ask for an entry stop and a breakpoint is armed on that
same first statement, exactly **one** `stopped` event may be sent. Two would make the
editor look as though it stopped twice for one statement — which is the defect
`phosphor.lpr:1497-1509` already records having fixed once, for re-arming mid-run.

### How to know it is fixed

`tests/debug_protocol_test.py`, which already pins this protocol:

- a breakpoint on the first executed statement fires **once**, with reason
  `breakpoint`, and the program then continues normally;
- the same, on a file whose first line is a `rem` — the breakpoint belongs to the first
  **statement**, not to line 1;
- `stopAtEntry: true` plus a breakpoint on that same statement reports exactly one
  `stopped` event, and the test states which reason it is and why.

---

## Debt 2 — `stackTrace` gives a line only to the innermost frame

### What happens

Stopped three calls deep in a recursion, the reply is:

```json
{"index":0,"name":"down","path":"…/deep.bas","line":4}
{"index":1,"name":"down","path":"…/deep.bas","line":0}
{"index":2,"name":"down","path":"…/deep.bas","line":0}
{"index":3,"name":"down","path":"…/deep.bas","line":0}
{"index":4,"name":"(main)","path":"…/deep.bas","line":0}
```

The names and the depth are right; `variables` works for every one of those frames
(`frame: 3` returns `n = 3`). Only the line is missing, which is what a call stack is
mostly **for** — a pane can list the callers and cannot take you to any of them.

The host says so itself, at `host/console/phosphor.lpr:1565-1569`: *"Only the innermost
frame has a line this host can name: the VM keeps the boundary it stopped at, not a
return line per frame."*

### Why that sentence is now too pessimistic

**The data is already recorded.** `TCallFrame` (`engine/PhosphorVM.pas:177`) carries
`CallerStmtPC`, written at every user-function call from the caller's live statement
boundary (`:3208`, `FFrames[FFrameSP].CallerStmtPC := stmtPC`) so that a fault after the
call returns can resume in the caller. `FProg.Instr(pc).Line` turns any pc into a line.
Nothing new has to be stored and no hot path is touched: this is a read, at the moment
a stopped editor asks a question.

### The fix this asks for

**Engine** — one accessor beside the existing ones (`DbgFrameFunc` is at
`engine/PhosphorVM.pas:3751`):

```pascal
{ The line in the CALLER from which frame AFrame was entered. -1 when there is no
  such frame, or when the frame carries no caller boundary (:4542 sets -1). }
function DbgFrameCallerLine(AFrame: Integer): Integer;
```

**Host** — in `DoStackTrace` (`host/console/phosphor.lpr:1538`), where the walk already
runs `for i := ADepth - 1 downto -1`:

```
line for activation i  :=  ALine                      when i = ADepth - 1
                           DbgFrameCallerLine(i + 1)  otherwise
```

**The off-by-one is the whole point.** A frame stores the line of *its own caller*, so
the line where activation `i` is standing is the `CallerStmtPC` of the frame `i` called
into — `i + 1`, not `i`. `(main)` is `i = -1` and takes `DbgFrameCallerLine(0)`; when
`ADepth = 0` main is itself the innermost and takes `ALine`, which the same rule already
gives.

A frame whose line still cannot be named must keep reporting **0**. The editor reads 0
as "no line" and leaves the cell empty rather than printing a location; it must never
start meaning line zero.

### How to know it is fixed

In `tests/debug_protocol_test.py`, against a recursion at least three deep:

- every frame carries a **non-zero** line, and each is the line of its own call site —
  in a self-recursive function that is the same line for the inner frames and the
  outermost call's line for `(main)`, which is what makes the assertion meaningful;
- a stop at top level with no calls open still reports one frame, `(main)`, with the
  current line;
- a `gosub` does not add a frame (already true, and worth keeping asserted next to
  this).

---

## Do not

- **Do not change the wire format.** Both debts are behaviour behind a contract that is
  already agreed and already implemented on both sides.
- **Do not make `setBreakpoints` refuse a line it cannot bind.** The installed set is
  the protocol's only verified/unverified marker and the editor draws the difference;
  refusing would remove the marker along with the problem. (`StoppableLines` is already
  filtering correctly here — both lost breakpoints were reported installed because they
  genuinely are stoppable statements.)
- **Do not remove the always-arm-with-entry trick** without replacing the way `FRunVM`
  is captured. `phosphor.lpr:1868-1874` says what that moment is for.
- **Do not paper over debt 2 in the editor.** Finding a function's header by searching
  the source for its name is an invented location, and PhosphorIDE deliberately does
  not do it.

---

## Keeping the two repositories in step

Nothing is needed on the editor side when these land, which is the test of whether the
contract was right:

- the call-stack pane already leaves the Line cell **empty** for any frame reporting 0
  and will show real lines the moment they arrive; its once-per-session note about
  callers having no line simply stops appearing
  (`src/umainform.pas`, `TFrmMain.DebugStack`);
- a breakpoint on the first statement already draws armed, because the editor believes
  the installed set — so the fix is invisible on this side except that the program now
  stops.

What to strike here when they do: the two bullets under **item 10** in
[`roadmap.md`](roadmap.md), and the two matching entries in
[`debugger-lane.md`](debugger-lane.md) under *What the host still owes* and in
`CLAUDE.md` under *Stepping*.

Reproduce either debt from this repository with `tools/lane/pdbp-probe.py` and the
fixtures beside it — no editor, no window, one process and a socket.
