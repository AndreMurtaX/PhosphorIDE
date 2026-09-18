# PDBP -- the Phosphor Debug Protocol

This document specifies the conversation between PhosphorIDE and a debug-capable
`phosphor` host. It is written so that the two ends can be implemented from this
page alone, by two people who never read each other's code.

**Both ends speak it now** (2026-09-15; this sentence used to read "nothing speaks it yet"). The host half ships in Phosphor as `phosphor debug --port`, driven by a 43-assertion contract test there; this side has the transport, the session driver and, since 2026-09-16, the menu -- start, breakpoints, the three steps, continue and a variables pane, driven against the real host. `docs/debugger-lane.md` records what each was verified against, and the two things the host still owes: a breakpoint on the FIRST statement is answered as installed and never fires, and an exception stop closes the socket in the same breath as the event. Original note follows, for the history of why the shape is what it is: The editor end exists -- `src/core/udebugproto.pas`
encodes and decodes every message below, and `tests/phosphoridetest.lpr` pins the
wire format -- but the host end does not, and cannot, without work inside the
Phosphor engine. [What the host is missing](#what-the-host-is-missing) says exactly
what that work is. Until it lands, PhosphorIDE's Debug menu offers breakpoints as
marks and greys out everything that would require the program to stop.

That order is deliberate. The wire format is the only part the two ends have to
*agree* on, and agreeing on it before either end exists is cheaper than discovering
the disagreement afterwards.

---

## Why this and not something else

**Why not DAP.** Microsoft's Debug Adapter Protocol would bring an editor-agnostic
ecosystem, and it is the right answer the day PhosphorIDE is not the only client.
It is the wrong answer for the first implementation, because the cost falls on the
half that is hardest to write: DAP's framing is HTTP-style `Content-Length` headers
over a byte stream, its message set runs to dozens of requests with optional
capability negotiation for most of them, and all of that would have to be built in
Free Pascal inside the interpreter. PDBP is small enough that the host end is a
day's work rather than a project.

The mitigation for the day DAP is wanted anyway: **every PDBP command is named
after its DAP equivalent.** `initialize`, `setBreakpoints`, `launch`, `continue`,
`pause`, `stepOver`, `stepInto`, `stepOut`, `stackTrace`, `variables`, `evaluate`,
`disconnect`. A bridge later is a mapping table, not a redesign.

**Why not the child's stdout.** The obvious transport -- protocol frames on the
child's own stdout, marked with a prefix -- is unusable for a language whose entire
observable behaviour is `PRINT`. A program that prints a line shaped like a frame
would drive its own debugger, and one `PRINTLN` of a forged `exited` event ends the
session from inside the program being debugged. It is also simply wrong for the
common case: the output pane wants the program's output, and the debugger wants the
protocol, and multiplexing them means every consumer has to un-multiplex.

**Why not a pipe on a third file descriptor.** It works on Unix and is awkward on
Windows, and `TProcess` gives portable access to exactly three streams.

**So: a TCP socket on the loopback interface.** It costs a port and a handshake,
and it buys three things beyond stream separation: the transport is identical on
both platforms, either end can be restarted independently for testing, and -- the
one that will matter -- the debuggee does not have to be on the same machine. A
`phosphor` running in a VM or a container can be debugged from an editor outside it
without changing a line of this specification.

---

## Transport and framing

- **TCP over the loopback interface.** The EDITOR listens; the DEBUGGEE connects.
  The editor binds `127.0.0.1` on an ephemeral port, passes that port to the host on
  its command line, and accepts one connection.
- Binding to `127.0.0.1` rather than `0.0.0.0` is a requirement, not a default. A
  debug channel accepts commands that read and write the debuggee's state; it must
  not be reachable from off the machine.
- **One JSON object per line.** UTF-8, terminated by a single `\n` (`0x0A`). A `\r`
  before the `\n` is tolerated on input and never produced on output.
- A frame contains no literal newline: JSON string escaping turns any newline in a
  value into `\n`, which is what the framing rests on.
- There is no length prefix and no header block. A line that does not parse is a
  protocol error; see [Desync](#desync-and-failure).
- Neither end may assume a frame arrives in one `read`. Both must buffer until they
  see the terminator. (The editor already does this for the child's pipes, for the
  same reason, in `src/core/uphosphorrun.pas`.)

### Starting a session

```
phosphor debug --port <port> [--stop-at-entry] <file.bas>
```

The host compiles the file, connects to `127.0.0.1:<port>`, and waits for
`initialize`. The program's own stdout, stderr and stdin remain its own, on the
ordinary pipes, exactly as they are for `phosphor run`.

If the connection cannot be made, the host must exit **2** with a diagnostic on
stderr in the existing shape (`phosphor: cannot connect to the debugger on port
<port>`). It must not run the program: a program launched under a debugger that
silently runs undebugged is worse than one that refuses.

---

## Requests

Every request is an object with:

| field | type | meaning |
| ----- | ---- | ------- |
| `seq` | integer | monotonically increasing from 1, chosen by the editor; unique within a session |
| `cmd` | string | one of the command names below |

plus whatever that command adds.

Every request gets exactly one response, carrying the same `seq`. Responses may
arrive out of order relative to requests; events may be interleaved with both.

### `initialize`

Must be the first frame. Nothing else is answered before it.

```json
{"seq":1,"cmd":"initialize","protocol":1,"client":"PhosphorIDE"}
```

| field | type | meaning |
| ----- | ---- | ------- |
| `protocol` | integer | the version the editor speaks. Currently `1`. |
| `client` | string | for the host's log. Never parsed. |

Response:

```json
{"seq":1,"ok":true,"protocol":1,"capabilities":{"stepOut":true,"pause":true,
 "evaluate":true,"evaluateCalls":false,"setVariable":false,
 "conditionalBreakpoints":true}}
```

`protocol` in the response is the version the HOST speaks. **If the two differ, the
editor disconnects and says so.** A debugger that half-works is harder to diagnose
than one that will not start.

`capabilities` is an object of booleans. **Every capability defaults to `false`**,
and an absent key means absent. A host that has breakpoints but no expression
evaluator says so, and the editor greys out what is missing rather than sending a
request it knows will be refused.

| capability | when true |
| ---------- | --------- |
| `stepOut` | `stepOut` is implemented |
| `pause` | `pause` can interrupt a running program |
| `evaluate` | `evaluate` can compute an expression in a frame |
| `evaluateCalls` | a function call written in an expression is PERFORMED. **Read it whenever `evaluate` is true**: a host may be able to evaluate `count% * 2` and refuse `len(s$)`, and those are different products. False does not mean an expression containing parentheses is refused -- index syntax (`a@[i]`, `s$[n]`) may reach a call the compiler put there rather than one the user wrote. It means a NAME the user types with arguments after it will be refused. |
| `setVariable` | a variable's value can be written (no command for this in version 1; the capability is reserved so a host cannot claim it by accident later) |
| `conditionalBreakpoints` | `setBreakpoints` honours the `conditions` array. **A host that reports false must never be sent one**: it would install the line, ignore the condition and stop on every hit, which looks exactly like a condition that is always true. |

### `setBreakpoints`

```json
{"seq":2,"cmd":"setBreakpoints","path":"C:/w/x.bas","lines":[3,11]}
```

Replaces **the entire breakpoint set for that one source file**. An empty `lines`
array clears it.

Whole-set replacement rather than add and remove is deliberate: an incremental
protocol requires both ends to agree on what is currently set, and they will not.
The editor's list moves every time a line is inserted above a mark, and a breakpoint
whose line was deleted is dropped rather than slid onto its neighbour
(`src/core/ubreakpoints.pas`, `TrackEdit`). Sending the whole set makes the editor's
view authoritative by construction.

`path` is the path as the editor knows it. The host resolves it against the file it
was launched with; a path it does not recognise is not an error, it simply matches
nothing.

#### A condition on a breakpoint

```json
{"seq":2,"cmd":"setBreakpoints","path":"C:/w/x.bas","lines":[3,11],
 "conditions":["","i% > 3"]}
```

`conditions` is **optional**, is an array of strings **the same length as `lines`**,
and is read **by the same index**. An empty string is an ordinary breakpoint, which
is why the common case can leave the whole key out. Send it only when
`capabilities.conditionalBreakpoints` is true.

**It is a sibling key and the condition is never put inside `lines`**, which is the
shape that suggests itself and the one that must not be used. `lines` stays an array
of numbers. The console host as it first shipped read that array with fpjson's
`Integers[]`, which CONVERTS: an object element raised inside its loop and **killed
the debuggee** over one element of an otherwise conformant frame. The hardening that
drops a non-integer instead is newer than hosts that may still be running, and an
editor cannot know which one is on the other end. A key an unaware host never looks
for cannot hurt it.

**The index is the INPUT index.** A host is allowed to drop a `lines` element it
cannot use, so its input and output indexes part company on the first bad element.
Both ends read `conditions[i]` against `lines[i]` as they arrived, before anything
is dropped. Getting this wrong gives a condition to the wrong breakpoint, silently.

**A condition is an expression, so everything `evaluate` says applies to it** --
including that a host may refuse every call the user writes, which
`capabilities.evaluateCalls` announces. `len(s$) > 2` is not a condition the console
host will take.

Response:

```json
{"seq":2,"ok":true,"lines":[3,11]}
```

With a condition the host would not read:

```json
{"seq":2,"ok":true,"lines":[3,11],"rejected":[
  {"line":11,"condition":"i% >","error":"unexpected token in expression"}]}
```

`rejected` is **omitted entirely when there is nothing to reject**, so a host that
has never heard of conditions answers exactly what it always answered. Each entry
carries the line, the condition quoted back, and the host's own wording.

**A rejected condition does not reject the breakpoint.** The line is still in
`lines` and still installed, **unconditional** -- because a mark that is visible and
never honoured is worse than one that fires too often. The editor is expected to say
so where the condition was typed and to stop drawing it as conditional.

**Only a condition that is not an EXPRESSION can be rejected here.** Whether its
names are in scope is a question about a frame, and at `setBreakpoints` time there
is no frame. That refusal arrives later, as a stop:

```json
{"event":"stopped","reason":"breakpoint","path":"C:/w/x.bas","line":11,
 "text":"the condition i% > q could not be evaluated: no variable \"q\" here"}
```

**A condition that cannot be evaluated STOPS the program**, and says why in `text` --
the same key an exception stop uses. The alternative is a breakpoint that silently
never fires, which is the one outcome a person cannot diagnose from the outside. A
condition that evaluates to something other than a boolean is the same case.

**Only a `breakpoint` stop is filtered.** A step that lands on a conditional line
stops, because the user asked to step and the condition is not about them; so does
an entry, a pause and an exception.

`lines` in the response is the set the host **actually installed**, which may be
smaller: a line holding no executable statement -- a blank line, a comment, `endif`
-- has nowhere to stop. The editor draws the difference, so a breakpoint that will
never fire looks different from one that will.

The host answers that cheaply, because `opStmt` is a stoppable-line index in
disguise: the set of `Instr(i).Line where Op = opStmt` is exactly the set of lines a
breakpoint can bind to. De-duplicate it -- `a = 1 : b = 2` emits two `opStmt` on one
line, and so does the inline `if c then ...` form.

A richer answer is worth considering before version 2 freezes this: report each
breakpoint as **requested line, effective line, verified** rather than as a filtered
list, so a mark that slid to the next stoppable statement can say where it went
instead of silently either vanishing or lying. That is the shape
`C:/Dev/Lyra/src/Lyra.Debug.pas` settled on (`TLyraBreakpoint.RequestedLine`,
`EffectiveLine`, `Verified`, `Bindings`), in the same language, against the same
problem.

May be sent at any time, including while the program is running.

### `launch`

```json
{"seq":3,"cmd":"launch","program":"C:/w/x.bas","stopAtEntry":true}
```

Begins execution. `stopAtEntry` true means the host emits a `stopped` event with
reason `entry` before the first statement, which is what gives the editor a chance
to set breakpoints against a program whose source it has just compiled.

Response `{"seq":3,"ok":true}` acknowledges the start, not the finish. The program's
progress arrives as events.

### `continue`, `pause`, `stepOver`, `stepInto`, `stepOut`

```json
{"seq":4,"cmd":"stepOver"}
```

No fields beyond `seq` and `cmd`. All five are only valid in the states named in
[The state machine](#the-state-machine); sent in the wrong state they are refused
with `ok:false` rather than ignored.

Stepping is by SOURCE LINE, not by instruction:

- **`stepOver`** -- run until the line changes, at the same frame depth or shallower.
  A call on the current line runs to completion.
- **`stepInto`** -- run until the line changes, at any depth. A call on the current
  line stops at the first line of the callee. When the current line contains no
  call, it behaves as `stepOver`.
- **`stepOut`** -- run until the current frame returns, then stop at the line the
  caller resumes on. At the outermost frame it behaves as `continue`.
- **`pause`** -- stop as soon as the next line boundary is reached. Only meaningful
  while running, and only where `capabilities.pause` is true.

Each of the four is acknowledged immediately (`ok:true`) and produces a `stopped`
event when it actually stops -- or an `exited` event if the program finished first.
**The acknowledgement is not the stop.** An editor that treats it as one will
repaint the current-line marker before there is a new line to paint.

### `stackTrace`

```json
{"seq":5,"cmd":"stackTrace"}
```

Valid only while stopped.

```json
{"seq":5,"ok":true,"frames":[
  {"index":0,"name":"greet","path":"C:/w/x.bas","line":4},
  {"index":1,"name":"(main)","path":"C:/w/x.bas","line":12}]}
```

Frame `0` is innermost. `name` is the user function's name, or `(main)` for the
outermost frame. Phosphor's `GOSUB` return addresses are **not** frames and must not
appear here; a GOSUB does not create a scope.

### `variables`

```json
{"seq":6,"cmd":"variables","frame":0}
```

Valid only while stopped. `frame` is an index from the most recent `stackTrace`.

```json
{"seq":6,"ok":true,"variables":[
  {"name":"count%","value":"3","kind":"int","scope":"local"},
  {"name":"name$","value":"Ada","kind":"string","scope":"global"},
  {"name":"list@","value":"array[3] of string","kind":"handle","scope":"global"}]}
```

- `name` **includes the type suffix**, because in Phosphor the suffix is part of the
  name: `count%` and `count$` are two variables.
- `value` is **already rendered by the host**, as `PRINT` would render it. The
  editor does not format values: it does not know the rules, and a second renderer
  is a second set of rules to keep in step. A handle renders as a short description
  rather than a number, because the number means nothing to a reader.
- `kind` is one of `number`, `int`, `string`, `bool`, `handle` -- Phosphor's five
  value kinds.
- `scope` is `local` or `global`. Both are listed, because in Phosphor **an
  undeclared name inside a function is a GLOBAL** -- only names in the `local` list
  are frame slots -- and a variables pane that hid globals would hide most of what a
  function touches.

### `evaluate`

```json
{"seq":7,"cmd":"evaluate","frame":0,"expr":"count% * 2"}
```

Valid only while stopped, and only where `capabilities.evaluate` is true.

```json
{"seq":7,"ok":true,"result":"6","kind":"int"}
```

An expression that does not compile, or that fails, is `ok:false` with `error` set.
**Evaluation must not change the program's state**: no assignment, no call to a
function with side effects that the host cannot undo. A host that cannot guarantee
that must report `evaluate:false` rather than offering a half-safe one.

**A HOST MAY MEET THAT BY REFUSING CALLS, and then it says so with
`evaluateCalls`.** That is the clause's other reading and it is the honest one: a
host with no way to know whether a library function has an effect cannot promise
anything about a call, and refusing every call is a guarantee rather than a
half-one. The console host does exactly this as of 2026-09-17, and the two keys
together are what an editor needs before it offers a watch box -- `evaluate: true`
says the request is worth sending, `evaluateCalls: false` says which requests are
worth sending.

**The editor does not have to read `evaluateCalls` to be correct**, because a
refused call is an ordinary `ok:false` with an `error` the user can read. It has
to read it to be KIND: a watch pane that offers completion for 1145 function names
and then refuses all of them is worse than one that says up front what it can do.

**What the console host refuses, as an example of the shape rather than as part of
this specification**: every registered name, because its registry carries no notion
of an effect; anything that would store, print, open a file or halt; and a
statement smuggled in behind `:` or a newline. What it answers: names in scope
(locals of the chosen frame first, then globals, which is the language's own
shadowing), every operator, and index syntax. Its own reasoning is in
`../Phosphor/docs/debugging.md`.

### `disconnect`

```json
{"seq":8,"cmd":"disconnect","terminate":true}
```

`terminate` true kills the program; false detaches and lets it run to completion
without a debugger. Both are answered `ok:true`, after which the host closes the
socket.

The editor also treats a closed socket as a disconnect, so a host that dies without
answering is handled by the same path.

---

## Events

An event is an object with an `event` field and no `seq`. Events are unsolicited and
may arrive at any time, including between a request and its response.

### `stopped`

```json
{"event":"stopped","reason":"breakpoint","path":"C:/w/x.bas","line":11}
```

`reason` is one of `entry`, `breakpoint`, `step`, `pause`, `exception`. On
`exception` the event also carries `text` with the engine's message, and the program
is finished -- an `exited` event follows once the host has cleaned up.

### `continued`

```json
{"event":"continued"}
```

Sent when execution resumes for a reason the editor did not ask for. A resume the
editor requested needs no event: the acknowledgement of `continue` already said so.

### `exited`

```json
{"event":"exited","exitCode":0}
```

The program is finished. `exitCode` follows the host's existing taxonomy: 0 fine, 1
the BASIC program failed, 2 the host refused to run it, 3 the interpreter itself
faulted.

### `trace`

```json
{"event":"trace","text":"checkpoint reached","line":7,"path":"C:/w/x.bas"}
```

A `BREAKPOINT` STATEMENT in the source fired -- the language's existing
report-and-continue facility, which is a different thing from a breakpoint set in
the margin. It reports and the program keeps going. Carrying it here rather than on
stdout keeps a debugging aid out of the program's own output.

### `error`

```json
{"event":"error","text":"cannot read frame 3: the program is running"}
```

The host is unhappy but still connected. Distinct from a failed response, which
answers one request; this reports something with no request to attach it to.

---

## The state machine

```
                    disconnect / socket closed
        +---------------------------------------------------+
        |                                                   v
   [connected] --initialize--> [initialized] --launch--> [running] --> [terminated]
                                                   ^         |
                                         continue/step       | breakpoint, step
                                         |                   v  complete, pause,
                                         +--------------- [stopped]    exception
```

- `stackTrace`, `variables` and `evaluate` are valid **only** in `stopped`.
- `continue`, `stepOver`, `stepInto`, `stepOut` are valid **only** in `stopped`.
- `pause` is valid **only** in `running`.
- `setBreakpoints` is valid in `initialized`, `running` and `stopped`.
- `disconnect` is valid in every state.

A command sent in the wrong state is answered `ok:false` with an `error` naming the
state, never ignored and never queued. Silence is indistinguishable from a lost
frame, and queueing means the editor's next request acts on state it can no longer
see.

---

## Desync and failure

The two ends are separate programs and may be separate versions.

- **A line that does not parse as JSON, or is not an object, or is neither an event
  nor a response**: the receiver reports it and disconnects. It does not skip the
  line and carry on -- a stream that has produced one frame the receiver cannot read
  has no claim to be understood from the next one.
- **A response with an unknown `seq`**: ignored, and logged. It is a duplicate or a
  stale answer, and neither is worth ending a session over.
- **An unknown `event` name**: refused, and the session ends. An event the editor
  does not understand may be the one announcing that the program stopped, and
  continuing as though it had not is worse than stopping.
- **An unknown field in a frame the receiver otherwise understands**: ignored. This
  is what lets version 1 and a later version interoperate for the things they share.
- **The socket closing without a `disconnect`**: treated as `disconnect` with
  `terminate` true. The editor kills the process if it is still there.
- **The program crashing the interpreter (exit 3)**: the socket closes; the editor
  reports the exit code it observes on the process, not the one the protocol never
  sent.

The editor's decoder never raises: `DecodePdbp` answers a record with `Valid=False`
and `ParseError` set (`src/core/udebugproto.pas`). This is pinned by tests that feed
it garbage, a JSON array, an unknown event and an empty line.

---

## Debugging a GUI program

A Phosphor program that opens a window is debugged the same way, with one thing to
know: **while the program is stopped, its window does not repaint.** The message
loop is inside the program, and the program is not running. The window will look
frozen because it is, and an editor should say so rather than let the user conclude
the debugger hung.

The host must not pump the widgetset's message loop on the debuggee's behalf while
stopped. It would keep the window responsive at the cost of running the program's
own event handlers during a breakpoint -- which changes the state the user stopped
to look at, and can re-enter the very line they are standing on.

---

## What the host is missing

The work is in the Phosphor repository, not this one, and it is real. In dependency
order:

1. **A blocking debug seam in the VM.** The existing `OnBreakpoint` cannot be
   reused: its contract says it "MUST NOT block: the engine treats it as a report,
   never a wait, so no confirm-answer is returned"
   (`engine/PhosphorValue.pas:73-74`), and it returns `void`. What is needed is a
   separate seam, called at each source-line boundary, that CAN block and whose
   return value tells the VM what to do next -- run, step, stop.

2. **A step state machine, hung on the statement boundary that already exists.**
   This entry used to say the fetch-decode-execute loop should notice when the
   current instruction's line differs from the last one. **That was wrong**, and
   measuring the emitted bytecode is what showed it: disassembling a compiled
   `for i = 1 to N / s = s + i / next` puts the loop's increment instructions on the
   `for` line and the body on its own, so a per-instruction line comparison fires
   twice per iteration and one Step Over would land back on the `for` every time.

   The engine already emits `opStmt` once per source statement, carrying the line
   (`engine/PhosphorCompiler.pas:2049`), and its VM handler already records the
   triple a stepper needs -- pc, stack depth, frame depth
   (`engine/PhosphorVM.pas:2256-2260`). The hook belongs inside that one case arm,
   and the rule is **stop at an `opStmt` whose line differs from the line the step
   began on, or whose frame depth is lower**.

   That also settles the cost question the right way round. Phosphor measured a test
   *per instruction* at 3-4% and deleted it as decoration
   (`engine/PhosphorVM.pas:2020-2024`); tests added to existing case arms measured at
   no cost at all (`:2045-2053`). One `opStmt` occurs per ~14 executed instructions in
   a tight loop, so a Boolean guard there is the cheap shape -- but it is still a
   number to put in a commit message, not a claim.

3. **Accessors for globals and frames -- AND a name table, which does not exist.**
   `variables` and `stackTrace` need to enumerate the global table and walk the
   frame stack, both private today with no accessor (`FCallStack` is an `array of
   Integer` of GOSUB return addresses -- explicitly not what `stackTrace` reports).

   The harder half was missed when this document was first written: **the compiled
   program carries no variable names at all.** `TProgram` declares `VarCount` and
   `VarTypes` and no name table (`engine/PhosphorOpcodes.pas:126-152`); `TUserFunc`
   declares the function's own name and no names for its locals (`:115-122`). The
   compiler has them and throws them away (`FVarNames`, `FLocalNames`). So
   `variables` is not merely unimplemented, it is unanswerable until `TProgram`
   carries names.

   They must NOT be serialised into the `.pbc`: `PBC_VERSION = 1` and `LoadProgram`
   refuses any other version, so a bump would brick every packed executable.
   `phosphor debug <file.bas>` compiles in-process, where the names are already in
   hand.

   One more thing this end cannot see: **a seam that blocks corrupts `TimeoutMs`**,
   which is wall-clock sampled once per run (`engine/PhosphorVM.pas:2030-2036`). The
   host must discount the time spent parked, or a session that pauses for a minute
   kills the program on resume.

4. **A `phosphor debug` subcommand** in `host/console/phosphor.lpr` that opens the
   socket, installs the seam, and speaks everything above. This is where the JSON
   lives; the engine must not know what JSON is, and a source gate already enforces
   that the engine names no host unit.

5. **A line in `--help`.** PhosphorIDE detects a debug-capable host by asking it for
   `--help` and looking for a line beginning `phosphor debug`
   (`src/core/udebugsession.pas`). Asking the binary what it can do is a fact about
   the binary in front of us; a version comparison would be a guess about the
   future.

Items 1 to 3 touch the engine and therefore have to pass Phosphor's source gates,
including `check-seams.py`, which requires a host to either fill a seam or record
why leaving it nil is right. The recorded exemption that exists today --
`'phosphor.lpr:OnBreakpoint': 'BREAKPOINT is report-and-continue; there is nowhere
for a host to pause to'` -- is precisely the sentence this work makes obsolete.

---

## Version 1 is not the last word

Known gaps, listed so that a later version does not have to rediscover them:

- **No conditional breakpoints.** The capability flag is reserved and the field is
  not specified. A condition is an expression, and an expression needs `evaluate`
  first.
- **No `setVariable`.** The capability is reserved so that a host cannot claim it by
  accident, but there is no command. Writing a variable back through a seam that
  currently hands out copies needs the engine to offer something it does not.
- **No data breakpoints, no logpoints, no exception breakpoints.**
- **One debuggee per session.** A `phosphor pack`ed executable cannot be debugged at
  all: it ignores its command line by design, so there is nowhere to put `--port`.
- **No source-map for `.pbc`.** A compiled `.pbc` reports its ORIGINAL source line,
  but the editor is told the `.pbc` path; mapping one back to the other is the
  editor's problem and is not solved.
