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
| `steps-signature.txt`, `steps-signature-linux.txt` | every arity of `mid$`, the argument marked as it moves, the hint gone when the call closes, and nothing at all for `callfunc` |
| `steps-fold-linux.txt` | the same under gtk2, clicking DOWN from the top because the editor is the part that does not move |
| `steps-fold.txt` + `folding.bas` | folding: four nested blocks with markers, four legal lines that only LOOK like blocks and get none, and a collapse that stops at `end function` rather than at the end of the file |
| `steps-repl.txt`, `steps-repl-linux.txt` | the REPL pane: the prompt arriving as an unterminated tail, 42, a variable surviving the line, the continuation prompt, an error in the transcript, Up and Down, End leaving no child behind, and a run beside a live prompt |
| `repl-probe.py` | speaks to the REPL over pipes with no editor involved -- how it was found that stderr is buffered on Unix (`docs/phosphor-repl-debt.md`) |
| `steps-outline-linux.txt` | the same under gtk2, including the Go to Definition dialog through `popshot` |
| `steps-outline.txt` + `outline.bas` | the outline pane and F12: ten definitions including two on one line, a click that keeps the keyboard, a jump, and the three answers F12 gives when there is nothing to jump to |
| `steps-accent.txt` + `acentos.bas` | the byte column: the same statement with and without accents, and the popup filtered on both |
| `steps-find.txt`, `steps-find-linux.txt` | find in files: the pane, a jump into a file that was not open, a walk of ~1000 files finished, a walk nobody would wait for stopped, and no rows from the binaries beside the sources |
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
- **`xwd -root` also fails on Xwayland**, so for a while a GTK menu — an
  override-redirect window of its own, not a child of the form — read as
  something that could not be photographed at all, twice. **That was wrong**, and
  `popshot` is the answer: those windows ARE in the root's tree, and the only
  hard part is telling them from the LCL's three permanent decoys. The script
  records the process's own top-level windows once, before anything can pop up,
  and photographs whatever is new. A hint window came out 217x42 on the first
  try. Menus and the completion list are reachable the same way.
- **Nothing may steal focus mid-script.** A GTK menu holds a keyboard grab, and
  `XSetInputFocus` on the form drops it, so consecutive keys go in ONE `xdrive`
  invocation and every invocation is `nofocus` unless the script says `raise`.
- **A background GUI holding ssh's stdout keeps ssh from returning** even after
  the script ends. `setsid` plus a redirect.

**Two columns are both called "the caret's column", and only one indexes
`LineText`.** `CaretX` is `FCaret.CharPos`, which `syneditpointclasses.pas:823`
computes through `LogicalToPhysical` -- a DISPLAY column -- and
`LogicalCaretXY.X` is `FCaret.LineBytePos` (`synedit.pp:2935`). `LineText` is
bytes. `steps-accent.txt` is the case that shows it, and it carries an ASCII
control line for a reason: the first run of it failed on BOTH lines, and the
cause was not the column at all but `Ctrl+End`, which SynEdit implements from
`Length(Lines[last])` -- a byte count used as a physical column -- so it lands
two columns past the end of a UTF-8 line.

**A GTK popup needs `popshot`, not `shot`.** The completion list, a menu and the
signature hint are each an override-redirect window of their own, so
`xwd -id <win>` shows the editor with nothing over it. `popshot` photographs the
window that was not there at startup -- and it tries EVERY window that was not
there, in order, rather than the first. A MODAL DIALOG is an ordinary top-level,
so mutter gives it a frame; the frame is new too, carries the same WM_CLASS, and
comes first in the tree, and `XGetImage` on a frame is `BadMatch`. That is the
trap at the top of this file met a second time from the other side, and it cost
one run of the Go to Definition case on 2026-09-16. Where a popup's EFFECT is the thing under
test — what the line says after Return — asserting that is still better than a
picture of it.

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

`SendKeys` is enough for the keyboard, with two escapes. `type` is literal text,
so `+ ^ % ~ ( ) { } [ ]` are braced by the driver — `type s = mid$(` opened a
modifier group and ate what followed, and the line came out as `s = mid$ bc",`.
`key` is a chord, so a step that wants a literal `)` writes `key {)}`. And
`key ^<space>` is Ctrl+Space: every line is trimmed and SendKeys has no
`{SPACE}`.

**THE LAYOUT DECIDES WHAT ARRIVES, ON BOTH SIDES, DIFFERENTLY.** SendKeys types
CHARACTERS, and on an ABNT2 keyboard `"` is a DEAD KEY: `"a` composes to a
diaeresis and both characters vanish, which is why the fixtures here write `"z`.
XTest injects a KEYCODE, and a keycode is a physical key carrying several symbols
at different shift levels: `XKeysymToKeycode('dollar')` names the key and not how
to reach it, so on the same Brazilian map pressing it bare typed `mid4(`. `xdrive`
now asks `XKeycodeToKeysym` which level the symbol is on and presses Shift or
AltGr to match. Both were measured on 2026-09-16, and both looked like editor
bugs first.

The two facts that are not obvious:

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
