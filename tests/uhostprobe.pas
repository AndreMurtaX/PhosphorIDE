unit uhostprobe;

{ Run the real `phosphor` and keep BOTH streams and the exit code.

  NOT IN src/core, ON PURPOSE. CLAUDE.md's invariant says the editor reaches the
  host two ways -- TPhosphorRunner for asynchronous work, RunAndCapture for the
  two questions a binary is asked about ITSELF -- and that "there is no third way
  in". A synchronous both-pipes-plus-exit-code runner sitting in src/core would be
  a third way in, and it would sit there for the next person to call from the UI
  thread. Widening RunAndCapture instead would change the one blocking call every
  start-up path already depends on, for a consumer that is not the editor. So it
  lives here, where only a test can link it.

  WHY IT EXISTS AT ALL: RunAndCapture keeps stdout and throws stderr away, and
  the entire contract this program checks is on stderr.

  THE DEADLINE IS NOT OPTIONAL, and its reason is sharper than RunAndCapture's.
  Measured on 2026-09-17: `phosphor run` with NO file argument does not refuse --
  it drops into the REPL and waits on stdin forever. One mistyped fixture name
  and a suite without a deadline hangs instead of failing, on a CI machine, for
  its whole job timeout.

  THE DEADLINE IS MEASURED WITH uphosphorclock AND NOT WITH `Now`, which is the
  rule CLAUDE.md states without an exception for deadlines. `Now` follows the WALL
  clock, so an NTP step landing mid-wait either fires the deadline early or
  suppresses it entirely, and neither failure leaves a trace. Worth knowing while
  reading this: `uphosphorhost.RunAndCapture` still measures its own 5000 ms with
  MilliSecondsBetween(Now, Started), so the invariant has one violation left in
  the editor proper. It is recorded rather than fixed here because this file is a
  test and that one is a start-up path.

  NOTHING HERE CONVERTS BYTES. Not SysToUTF8, not a codepage round trip. The
  streams come back exactly as the child wrote them, because a contract test that
  re-encodes what it captured is asserting its own conversion. That matters more
  than it sounds: measured 2026-09-17, the host's `cannot write to` tail is the
  FPC RTL's Ex.Message, localised by the OS and emitted in the console OEM
  codepage -- byte $C6 where a-tilde belongs, which is CP850 and is neither UTF-8
  nor CP1252. Passing it through untouched is how this program can see that at
  all. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TRunResult = record
    { It started AND finished inside the deadline. False means nothing about the
      other fields is worth reading except Diagnostic. }
    Ok: Boolean;
    TimedOut: Boolean;
    ExitCode: Integer;
    { Raw bytes, exactly as written by the child. }
    StdOut: String;
    StdErr: String;
    { Why not, when Ok is False. }
    Diagnostic: String;
    { How long it took, for the report. }
    Ms: Double;
  end;

{ Spawn AExe with AArgs in ACwd and wait.

  ACwd is not a convenience: the path-echo assertions need the host to be given a
  spelling THIS side chose, and a bare fixture name is only bare when the working
  directory is the fixture's own.

  AStdIn is written and then the child's input is CLOSED, which is the only
  deterministic way to end a REPL session. A host that never reads it sees EOF,
  which costs nothing. }
function RunHost(const AExe, ACwd: String; const AArgs: array of String;
  const AStdIn: String = ''; AMaxWaitMs: Integer = 20000): TRunResult;

{ Split on LF and drop one trailing CR per line.

  Every diagnostic measured on Windows ends CRLF and every one on Linux ends LF,
  so a test comparing raw stderr is a test that is red on one platform. A final
  fragment with no terminator IS a line here and not a discard: `print "hello"`
  is five bytes and no newline, and losing it would be losing the only thing that
  run produced. }
procedure SplitLines(const AText: String; ADest: TStrings);

{ One line of report: `(empty)`, or `N line(s): [first] [second] ...`, with the
  bytes shown as-is. For the failure block, where what was actually received
  matters more than a tidy rendering of it. }
function Describe(const AText: String): String;

implementation

uses
  { Pipes for TInputPipeStream, which is what TProcess hands back and what the
    non-blocking drain below is typed against. uphosphorrun names it for the
    same reason. }
  Process, UTF8Process, Pipes, uphosphorclock;

procedure SplitLines(const AText: String; ADest: TStrings);
var
  Start, I: Integer;
  Line: String;
begin
  ADest.Clear;
  if AText = '' then
    Exit;
  Start := 1;
  for I := 1 to Length(AText) do
    if AText[I] = #10 then
    begin
      Line := Copy(AText, Start, I - Start);
      if (Line <> '') and (Line[Length(Line)] = #13) then
        SetLength(Line, Length(Line) - 1);
      ADest.Add(Line);
      Start := I + 1;
    end;
  if Start <= Length(AText) then
  begin
    Line := Copy(AText, Start, Length(AText) - Start + 1);
    if (Line <> '') and (Line[Length(Line)] = #13) then
      SetLength(Line, Length(Line) - 1);
    ADest.Add(Line);
  end;
end;

function Describe(const AText: String): String;
var
  L: TStringList;
  I: Integer;
begin
  if AText = '' then
    Exit('(empty)');
  L := TStringList.Create;
  try
    SplitLines(AText, L);
    Result := Format('%d line(s):', [L.Count]);
    for I := 0 to L.Count - 1 do
      Result := Result + ' [' + L[I] + ']';
  finally
    L.Free;
  end;
end;

function RunHost(const AExe, ACwd: String; const AArgs: array of String;
  const AStdIn: String; AMaxWaitMs: Integer): TRunResult;
var
  P: TProcessUTF8;
  I: Integer;
  Started: Int64;

  { One drain of one pipe, never blocking. Answers whether anything moved, so the
    loop can tell "nothing to do" from "still talking" without ever sitting in a
    Read. }
  function Drain(AStream: TInputPipeStream; var ADest: String): Boolean;
  var
    Avail, Got: Integer;
    Chunk: String;
  begin
    Result := False;
    if AStream = nil then
      Exit;
    Avail := AStream.NumBytesAvailable;
    if Avail <= 0 then
      Exit;
    SetLength(Chunk, Avail);
    Got := AStream.Read(Chunk[1], Avail);
    if Got <= 0 then
      Exit;
    ADest := ADest + Copy(Chunk, 1, Got);
    Result := True;
  end;

begin
  Result := Default(TRunResult);
  Started := ClockTicks();
  { TProcessUTF8 and not TProcess: Executable is converted through the Windows
    system code page otherwise, and a non-ASCII path is mangled before the OS
    sees it. The same rule uphosphorrun and uphosphorhost follow. }
  P := TProcessUTF8.Create(nil);
  try
    P.Executable := AExe;
    for I := Low(AArgs) to High(AArgs) do
      P.Parameters.Add(AArgs[I]);
    P.CurrentDirectory := ACwd;
    P.Options := [poUsePipes];
    {$IFDEF WINDOWS}
    P.ShowWindow := swoHide;
    {$ENDIF}

    try
      P.Execute;
    except
      on E: Exception do
      begin
        Result.Diagnostic := E.ClassName + ': ' + E.Message;
        Result.Ms := ClockMs(Started, ClockTicks());
        Exit;
      end;
    end;

    if AStdIn <> '' then
      P.Input.Write(AStdIn[1], Length(AStdIn));
    P.CloseInput;

    while True do
    begin
      { BOTH PIPES EVERY PASS, and the deadline tested FIRST. One pipe read while
        the other fills is the deadlock CLAUDE.md names as an invariant; a
        deadline tested only when the child is idle is a child that talks its way
        straight past it. }
      if ClockMs(Started, ClockTicks()) > AMaxWaitMs then
      begin
        P.Terminate(1);
        Result.TimedOut := True;
        Result.Diagnostic := Format('no answer in %d ms', [AMaxWaitMs]);
        Result.Ms := ClockMs(Started, ClockTicks());
        Exit;
      end;
      if Drain(P.Output, Result.StdOut) then
        Continue;
      if Drain(P.Stderr, Result.StdErr) then
        Continue;
      if not P.Running then
      begin
        { ONE LAST PASS. The child can exit with bytes still sitting in the pipes,
          and `print "hello"` is five bytes with no newline -- exactly the shape
          that goes missing when a loop stops at `not Running`. }
        Drain(P.Output, Result.StdOut);
        Drain(P.Stderr, Result.StdErr);
        Break;
      end;
      Sleep(5);
    end;

    { ExitCode, NOT ExitStatus, and this cost a red Linux run on 2026-09-17 with
      Windows green. On Unix ExitStatus is the raw wait status, so a program that
      exited 1 reads back as 256 and one that exited 2 reads back as 512; on
      Windows the two are the same, which is exactly why the defect could not be
      seen here. uphosphorrun.pas:752-756 already said so, in the unit this one
      is modelled on. }
    Result.ExitCode := P.ExitCode;
    Result.Ok := True;
    Result.Ms := ClockMs(Started, ClockTicks());
  finally
    P.Free;
  end;
end;

end.
