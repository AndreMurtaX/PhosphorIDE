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
| `lane345.bas`, `blocked.bas`, `boom.bas` | the fixtures: a function to step into, a program that blocks on `line input`, a division by zero |
| `steps-lane.txt` | breakpoints, start, step over ×2, step into, step out, continue |
| `steps-blocked.txt` | stop, continue into a blocking read, Preferences during a live session |
| `steps-stop.txt` | end a running session from the process side |
| `steps-exception.txt` | a breakpoint on line 1, then the exception stop |
| `lane-linux.sh` + `xdrive.lpr` + `shot.py` | the Linux half |
| `lane-windows-*.ps1` + `win.ps1` + `gettext.ps1` | the Windows half |
| `pdbp-probe.py` | speaks PDBP to the host with no editor involved, which is how the host's own defects were separated from the editor's |

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

Still not driveable here: the gtk2 **menu bar**, from a synthetic click or from
F10 navigation. `Debug > Stop Debugging` is therefore driven on Windows, and on
Linux the same teardown is reached from the process side by `steps-stop.txt`.

## Windows

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\lane\lane-windows-steps.ps1
```

`SendKeys` is enough for the keyboard. The two facts that are not obvious:

- **`Process.MainWindowHandle` is not the form.** The LCL creates a hidden
  top-level window holding `Application.Title` and Windows returns that one, so
  `MoveWindow` moves something invisible and `EnumChildWindows` finds it
  childless — both succeeding. `win.ps1` enumerates visible top-levels instead.
- **`GetWindowText` does not cross a process boundary for a control.** It is
  documented, and it fails by returning `""`, so a full Output pane reads as
  blank. `gettext.ps1` sends `WM_GETTEXT` explicitly.

Read the transcript as TEXT and the colours from a screenshot. The claims about
ORDER are better served by the first and the claims about the current-line
stripe only by the second.
