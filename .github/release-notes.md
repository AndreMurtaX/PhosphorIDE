A desktop editor for **Phosphor BASIC**: tabs, a purpose-built highlighter, folding,
an outline, completion, signature help, find and replace across a tree, an integrated
REPL, and a step debugger.

## Get it running

1. Download the archive for your platform below and unpack it. There is no installer;
   `phosphoride` is a single binary.
2. **Get a `phosphor` binary.** This is an editor for an interpreter it does not
   contain, and that is deliberate: a BASIC program that loops forever or exhausts
   memory has to take *its own* process down and leave the editor holding your unsaved
   work. Build one from [AndreMurtaX/Phosphor](https://github.com/AndreMurtaX/Phosphor).
3. The editor looks for it in five places, in order: **Tools > Preferences**, then
   `$PHOSPHOR_HOST`, then beside `phosphoride` itself, then `../Phosphor/bin/`, then
   your `PATH`. Preferences shows which one it found and where it came from.

**Without a host** the editor opens, edits, highlights, folds, outlines, completes and
searches. It cannot run, check syntax, compile, pack or debug, and the menu items for
those say so rather than failing quietly.

On Linux the binary needs the gtk2 runtime (`libgtk2.0-0`), which most desktops
already have.

## What works

Running with live output and a Stop that works on a program that will not finish;
answering `INPUT` from the row under the transcript; diagnostics you can double-click
to land on the line; breakpoints that follow your edits, with conditions the host
evaluates; stepping over, into and out; panes for variables, the call stack and
watches; and a REPL you can send the selection to.

`docs/getting-started.md` travels in the archive and walks the first program and the
first debug session.

## What this release is built from

Every artifact here comes from a run that passed all five gates on both platforms:
`lazbuild` at `-vewn` with **zero** errors, warnings and notes in the Release mode;
the unit checks; the contract test **against a real `phosphor` binary** the run built
itself; `--selftest` constructing every form under a timeout; both generated units
current; and every `file:line` citation still pointing at what it claimed.

The Release build is about 4.8 MB against the debug build's 37 MB, and it is the mode
`-O3` flow analysis actually looks at.

## Known, measured, and written down

- **A hot breakpoint can lose a hit** -- between 1 and 13 stops in ten thousand, over
  eleven runs of a 10 000-iteration loop. Measured, and as of this release not yet
  diagnosed.
- **A breakpoint condition is recompiled on every hit**: 0,04 ms on a small program,
  2,3 ms on a 606-line one. The cache is proven and not built.
- **`evaluate` refuses every function call you write**, because the engine's registry
  cannot say whether a function has an effect. The three the compiler generates from
  bracket syntax do answer.

MIT. `docs/roadmap.md` has all thirty-one items and what each one cost.
