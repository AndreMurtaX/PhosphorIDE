# Getting started with Phosphor and PhosphorIDE

This page takes you from nothing to a running debug session. It spans **two
repositories**, because the editor and the language are two programs and that is
the whole design:

- **Phosphor** — the language. A BASIC interpreter plus a console host, `phosphor`.
  It compiles, runs, checks and packs `.bas` files, and it speaks a debug protocol.
- **PhosphorIDE** — the editor, `phosphoride`. It edits `.bas` files and **drives
  `phosphor` as a child process**. It does not contain an interpreter and never
  will: a script that loops forever or faults has to take its own process down, not
  the one holding your unsaved work.

Everything below has been run on Windows 11 and on Ubuntu 24. Where the two differ,
both are given.

---

## 1. What you need first

| | version | why |
| --- | --- | --- |
| **Free Pascal** | 3.2.2 | both repositories are written in it |
| **Lazarus** | 3.6 or 4.8 | the editor uses the LCL and SynEdit |
| **Python** | 3.x | the generators and several test gates are Python |

On Linux you also need the **gtk2** development packages, because that is the
widgetset the editor is built against.

There are no other dependencies. Neither repository downloads anything at build
time.

### Where to put them

Put the two checkouts **side by side**:

```
C:\Dev\Phosphor
C:\Dev\PhosphorIDE
```

That is not cosmetic. When the editor looks for the `phosphor` binary it searches
six places in order, and `../Phosphor/bin/phosphor` is the fourth — the layout of
someone working on both (`src/core/uphosphorhost.pas:8-24`). Put them side by side
and the editor finds the interpreter with no configuration at all.

---

## 2. Build the language first

The editor is useless without it, so start here.

```powershell
cd C:\Dev\Phosphor
powershell -NoProfile -File scripts\build.ps1
```

```bash
cd ~/Phosphor
bash scripts/build.sh
```

It should end with two lines naming the binary it built and the version it answered.
If it does, you have `bin/phosphor`.

**Try it on its own**, before involving the editor:

```bash
bin/phosphor --version
bin/phosphor --help
```

A bare `phosphor` with no arguments opens a REPL — variables and functions persist
across lines. It prints how to leave it in its own banner; take that rather than this
page's word for it.

---

## 3. Build the editor

```powershell
cd C:\Dev\PhosphorIDE
powershell -NoProfile -File scripts\build.ps1
```

```bash
cd ~/PhosphorIDE
bash scripts/build.sh
```

The script does four things and refuses to say "built" unless all four worked: it
regenerates nothing but **checks** that the two generated units are current, builds
the editor clean, builds the test program, and runs `--selftest` under a timeout.

It ends with `built and checked:` and the path.

---

## 4. Check that it is really working

Three commands, and they are the same three the project's own bar uses. Run them
before you believe anything else on this page.

```bash
bin/phosphoridetest                       # prints "<n> checks, all green." and exits 0
```

```powershell
$p = Start-Process bin\phosphoride.exe -PassThru `
       -ArgumentList '--selftest', "$env:TEMP\report.txt"
if (-not $p.WaitForExit(30000)) { $p.Kill(); throw '--selftest hung' }
$p.ExitCode
```

That is more ceremony than it looks like it needs, and every line of it earns its
place. `Start-Process` is there because a GUI-subsystem binary does not hold the
shell, so a bare call returns at once and tells you nothing; `WaitForExit` with a
number is the timeout; and `$p.ExitCode` is read off the process rather than from
`$LASTEXITCODE`, which would be measuring the wrong thing.

```bash
xvfb-run -a timeout 30 bin/phosphoride --selftest /tmp/report.txt; echo $?
```

`--selftest` constructs every window once, writes what it found to the report file
and exits 0 or 1. **It reports through a file and an exit code, never through
stdout**, because a Windows GUI binary has no console and a `WriteLn` into an
invalid handle becomes a modal dialog with nobody there to dismiss it. Open the
report — it lists what it built and counted, and it is the quickest picture of
whether the program is whole.

On Linux the selftest needs a display. `xvfb-run` gives it one; if you are sitting
at the machine, `DISPLAY=:0` works too.

---

## 5. Your first program

Start the editor and type this:

```basic
rem hello
nome$ = "Ada"
total = 0
for i = 1 to 3
  total = total + i
  println "i="; i; " total="; total
next
println "hello, "; nome$
```

- **F9** runs it. Output appears in the Output tab at the bottom.
- **Ctrl+F9** checks the syntax without running.
- **Ctrl+F2** stops a program that is still going.

Break it on purpose — delete the `next` — and press Ctrl+F9. The Problems tab fills,
and **double-clicking a problem jumps to the line**. Not every message has a line:
`file not found:` and a `--check` warning carry no location, and those rows have no
`(n)` in them and jump nowhere, deliberately.

Files are saved as **UTF-8 with no byte-order mark**. That matters: the host strips
a BOM from a file but not from a line typed at the REPL, so a BOM would cost you
your first line there.

---

## 6. Your first debug session

This is the part worth trying, because it is the part two programs have to agree on.

1. Put the caret on the `total = total + i` line and press **F5**. A maroon dot
   appears in the gutter.
2. Press **Shift+F9** — Start Debugging.
3. The program runs and stops on your line. A navy band marks where it is.
4. The **Call Stack** and **Variables** tabs fill. Click a frame in the call stack
   and the variables follow it.
5. **F8** steps over, **F7** steps into, **Shift+F8** steps out, **F6** continues.
6. Press F6 twice more and watch it stop again on each pass of the loop.

**A hollow ring instead of a solid dot** means the host could not arm that line —
a blank line, a comment or an `endif` has no statement to stop at. The editor draws
the difference because the host answers which lines it actually installed.

**If Start Debugging is greyed out**, the editor has not found a `phosphor` that
speaks the protocol. `Debug > Why is stepping unavailable?` says which of the six
search positions it tried and what it found.

---

## 7. What works today

Honest, as of 2026-09-17.

| | state |
| --- | --- |
| Editing `.bas` in tabs, with a purpose-built highlighter | yes |
| Run, Check Syntax, Stop — as a child process, never blocking the window | yes |
| Problems pane, with jump-to-line for the messages that carry one | yes |
| Completion (Ctrl+Space) and signature help, from the real function catalogue | yes |
| Find, Replace, **Find in Files** and **Replace in Files** across a tree | yes |
| Outline pane, and **F12** to a definition | yes |
| Folding, and **Ctrl+Shift+M** to the other end of a block | yes |
| An embedded REPL, and **Ctrl+Shift+Enter** to send the selection to it | yes |
| Breakpoints that follow your edits, and that survive a fold | yes |
| **Step debugging** — start, breakpoints, over/into/out, continue, stop | yes, both platforms |
| Call stack pane, with every frame carrying its line | yes |
| Variables pane, locals and globals, by frame | yes |
| A failed run tinting the line it blamed | yes |
| `evaluate` — the host computes an expression at a stop | yes, **host side only** |

## 8. What does not work today

Said plainly, because a limitation recorded in the present tense is a claim with an
expiry date nobody set.

- **No watch pane.** The host answers `evaluate` and the editor reads the capability,
  but nothing consumes it yet. That is roadmap item 26.
- **No conditional breakpoints.** `capabilities.conditionalBreakpoints` is false and
  the protocol field is not yet specified. Also item 26.
- **`evaluate` refuses every function call you write.** `count% * 2`, `a$ + b$`,
  `x > 3 and y < 9`, a local, a global, a `const` and `a@[i]` all answer. `len(x$)`
  does not, and will not until the engine's registry can say whether a function has
  an effect. The host says so up front, in a second capability key called
  `evaluateCalls`.
- **A hot breakpoint can lose a hit.** Measured over eleven runs of a
  10 000-iteration loop, between 1 and 13 stops in ten thousand never reached the
  editor. It is not a conditional-breakpoint problem — it happens with a plain
  breakpoint too — and it is not yet diagnosed.
- **The gtk2 menu bar cannot be driven by a script.** It answers neither a synthetic
  click nor F10 from XTest, so it is the one part of the Linux UI that is only ever
  checked by a person.

---

## 9. The keys

Read out of `src/umainform.lfm` rather than from memory.

| | |
| --- | --- |
| Ctrl+N / Ctrl+O / Ctrl+S / Ctrl+Shift+S | New, Open, Save, Save As |
| Ctrl+W / Ctrl+Q | Close Tab, Exit |
| Ctrl+F / F3 / Ctrl+R | Find, Find Next, Replace |
| Ctrl+Shift+F | Find in Files |
| Ctrl+G | Go to Line |
| F12 | Go to Definition |
| Ctrl+Shift+M | Go to Matching Block |
| Ctrl+Space | Complete Word |
| Ctrl+Shift+O / Ctrl+Shift+R | Outline, REPL |
| Ctrl+Shift+Enter | Send selection to the REPL |
| **F9 / Ctrl+F9 / Ctrl+F2** | **Run, Check Syntax, Stop** |
| **F5** | **Toggle Breakpoint** |
| **Shift+F9** | **Start Debugging** |
| **F8 / F7 / Shift+F8 / F6** | **Step Over, Into, Out, Continue** |

---

## 10. If something goes wrong

**The editor builds but the form looks wrong.** A changed `.lfm` needs a CLEAN
build: `lazbuild -B`. Without it the old form resource is kept and the binary
streams the previous version of the window. Both build scripts pass `-B` for exactly
this reason, so use the scripts rather than a bare `lazbuild`.

**`--selftest` hangs instead of answering.** That is what the timeout is for. It is
almost always a modal dialog nobody can dismiss — usually an `.lfm` naming a property
its `.pas` does not publish, which the LCL reports by asking a question and waiting.

**The editor cannot find `phosphor`.** In order: set it in Preferences; or set
`$PHOSPHOR_HOST`; or put the checkouts side by side. Nothing is executed during the
search — a path that exists is reported as a candidate and only a path you have
settled on is ever probed.

**A run fails with exit code 2 and no line number.** That is the host refusing to run
rather than the program failing. The codes are: **0** fine, **1** the BASIC program
failed, **2** the host refused so nothing executed, **3** the interpreter itself
faulted.

---

## 11. Where to read next

| | |
| --- | --- |
| [`README.md`](../README.md) | what the editor is, feature by feature |
| [`docs/building.md`](building.md) | the build in detail, and the checks |
| [`docs/architecture.md`](architecture.md) | how it is put together, and why |
| [`docs/debug-protocol.md`](debug-protocol.md) | PDBP, the wire format both ends agree on |
| [`docs/debugger-lane.md`](debugger-lane.md) | how the debugger is driven and verified |
| [`docs/roadmap.md`](roadmap.md) | what is done, what is next, and what each cost |
| `../Phosphor/README.md` | the language itself |
| `../Phosphor/docs/debugging.md` | the host's end of the debugger, including `evaluate` |

**One habit worth borrowing before you change anything.** Both repositories hold the
same rule: nothing is done on a claim. An increment is complete when it builds with
zero warnings *and* zero notes, the checks are green, the selftest exits 0 under a
timeout, the generated units are current, **and it is green on the other operating
system too**. Windows-green has shipped Linux-broken defects in this pair of
repositories more than once.
