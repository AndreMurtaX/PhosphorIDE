# Work order for the Phosphor engine

**This document describes work in the OTHER repository** -- `AndreMurtaX/Phosphor`, the
engine -- and it lives here because this is the repository that needs it. PhosphorIDE's
Debug menu is greyed out, and every item in Part B is a reason why.

It is kept on this side for the same reason `docs/debug-protocol.md` is: the wire format
and the ask are the editor's half of a two-repository contract, and a contract kept in
the repository that must satisfy it tends to be edited into agreement with whatever was
built. See [Keeping the two repositories in
step](#keeping-the-two-repositories-in-step) at the end.

**MOSTLY LANDED.** Parts A and B were taken up in the Phosphor repository on
2026-09-15 and the editor's half followed on 2026-09-16; `docs/debugger-lane.md` records
what each step was verified against. The document is kept unedited below, as the ask it
was, because the evidence in it is what made the case and because a work order rewritten
after the fact stops being one.

Two debts found while building the editor's half are **not** in it, because nobody knew
about them when it was written. They have their own document:
[`phosphor-debugger-debts.md`](phosphor-debugger-debts.md).

Original note follows. Nothing in this document has been applied. It is an ask, with
evidence attached.

---

You are working in the Phosphor BASIC repository. Read `CLAUDE.md` and
`docs/dev-agent-playbook.md` before touching anything; this order assumes the bar they
set and does not restate it.

Everything below was **measured against the shipped `bin/phosphor.exe` on 2026-09-10/11**,
or read from the source at the line cited. Where a claim says *measured*, a reproduction
is given -- run it first and confirm you see the same thing, because a fix aimed at a
defect that has since moved is worse than no fix. Where a claim is only read from the
source, it says so.

**Do not trust this document over the file.** Open the file. One recommendation that
reached me was wrong precisely because its author worked from a description of the engine
rather than the engine.

Two independent pieces of work follow. **Part A is correctness and can ship today. Part B
is the debugger.** They do not depend on each other; A is worth more per hour.

---

# Part A -- correctness, ordered by what it costs a user

## A1. An ON ERROR handler that never resumes abandons its activation

**This is the first thing to fix.** It is the only confirmed silent wrong answer with
side effects in the tree.

Reproduce, exactly (write to a temp directory, not into the repo):

```basic
function risky(n) local z
  on error goto h
  z = 1 / 0
  return 7
endfunction

println "start"
r = callfunc("risky", 1)
goto tail

h:
println "HANDLER"

tail:
println "appending one ledger row"
n = file_appendalltext("<temp>/ledger.txt", "ROW" + chr$(10))
println "append said " + str$(n)
```

Observed, with the shipped binary:

```
start
HANDLER
appending one ledger row
append said 1
appending one ledger row      <-- the tail ran a second time
append said 1
EXIT=0
```

and **two `ROW` lines on disk** from a program that appends one. Exit code 0.

A handler entered inside a function that never reaches `resume` walks off the end of the
program without unwinding the activation. A duplicated `print #` row, a duplicated HTTP
post, a duplicated ledger append -- and the program reports success, so no golden, no
gate and neither operating system can see it.

The direct-call form loses a statement instead of duplicating one: the rest of the
calling statement is silently dropped, also exit 0. Reproduce both.

**Where the repair belongs.** Your own compiler comment already says: *"closing it belongs
to the VM, which can see at fault time what this site cannot -- that a handler jump
crossed a frame boundary"* (`PhosphorCompiler.pas:725-727`). The VM holds both frame
depths it needs.

**Do NOT fix it at `AddGoto` in the compiler.** The first version of that guard refused
twelve measured-correct programs, which is why the discriminator there is deliberately a
bound and not an equivalence (`PhosphorCompiler.pas:710-712`).

**Smallest version:** one check at the point control would leave the program -- fall-through
past `FProg.Count`, and `opEnd` -- when a handler was entered and never resumed at a frame
depth other than the one it was installed at. Fault with a message naming the handler
label, the way an orphan `next` is already reported.

**Prove it** by removing the fix and watching the new negative assertion fail. The suites
that would catch a regression here are `tests/suite/54_onerror_reentrancy` and
`15_breakpoint_degrade`.

---

## A2. Overload resolution is a linear scan run 2^(int args) times

*Measured.* `TPhosphorRegistry.IndexOfKey` is `for i := 0 to FCount - 1 do if FKeys[i] =
AKey then Exit(i)` with no index (`PhosphorRegistry.pas:220-228`). `Resolve` enumerates
`for mask := 0 to (1 shl k) - 1` (`:363`), calls `IndexOfKey` once per mask (`:378`) and
builds a fresh key each time (`:373-377`). The VM calls `Resolve` per `opCall`
(`PhosphorVM.pas:2558`) with **no cache**. The full host registers ~1230 keys.

300,000 iterations of the same loop, shipped binary:

| program | time | per call |
| --- | --- | --- |
| `t = t + i * 2 - 1` (no built-in) | 476 ms | -- |
| `t = t + abs(i)` (1 numeric arg) | 2529 ms | **+6.8 us** |
| `t% = t% + min(i, 5)` (2 int args) | 6250 ms | **+19.2 us** |

A built-in call costs 5x the entire loop body without it; with two integer arguments,
13x. The 1-to-2-argument jump being ~3x is the `2^k` masks, each a full scan.

The part that stings: the penalty attaches to **the spelling the language reference
teaches** -- base-1 integer subscripts. Writing `i%` instead of `i` makes the loop an order
of magnitude slower and nothing says so.

**Smallest version:** a hash index from signature key to slot, maintained inside
`EnsureSlot` so the overwrite-by-signature rule falls out unchanged. `IndexOfKey` becomes
a dictionary lookup. Two free riders in the same function: hoist the `SetLength(key, ...)`
out of the mask loop (its length is constant across masks, so it is `2^k` allocations
where one would do), and skip the mask loop entirely when `k = 0`.

**Do NOT change overload resolution ORDER.** The tie-break -- fewest widenings, wildcards
only after an exact match fails -- is observable behaviour. The hash must make each probe
cheap and nothing else. Byte-exact green across every corpus is the proof that nothing
moved.

---

## A3. `str$` loses Double precision with no escape hatch

*Measured.* `vkDouble: Result := FloatToStr(V.Num, InvariantFS)` -- FPC's 15-significant-digit
default (`PhosphorValue.pas:632`). A loop computing 200 Doubles (`x = x*1.0000001 +
0.000000123`) and comparing `val(str$(x))` to `x` reports **196 of 200 changed**.

`print #` then `input #` is the documented way to persist a number, and it alters every
computed value. The two values *print identically*, so no amount of reading output finds
it. There is no way out: `format$` does not offer a round-trip form.

**Smallest version:** in `ValToStr`, emit the shortest string that reads back as the same
Double -- format at 15 significant digits, and if `val()` of it does not compare equal, try
16 then 17.

**Derive the test from the property, not from a list of literals:** assert `val(str$(x)) =
x` over a swept range. A hand-picked literal list is exactly what let an earlier
finiteness patch pass byte-identical.

Expect golden churn: any test whose expectation contains a 16th or 17th digit changes.
Audit that churn rather than regenerating it.

---

## A4. A call without parentheses compiles, runs, and does nothing

*Measured.* This prints `code 2 / after bare: 2 / after call: 0`:

```basic
on error goto h
x = 1 / 0
h:
println "code " + str$(err())
err_clear
println "after bare: " + str$(err())
err_clear()
println "after call: " + str$(err())
```

The bare `err_clear` is compiled, executed, and does nothing -- in the error-handling
library itself, with no diagnostic. Phosphor's own convention is that empty parens mark a
call; a beginner arriving from another BASIC writes `cls`, `err_clear`, `g`.

`check-examples.py` cannot see it, because the block compiles.

**Smallest version:** ~10 lines at the expression-statement fallback in
`PhosphorCompiler.pas` (around `:2448`): record `FProg.Count` before `ParseExpr`, scan the
emitted range for an `opCall`, and if there is none, fail with
`'<name>' on its own does nothing -- a call needs parentheses: <name>()`.

This generalises the check the compiler already has for eleven contextual keywords to the
class it is an instance of.

---

## A5. An unterminated block reports a line that does not exist

*Measured.* A 3-line file:

```basic
let a = 1
if a = 1 then
  println "yes"
```

gives `phosphor: b.bas:4: expected 'endif'` -- line 4 of a 3-line file.

For an unclosed block the only actionable location is **where it opened**; the end of the
file is the one place the user cannot fix anything, and a line past the end is a
plausible-looking target, which is worse than none. PhosphorIDE clamps it before
scrolling, which is a workaround for a diagnostic that should not need one.

All seven block parsers already hold the line the block opened on.

**Smallest version:** seven one-line changes, e.g.
`Fail('expected ''endif'' -- the ''if'' on line ' + IntToStr(ln) + ' is never closed', ln)`.
While `ParseFor` is open, three more lines are worth spending: if the token after `next`
is an identifier, say that this loop's variable does not belong there.

---

## A6. The dictionary is a linear array

*Measured.* `TPhosphorDict.IndexOf` is `for i := 0 to Count - 1 do if Keys[i] = AKey then
Exit(i)` (`PhosphorDictLib.pas:47-53`), called by `SetVal` on every set (`:58`) and by
`Remove` on every delete. Inserting n distinct keys with `dict_set@`: **n=8000 352 ms,
n=16000 956 ms, n=32000 3169 ms** -- quadratic.

Every other container in the language is honest about its cost: the language reference
already warns that string building is quadratic and points at buffers. The dictionary
carries no such warning and is described as a map keyed by string, which is universally
read as O(1).

**Smallest version:** keep `Keys` and `Vals` exactly as they are -- they *are* the
documented insertion order -- and add a private hash index beside them that `IndexOf`
consults.

**If that is judged too much for now**, the honest cheap half is one sentence in
`docs/function-reference.md` saying lookup is linear. A documented O(n) map is a design;
an undocumented one is a trap.

---

## A7. Two documentation defects found while measuring

- **`CLAUDE.md` may be carrying a stale OPEN warning.** It says gauntlet finding 7 --
  *"`resume next` on the LAST statement of a block leaves the block"* -- is OPEN. I tried
  three shapes (arithmetic fault as the last statement of a `for` body; a failing library
  call as the last statement of a `while` body; handler before and after `end`) and **all
  three completed every pass correctly**. Either it is fixed and the warning was not
  retired, or the shape is narrower than the text. Settle it: if fixed, delete the warning
  and the workaround advice it gives, because every author who reads it writes a
  contortion for something that may no longer happen.

- **`docs/language-reference.md:709-711` says a `breakpoint` "reports a frame to the host
  debugger".** It reports to nobody in the only shipped host -- see B0.

---

# Part B -- a real debugger in the engine

The goal is the traditional set: **breakpoints, step into, step over, step out, continue,
pause, call stack, variable inspection, stop-at-entry, run-to-cursor**. This section says
what each costs, in dependency order, and what is honestly out of reach in version 1.

The editor end already exists: `AndreMurtaX/PhosphorIDE` ships `src/core/udebugproto.pas`,
a tested codec for **PDBP**, a line-delimited JSON protocol specified in that repo's
`docs/debug-protocol.md`. Read it -- but note that **two of its claims about this engine
are wrong**, corrected in B2 and B1 below.

## The key fact that makes this cheap: `opStmt` already exists

The engine already emits a per-statement boundary opcode carrying the source line:

- emitted once per statement by `ParseStatement`:
  `stmtIdx := FProg.Emit(opStmt, 0, 0, FLex.Cur().Line);` (`PhosphorCompiler.pas:2049`),
  patched at `:2051` with the pc the statement ends at;
- its VM handler already records the exact triple a stepper needs
  (`PhosphorVM.pas:2256-2260`):

```pascal
opStmt:
  begin
    // Mark this clean statement boundary; a fault resumes from here.
    stmtPC := pc; stmtSP := FSP; stmtFrameSP := FFrameSP;
  end;
```

**The step hook goes inside that arm.** Not in the dispatch loop.

**PDBP is wrong about this and you should ignore it there.** Its "What the host is
missing" item 2 says the fix is to make the fetch-decode-execute loop notice when the
current instruction's line differs from the last. Against the bytecode this compiler
actually emits, that rule fires twice per iteration: disassembling a compiled
`for i = 1 to N / s = s + i / next` shows the loop's increment instructions carrying the
`for` line and the body carrying its own, so one Step Over would land on the `for` line
every iteration. The correct rule is **"stop at an `opStmt` whose Line differs from the
line the step began on, or whose FFrameSP is lower"**, and `opStmt` is the only place it
can be evaluated.

---

## B0. Wire `OnBreakpoint` in the console host -- half a day, ships alone

*Measured.* This prints exactly `after`, exit 0, nothing on stderr:

```basic
trace 1
x = 5
breakpoint "checkpoint", x, x*2
println "after"
```

The seam is nil in `host/console/phosphor.lpr`, with the exemption recorded at
`scripts/check-seams.py:98`.

**Do:** about fifteen lines in `phosphor.lpr` filling `OnBreakpoint`, writing one line per
fired breakpoint to **stderr** in the diagnostic shape the host already uses. Delete the
exemption line. Correct `docs/language-reference.md:709-711`.

**Why first:** no engine change, no seam design, no protocol, no socket. It makes the
language's only debugging statement do something, retires a recorded exemption in a small
commit instead of burying it in a large one, and writes the host-side value renderer that
everything later needs -- once, before anything depends on it.

stderr and not stdout, for the reason PDBP gives for not using stdout at all: a program's
output is its own.

Risk to existing goldens: none I could find. `tests/suite/15_breakpoint_degrade.bas` runs
under `phosphortest.lpr`, which stays exempt and installs no seam.

---

## B1. Name tables and read-only accessors -- no execution path touched

**PDBP's `variables` request is unimplementable today, and PDBP does not know it.** The
compiled program carries **no variable names at all**: `TProgram` declares `VarCount` and
`VarTypes` and no name table (`PhosphorOpcodes.pas:126-152`); `TUserFunc` declares
`Name, Entry, ParamCount, LocalTypes, RetType` and no local names (`:115-122`). The
compiler *has* them and throws them away -- `FVarNames` (`PhosphorCompiler.pas:74`) and
`FLocalNames` (`:84`) are compiler fields only.

**Do:**

- add `VarNames: array of String` to `TProgram` and `LocalNames: array of String` to
  `TUserFunc`; populate in `VarIndex` and the local allocator;
- **do NOT serialise them, and do NOT bump `PBC_VERSION`.** `PBC_VERSION = 1`
  (`PhosphorBytecode.pas:36`) and `LoadProgram` hard-refuses any other version (`:571-572`)
  -- a bump bricks every packed executable. `phosphor debug <file.bas>` compiles in-process,
  so `TProgram` has the names without the format being involved. `ValidateProgram` must
  then tolerate `Length(VarNames)` of either 0 (a loaded `.pbc`) or `VarCount` (a freshly
  compiled program); it asserts the parallel rule for `VarTypes` at `:395`, so decide this
  deliberately rather than copying;
- filter out the compiler's hidden temporaries -- `FHidden` (`PhosphorCompiler.pas:77`)
  counts compiler-generated globals such as a SELECT subject -- so a variables pane never
  shows them;
- add the read-only surface on `TPhosphorVM`: `DbgFrameDepth`, `DbgFrameFunc(i)`,
  `DbgLocal(frame, slot)`, `DbgGlobal(i)`, `DbgProgram`. All are valid only while the
  debug seam is on the stack; document that lifetime the way `ContainFaults` documents
  its own;
- **`TPhosphorEngine` does not keep a handle on the running VM** -- `Run` creates it as a
  local (`PhosphorEngine.pas:313, :324`). Add a private `FLiveVM`, set immediately after
  `ConfigureVM`, and cleared **in the existing `finally`**, not after the `if`, or an
  accessor called after the run reads a freed VM;
- add `function TPhosphorEngine.StoppableLines: TIntegerDynArray` -- a walk collecting
  `Instr(i).Line where Op = opStmt`. That is exactly the set of lines a breakpoint can be
  installed on, which is what PDBP's `setBreakpoints` response must report back.
  De-duplicate: `a = 1 : b = 2` produces two `opStmt` on one line.

The frame and global accessors **cannot avoid copying** a `TValue` -- it is a record with a
managed `Str` field. That is one refcount per variable per stop, not per instruction.

**Proves on its own:** a Pascal probe compiles a fixture and prints every global and local
by name and value. That is also what an embedder needs to dump state after a `Run`, so it
is useful with no debugger at all.

---

## B2. The seam, the hook, and the step state machine -- the risky step

**The seam.** In `PhosphorValue.pas`, after `TPhosphorBreakpointProc` (`:75-76`) -- it must
come after `TValue` in the same type block, which the playbook records at `:2688-2691`:

```pascal
{ Why a debugger stopped, and what it wants next. daRun resumes until the next
  armed line; daStop ends the run with peHalted. The seam MAY block -- that is
  the whole difference from TPhosphorBreakpointProc above, which may not. }
TPhosphorStopReason = (srEntry, srBreakpoint, srStep, srPause);
TPhosphorDebugAction = (daRun, daStepInto, daStepOver, daStepOut, daStop);
TPhosphorDebugProc = function(AReason: TPhosphorStopReason; ALine: Integer;
                              AFrameDepth: Integer): TPhosphorDebugAction of object;
```

On `TPhosphorVM`, beside `OnBreakpoint` (`PhosphorVM.pas:374`): `OnDebug`, plus
`ArmDebug(const ALines: array of Integer; AStopAtEntry: Boolean)` and `InterruptDebug`
(one Boolean write, safe from the host's socket thread -- that is `pause`, for free). On
`TPhosphorEngine`, a forwarded property, one line in `ConfigureVM` beside `:302`.

Give the VM the **line set**, not a callback per boundary: that is what keeps `continue`
fast during a session, and the engine still knows nothing about breakpoints -- to it the
set is only "lines to consult on".

**The hook**, the whole of it:

```pascal
opStmt:
  begin
    stmtPC := pc; stmtSP := FSP; stmtFrameSP := FFrameSP;
    if FDbgArmed then
      if not DebugPoll(ins.Line, pc) then Exit(False);
  end;
```

`DebugPoll` is a private method holding the state machine: `dmStepInto` stops at any
boundary; `dmStepOver` stops when `FFrameSP <= FDbgDepth`; `dmStepOut` when
`FFrameSP < FDbgDepth`; plus the armed line set and the interrupt flag. `FDbgDepth` is
captured when the step command was given.

**Cost when nothing is attached.** One never-taken branch, on an arm reached once per
statement -- measured at one `opStmt` per 14 executed instructions in a tight loop. Compare
against the two shapes this project has already costed: one test *per instruction* was
3-4% and was deleted as decoration (`PhosphorVM.pas:2020-2024`); tests added to existing
case arms measured at *no cost at all* (`:2045-2053`). Prove it the same way: three runs
of a fixed tight-loop fixture on pristine and on patched, both OSes, numbers in the commit
message.

**`stepOut` must be clamped at the re-entrancy floor.** `ExecFrom` stops when the frame
stack returns to `AStopFrameSP`, the bound that lets `CallUserFunc` invoke a BASIC routine
re-entrantly (`PhosphorVM.pas:1585-1589, :2992, :3004`). Pass `AStopFrameSP` into
`DebugPoll` and clamp: `if FDbgDepth <= AStopFrameSP + 1 then treat daStepOut as daRun for
this activation`.

**Step state must not survive an ON ERROR unwind.** Wherever `FFrameSP` is assigned
wholesale (`:1833`, and `RestoreOverlap` at `:1647`), set `FDbgDepth` to the new `FFrameSP`
and force `dmStepInto`, so the next boundary stops and the user sees where the handler
took them. **This is the highest-risk piece of the whole plan** -- it touches the resume
machinery the playbook records as having gone wrong twice.

**A blocking seam corrupts `TimeoutMs`**, which is wall-clock and sampled from a tick taken
once per run (`:2030-2036`). Inside `DebugPoll`, sample `GetTickCount64` before the seam
and `Inc(FStartTick, elapsed)` after it. `MaxSteps` is an instruction count and is correct
by construction. Say which of the four ceilings needed correcting in the seam's header, so
the next reader does not rediscover it. Wrap the seam call in a `try/except` so a socket
exception in the host cannot unwind through `ExecFrom`.

**Proves:** a probe installs a scripted seam returning a fixed sequence of actions and
asserts the exact list of `(line, depth)` pairs offered for a fixture containing a function
call, a loop, an ON ERROR handler and a `resume`. Remove the fix, watch it fail, put it
back.

---

## B3. `phosphor debug --port N [--stop-at-entry] <file.bas>`

All of it in `host/console/phosphor.lpr`, beside the existing subcommand dispatch
(`RunCommandLine` at `:1317`, with `compile` at `:1384` and `pack` at `:1418` as the
template). The engine must not learn what JSON is -- and note that the boundary check is a
uses-clause scan for platform and GUI units only (`scripts/build.ps1:57-59`), so it would
*not* catch `uses fpjson` in the engine. What keeps the protocol in the host is the
architecture rule, not a gate. Keep it there anyway.

The gate that will actually bite is **`check-codepage.py`**: build the encoder's output as
`RawByteString` appending **substrings**, never single `Char`s, and pass bytes >= 128
through untouched -- PDBP is UTF-8 on the wire, so no `\u` escaping is needed.

`check-sandbox.py` does not scan `host/console`, so the socket does not answer to it --
worth stating deliberately, since `--sandbox` and `debug` can appear on one command line.
Decide what that combination means before someone discovers it.

Add the `--help` line (`phosphor.lpr` usage block): PhosphorIDE detects a debug-capable
host by looking for a line beginning `phosphor debug`, which is a fact about the binary in
front of it rather than a version guess.

`check-seams.py` will fail six hosts the moment `OnDebug` is declared, because it derives
seam types structurally (`:69-71, :200-210`). Budget five new EXEMPT entries with real
reasons (`phosphortest.lpr:OnDebug`: *headless: a suite run has no debugger to answer*, and
the same for the gui/pkg/http runners and `phosphorembed.lpr`).

### What version 1 should report as unavailable, and why

Ship `"pause":true, "stepOut":true, "evaluate":false, "setVariable":false,
"conditionalBreakpoints":false`.

`evaluate` is false because of a **frozen language decision**, not a missing feature: an
undeclared name inside a function resolves to a GLOBAL, and the engine's only expression
entry points (`ReplRun`, `CallFunction`) are not side-effect-free -- `ReplRun`'s own header
says a line that compiles is *kept*. An evaluator that is nearly side-effect-free is worse
than none. `conditionalBreakpoints` follows: a condition is an expression. If `evaluate` is
wanted later, the honest route is a read-only expression subset compiled against the
frame, not `ReplRun`.

PhosphorIDE greys out what a capability denies and shows the reason, so the user gets an
explained absence.

**Run-to-cursor** needs nothing new: it is a one-shot line added to the armed set.
**Call stack** is `DbgFrameDepth` + `DbgFrameFunc` + `DbgProgram.UserFuncs[i].Name`. Note
that `FCallStack` (`PhosphorVM.pas:206`) is GOSUB return addresses and is **not** what a
call stack reports.

---

# Do not

- **Do not put the step check in the instruction dispatch loop.** Already measured at 3-4%
  and deleted as decoration; the reasoning survives at `PhosphorVM.pas:2020-2024`.
- **Do not add an opcode for the debug boundary**, however good the zero-cost story
  sounds. It changes `Ord(High(TOpcode))`, which is written into every `.pbc` as the
  opcode-set guard and refused on mismatch (`PhosphorBytecode.pas:284, :574-575`) -- every
  packed executable stops loading. It also blinds `ResumeAtNextStmt`, which finds the next
  statement by scanning for `Op = opStmt` (`PhosphorVM.pas:1722`), so `resume next` inside
  a debugged program would silently skip statements.
- **Do not serialise variable names into the `.pbc`** and do not bump `PBC_VERSION`.
- **Do not carry the protocol on the child's stdout**, and do not adopt DAP. A language
  whose entire observable behaviour is PRINT can forge a frame; one `println` of an
  exited-event ends the session from inside the program being debugged.
- **Do not unfreeze a decision in `docs/decisions.md`** to make any of this easier.
- **Do not rewrite `Push`/`Pop` and the binary opcodes** chasing per-instruction dispatch
  cost. The attribution is unprofiled, and that file carries a fix for a real access
  violation and `Pop`'s deliberate underflow contract. Profile first; land it alone.
- **Do not widen `coverage.py`'s glob to `host/gui/libs` and then relax its pass
  condition.** It prints *"every registered function is exercised by a test"* while its
  libs list (`:141-142`) never reaches `host/gui/libs`. Widen it, take the red, close each
  name. Turning a narrow-but-true claim into a broad-and-false one is the worse outcome.
- **Do not renumber the exit codes** to give a syntax error its own. Carry the distinction
  in the message.

---

# Order

```
A1  ON ERROR abandonment          correctness, silent, has side effects   <- first
B0  wire OnBreakpoint             half a day, ships alone, retires a gate exemption
A2  registry hash index           measured 5-13x on every built-in call
A5  unterminated-block line       seven one-line changes
A4  bare-call diagnostic          ~10 lines
B1  name tables + accessors       no execution path touched; useful to embedders alone
A3  str$ round-trip               expect golden churn; audit it
A6  dictionary index              or the one-sentence doc, deliberately
B2  seam + hook + step machine    the risky one; measure the tight loop on both OSes
B3  phosphor debug subcommand     no engine risk left by here
A7  settle the stale OPEN warning  any time
```

Each item is a commit. `--author="AndreMurtaX <andre.murta@fhinck.com>"`, and nothing is
done until `build.ps1`, `test-suite.ps1` and the eight gates are green on **both**
machines.


---

# Keeping the two repositories in step

Three couplings already exist and two of them are automatic. The fourth does not exist
yet and is the one worth building.

**1. The function catalogue, automatic and already red-on-change.**
`tools/gen-keywords.py ../Phosphor --check` asserts `{'core': 534, 'package': 181,
'gui': 426}` and refuses to generate when Phosphor has moved. PhosphorIDE's CI checks out
`AndreMurtaX/Phosphor` beside itself on every push and runs it, so a Phosphor release that
adds a built-in turns THIS repository red rather than quietly leaving the editor ignorant
of the new name. Nothing to do; it works.

**2. Debug capability, automatic and at runtime.** `src/core/udebugsession.pas` asks the
binary in front of it for `--help` and looks for a line beginning `phosphor debug`. It
never hard-codes a version, because which Phosphor first shipped the subcommand is a fact
about the future. The day B3 lands and that `--help` line appears, the editor's Debug menu
lights up with no change here.

**3. The protocol, one document, two implementations.** `docs/debug-protocol.md` is the
contract. It lives HERE and the engine implements it. When Phosphor implements B3, the
pointer that belongs in its `CLAUDE.md` is *"the wire format is specified in
PhosphorIDE/docs/debug-protocol.md; do not restate it here"* -- because a fact stated in
two places drifts, which is the same rule that put the word lists behind a generator.

**4. The host contract, NOT yet checked -- build this.** The editor parses things the
engine is free to change: four diagnostic shapes, four exit codes, the `--help` block, and
the fact that diagnostics go to stderr one per failed run. `src/core/uphosphormsg.pas`
encodes all of it, and its 40-odd checks run against *strings this repository wrote down*,
not against the binary. If Phosphor reworded a message or renumbered an exit code, every
test here would still pass and jump-to-error would silently stop working.

The fix is small and belongs here: a contract test that runs the REAL `phosphor` binary
against a handful of deliberately broken `.bas` files and asserts the shapes -- skipped
with an announcement when no host is found, the way `scripts/build.sh` already announces
a skipped selftest. CI already has a Phosphor checkout beside it, so it would run there
on every push to either repository.

That is the honest answer to "how do the two stay mapped": **one generated table, one
runtime handshake, one shared document, and one contract test that runs the other side's
actual binary.** Three exist. The fourth is tracked in `docs/roadmap.md`.
