# tools/lane — driving the debugger, on both machines

Three of this repository's five bar conditions are gates a script can run. The
other two — "the editor DRIVEN under gtk2", and a debug session at all — are a
person pressing keys in a window and looking at what comes back. These files are
that person, written down, so the answer is repeatable rather than remembered.

**None of this is part of the build.** `scripts/build.ps1` and `scripts/build.sh`
do not touch it, `bin/phosphoridetest` does not link it, and nothing here is
compiled by `lazbuild`. It is verification tooling for a conversation with a live
`phosphor debug --port` child, which no headless gate can stand in for. Roadmap
item 2a is the contract test that would turn part of it into a gate.

## What is here

| | |
| --- | --- |
| `lane345.bas`, `blocked.bas`, `boom.bas`, `deep.bas` | the fixtures: a function to step into, a program that blocks on `line input`, a division by zero, and a three-deep recursion |
| `steps-lane.txt` | breakpoints, start, step over ×2, step into, step out, continue |
| `steps-blocked.txt` | stop, continue into a blocking read, Preferences during a live session |
| `steps-stop.txt` | end a running session from the process side |
| `steps-exception.txt` | a breakpoint on line 1, then the exception stop |
| `steps-stack.txt`, `steps-stack-linux.txt` | the call stack pane: the frames, a selection driving the variables pane, a double-click, and both panes emptying on resume |
| `steps-stack-running.txt` | the same panes, empty, while a program runs |
| `steps-gutter.txt`, `steps-gutter-linux.txt` | the hollow ring beside the solid dot, and both solid before any session |
| `steps-gutter-edit.txt` | a gutter mark following its statement across an insertion above it |
| `steps-complete.txt`, `steps-complete-linux.txt` | the completion popup, the case it preserves, and its silence inside a string |
| `steps-toolbar.txt` | nothing driven: the toolbar, to look at |
| `lane-linux.sh` + `xdrive.lpr` + `shot.py` | the Linux half |
| `lane-windows.ps1` | the Windows driver: takes a fixture and a step script, same commands as the Linux one |
| `lane-windows-*.ps1` + `win.ps1` + `gettext.ps1` | the earlier, single-purpose Windows drivers |
| `pdbp-probe.py` | speaks PDBP to the host with no editor involved, which is how the host's own defects were separated from the editor's |
| `first-statement-probe.py` | the reproduction for the first of the two debts in `docs/phosphor-debugger-debts.md`: a breakpoint on the first executed statement is answered installed and never fires |

## Linux

```bash
cd tools/lane
fpc -O2 -k-lXtst xdrive.lpr
./lane-linux.sh ./lane345.bas ./steps-lane.txt
```

`xdrive` injects keys through **XTest** because GTK ignores a synthetic
`XSendEvent` — the naive version produces a window that visibly has focus and
answers nothing. The VM this was written against has no xdotool, no xte and no
ImageMagick, so `shot.py` decodes `xwd` output with PIL: a 100-byte big-endian
header, BGRA pixels, rows padded to `bytes_per_line`.

Four things cost real time on 2026-09-16 and are worth not rediscovering:

- **`xwininfo -root -tree | grep PhosphorIDE` finds the mutter FRAME first**, and
  `XGetImage` on a frame is `BadMatch` — `xwd` then writes a zero-byte file and
  exits 1. Match on the window CLASS. There are also three decoy 10×10 windows
  named `phosphoride`: the LCL's own hidden top-levels.
- **`xwd -root` also fails on Xwayland**, so a GTK menu — which is an
  override-redirect window of its own, not a child of the form — cannot be
  photographed at all. Twice this read as "the menu never opened".
- **Nothing may steal focus mid-script.** A GTK menu holds a keyboard grab, and
  `XSetInputFocus` on the form drops it, so consecutive keys go in ONE `xdrive`
  invocation and every invocation is `nofocus` unless the script says `raise`.
- **A background GUI holding ssh's stdout keeps ssh from returning** even after
  the script ends. `setsid` plus a redirect.

**A GTK popup cannot be photographed either.** The completion list, like a menu,
is an override-redirect window of its own, so `xwd -id <win>` shows the editor
with no popup over it. The Linux completion case therefore asserts the RESULT --
what the line says after Return -- rather than the picture, which is the same
lesson as reading the transcript as text.

**Click coordinates on Linux are measured UP FROM THE BOTTOM EDGE** (`bot DX DYUP`),
not down from the top. mutter gives this window a different height on different
runs -- 700, 725 and 750 all seen on one afternoon -- so everything below the editor
moves between runs, and an offset from the top lands in a different pane each time.
Two attempts at the call-stack pane clicked into the variables list instead, and both
read as a pane that did not work. The output panel is bottom-anchored; from the bottom
every row keeps its place.

Still not driveable here: the gtk2 **menu bar**, from a synthetic click or from
F10 navigation. `Debug > Stop Debugging` is therefore driven on Windows, and on
Linux the same teardown is reached from the process side by `steps-stop.txt`.

## Windows

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\lane\lane-windows.ps1 `
           -Fixture tools\lane\deep.bas -Steps tools\lane\steps-stack.txt
```

`SendKeys` is enough for the keyboard. The two facts that are not obvious:

- **`Process.MainWindowHandle` is not the form.** The LCL creates a hidden
  top-level window holding `Application.Title` and Windows returns that one, so
  `MoveWindow` moves something invisible and `EnumChildWindows` finds it
  childless — both succeeding. `win.ps1` enumerates visible top-levels instead.
- **`GetWindowText` does not cross a process boundary for a control.** It is
  documented, and it fails by returning `""`, so a full Output pane reads as
  blank. `gettext.ps1` sends `WM_GETTEXT` explicitly.

**`-KeepOpen` leaves a binary locked, and the next build says something else.**
A phosphoride left running holds `bin\phosphoride.exe` open, and lazbuild then fails
with `Error: (9003) Can't create object file ... (error code: 5)` and
`Fatal: Can't create executable` -- which reads as a compiler problem and is an
access-denied on a file somebody is still using. Paid for on 2026-09-16, one probe
run earlier. If a build fails that way, look for a process before looking at the code.

Both drivers close the editor **and its `phosphor` child** when they finish.
Killing the editor does not kill the program it was debugging -- one stopped at a
breakpoint simply loses the only thing that was going to tell it to continue -- and
leaving one of those on someone's desktop is how this project learned to check.

Read the transcript as TEXT and the colours from a screenshot. The claims about
ORDER are better served by the first and the claims about the current-line
stripe only by the second.
