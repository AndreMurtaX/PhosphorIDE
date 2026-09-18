program phosphorcontract;

{ The one coupling between the two repositories that had no automatic check.

  `src/core/uphosphormsg.pas` is tested by forty-odd checks in
  `tests/phosphoridetest.lpr` -- against strings THIS repository wrote down, not
  against the binary. If Phosphor reworded a message, renumbered an exit code or
  moved a diagnostic to stdout, every one of those checks would still pass and
  jump-to-error would silently stop working. This program runs the ACTUAL
  `phosphor` binary against fixtures that are broken on purpose and asserts the
  shapes the editor parses.

  It also cuts the other way, which is the better half: it is the only thing that
  can tell the engine's authors that a message they improved reached a consumer.

  ---------------------------------------------------------------- WHY SEPARATE

  Not a mode of `phosphoridetest`, for three reasons each sufficient:

  * THAT PROGRAM'S EXIT CODE IS ALREADY SPOKEN FOR. It ends `Halt(Failures)` --
    the code IS the failure count. This one needs a third answer, SKIPPED, which
    is neither zero nor a count.
  * THAT PROGRAM IS HERMETIC and it is worth keeping so structurally rather than
    by discipline. It spawns nothing and depends on no other repository. Merged,
    "850 checks, all green" would quietly come to mean "green against whichever
    binary happened to be on this machine".
  * THE UNIT LISTS DIVERGE IN THE RIGHT DIRECTION. This program needs LazUtils
    and nothing else -- no LCL, no SynEdit. The trap CLAUDE.md records (linking
    `SynEdit` headless dies BEFORE `main`, silently, with exit code 0 and no
    output) stops being something an author must remember and becomes a fact
    about the project file.

  The scoreboard is shared rather than copied: `checks.inc`.

  ------------------------------------------------------------- THE EXIT CODES

      0       every shape held
      77      no host found; NOTHING RAN, and it said so
      1..76   that many checks failed

  77 is the automake convention for skipped. There are nowhere near 76 checks
  here, but "nowhere near" is how a defect gets a year of runway, so a count that
  would reach 77 is clamped to 76 and the true number is printed beside it.

  A SKIP IS ANNOUNCED, because a check that quietly does not run reads as a pass.
  And `--require-host` removes the skip entirely: in CI the binary is built two
  steps earlier, so a skip there can only mean the build step lied.

  --------------------------------------------- WHAT IS HARD AND WHAT IS SOFT

  A test in this repository must never become the reason Phosphor cannot reword a
  message. The line:

      A MESSAGE THIS REPOSITORY HAS COPIED INTO ITS OWN SOURCE IS HARD.
      A MESSAGE IT MERELY OBSERVES IS SOFT.

  `uphosphormsg.pas` quotes `no function nosuchfunc$:%`, `cannot open "cafe.txt"
  for input: no such file` and `file not found: nope.bas` as its worked examples.
  Those are not observations; they are facts about the other repository retyped
  into this one -- the thing CLAUDE.md forbids, allowed there only because a
  design header needs a concrete example. `check-citations.py` cannot protect
  them: they carry no `file:line`, which is exactly the second failure mode that
  tool's own docstring says no mechanism finds. THIS PROGRAM IS THAT MECHANISM.
  If one of them is reworded, that header lies, and a red build naming the string
  is the correct answer.

  Everything else is SOFT: checked, reported as `WORDING MOVED`, printed in the
  summary, and not counted as a failure.

  What is hard regardless of wording is the FRAMING, which is the actual
  contract: the `phosphor: ` prefix byte-exact, the `:<digits>: ` separator, the
  echoed path byte-equal to the argument passed, the line number, the stream each
  thing arrives on, one diagnostic per failed run, the exit code -- and, on every
  captured line, what `ParsePhosphorMessage` makes of it. That last one is what
  actually protects jump-to-error, and it is wording-independent by construction.

  ------------------------------------------------ THREE GAPS PINNED AS TRUTH

  Measured 2026-09-17, and all three are the editor's, not the host's. They are
  asserted AS THEY ARE rather than as `uphosphormsg.pas` wishes they were, so
  that whichever side is fixed, the other cannot drift quietly. Roadmap item 30
  is where they are written up; this program becomes its regression test.

  1. `usage:` lines carry NO `phosphor: ` prefix, so they come back pmkPlain.
     The unit's header lists `usage:` among the shapes that reach pmkHostError.
     It cannot: ParsePhosphorMessage returns early on any line lacking the
     prefix.
  2. `phosphor debug: ` is a SECOND prefix the parser does not know, so every
     `--port` refusal reaches the Output pane as ordinary program text -- on
     exactly the path where the editor most wants to surface a refusal.
  3. A refusal whose echoed path contains `:12: ` FORGES a source location:
     `phosphor: file not found: a:12: b.bas` parses as pmkSourceError, path
     `file not found: a`, line 12, jumpable. Unreachable by accident on Windows,
     where a path cannot contain a colon; reachable by accident on Linux, where a
     filename may legally contain one.

  --------------------------------------------------- AND WHAT IS NOT ASSERTED

  * EXIT CODE 3. The taxonomy says the interpreter faulted. Measured over deep
    recursion (guarded at 262 144 frames, answers 1), 200 000 nested parens
    (guarded at 256 levels, answers 1) and four kinds of corrupt bytecode (all
    guarded, all 1), the only provocation found cost 126 seconds and a 24 GB
    working set. Every natural route is closed upstream by design. This program
    must never try to make the binary produce a 3; `PhosphorExitCodeText(3)`
    stays a pure-string check in `phosphoridetest`, where it already is.
  * A LINE NUMBER PAST THE END OF THE FILE. `uphosphormsg.pas` gives "an
    unterminated block in a three-line file reports line 4" as its example. It is
    not true today: 34 constructed shapes, not one past the end, because
    unterminated blocks go through Phosphor's `FailUnterminated`, which names the
    line the block OPENED on. The parser's handling of such a line stays pinned
    on a synthetic string in `phosphoridetest`, and the editor's clamp stays as
    defensive code -- both correct, neither provable here.
  * THE OS TAIL OF `cannot write to <path>: <message>`. That tail is Ex.Message
    from the FPC RTL, localised by the OS and emitted in the CONSOLE OEM
    codepage: measured byte $C6 where a-tilde belongs, which is CP850 and is
    neither UTF-8 nor CP1252. Asserting it would fail on an English machine, and
    it is a real counter-example to CLAUDE.md's "the host emits UTF-8" invariant
    -- a defect belonging to the sibling repository.
  * `--help`'s text, length or layout. Only `udebugsession`'s actual predicate:
    that some line, trimmed, begins with `phosphor debug`.
  * The version NUMBER. Non-empty, on stdout, exit 0. `uphosphorhost.pas` says
    the format is the host's to change, deliberately. }

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, FileUtil, LazFileUtils,
  uphosphormsg, uphosphorhost, uhostprobe;

{ The scoreboard, shared with tests/phosphoridetest.lpr. }
{$I checks.inc}

const
  SkipExitCode = 77;
  MaxFailExitCode = 76;

  { The packed executable this program builds and then runs. }
  PackedName = {$IFDEF WINDOWS} 'boom.exe' {$ELSE} 'boom' {$ENDIF};

var
  Host: String = '';
  HostVersion: String = '';
  RequireHost: Boolean = False;
  WorkDir: String = '';
  MovedShapes: TStringList = nil;
  SoftMoves: TStringList = nil;
  LastFixture: String = '';
  LastCommand: String = '';
  LastResult: TRunResult;

{ ------------------------------------------------------------- the reporter -- }

{ A SHAPE'S IDENTITY IS THE PAIR (kind, how it was reached) -- `pmkSourceError
  (runtime)` -- because two of them are the same shape reached two ways, and a
  message naming only the kind sends a reader to the wrong fixture.

  The shape name has to survive into the SUMMARY and not only appear in a block
  forty lines up: the last line of output is the part a CI reader actually sees,
  and roadmap item 2a asks for a log that names which shape moved. }
procedure ShapeFail(const AShape, AWhat, AExpected, AGot: String);
begin
  Inc(Failures);
  if MovedShapes.IndexOf(AShape) < 0 then
    MovedShapes.Add(AShape);
  WriteLn;
  WriteLn('FAIL  [', Section, '] SHAPE MOVED: ', AShape);
  WriteLn('        what:     ', AWhat);
  WriteLn('        fixture:  ', LastFixture);
  WriteLn('        command:  ', LastCommand);
  WriteLn('        expected: ', AExpected);
  WriteLn('        got:      ', AGot);
  WriteLn('        exit:     ', LastResult.ExitCode);
  WriteLn('        stdout:   ', Describe(LastResult.StdOut));
  WriteLn('        stderr:   ', Describe(LastResult.StdErr));
  WriteLn('        host:     ', Host, '  (', HostVersion, ')');
end;

{ A hard assertion: a mismatch is a failure. }
procedure ShapeEq(const AShape, AWhat, AExpected, AGot: String);
begin
  Inc(Checks);
  if AExpected = AGot then
    Exit;
  ShapeFail(AShape, AWhat, AExpected, AGot);
end;

procedure ShapeEqInt(const AShape, AWhat: String; AExpected, AGot: Integer);
begin
  ShapeEq(AShape, AWhat, IntToStr(AExpected), IntToStr(AGot));
end;

{ AGot is what to SHOW when it did not hold -- the captured text, usually, since
  `expected: true / got: false` tells a reader nothing they can act on. }
procedure ShapeTrue(const AShape, AWhat: String; ACondition: Boolean;
  const AGot: String);
begin
  Inc(Checks);
  if ACondition then
    Exit;
  ShapeFail(AShape, AWhat, 'the condition above to hold', AGot);
end;

{ A SOFT assertion: engine wording this repository merely observes. Reported,
  counted in the summary, and NOT a failure -- because a reword in Phosphor must
  not be a red build here, and because telling the engine's authors that a
  message reached a consumer is the half of item 2a worth the most. }
procedure Wording(const AShape, AWhat, AExpected, AGot: String);
begin
  Inc(Checks);
  if AExpected = AGot then
    Exit;
  SoftMoves.Add(Format('%s -- %s: was "%s", now "%s"',
    [AShape, AWhat, AExpected, AGot]));
  WriteLn('note  [', Section, '] WORDING MOVED: ', AShape);
  WriteLn('        was:  ', AExpected);
  WriteLn('        now:  ', AGot);
end;

{ ------------------------------------------------------------------ running -- }

function ArgValue(const AName: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to ParamCount - 1 do
    if ParamStr(I) = AName then
      Exit(ParamStr(I + 1));
end;

function HasArg(const AName: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if ParamStr(I) = AName then
      Exit(True);
end;

{ Run the host in the work directory and remember what for, so a failure block
  can name the command that produced it without every caller repeating itself. }
function Go(const AFixture: String; const AArgs: array of String;
  const AStdIn: String = ''): TRunResult;
var
  I: Integer;
begin
  LastFixture := AFixture;
  LastCommand := 'phosphor';
  for I := Low(AArgs) to High(AArgs) do
    LastCommand := LastCommand + ' ' + AArgs[I];
  if AStdIn <> '' then
    LastCommand := LastCommand + '   (stdin: ' + StringReplace(AStdIn,
      #10, '\n', [rfReplaceAll]) + ')';
  Result := RunHost(Host, WorkDir, AArgs, AStdIn);
  LastResult := Result;
  if not Result.Ok then
  begin
    Inc(Failures);
    WriteLn('FAIL  [', Section, '] the host did not answer: ', Result.Diagnostic);
    WriteLn('        command:  ', LastCommand);
  end;
end;

{ The first line of a stream, or a marker naming what was there instead. Every
  assertion below wants one line and wants to say so when it did not get one. }
function FirstLine(const AText: String): String;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    SplitLines(AText, L);
    if L.Count = 0 then
      Exit('(no lines)');
    Result := L[0];
  finally
    L.Free;
  end;
end;

function LineCount(const AText: String): Integer;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    SplitLines(AText, L);
    Result := L.Count;
  finally
    L.Free;
  end;
end;

{ What the REAL parser made of a line, for the two assertions that are about the
  path and the line rather than about the whole classification. Going through
  ParsePhosphorMessage rather than doing the split here is the point: a helper
  that did its own splitting would be a second parser, and a second parser is
  what this whole program exists to prevent. }
function ParsedPathOf(const ALine: String): String;
var
  M: TPhosphorMessage;
begin
  ParsePhosphorMessage(ALine, M);
  Result := M.Path;
end;

function ParsedLineOf(const ALine: String): Integer;
var
  M: TPhosphorMessage;
begin
  ParsePhosphorMessage(ALine, M);
  Result := M.Line;
end;

{ Feed a captured line to the REAL parser and assert what it made of it. This is
  the assertion that actually protects jump-to-error: it does not care what the
  message says, only where the editor thinks the error is. }
procedure ParsesAs(const AShape, ALine: String; AKind: TPhosphorMsgKind;
  const APath: String; ALineNo: Integer; AJumpable: Boolean);
var
  M: TPhosphorMessage;
  Parsed: Boolean;
begin
  Parsed := ParsePhosphorMessage(ALine, M);
  ShapeEqInt(AShape, 'ParsePhosphorMessage kind', Ord(AKind), Ord(M.Kind));
  ShapeEq(AShape, 'ParsePhosphorMessage path', APath, M.Path);
  ShapeEqInt(AShape, 'ParsePhosphorMessage line', ALineNo, M.Line);
  ShapeEq(AShape, 'ParsePhosphorMessage raw is the line unmodified', ALine, M.Raw);
  ShapeTrue(AShape, 'HasSourceLocation', HasSourceLocation(M) = AJumpable,
    BoolToStr(HasSourceLocation(M), True));
  { Result and pmkPlain move together: the unit answers False exactly when it
    found nothing it recognised. }
  ShapeTrue(AShape, 'parsed answers whether it was a diagnostic',
    Parsed = (M.Kind <> pmkPlain), BoolToStr(Parsed, True));
end;

{ ------------------------------------------------------------------- checks -- }

procedure TestSourceErrors;
var
  R: TRunResult;
  Abs: String;
begin
  Group('pmkSourceError: the only shape that can be jumped to');

  R := Go('syntax.bas', ['run', 'syntax.bas']);
  ShapeEqInt('pmkSourceError (compile)', 'exit code', 1, R.ExitCode);
  ShapeEqInt('pmkSourceError (compile)', 'one diagnostic, not a list',
    1, LineCount(R.StdErr));
  ShapeEq('pmkSourceError (compile)', 'nothing on stdout', '', R.StdOut);
  Wording('pmkSourceError (compile)', 'the diagnostic line',
    'phosphor: syntax.bas:2: unexpected token in expression', FirstLine(R.StdErr));
  ParsesAs('pmkSourceError (compile)', FirstLine(R.StdErr),
    pmkSourceError, 'syntax.bas', 2, True);

  R := Go('divzero.bas', ['run', 'divzero.bas']);
  ShapeEqInt('pmkSourceError (runtime)', 'exit code', 1, R.ExitCode);
  ShapeEqInt('pmkSourceError (runtime)', 'one diagnostic, not a list',
    1, LineCount(R.StdErr));
  Wording('pmkSourceError (runtime)', 'the diagnostic line',
    'phosphor: divzero.bas:4: division by zero', FirstLine(R.StdErr));
  ParsesAs('pmkSourceError (runtime)', FirstLine(R.StdErr),
    pmkSourceError, 'divzero.bas', 4, True);

  { A COMPILE ERROR AND A RUNTIME ERROR ARE TEXTUALLY INDISTINGUISHABLE, which is
    what uphosphormsg's "(compile or runtime)" comment claims and what lets one
    parser handle both. Nothing in the line says which phase it came from, and
    the exit code is 1 for each. }
  ShapeEqInt('pmkSourceError (both phases)', 'the same exit code for both',
    1, R.ExitCode);

  Group('the echoed path is the spelling the CALLER gave');

  { THE SHARPEST OF THE EIGHT SPELLINGS MEASURED. The file on disk is
    divzero.bas, Windows opened it case-insensitively, and the echo is still
    what was typed -- which is precisely why uphosphormsg says the editor must
    attribute an error to the file it PASSED rather than to the echo. }
  R := Go('DIVZERO.BAS', ['run', 'DIVZERO.BAS']);
  ShapeEq('path echo (case)', 'the echo is not case-folded to the real name',
    'DIVZERO.BAS', ParsedPathOf(FirstLine(R.StdErr)));

  Abs := IncludeTrailingPathDelimiter(WorkDir) + 'divzero.bas';
  R := Go(Abs, ['run', Abs]);
  ShapeEq('path echo (absolute)', 'an absolute path comes back verbatim',
    Abs, ParsedPathOf(FirstLine(R.StdErr)));
  ShapeEqInt('path echo (absolute)', 'and the line survives the drive colon',
    4, ParsedLineOf(FirstLine(R.StdErr)));
end;

procedure TestColons;
var
  R: TRunResult;
  Abs: String;
begin
  Group('messages that contain colons, which is why nothing splits on one');

  { HARD, not soft. uphosphormsg.pas quotes this exact string in its own header
    as a worked example -- a fact about the other repository retyped into this
    one. If it is reworded, that header lies. }
  R := Go('nofunc.bas', ['run', 'nofunc.bas']);
  ShapeEq('colon in message (retyped into uphosphormsg.pas)',
    'the header''s first worked example',
    'phosphor: nofunc.bas:2: no function nosuchfunc$:%', FirstLine(R.StdErr));
  ParsesAs('colon in message (retyped into uphosphormsg.pas)', FirstLine(R.StdErr),
    pmkSourceError, 'nofunc.bas', 2, True);

  R := Go('openfail.bas', ['run', 'openfail.bas']);
  ShapeEq('colon in message (retyped into uphosphormsg.pas)',
    'the header''s second worked example',
    'phosphor: openfail.bas:2: cannot open "cafe.txt" for input: no such file',
    FirstLine(R.StdErr));
  ParsesAs('colon in message (retyped into uphosphormsg.pas)', FirstLine(R.StdErr),
    pmkSourceError, 'openfail.bas', 2, True);

  { BOTH COLONS AT ONCE: a drive letter BEFORE the separator and a message colon
    AFTER it, in one line. This breaks a first-colon split and a last-colon split
    simultaneously, and it is the reason FindLineSeparator starts at index 3 and
    searches for `:<digits>: ` rather than for a colon. }
  Abs := IncludeTrailingPathDelimiter(WorkDir) + 'openfail.bas';
  R := Go(Abs, ['run', Abs]);
  ParsesAs('colon before AND after the separator', FirstLine(R.StdErr),
    pmkSourceError, Abs, 2, True);
end;

procedure TestStreams;
var
  R: TRunResult;
  L: TStringList;
begin
  Group('which stream each thing arrives on');

  R := Go('ok.bas', ['run', 'ok.bas']);
  ShapeEqInt('exit 0', 'a program that works', 0, R.ExitCode);
  ShapeEq('exit 0', 'nothing at all on stderr', '', R.StdErr);
  { `print` WITHOUT A TERMINATOR, which is the shape a drain loop that stops at
    `not Running` loses. Five bytes and no newline. }
  ShapeEq('exit 0', 'stdout is the program output, unterminated', 'hello', R.StdOut);

  R := Go('out_then_fail.bas', ['run', 'out_then_fail.bas']);
  ShapeEqInt('the stream split', 'exit code', 1, R.ExitCode);
  L := TStringList.Create;
  try
    SplitLines(R.StdOut, L);
    ShapeEqInt('the stream split', 'two lines of program output on stdout', 2, L.Count);
    if L.Count = 2 then
    begin
      ShapeEq('the stream split', 'stdout line 1', 'line one', L[0]);
      ShapeEq('the stream split', 'stdout line 2', 'line two', L[1]);
    end;
  finally
    L.Free;
  end;
  ShapeEqInt('the stream split', 'exactly one diagnostic on stderr',
    1, LineCount(R.StdErr));
  ShapeTrue('the stream split', 'no diagnostic leaked into stdout',
    Pos(PhosphorDiagPrefix, R.StdOut) = 0, R.StdOut);
  ShapeTrue('the stream split', 'no program output leaked into stderr',
    Pos('line one', R.StdErr) = 0, R.StdErr);
  ShapeTrue('the stream split', 'the diagnostic is terminated',
    (R.StdErr <> '') and (R.StdErr[Length(R.StdErr)] = #10),
    Describe(R.StdErr));
  ParsesAs('the stream split', FirstLine(R.StdErr),
    pmkSourceError, 'out_then_fail.bas', 4, True);
end;

procedure TestRefusals;
var
  R: TRunResult;
begin
  Group('pmkHostError: a refusal is not a location');

  { HARD: retyped into uphosphormsg.pas's header as the example of the shape a
    naive parser turns into a jump to line 0 of a file called `file not`. }
  R := Go('nope.bas (deliberately absent)', ['run', 'nope.bas']);
  ShapeEqInt('pmkHostError (file not found)', 'exit code -- nothing executed',
    2, R.ExitCode);
  ShapeEq('pmkHostError (file not found)',
    'the example retyped into uphosphormsg.pas',
    'phosphor: file not found: nope.bas', FirstLine(R.StdErr));
  ParsesAs('pmkHostError (file not found)', FirstLine(R.StdErr),
    pmkHostError, '', 0, False);

  { GAP 1, PINNED AS CURRENT TRUTH. uphosphormsg.pas's header lists `usage:`
    among the shapes that become pmkHostError. It cannot: the real line has no
    `phosphor: ` prefix, and ParsePhosphorMessage returns early without one. The
    assertion below is what today does, not what the header wishes. Roadmap item
    30. }
  R := Go('(no fixture -- an argument shape)', ['compile']);
  ShapeEqInt('usage: (gap 1)', 'exit code', 2, R.ExitCode);
  ShapeTrue('usage: (gap 1)', 'the line has NO `phosphor: ` prefix',
    Pos(PhosphorDiagPrefix, FirstLine(R.StdErr)) <> 1, FirstLine(R.StdErr));
  Wording('usage: (gap 1)', 'the usage line',
    'usage: phosphor compile [--check] <in.bas> <out.pbc>', FirstLine(R.StdErr));
  ParsesAs('usage: (gap 1)', FirstLine(R.StdErr), pmkPlain, '', 0, False);

  { GAP 2, PINNED AS CURRENT TRUTH. `phosphor debug: ` is a second prefix the
    parser does not know, so the debugger's own refusals reach the Output pane as
    ordinary program text -- on exactly the path where the editor most wants to
    surface one. Roadmap item 30. }
  R := Go('ok.bas', ['debug', '--port', '99999', 'ok.bas']);
  ShapeEqInt('phosphor debug: (gap 2)', 'exit code', 2, R.ExitCode);
  ShapeTrue('phosphor debug: (gap 2)', 'the prefix is `phosphor debug: `',
    Pos('phosphor debug: ', FirstLine(R.StdErr)) = 1, FirstLine(R.StdErr));
  Wording('phosphor debug: (gap 2)', 'the port refusal',
    'phosphor debug: --port wants 1..65535, got 99999', FirstLine(R.StdErr));
  ParsesAs('phosphor debug: (gap 2)', FirstLine(R.StdErr), pmkPlain, '', 0, False);

  { GAP 3, PINNED AS CURRENT TRUTH: a refusal whose echoed path carries
    `:<digits>: ` forges a source location, which is the exact failure the unit
    exists to prevent. On Windows a real path cannot contain a colon, so this
    needs a deliberately crafted argument; on Linux a filename may legally
    contain one and this becomes reachable by accident. Roadmap item 30. }
  R := Go('a:12: b.bas (a crafted name)', ['run', 'a:12: b.bas']);
  ShapeEqInt('forged location (gap 3)', 'exit code is still a refusal',
    2, R.ExitCode);
  ParsesAs('forged location (gap 3)', FirstLine(R.StdErr),
    pmkSourceError, 'file not found: a', 12, True);
end;

procedure TestWarningAndRepl;
var
  R: TRunResult;
begin
  Group('pmkWarning and pmkReplError: the two shapes with no path');

  R := Go('nofunc.bas', ['compile', '--check', 'nofunc.bas', 'w.pbc']);
  ShapeEqInt('pmkWarning', 'a --check warning NEVER fails', 0, R.ExitCode);
  ShapeTrue('pmkWarning', 'the first line is the warning',
    Pos('phosphor: warning: ', FirstLine(R.StdErr)) = 1, FirstLine(R.StdErr));
  ParsesAs('pmkWarning', FirstLine(R.StdErr), pmkWarning, '', 0, False);
  { A REFUSAL IS NOT ONE LINE, and uphosphormsg's "exactly ONE diagnostic per
    failed run" is about a failed RUN, not about a warning block. The
    continuation lines are unprefixed and come back pmkPlain, which is right for
    the Output pane. }
  ShapeTrue('pmkWarning', 'the block has continuation lines',
    LineCount(R.StdErr) > 1, IntToStr(LineCount(R.StdErr)));

  R := Go('(no fixture -- stdin)', [], 'x = 1 / 0'#10);
  ShapeEqInt('pmkReplError', 'a REPL error does not change the exit code',
    0, R.ExitCode);
  ShapeTrue('pmkReplError', 'the error is on stderr',
    Pos(PhosphorReplPrefix, R.StdErr) = 1, Describe(R.StdErr));
  ShapeTrue('pmkReplError', 'the banner and prompt are on stdout',
    Pos('phosphor> ', R.StdOut) > 0, Describe(R.StdOut));
  Wording('pmkReplError', 'the REPL error line',
    'error: division by zero', FirstLine(R.StdErr));
  ParsesAs('pmkReplError', FirstLine(R.StdErr), pmkReplError, '', 0, False);
end;

procedure TestPacked;
var
  R: TRunResult;
  Exe: String;
begin
  Group('pmkPackedError: a packed executable has no path to print');

  R := Go('divzero.bas', ['compile', 'divzero.bas', 'boom.pbc']);
  ShapeEqInt('packed (compile step)', 'compile succeeds', 0, R.ExitCode);

  R := Go('boom.pbc', ['pack', 'boom.pbc', PackedName]);
  ShapeEqInt('packed (pack step)', 'pack succeeds', 0, R.ExitCode);

  Exe := IncludeTrailingPathDelimiter(WorkDir) + PackedName;
  if not FileExists(Exe) then
  begin
    Inc(Failures);
    WriteLn('FAIL  [', Section, '] pack produced no executable at ', Exe);
    Exit;
  end;

  LastFixture := PackedName;
  LastCommand := Exe;
  R := RunHost(Exe, WorkDir, []);
  LastResult := R;
  ShapeEqInt('pmkPackedError', 'exit code', 1, R.ExitCode);
  ShapeEqInt('pmkPackedError', 'one diagnostic', 1, LineCount(R.StdErr));
  Wording('pmkPackedError', 'the pathless diagnostic',
    'phosphor: 4: division by zero', FirstLine(R.StdErr));
  { THE HEADLINE: no path -- and STILL JUMPABLE, which is the half this program
    got wrong on its first run and the host got right. HasSourceLocation is
    `Kind in [pmkSourceError, pmkPackedError]) and (Line > 0)`
    (`uphosphormsg.pas:223-226`): a packed diagnostic carries a line and no path,
    and the editor supplies the path itself, because it knows which file it
    packed. Asserting False here would have pinned a bug that does not exist. }
  ParsesAs('pmkPackedError', FirstLine(R.StdErr), pmkPackedError, '', 4, True);
end;

procedure TestSelfDescription;
var
  R: TRunResult;
  L: TStringList;
  I: Integer;
  Found: Boolean;
begin
  Group('what the binary says about itself, which the editor reads');

  R := Go('(none)', ['--version']);
  ShapeEqInt('--version', 'exit code', 0, R.ExitCode);
  ShapeEq('--version', 'nothing on stderr', '', R.StdErr);
  ShapeTrue('--version', 'a non-empty line on stdout',
    Trim(FirstLine(R.StdOut)) <> '', Describe(R.StdOut));
  { The FORMAT is the host's to change and uphosphorhost.pas says so
    deliberately, so the number is not asserted. }

  R := Go('(none)', ['--help']);
  ShapeEqInt('--help', 'exit code', 0, R.ExitCode);
  ShapeEq('--help', 'nothing on stderr', '', R.StdErr);
  ShapeTrue('--help', 'no `phosphor: ` prefix anywhere in it',
    Pos(PhosphorDiagPrefix, R.StdOut) = 0, '(prefix found)');

  { udebugsession.pas's ACTUAL predicate and nothing more. Pinning the layout
    would make a help-text tidy-up in Phosphor a red build here. }
  L := TStringList.Create;
  try
    SplitLines(R.StdOut, L);
    Found := False;
    for I := 0 to L.Count - 1 do
      if Pos('phosphor debug', LowerCase(Trim(L[I]))) = 1 then
      begin
        Found := True;
        Break;
      end;
    ShapeTrue('--help (the debug marker)',
      'a line begins with `phosphor debug`, which is what enables stepping',
      Found, Describe(R.StdOut));
  finally
    L.Free;
  end;
end;

{ --------------------------------------------------------------- the harness -- }

procedure Announce;
begin
  WriteLn;
  WriteLn('  SKIPPED: no phosphor binary was found. The shapes this editor parses');
  WriteLn('  are the host''s to change, and there is nothing here to check them');
  WriteLn('  against.');
  WriteLn('  Build one, or point at one, to include this check:');
  WriteLn('      lazbuild --build-mode=Default ../Phosphor/host/console/phosphor.lpi');
  WriteLn('      bin/phosphorcontract --host <path to phosphor>');
  WriteLn('      PHOSPHOR_HOST=<path> bash scripts/build.sh');
  WriteLn;
end;

{ PROBE, THEN TAKE -- not take-the-first. LocateHost answers Cands[0] unprobed,
  which is right for the editor (it shows Preferences and lets a person fix it)
  and wrong here, because there is nobody to ask.

  The `Phosphor BASIC` test is a SELECTION criterion and not an assertion: a
  `phosphor` on PATH that is some other tool must not be picked, but a rename
  upstream must not turn the whole suite red from one Pos. Every rejected
  candidate is printed with its reason, because a run whose first line does not
  name the binary that answered is a run whose numbers cannot be attributed. }
function FindHost: Boolean;
var
  Cands: TPhosphorHostCandidates;
  Info: TPhosphorHostInfo;
  I: Integer;
begin
  Cands := LocateHostCandidates(ArgValue('--host'));
  for I := 0 to High(Cands) do
  begin
    Info := ProbeHost(Cands[I].Path);
    if Info.Ok and (Pos('Phosphor BASIC', Info.Version) = 1) then
    begin
      Host := Cands[I].Path;
      HostVersion := Trim(Info.Version);
      WriteLn(Format('host:    %s  (%s)', [Host, HostOriginText(Cands[I].Origin)]));
      WriteLn(Format('version: %s', [HostVersion]));
      Exit(True);
    end;
    WriteLn(Format('  skipped %s (%s): %s',
      [Cands[I].Path, HostOriginText(Cands[I].Origin), Info.Diagnostic]));
  end;
  Result := False;
end;

function MakeWorkDir: Boolean;
var
  Src, Name: String;
  Files: TStringList;
  I: Integer;
begin
  Randomize;
  WorkDir := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    'phosphoride-contract-' + IntToStr(Random(1000000));
  Result := ForceDirectoriesUTF8(WorkDir);
  if not Result then
  begin
    WriteLn('FAIL  could not create a work directory at ', WorkDir);
    Exit;
  end;

  { A FRESH DIRECTORY PER RUN, and the fixtures copied into it. Three reasons:
    compile/pack output and the --out victims stay out of the working tree, the
    path-echo assertions get a spelling this side chose, and two runs on one
    machine cannot collide -- which is a hazard the ground-truth probe hit for
    real when two agents shared one directory. }
  Src := IncludeTrailingPathDelimiter(
    IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    '..' + PathDelim + 'tests' + PathDelim + 'fixtures' + PathDelim + 'contract');
  if not DirectoryExists(Src) then
  begin
    WriteLn('FAIL  no fixtures at ', Src);
    Exit(False);
  end;

  Files := FindAllFiles(Src, '*.bas', False);
  try
    for I := 0 to Files.Count - 1 do
    begin
      Name := ExtractFileName(Files[I]);
      if not CopyFile(Files[I], IncludeTrailingPathDelimiter(WorkDir) + Name) then
      begin
        WriteLn('FAIL  could not copy fixture ', Name);
        Exit(False);
      end;
    end;
    Result := Files.Count > 0;
    if not Result then
      WriteLn('FAIL  no .bas fixtures found in ', Src);
  finally
    Files.Free;
  end;
end;

procedure Summary;
var
  I, Code: Integer;
  Against: String;
begin
  WriteLn;
  for I := 0 to SoftMoves.Count - 1 do
    WriteLn('WORDING MOVED: ', SoftMoves[I]);
  if SoftMoves.Count > 0 then
  begin
    WriteLn('  (', SoftMoves.Count, ' message(s) reworded upstream. Not a failure: ',
      'this repository observes them, it has not copied them.)');
    WriteLn;
  end;

  { Under --require-host with nothing found there is no binary to name, and
    `against  ()` is a summary line that reads as a bug in the reporter rather
    than as the answer it is. }
  if Host = '' then
    Against := 'against no host'
  else
    Against := Format('against %s (%s)', [Host, HostVersion]);

  if Failures = 0 then
  begin
    WriteLn(Format('%d checks %s, all green.', [Checks, Against]));
    Halt(0);
  end;

  WriteLn(Format('%d checks %s, %d FAILED.', [Checks, Against, Failures]));
  if MovedShapes.Count > 0 then
    WriteLn('SHAPES THAT MOVED: ', MovedShapes.CommaText);

  { 77 IS THE SKIP, so it may never also be a count. Clamped, with the true
    number printed above, because a hidden number is how a defect gets runway. }
  Code := Failures;
  if Code >= SkipExitCode then
  begin
    WriteLn(Format('  (exit clamped to %d; %d means skipped)',
      [MaxFailExitCode, SkipExitCode]));
    Code := MaxFailExitCode;
  end;
  Halt(Code);
end;

begin
  MovedShapes := TStringList.Create;
  SoftMoves := TStringList.Create;
  try
    RequireHost := HasArg('--require-host');

    if not FindHost then
    begin
      if not RequireHost then
      begin
        Announce;
        Halt(SkipExitCode);
      end;
      { In CI the binary was built two steps earlier, so a skip there can only
        mean the build step lied. --require-host turns it into a check. }
      Section := 'host';
      Check('a phosphor binary was found (--require-host)', False);
      Summary;
    end;

    if not MakeWorkDir then
    begin
      Inc(Failures);
      Summary;
    end;

    try
      TestSourceErrors;
      TestColons;
      TestStreams;
      TestRefusals;
      TestWarningAndRepl;
      TestPacked;
      TestSelfDescription;
    finally
      if (WorkDir <> '') and DirectoryExists(WorkDir) then
        DeleteDirectory(WorkDir, False);
    end;

    Summary;
  finally
    MovedShapes.Free;
    SoftMoves.Free;
  end;
end.
