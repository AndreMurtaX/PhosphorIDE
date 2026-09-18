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

## A case is written twice, not once

The two drivers share **six verbs of eight**, and do not share key names at all.

| | |
| --- | --- |
| both | `key`, `type`, `wait`, `raise`, `shot`, `at`, `text` |
| Windows only | `dblclick`, `memo`, `says` |
| Linux only | `at2` (what `dblclick` is called there), `bot` and `bot2` (a click measured UP from the bottom edge, because mutter gives the window a different height on different runs), `outtab`, `rootshot`, `popshot`, `say`, `menu` |

`text <needle>` is the one verb that means the same thing on both sides and gets there
by different roads: it ASSERTS that some control in the window says the needle, counts
what fails, and decides the run's exit code. Linux asks AT-SPI through `readtext.py`;
Windows sends `WM_GETTEXT` to every visible child. It arrived here on 2026-09-17, with
the stdin row's hint -- before that this side only had `memo`, which PRINTS, and a lane
that only prints is a lane somebody has to read. `says` and `say` are the matching dump
verbs, for writing a case rather than for asserting in one.

`key` is **SendKeys** on Windows (`^g`, `{ENTER}`, `{F5}`, `+{F9}`) and an **X
keysym** on Linux (`ctrl+g`, `Return`, `F5`, `shift+F9`).

**Feeding one driver the other's script does not fail.** SendKeys renders any
token it does not recognise as literal text, so `steps-lane.txt` run through
`lane-windows.ps1` on 2026-09-17 typed `ctrlGctrlA3ReturnF5...` into the fixture
and drove nothing at all. The screenshots came out, the run reported no error, and
only reading them showed it. It cost one run, and nothing worse only because the
driver kills the editor without saving.

So the file names carry the platform: **`steps-NAME.txt` is the Windows driver's
and `steps-NAME-linux.txt` is the Linux one's.** Four files predate that rule and
are **Linux-only despite having no suffix** — `steps-lane.txt`,
`steps-blocked.txt`, `steps-exception.txt` and `steps-stop.txt`. Their Windows
counterparts are not missing: they are `lane-windows-steps.ps1`,
`lane-windows-session.ps1` and `lane-windows-exception.ps1`, written before the
generic driver existed, with the steps baked into the PowerShell.

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
| `steps-blame.txt`, `steps-blame-linux.txt` + `blame.bas` | roadmap item 24: a failed run tinting the line it blamed, the tint surviving a scroll, a second run replacing rather than accumulating it, and an edit to that line clearing it. The edit is LAST on purpose — F9 saves before it runs, so any run after an edit would leave this fixture changed |
| `steps-sendrepl.txt`, `steps-sendrepl-linux.txt` + `sendrepl.bas` | roadmap item 23: five selected lines reaching the prompt as five lines, each after its own prompt and the middle three after the continuation, a REPL started by the send itself, and `twice` callable afterwards |
| `steps-matching.txt`, `steps-matching-linux.txt` + `matching.bas` | roadmap item 22: the pair outlined in the text (SynEdit's own markup, once the highlighter offers fmMarkup), Ctrl+Shift+M jumping both ways, a pair that opens and closes on one line, and the four answers for a word that only looks like a block keyword |
| `replace-tree.ps1`, `replace-tree.sh` | roadmap item 21, and NOT a step file: it builds a four-file tree in the temp directory, drives a search and a replace over it, and compares the BYTES before and after — which is the only way to check that the files nobody listed were not touched and that the ones that were kept their line endings. A checked-in fixture would be rewritten on every run |
| `steps-hidden.txt`, `steps-hidden-linux.txt` | roadmap item 20: a breakpoint inside a collapsed function, the badge the header then carries, the gutter click that OPENS the block instead of adding a second breakpoint, and the control case — a collapsed header hiding nothing, which toggles like any other line |
| `steps-typing.txt` + `typing.bas` | roadmap item 19, DRIVEN: 2000 lines, a word one character short of a definition at the top, the keystroke that completes it, and the fold marker arriving. The NUMBER is not here -- it comes from `phosphoride --measure-typing`, and the script says why two ways of timing it from outside the process both lie |
| `steps-accent.txt` + `acentos.bas` | the byte column: the same statement with and without accents, and the popup filtered on both |
| `steps-find.txt`, `steps-find-linux.txt` | find in files: the pane, a jump into a file that was not open, a walk of ~1000 files finished, a walk nobody would wait for stopped, and no rows from the binaries beside the sources |
| `steps-stdin.txt`, `steps-stdin-linux.txt` + `stdin.bas` | the stdin row, and the hint that says what it is: the prompt arriving as an unterminated tail, the hint readable before anything is typed, the box clicked the way a person has to click it, and the child receiving `Andre` rather than the 45 characters of the hint. Written because the clause this proves had been GREEN since the morning -- see roadmap item 1 -- while the author of the editor was killing an INPUT program rather than answering it |
| `steps-toolbar.txt` | nothing driven: the toolbar, to look at |
| `lane-linux.sh` + `xdrive.lpr` + `shot.py` | the Linux half |
| `lane-windows.ps1` | the Windows driver: takes a fixture and a step script, the same VERBS as the Linux one — but not the same key names, see below |
| `lane-windows-*.ps1` + `win.ps1` + `gettext.ps1` | the earlier, single-purpose Windows drivers, with their steps baked into the PowerShell: they are the Windows half of the four cases that have no `-linux` twin |
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
- **AND ON WINDOWS, `SendKeys` TYPES INTO WHOEVER HAS FOCUS -- INCLUDING AN APP
  THAT IS NOT YOURS.** `raise` at the top of a script is not enough, because it
  answers the question once and the desktop keeps asking it. Measured twice on
  2026-09-18: `steps-stdin.txt` was run while the agent driving it was streaming
  output into a chat window on the same desktop, that window took focus back
  between the `raise` and the `type`, and the fixture's answer went into the chat
  instead of into the editor. The shots prove it -- `3-typed.png` and
  `4-answered.png` are photographs of the chat client. The case then failed on
  `< Andre` and `hello, Andre` with a `phosphor` child still alive, which reads
  exactly like a stdin row that does not work.

  There is no defence inside the script: `SendKeys` has no target window, and the
  Linux side's `xdrive` does (`nofocus` sends to a window id). So the rule is
  operational rather than technical -- **a Windows lane run owns the desktop for
  its duration.** Do not run one on a machine somebody is using, and if a case
  fails on an assertion about text the script typed, look at the shot before
  looking at the editor.

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
read as a pane that did not work.

**AND THE BOTTOM EDGE IS NOT THE SAME CONTROL ON BOTH PLATFORMS.** `StatusBar1` and
`PagesOutput` are both `alBottom`, and the two widgetsets order that pair differently:
win32 puts the status bar at the very bottom with the output panel's input row above
it, gtk2 puts the status bar ABOVE the output panel, so on this side the input row is
flush with the window's bottom edge. An offset carried over from a Windows script is
therefore one control out. Measured on 2026-09-17 by scanning a screenshot's rows for
where the bands change, which is the cheap way to calibrate a `bot` and worth doing
once per pane rather than reasoning from control heights. The output panel is bottom-anchored; from the bottom
every row keeps its place.

Still not driveable **through XTest**: the gtk2 **menu bar**, from a synthetic click or
from F10 navigation. It IS driveable through **AT-SPI** -- `readtext.py --invoke <name>`,
and the `menu <name>` verb that wraps it, perform a menu item's exposed action and open
what a click would open. `Debug > Stop Debugging` is still driven on Windows, and on
Linux the same teardown is still reached from the process side by `steps-stop.txt`: that
case was written before the verb existed, it asserts the child is gone rather than that a
menu opened, and it is the stronger question of the two.

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

  **AND NEITHER DOES `GetWindowTextLengthW`, WHICH IS THE HALF THAT BITES.**
  `Wnd::Kids` asks it first and skips the read when it answers 0, so the text
  column of every row it returns is empty for exactly the panes and edits a lane
  wants to assert on -- a column that looks like an answer and is an artefact.
  Measured on 2026-09-17 against `EditInput`, whose TextHint was plainly drawn in
  the screenshot at the time: `GetWindowTextLengthW` said 0 and an explicit
  `WM_GETTEXTLENGTH` said 45. Believing the 0 cost an afternoon and two wrong
  theories -- that the hint lived in a cue banner no message could reach, and then
  that UI Automation was needed to get it out. Nothing in this directory reads that
  column; every caller sends `WM_GETTEXT` for itself, and so should you.

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
