A desktop editor for **Phosphor BASIC**: tabs, a purpose-built highlighter, folding,
an outline, completion, signature help, find and replace across a tree, an integrated
REPL, and a step debugger.

## What changed since 0.1.0

Two latent defects in the debug transport, neither of them reachable in an ordinary
session, both found while diagnosing something else and both fixed with their own
red run:

- **A debug link that ended badly now says so.** Past a megabyte with no newline in
  it the transport drops what it has and ends the session -- through the *same*
  callback a program that finished perfectly well arrives at, so a session that lost
  everything was reported as one that succeeded. It now counts what it discarded and
  reports it.
- **Draining the socket survives a frame handler that misbehaves.** A handler that
  raised discarded every frame still in the buffer; one that re-entered the drain
  delivered newer frames before older ones. Neither can happen today, because nothing
  in the stop path shows a dialog or pumps messages -- this is for the first one that
  does.

The 0.1.0 binary is not wrong about anything a user could see; this release exists so
the published build matches the source.

Also: the `initialize` sample in `docs/debug-protocol.md` showed a `client` string the
editor has never sent.

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

**On Linux you almost certainly have to install one package first.** The binary is
built against **GTK 2**, which has not been part of a default desktop install for
years — measured on a stock Ubuntu 24.04 on 2026-09-18, it does not load at all:

```
libgdk-x11-2.0.so.0 => not found
libgtk-x11-2.0.so.0 => not found
```

Nothing appears when you double-click it, and nothing says why. One command fixes it:

```
sudo apt install libgtk2.0-0
```

(or your distribution's equivalent — the package may carry a `t64` suffix, which apt
resolves for you). The `smoke` workflow runs exactly that command on a clean runner and
then starts the editor, so this instruction is tested rather than remembered.

Building against GTK 3 or Qt5 instead would remove the step. It is not done, and it is
not a line of configuration: the LCL widgetset is chosen at build time and every visual
assertion in this project — the gutter marks at two resolutions, the toolbar's light and
dark readability, thirty-odd driven lane cases — was measured under GTK 2.

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

- **A hot breakpoint can lose a hit, in the `phosphor` host** -- an interrupt landing
  on an armed line makes the engine report a pause instead of a breakpoint, and the
  host resumes without re-checking. Diagnosed 2026-09-18; the fix is one branch in the
  sibling repository. **This editor does not provoke it**: it drains its debug socket
  every 40 ms, and at that rate a 10 000-iteration loop measures 10000/10000. A driver
  answering as fast as it can loses 4 or 5. See `docs/phosphor-lost-stop.md`.
- **A breakpoint condition is recompiled on every hit**: 0,04 ms on a small program,
  2,3 ms on a 606-line one. The cache is proven and not built.
- **`evaluate` refuses every function call you write**, because the engine's registry
  cannot say whether a function has an effect. The three the compiler generates from
  bracket syntax do answer.

MIT. `docs/roadmap.md` has all thirty-one items and what each one cost.
