# One debt the Phosphor REPL owes: stderr is buffered on Unix, measured 2026-09-16

**This document describes work in the OTHER repository** — `AndreMurtaX/Phosphor`, the
host — and it lives here for the reason
[`phosphor-debugger-debts.md`](phosphor-debugger-debts.md) gives: the ask is the
editor's half of a two-repository contract, and a contract kept only in the repository
that must satisfy it tends to be edited into agreement with whatever was built.

It was found while building PhosphorIDE's REPL pane (roadmap item 16), **measured with
no editor involved** — a Python driver holding the child's three pipes — and the
mechanism was then read in the sources rather than guessed.

---

## What happens

A REPL error reaches a caller on Windows immediately and on Linux **not until the
process exits**. On a long-lived REPL that means the diagnostic for a line you typed
arrives minutes later, underneath whatever has happened since.

Measured on 2026-09-16, the same binary driven the same way on both platforms, stdin on
a pipe, stdout and stderr on pipes, reading a byte at a time:

| | send `nosuchthing(` | 1.5 s later | after stdin is closed |
| --- | --- | --- | --- |
| Windows | — | stderr: `error: unexpected token in expression\r\n` | — |
| Linux | — | stderr: *(nothing)* | stderr: `error: unexpected token in expression\n` |

stdout is unaffected on both: `phosphor> ` arrives at once, so the prompt after the
failed line is there while the reason for it is not.

In the editor the effect is a transcript that reads like this — the error landing after
the session had already been ended:

```
phosphor> nosuchthing(
phosphor>
> end of input

error: unexpected token in expression
> the REPL ended, exit code 0
```

## Why nothing had caught it

Every other use of the host is SHORT-LIVED. `phosphor run x.bas` writes at most one
diagnostic and then exits, and the exit flushes it — so the buffering is invisible to
every existing test, to `--check`, to the editor's Run path and to the debugger, all of
which see a correct-looking stream because the process ends a moment later.

**A REPL is the first thing that keeps the process alive after an error**, which is why
this appears now and not a year ago. It is the same shape as the `BREAKPOINT` seam's
report-and-continue contract being invisible until something tried to wait on it.

## The mechanism

FPC gives `StdErr` a buffered text file like any other, and the RTL flushes a text file
when it is closed — at `Halt`, for `StdErr`, via the unit finalisation. On Windows the
console/pipe write path ends up unbuffered in practice; on Unix it does not. Nothing in
`host/console/phosphor.lpr` flushes after writing a REPL diagnostic: the REPL loop's
error path is `Writeln(StdErr, 'error: ', msg)` with no `Flush`.

This is not a claim about which platform is "right" — it is a claim that the two differ
and that a caller cannot tell the difference from the outside.

## The ask

**Flush `StdErr` after writing a diagnostic in the REPL loop.** One line, in the path
that writes `error: ` at the prompt. `Flush(StdErr)` after the `Writeln`, or
`SetTextBuf(StdErr, buf, 0)` once at startup if unbuffered stderr is wanted everywhere —
the second is the broader fix and the one that also covers a future long-lived mode.

It changes no output, no exit code and no format. It changes only WHEN the bytes leave.

### How to check it from the other side

```
printf 'nosuchthing(\n' | timeout 5 ./bin/phosphor
```

does not show it, because the pipe closes immediately and the flush at exit covers the
defect. It has to be a driver that keeps stdin OPEN and reads stderr while the child is
still alive; `tools/lane/repl-probe.py` in this repository is one, and the table above is
its output.

## What the editor does meanwhile

Nothing, deliberately. `TPhosphorRunner` shows lines in the order the bytes arrive, and
inventing an order for them would be the editor guessing at something only the host
knows. The REPL pane's transcript is therefore correct on both platforms and merely
*late* on one, and `src/core/uphosphorrepl.pas` says so in its header so that nobody
reads the lateness as a defect on this side.
