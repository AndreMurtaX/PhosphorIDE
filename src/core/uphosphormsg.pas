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
     `cannot write to`, `usage:`, the `--check` warning block) has no source
     location at all. A parser that assumes the first shape turns `file not found:
     nope.bas` into a jump to line 0 of a file called `file not`.

  There is never a column: the compiler and the lexer track ErrorLine and nothing
  else. A line number CAN exceed the file's line count -- an unterminated block in
  a three-line file reports line 4 -- so a caller must clamp before scrolling.

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
    pmkHostError     // phosphor: <anything else>        (refused to run, usage)
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
  PhosphorReplPrefix = 'error: ';

{ Classify one line of the host's stderr. Always fills AMsg (pmkPlain with Raw set
  when the line is not a diagnostic), and answers whether it was one. }
function ParsePhosphorMessage(const ALine: String; out AMsg: TPhosphorMessage): Boolean;

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

{ Find the `:<digits>: ` that separates an echoed path from its line number.

  Answers the index of that colon, or 0. The scan starts at 3 so that the colon in
  a Windows drive letter (`C:\...`) is never a candidate; on Linux a path may in
  principle contain a colon, and one followed by digits and a colon-space would
  fool this -- the caller is expected to prefer the path it passed to the host,
  which is why this is a fallback and not the primary source of truth. }
function FindLineSeparator(const S: String; out ALine, AAfter: Integer): Integer;
var
  I, J, Value, Code: Integer;
begin
  Result := 0;
  ALine := 0;
  AAfter := 0;
  for I := 3 to Length(S) do
  begin
    if S[I] <> ':' then
      Continue;
    J := I + 1;
    while (J <= Length(S)) and IsDigitCh(S[J]) do
      Inc(J);
    // Needs at least one digit, then a colon, then a space (or end of line).
    if (J = I + 1) or (J > Length(S)) or (S[J] <> ':') then
      Continue;
    Val(Copy(S, I + 1, J - I - 1), Value, Code);
    if Code <> 0 then
      Continue;
    ALine := Value;
    // J is the second colon; the message starts after it.
    AAfter := J + 1;
    Exit(I);
  end;
end;

function ParsePhosphorMessage(const ALine: String; out AMsg: TPhosphorMessage): Boolean;
var
  Rest: String;
  Sep, Line, Code, After: Integer;
  Head: String;
begin
  AMsg := Default(TPhosphorMessage);
  AMsg.Kind := pmkPlain;
  AMsg.Raw := ALine;
  AMsg.Text := ALine;
  Result := False;

  if ALine = '' then
    Exit;

  // The REPL's own shape. No prefix, no path, no line -- just a message.
  if Copy(ALine, 1, Length(PhosphorReplPrefix)) = PhosphorReplPrefix then
  begin
    AMsg.Kind := pmkReplError;
    AMsg.Text := Copy(ALine, Length(PhosphorReplPrefix) + 1, MaxInt);
    Exit(True);
  end;

  if Copy(ALine, 1, Length(PhosphorDiagPrefix)) <> PhosphorDiagPrefix then
    Exit;

  Rest := Copy(ALine, Length(PhosphorDiagPrefix) + 1, MaxInt);

  if Copy(Rest, 1, 9) = 'warning: ' then
  begin
    AMsg.Kind := pmkWarning;
    AMsg.Text := Copy(Rest, 10, MaxInt);
    Exit(True);
  end;

  // A packed executable has no path to print: `phosphor: 4: division by zero`.
  Sep := Pos(':', Rest);
  if Sep > 1 then
  begin
    Head := Copy(Rest, 1, Sep - 1);
    Val(Head, Line, Code);
    if (Code = 0) and (Line > 0) and (Sep + 1 <= Length(Rest)) and (Rest[Sep + 1] = ' ') then
    begin
      AMsg.Kind := pmkPackedError;
      AMsg.Line := Line;
      AMsg.Text := Trim(Copy(Rest, Sep + 1, MaxInt));
      Exit(True);
    end;
  end;

  Sep := FindLineSeparator(Rest, Line, After);
  if (Sep > 0) and (Line > 0) then
  begin
    AMsg.Kind := pmkSourceError;
    AMsg.Path := Copy(Rest, 1, Sep - 1);
    AMsg.Line := Line;
    AMsg.Text := Trim(Copy(Rest, After, MaxInt));
    Exit(True);
  end;

  // `file not found: x.bas`, `cannot write to ...`, `usage: ...`: a refusal, not
  // a source location. Reported as such rather than guessed at.
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
