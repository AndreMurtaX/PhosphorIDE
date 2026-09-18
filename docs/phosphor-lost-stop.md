# The lost stop: a breakpoint swallowed by a pause, diagnosed 2026-09-18

**This document describes work in the OTHER repository** — `AndreMurtaX/Phosphor`, the
engine — and it lives here for the reason
[`phosphor-engine-work-order.md`](phosphor-engine-work-order.md) gives, and that
[`phosphor-debugger-debts.md`](phosphor-debugger-debts.md) gives again: the ask is the
editor's half of a two-repository contract, and a contract kept only in the repository
that must satisfy it tends to be edited into agreement with whatever was built.

It was found the way both of those were — by speaking PDBP to the real host with no
editor involved — and the mechanism was then read in the Phosphor sources rather than
guessed. It needs no change to the wire format and no change to the editor.

---

## What was recorded here for a day, and what is actually true

This repository carried, in four files, that **"a hot breakpoint can lose a hit —
between 1 and 13 stops in ten thousand, measured over eleven runs, not yet
diagnosed."** That sentence was honest and it was incomplete in a way that mattered:

**It is a real defect, it is the HOST's, and the shipped editor does not provoke it.**

The measurement that produced "1 to 13" was taken in a prompt-reply regime — answer
each `stopped` as fast as the driver can. The editor does not run that way: it drains
its socket from a timer at `DebugPollIntervalMs = 40` (`src/umainform.pas:631`), and
at 40 ms the same 10 000-iteration loop measured **10000/10000, zero gaps** — in the
Python driver and again in a Pascal harness built from the editor's own byte-identical
units. Drive the same host with no delay and it is 9995 to 9996 out of 10 000.

So the correct sentence, and the one now in the prose here, is: *a host driven faster
than the editor drives it can be made to swallow a breakpoint; the editor's own 40 ms
drain does not reach the window.*

## How it was caught, and why the transport is ruled out arithmetically

The driver reads the loop counter back with `variables` at every stop, so each loss is
an **identified iteration** rather than a shortfall: 3982, 4457, 7156 and 7717 in one
run; nine near-consecutive losses around 7655–7671 in another, with the child printing
`ran 10000` both times.

**Frame accounting was exact in every run** — received == `3 + 4*stops + 1`, to the
frame. Nothing was dropped between the host's write and the driver's read, so the
`stopped` events were **never emitted**. That rules out the editor's socket and line
framing by arithmetic rather than by statistics, which matters because those were the
first suspects. (They were also ruled out directly: ~128 000 frames through an
unmodified copy of `udebugtransport.pas`, split every way a socket can split them —
two frames in one read, frames spanning the 4096-byte chunk, one byte per send — with
zero lost.)

Three controls locate it:

| control | result |
| --- | --- |
| a 20 ms wait after each `stopped`, nothing else changed | **10000/10000**, 0 gaps |
| a 1000 Hz background of harmless frames during the run | 1 lost per 1000 → **193 per 1000** |
| the Pascal harness at `--pollms 0` vs `--pollms 40` | 9995/10000 vs **10000/10000** |

The second one is the tell: the loss rate is a function of **how much unrelated traffic
the editor end is sending**, not of the loop, which is what an interrupt-shaped race
looks like from outside.

## The mechanism

Two sites, each defensible alone, composing into a swallowed breakpoint.

**One — the armed-line test is skipped when an interrupt is consumed**
(`engine/PhosphorVM.pas:4217-4222`):

```pascal
  if InterlockedExchange(FDbgInterrupt, 0) <> 0 then
  begin
    if not stop then reason := srPause;
    stop := True;
  end;
  if (not stop) and (Length(FDbgLines) > 0) and DebugLineArmed(ALine) then
  begin
    reason := srBreakpoint;
```

An interrupt arriving while the VM is at an **armed line** sets `stop := True` and
therefore makes the second `if` — the one that would have said `srBreakpoint` —
unreachable. The stop is reported as `srPause`.

**Two — the pause drain resumes without re-checking the line**
(`host/console/phosphor.lpr`, the `srPause` branch around `:2664-2688`):

```pascal
      if pending then InterruptRun();
      Exit(daRun);
```

Its `srEntry` sibling, twenty lines above, does re-check:

```pascal
      if not ArmedAt(ALine) then
        Exit(daRun);
      AReason := srBreakpoint;
```

So the pause drain finds nothing owed, resumes, and the breakpoint that was actually
due at that line is gone. Nobody is told; the loop simply runs on.

**Two behavioural discriminators back the reading.** A two-line loop body drops the
loss rate 4,7× under the same hammer (193 → 41 per 1000) — more statements per
iteration means fewer chances for an interrupt to land exactly on the armed one. And
arming `next` gives **zero** stops in 100 iterations, i.e. `next` is not a statement
boundary, which is why a single-line body is the worst case.

## The ask

`srPause` should do what `srEntry` already does: before `Exit(daRun)`, ask
`ArmedAt(ALine)`, and if it is armed, report `srBreakpoint` instead of resuming.
One branch, in the host, beside a sibling that has it.

The engine-side alternative — not skipping the armed-line test when an interrupt is
consumed, so that a stop can carry both reasons — is the more thorough fix and the
more invasive one, because `reason` is a single value on the wire. The host-side branch
restores the user-visible behaviour without touching PDBP.

## What the editor does NOT need

Nothing. `BreakpointIsArmed` already believes the installed set, the transport is
clean, and the 40 ms drain does not reach the window. If Phosphor takes the fix, the
only change here is that this document and four sentences of prose stop being true —
which is the third time a two-repository contract has been settled that way, and the
test of whether the line was drawn in the right place.

## Two latent defects found on this side while looking, neither of them this one

Both were **reproduced** in a harness over an unmodified copy of the unit, and both were
recorded here rather than fixed in the same commit, because neither can produce the
measured defect and a fix smuggled in beside a diagnosis is a fix nobody reviewed.

**Both are FIXED now**, in their own increment with their own red run — and that run is
the part worth reading, because **two of the three tests written for them asserted
nothing on the first attempt.** Reverting each fix in turn:

| fix reverted | first attempt | after |
| --- | --- | --- |
| the `try/finally` around the delivery loop | **red**, 2 failures | red |
| the re-entrancy guard | **stayed green** | red |
| counting the discarded bytes | **stayed green** | red |

The re-entrancy case queued its second batch *before* the first `Poll`, so the bytes
were already in the buffer when the outer drain took them and the re-entrant call had
nothing to reorder; it now writes that batch from **inside** the handler. The overflow
case looked for the words `discarded` and `newline`, which live in the format string and
are there whether or not anything was counted; it now asserts the **number**.

Neither would have been caught by writing the tests carefully. They were caught by
breaking the code on purpose and looking — which is this repository's rule, and this is
the second time in two days it has found a green that meant nothing.

The defects, for the record:

- **`Deposit`'s overflow cap discards silently and ends the session like a clean exit.**
  Past `MaxFrameBytes` the chunk is dropped, `FOverflow` is set, and `Drain` then fires
  `OnDisconnect` — which `TDebugSession.HandleDisconnect` treats as "the end of a
  session, not an error". 38 183 frames vanished in one cut in the harness, with no
  diagnostic anywhere. It needs a >1 MB unconsumed backlog, which a stop/continue loop
  cannot build because the editor's own `continue` is the flow control. **A reporting
  hole, not a loss path.**
- **`Drain` is neither re-entrant nor exception-safe.** The undelivered remainder lives
  in a local while `FPartial` is already `''`, so a re-entry from inside a frame handler
  delivers newer frames before older ones (reproduced: 119 reorderings in 20 000), and
  an exception escaping `FOnFrame` skips `FPartial := buf` and discards the rest. No
  path in the hot loop re-enters today — `DebugStopped` shows no dialog and pumps no
  messages — so it is latent until the first `MessageDlg` is added to a stop handler.

The fixes are small. `Deposit` counts what it throws away and the transport exposes
`EndReason`, which is `''` for an ordinary close and a sentence with a byte count
otherwise; `HandleDisconnect` asks, and `Note`s it when there is one, so the one channel
the session has for saying something unprompted gets used for the one case that needs
it. `Drain` returns immediately when it is already on the stack, and puts the
undelivered remainder back in a `finally`.
