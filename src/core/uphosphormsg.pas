unit uphosphormsg;

{ Reading what the phosphor host says on stderr.

  The host prints exactly ONE diagnostic per failed run -- the engine stops at the
  first error, so there is no error list to collect -- in the shape

      phosphor: <path>:<line>: <message>

  and that single line is the whole contract for jump-to-error. Three things about
  it cost more than they look:

  1. THE PATH IS ECHOED VERBATIM, never normalised. The host formats with the raw
     ParamStr value, so `./x.bas` stays `./x.bas` and a relative path stays
     relative to the working directory the child was spawned in. This unit
     therefore reports the path AS SEEN and lets the caller decide; the IDE
     attributes the error to the file it passed rather than trusting the echo.

  2. MESSAGES CONTAIN COLONS. `no function nosuchfunc$:%` is a real message, and
     so is `cannot open "cafe.txt" for input: no such file`. Splitting on the last
     colon, or on the first, both produce garbage. The separator is found by
     looking for `:<digits>: ` and nothing else -- and the search starts past a
     Windows drive letter, which is the only other colon a path can carry here.

  3. THERE ARE THREE OTHER SHAPES. A packed executable has no path to print, so it
     says `phosphor: <line>: <message>`. The REPL says `error: <message>` with no
     prefix, no path and no line. And a host-level refusal (`file not found`,
     `cannot write to`, the `--check` warning block) has no source location at
     all. A parser that assumes the first shape turns `file not found: nope.bas`
     into a jump to line 0 of a file called `file not`.

     AND THERE ARE THREE PREFIXES, not one. `phosphor: ` is the common one;
     `phosphor debug: ` carries every refusal the debug door emits, which is
     exactly where this editor most needs to say why a session did not start; and
     a usage refusal carries NO prefix at all -- `usage: phosphor compile
     [--check] <in.bas> <out.pbc>`. All three were measured on 2026-09-17 against
     the real binary, and until that day this unit knew only the first, so the
     other two reached the Output pane as ordinary program output while their exit
     code said nothing had run. The usage branch matches `usage: phosphor `, with
     the host's own name in it: a bare `usage: ` would claim a line any BASIC
     program can write to stderr on Linux.

  4. A REFUSAL CAN FORGE A LOCATION, AND ONLY THE CALLER CAN TELL. This is the
     one that mattered. `phosphor run "a:12: b.bas"` prints
     `phosphor: file not found: a:12: b.bas`, and a scan for `:<digits>: ` reads
     it as line 12 of a file called `file not found: a` -- jumpable. With exactly
     one Problems row `umainform` calls ListProblemsDblClick ITSELF, so that was
     not a row waiting to be clicked: it scrolled the user's own file to a line it
     had nothing to do with and painted the band. On Windows it takes a crafted
     argument; on Linux a filename may legally contain `:12: `.

     THE FIX IS AEXPECTPATH, AND A TABLE OF REFUSAL OPENINGS WAS THE TRAP. Every
     located site formats `phosphor: %s:%d: %s` with %s echoed verbatim from the
     command line -- `../Phosphor/host/console/phosphor.lpr:855`, `:999`, `:2859`
     and `:3233`, and there are exactly four. So a caller that knows what it
     passed can decide by rule instead of by guess: the line is a location when it
     opens with that path AND a separator follows at that offset, and everything
     else under the prefix is a refusal whatever it says. A table of openings
     would instead have matched at the position the PATH occupies, taking the jump
     away from any file named `unhandled x.bas` or `--weird.bas` and from every
     file in a folder called `unhandled cases` -- both measured out of the real
     binary -- while still never reaching the three refusals that lead with the
     echoed path.

     WHAT IT RESTS ON, so that whoever breaks it knows where to come: no Phosphor
     diagnostic names a file other than the one on the command line, because the
     language has no include and no import. The day that changes, a real location
     becomes a refusal and the jump disappears with no symptom at all.

  There is never a column: the compiler and the lexer track ErrorLine and nothing
  else. A line number MAY IN PRINCIPLE exceed the file's line count, so a caller
  clamps before scrolling -- but the worked example this paragraph used to give,
  "an unterminated block in a three-line file reports line 4", IS NOT TRUE TODAY.
  Measured 2026-09-17 over 34 constructed shapes, not one reported a line past the
  end: Phosphor's compiler routes unterminated blocks through FailUnterminated,
  which deliberately names the line the block OPENED on. The value is
  constructible -- the lexer gives tkEOF the line count plus one -- but no error
  site reaches it. Whoever would have to change it for this to become true is
  Phosphor, in FailUnterminated. The clamp stays: it is the editor being right
  about a protocol rather than about one implementation of it, and this unit's
  handling of such a line is still pinned on a synthetic string in
  tests/phosphoridetest.lpr.

  Nothing here reads a file or touches the LCL: it is pure text, so it is testable
  without a UI and without the host installed. }

{$mode objfpc}{$H+}

interface

type
  { What a diagnostic line turned out to be.

    pmkSourceError is the only kind that carries a place to jump to. The rest are
    reported so the output pane can style them, and so that an unrecognised
    `phosphor: ` line is never silently mistaken for a location. }
  TPhosphorMsgKind = (
    pmkPlain,        // not a diagnostic at all -- ordinary program output
    pmkSourceError,  // phosphor: <path>:<line>: <msg>   (compile or runtime)
    pmkPackedError,  // phosphor: <line>: <msg>          (a packed executable)
    pmkReplError,    // error: <msg>                     (the REPL)
    pmkWarning,      // phosphor: warning: ...           (compile --check, pack)
    pmkHostError     // phosphor: <anything else>        (refused to run)
  );

  TPhosphorMessage = record
    Kind: TPhosphorMsgKind;
    { The path exactly as the host echoed it: relative if the host was given a
      relative path, backslashed if it was given backslashes. Empty for every kind
      but pmkSourceError. }
    Path: String;
    { 1-based, and may point past the end of the file. Zero when the shape carries
      no line. }
    Line: Integer;
    { The message with the prefix, path and line removed. }
    Text: String;
    { The line as received, unmodified, for the output pane. }
    Raw: String;
  end;

const
  PhosphorDiagPrefix = 'phosphor: ';

  { A SECOND PREFIX, and the editor's own debug launch is what provokes it.
    Fourteen sites use it (`../Phosphor/host/console/phosphor.lpr:3115-4048`) and
    this unit knew none of them, so a failed debug start reached the Output pane
    as ordinary program text -- on exactly the path where the editor most wants
    to surface a refusal. }
  PhosphorDebugPrefix = 'phosphor debug: ';

  PhosphorReplPrefix = 'error: ';

  { `usage: phosphor `, NOT a bare `usage: `. The host's two usage refusals are
    the only ones it writes without its own name in front, and matching the bare
    form would claim a line anybody can write: on Linux a BASIC program reaches
    this very pipe through `savetext$("/dev/stderr", ...)`, and its own
    `usage: myreport.bas <infile>` banner would then be filed as a host refusal.
    Four more characters put the host's name back in and cost nothing. }
  PhosphorUsagePrefix = 'usage: phosphor ';

  { A LINE NUMBER IS AT MOST NINE DIGITS, because FPC's Val does not refuse a
    tenth -- it WRAPS. Measured 2026-09-17: `4294967299` comes back as 3 with
    Code=0, and `99999999999` as 1215752191. A wrapped line is worse than a
    rejected one, because it is small and plausible and the caller's clamp cannot
    help: 3 needs no clamping. }
  PhosphorMaxLineDigits = 9;

{ Classify one line of the host's stderr. Always fills AMsg (pmkPlain with Raw set
  when the line is not a diagnostic), and answers whether it was one.

  AEXPECTPATH IS THE PATH THE CALLER HANDED THE HOST, and it is the only sound way
  to tell a location from a refusal. Empty means "I do not know", and the scan is
  then a heuristic that CANNOT be made safe -- `phosphor: file not found: a:12:
  b.bas` still comes back as a location, because nothing in the text distinguishes
  a path from the English in front of one. Pass the path whenever you have it. }
function ParsePhosphorMessage(const ALine: String; out AMsg: TPhosphorMessage;
  const AExpectPath: String = ''): Boolean;

{ True when the kind names a place in a source file that an editor can jump to. }
function HasSourceLocation(const AMsg: TPhosphorMessage): Boolean;

{ What an exit code from the host means, in one line, for the status bar.

  The host's four codes are a real taxonomy and worth keeping straight: 1 is the
  BASIC program's fault, 2 means nothing ever ran, and 3 is the interpreter itself
  faulting. Anything else came from the OS or from whoever killed the process. }
function PhosphorExitCodeText(ACode: Integer): String;

implementation

uses
  SysUtils;

function IsDigitCh(C: Char): Boolean; inline;
begin
  Result := (C >= '0') and (C <= '9');
end;

function IsAllDigits(const S: String): Boolean;
var
  I: Integer;
begin
  Result := S <> '';
  for I := 1 to Length(S) do
    if not IsDigitCh(S[I]) then
      Exit(False);
end;

{ Does a `:<digits>: ` separator begin at AAt? Answers the line, and where the
  message starts after it.

  THE SPACE IS TESTED HERE, which the comment this replaces claimed and the code
  never did. It is not decoration: the host formats every located diagnostic with
  `%s:%d: %s`, so the space is always there, and requiring it is what lets the
  scan walk PAST a colon inside a path. Measured 2026-09-17:
  `phosphor: /tmp/a:12:b.bas:3: division by zero` used to report line 12 of
  `/tmp/a`, and now reports line 3 of the whole name, because `:12:` is followed
  by `b` and is no longer a candidate.

  ALL DIGITS, NOT `Val`. Val accepts `$10`, `&17`, `%101`, `+4` and a leading
  blank -- every one of those measured reaching the line number -- and it wraps
  rather than refusing past nine digits. }
function SeparatorAt(const S: String; AAt: Integer; out ALine, AAfter: Integer): Boolean;
var
  J, Value, Code: Integer;
begin
  Result := False;
  ALine := 0;
  AAfter := 0;
  if (AAt < 1) or (AAt > Length(S)) or (S[AAt] <> ':') then
    Exit;
  J := AAt + 1;
  while (J <= Length(S)) and IsDigitCh(S[J]) do
    Inc(J);
  if (J = AAt + 1) or (J - AAt - 1 > PhosphorMaxLineDigits) then
    Exit;
  if (J > Length(S)) or (S[J] <> ':') then
    Exit;
  if (J < Length(S)) and (S[J + 1] <> ' ') then
    Exit;
  Val(Copy(S, AAt + 1, J - AAt - 1), Value, Code);
  if (Code <> 0) or (Value <= 0) then
    Exit;
  ALine := Value;
  AAfter := J + 1;
  Result := True;
end;

{ Where a scan for the separator may begin.

  A WINDOWS DRIVE LETTER IS THE ONLY COLON A PATH CARRIES THAT IS NEVER A
  SEPARATOR, and it is the only reason this ever skipped anything. It used to
  start unconditionally at 3, which also skipped the colon after any
  ONE-CHARACTER path: measured 2026-09-17, `phosphor: a:4: division by zero`
  came back pmkHostError with no jump at all, and
  `phosphor: 7:2: cannot open "z:9: q" for input: no such file` -- which the real
  binary emits for a file named `7` -- locked onto the `:9: ` INSIDE the message.
  A drive letter is a letter, a colon and a slash; nothing less. }
function ScanStart(const S: String): Integer;
begin
  Result := 1;
  if (Length(S) >= 3) and (S[2] = ':') and ((S[3] = '\') or (S[3] = '/')) and
     (((S[1] >= 'A') and (S[1] <= 'Z')) or ((S[1] >= 'a') and (S[1] <= 'z'))) then
    Result := 3;
end;

{ The leftmost `:<digits>: `, or 0.

  LEFTMOST, NOT RIGHTMOST. The path precedes the message, so the first separator
  is the right one whenever the path itself is clean -- and
  `phosphor: x.bas:2: cannot open "a:12: b" for input: no such file` is a
  measured line whose MESSAGE carries a later one. Taking the last match would
  trade that real case for a constructed one. }
function FindLineSeparator(const S: String; out ALine, AAfter: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  ALine := 0;
  AAfter := 0;
  for I := ScanStart(S) to Length(S) do
    if SeparatorAt(S, I, ALine, AAfter) then
      Exit(I);
end;

function ParsePhosphorMessage(const ALine: String; out AMsg: TPhosphorMessage;
  const AExpectPath: String): Boolean;
var
  Rest, Head: String;
  Sep, Line, After, Code: Integer;
  FromDebug: Boolean;
begin
  AMsg := Default(TPhosphorMessage);
  AMsg.Kind := pmkPlain;
  AMsg.Raw := ALine;
  AMsg.Text := ALine;
  Result := False;

  if ALine = '' then
    Exit;

  { FIRST, because the REPL's shape has no prefix to strip and nothing else may
    claim a line that opens `error: `. }
  if Copy(ALine, 1, Length(PhosphorReplPrefix)) = PhosphorReplPrefix then
  begin
    AMsg.Kind := pmkReplError;
    AMsg.Text := Copy(ALine, Length(PhosphorReplPrefix) + 1, MaxInt);
    Exit(True);
  end;

  { BEFORE the prefix test below, because a usage refusal carries no `phosphor: `
    and would otherwise come back as ordinary program output -- which it did, and
    which `tests/phosphorcontract.lpr` pinned as gap 1 until today.

    THE WHOLE LINE IS THE TEXT here, where every other branch strips its prefix.
    Stripping this one leaves `phosphor compile [--check] <in.bas> <out.pbc>`,
    which reads in a Problems row as a command to run rather than as a complaint. }
  if Copy(ALine, 1, Length(PhosphorUsagePrefix)) = PhosphorUsagePrefix then
  begin
    AMsg.Kind := pmkHostError;
    AMsg.Text := ALine;
    Exit(True);
  end;

  { TWO PREFIXES, ONE CHAIN. `phosphor debug: ` gets the same branches rather
    than a blanket answer, so that a located diagnostic under it -- which no site
    emits today, and whoever would have to change that is Phosphor, in the debug
    door -- would be jumped to rather than silently dropped. The two cannot both
    match: `phosphor d` is not `phosphor: `. }
  FromDebug := False;
  if Copy(ALine, 1, Length(PhosphorDebugPrefix)) = PhosphorDebugPrefix then
  begin
    Rest := Copy(ALine, Length(PhosphorDebugPrefix) + 1, MaxInt);
    FromDebug := True;
  end
  else if Copy(ALine, 1, Length(PhosphorDiagPrefix)) = PhosphorDiagPrefix then
    Rest := Copy(ALine, Length(PhosphorDiagPrefix) + 1, MaxInt)
  else
    Exit;

  if Copy(Rest, 1, 9) = 'warning: ' then
  begin
    AMsg.Kind := pmkWarning;
    AMsg.Text := Copy(Rest, 10, MaxInt);
    Exit(True);
  end;

  { A packed executable has no path to print: `phosphor: 4: division by zero`,
    formatted `%d: %s`.

    THE SPACE IS THE WHOLE DISCRIMINATOR and nothing used to say so. A source
    line is `%s:%d: %s` and so never has a space after the PATH's colon, while a
    packed line always has one after the LINE's. It is the only thing keeping a
    file named `4`, run relatively, out of this branch. }
  Sep := Pos(':', Rest);
  if Sep > 1 then
  begin
    Head := Copy(Rest, 1, Sep - 1);
    if IsAllDigits(Head) and (Length(Head) <= PhosphorMaxLineDigits) and
       (Sep + 1 <= Length(Rest)) and (Rest[Sep + 1] = ' ') then
    begin
      Val(Head, Line, Code);
      if (Code = 0) and (Line > 0) then
      begin
        AMsg.Kind := pmkPackedError;
        AMsg.Line := Line;
        AMsg.Text := Trim(Copy(Rest, Sep + 1, MaxInt));
        Exit(True);
      end;
    end;
  end;

  { THE PATH THE CALLER PASSED IS THE DISCRIMINATOR, AND IT IS THE ONLY SOUND
    ONE. Every located site formats `phosphor: %s:%d: %s` with %s the argument
    the host was GIVEN, echoed verbatim. So when the caller knows that argument
    the question stops being a guess: the line is a location exactly when it
    opens with that string AND a separator follows at that offset. Everything
    else under this prefix is a refusal, whatever it says.

    THE ALTERNATIVE WAS A TABLE OF REFUSAL OPENINGS AND IT IS A TRAP. Those
    openings would be matched at exactly the position where this shape puts the
    PATH, so every entry doubles as a filename prefix that can no longer be
    jumped to. Measured 2026-09-17 against the real binary:
    `phosphor: unhandled x.bas:2: division by zero` and
    `phosphor: --weird.bas:2: division by zero` are ordinary runtime errors in
    files a person may legally name, and a table containing `unhandled ` or `--`
    takes the jump away from both -- and from every file in a directory called
    `unhandled cases`. It would also have needed nine entries for the sixteen
    sites that lead with English, and could never reach the three that lead with
    the echoed path.

    A MISMATCH IS A REFUSAL, AND THAT RESTS ON ONE FACT ABOUT THE OTHER
    REPOSITORY: no diagnostic names a file other than the one on the command
    line, because the language has no include and no import. The day Phosphor
    grows one, this demotes a real location to a refusal and the jump goes
    silently -- the same shape as breakpoints that quietly did not move. Whoever
    adds it has to come back here. }
  if AExpectPath <> '' then
  begin
    if (Copy(Rest, 1, Length(AExpectPath)) = AExpectPath) and
       SeparatorAt(Rest, Length(AExpectPath) + 1, Line, After) then
    begin
      AMsg.Kind := pmkSourceError;
      AMsg.Path := AExpectPath;
      AMsg.Line := Line;
      AMsg.Text := Trim(Copy(Rest, After, MaxInt));
      Exit(True);
    end;
    AMsg.Kind := pmkHostError;
    AMsg.Text := Rest;
    Exit(True);
  end;

  { AND WITHOUT ONE, THE DEBUG PREFIX NEVER CARRIES A LOCATION. Not one of its
    sites is located -- the debug door's own compile error falls back to the
    plain prefix -- so guessing a location out of this prefix could only forge
    one. Measured: without this branch,
    `phosphor debug: file not found: a:12: b.bas` goes from safe-by-accident to a
    jump to line 12. }
  if FromDebug then
  begin
    AMsg.Kind := pmkHostError;
    AMsg.Text := Rest;
    Exit(True);
  end;

  { NO CALLER KNEW THE PATH, so this is a heuristic and it CANNOT be made safe:
    `phosphor: file not found: a:12: b.bas` still comes back as a location here,
    because nothing in the text distinguishes a path from the English in front of
    one. It is kept for the shapes that genuinely have no expected path, and the
    honest answer is to pass one. }
  Sep := FindLineSeparator(Rest, Line, After);
  if Sep > 0 then
  begin
    AMsg.Kind := pmkSourceError;
    AMsg.Path := Copy(Rest, 1, Sep - 1);
    AMsg.Line := Line;
    AMsg.Text := Trim(Copy(Rest, After, MaxInt));
    Exit(True);
  end;

  AMsg.Kind := pmkHostError;
  AMsg.Text := Rest;
  Result := True;
end;

function HasSourceLocation(const AMsg: TPhosphorMessage): Boolean;
begin
  Result := (AMsg.Kind in [pmkSourceError, pmkPackedError]) and (AMsg.Line > 0);
end;

function PhosphorExitCodeText(ACode: Integer): String;
begin
  case ACode of
    0: Result := 'finished';
    1: Result := 'the program failed';
    2: Result := 'the host refused to run it';
    3: Result := 'the interpreter itself faulted';
  else
    // Not the host's. A kill on Windows sets whatever the killer chose; Ctrl+C in
    // a console group gives STATUS_CONTROL_C_EXIT; a POSIX signal gives 128+n.
    Result := Format('stopped (exit code %d)', [ACode]);
  end;
end;

end.
