unit uphosphorhost;

{ Finding the phosphor binary, and asking it what it is.

  The editor does not contain the interpreter -- it drives one as a child process
  -- so "where is it" is a question this program has to answer on every start, on
  two operating systems, without a registry key or an installer to lean on.

  The search order below is not arbitrary. It goes from the most deliberate answer
  to the most incidental, so that a person who has said which binary to use is
  never overruled by one that merely happens to be on PATH:

    1. the setting, if the user picked a binary in Preferences
    2. $PHOSPHOR_HOST, for a shell or a CI job that wants to pin one
    3. beside this executable -- ./phosphor, ./bin/phosphor
    4. a Phosphor checkout sitting next to this one -- ../Phosphor/bin/phosphor,
       which is the layout a contributor working on both repositories has
    5. PATH
    6. the usual install directories

  WHAT IS NOT DONE HERE, deliberately: nothing on this list is executed while
  searching. A path that exists is reported as a candidate, and the caller decides
  whether to probe it. Running an unknown executable to find out whether it is the
  right one is how a file dropped in the working directory gets run, and the
  editor already spawns quite enough processes on the user's behalf.

  ProbeHost is the one place that does run it, with --version, and only against a
  path the caller has settled on. `phosphor --version` prints one line and halts,
  so the wait is bounded in practice -- but it IS a synchronous wait on a program
  this unit did not write, which is why it is a separate call the caller makes
  knowingly rather than something LocateHost does behind their back. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { Where a candidate came from. Shown in Preferences so that "it is using the
    wrong phosphor" is a question with a visible answer. }
  THostOrigin = (
    hoSetting,     // the path configured in Preferences
    hoEnvironment, // $PHOSPHOR_HOST
    hoBeside,      // next to phosphoride itself
    hoSibling,     // ../Phosphor/bin, a checkout beside this one
    hoSearchPath,  // found on PATH
    hoCommon       // a conventional install directory
  );

  TPhosphorHostCandidate = record
    Path: String;
    Origin: THostOrigin;
  end;

  TPhosphorHostCandidates = array of TPhosphorHostCandidate;

  { What the binary said about itself. Version is the raw line, because the host's
    own format ('Phosphor BASIC 0.0.1') is its to change and this editor has no
    business parsing it into fields it would then have to keep in step. }
  TPhosphorHostInfo = record
    Path: String;
    Version: String;
    Ok: Boolean;
    Diagnostic: String;   // why not, when Ok is False
  end;

const
  { The binary's name, which differs only by extension. }
  PhosphorExeName = {$IFDEF WINDOWS} 'phosphor.exe' {$ELSE} 'phosphor' {$ENDIF};

  { The environment variable a shell or a CI job can pin the host with. }
  PhosphorHostEnvVar = 'PHOSPHOR_HOST';

{ Every candidate, in the order described above, with duplicates and
  non-existent paths already dropped. APreferred is the configured setting and may
  be empty. Never runs anything. }
function LocateHostCandidates(const APreferred: String): TPhosphorHostCandidates;

{ The first candidate, or '' when there is none. }
function LocateHost(const APreferred: String): String;

{ Run `<AExe> --version` and report what came back. Blocks until the child exits.
  A path that is not an executable, or that fails to start, comes back Ok=False
  with the reason in Diagnostic rather than as an exception. }
function ProbeHost(const AExe: String): TPhosphorHostInfo;

{ Run a short-lived program and collect its standard output. For asking a binary
  about itself -- --version, --help -- and nothing else: it BLOCKS the caller, so
  the UI is frozen for as long as it takes.

  Which is why it has a deadline. `phosphor --version` prints one line and halts,
  but the path it runs is a SETTING, and a setting can point at anything: the day
  it points at something that waits for input, an editor without this timeout
  never finishes starting and there is nothing on screen to say why. Past the
  deadline the child is killed and the answer is False. }
function RunAndCapture(const AExe: String; const AArgs: array of String;
  out AOutput: String; AMaxWaitMs: Integer = 5000): Boolean;

function HostOriginText(AOrigin: THostOrigin): String;

implementation

uses
  Process, UTF8Process, FileUtil, LazFileUtils, DateUtils;

function RunAndCapture(const AExe: String; const AArgs: array of String;
  out AOutput: String; AMaxWaitMs: Integer): Boolean;
var
  P: TProcessUTF8;
  I, Avail, Got: Integer;
  Chunk: String;
  Started: TDateTime;
begin
  AOutput := '';
  Result := False;
  P := TProcessUTF8.Create(nil);
  try
    P.Executable := AExe;
    for I := Low(AArgs) to High(AArgs) do
      P.Parameters.Add(AArgs[I]);
    P.Options := [poUsePipes];
    {$IFDEF WINDOWS}
    P.Options := P.Options + [poNoConsole];
    P.ShowWindow := swoHide;
    {$ENDIF}

    try
      P.Execute;
    except
      on E: Exception do
        Exit(False);
    end;

    Started := Now;
    { NumBytesAvailable rather than a blocking Read, because a blocking read on a
      child that never writes and never exits cannot be given up on. }
    while True do
    begin
      { THE DEADLINE IS TESTED FIRST, on every pass. Testing it only when the child
        happened to be idle -- which is what this loop used to do -- means a child
        that keeps producing output is never given up on, and `--version` against
        the wrong binary hangs the editor's startup for as long as that binary
        feels like talking. }
      if MilliSecondsBetween(Now, Started) > AMaxWaitMs then
      begin
        P.Terminate(1);
        Exit(False);
      end;

      Avail := P.Output.NumBytesAvailable;
      if Avail > 0 then
      begin
        SetLength(Chunk, Avail);
        Got := P.Output.Read(Chunk[1], Avail);
        if Got > 0 then
          AOutput := AOutput + Copy(Chunk, 1, Got);
        Continue;
      end;

      { STDERR MUST BE DRAINED TOO, even though it is thrown away. poUsePipes gives
        the child all three streams, and a child that fills the stderr pipe blocks
        on the write -- forever, if nothing ever reads it. Only stdout is wanted
        here, but a pipe nobody reads is a pipe that stops the child. }
      Avail := P.Stderr.NumBytesAvailable;
      if Avail > 0 then
      begin
        SetLength(Chunk, Avail);
        P.Stderr.Read(Chunk[1], Avail);
        Continue;
      end;

      if not P.Running then
        Break;
      Sleep(10);
    end;

    Result := True;
  finally
    P.Free;
  end;
end;

function HostOriginText(AOrigin: THostOrigin): String;
begin
  case AOrigin of
    hoSetting: Result := 'configured in Preferences';
    hoEnvironment: Result := 'from $' + PhosphorHostEnvVar;
    hoBeside: Result := 'beside the editor';
    hoSibling: Result := 'from a Phosphor checkout beside this one';
    hoSearchPath: Result := 'found on PATH';
  else
    Result := 'a conventional install directory';
  end;
end;

{ Append APath if it names an existing file this process could plausibly run, and
  is not already in the list. Comparison is case-insensitive on Windows, where two
  spellings of one path are the same file. }
procedure AddCandidate(var ACands: TPhosphorHostCandidates; const APath: String;
  AOrigin: THostOrigin);
var
  I: Integer;
  Full: String;
begin
  if APath = '' then
    Exit;
  Full := ExpandFileNameUTF8(APath);
  if not FileExistsUTF8(Full) then
    Exit;
  { CompareFilenames already knows that Windows is case-insensitive and Linux is
    not, which is one fewer platform rule spelled out by hand here. }
  for I := 0 to High(ACands) do
    if CompareFilenames(ACands[I].Path, Full) = 0 then
      Exit;
  SetLength(ACands, Length(ACands) + 1);
  ACands[High(ACands)].Path := Full;
  ACands[High(ACands)].Origin := AOrigin;
end;

function LocateHostCandidates(const APreferred: String): TPhosphorHostCandidates;
var
  Here, Parent: String;
  OnPath: String;
begin
  Result := nil;

  AddCandidate(Result, APreferred, hoSetting);
  AddCandidate(Result, GetEnvironmentVariable(PhosphorHostEnvVar), hoEnvironment);

  Here := ExtractFilePath(ExpandFileNameUTF8(ParamStr(0)));
  AddCandidate(Result, Here + PhosphorExeName, hoBeside);
  AddCandidate(Result, Here + 'bin' + PathDelim + PhosphorExeName, hoBeside);

  { A contributor usually has both repositories checked out side by side, and the
    Phosphor build script puts the binary in its own bin/. Two levels up covers
    both `PhosphorIDE/bin/phosphoride` and `PhosphorIDE/phosphoride`. }
  Parent := ExtractFilePath(ExcludeTrailingPathDelimiter(Here));
  AddCandidate(Result, Parent + 'Phosphor' + PathDelim + 'bin' + PathDelim + PhosphorExeName, hoSibling);
  Parent := ExtractFilePath(ExcludeTrailingPathDelimiter(Parent));
  AddCandidate(Result, Parent + 'Phosphor' + PathDelim + 'bin' + PathDelim + PhosphorExeName, hoSibling);

  OnPath := FindDefaultExecutablePath(PhosphorExeName);
  AddCandidate(Result, OnPath, hoSearchPath);

  {$IFDEF WINDOWS}
  AddCandidate(Result, GetEnvironmentVariable('ProgramFiles') + '\Phosphor\' + PhosphorExeName, hoCommon);
  AddCandidate(Result, GetEnvironmentVariable('LOCALAPPDATA') + '\Programs\Phosphor\' + PhosphorExeName, hoCommon);
  {$ELSE}
  AddCandidate(Result, '/usr/local/bin/' + PhosphorExeName, hoCommon);
  AddCandidate(Result, '/usr/bin/' + PhosphorExeName, hoCommon);
  AddCandidate(Result, GetEnvironmentVariable('HOME') + '/.local/bin/' + PhosphorExeName, hoCommon);
  {$ENDIF}
end;

function LocateHost(const APreferred: String): String;
var
  Cands: TPhosphorHostCandidates;
begin
  Cands := LocateHostCandidates(APreferred);
  if Length(Cands) = 0 then
    Result := ''
  else
    Result := Cands[0].Path;
end;

function ProbeHost(const AExe: String): TPhosphorHostInfo;
var
  Output: String;
  Lines: TStringList;
begin
  Result := Default(TPhosphorHostInfo);
  Result.Path := AExe;
  Result.Ok := False;

  if AExe = '' then
  begin
    Result.Diagnostic := 'no phosphor binary configured or found';
    Exit;
  end;
  if not FileExistsUTF8(AExe) then
  begin
    Result.Diagnostic := 'not there: ' + AExe;
    Exit;
  end;

  Output := '';
  try
    if not RunAndCapture(AExe, ['--version'], Output) then
    begin
      Result.Diagnostic := 'it would not run, or did not answer in time: ' + AExe;
      Exit;
    end;
  except
    on E: Exception do
    begin
      Result.Diagnostic := E.ClassName + ': ' + E.Message;
      Exit;
    end;
  end;

  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    if Lines.Count > 0 then
      Result.Version := Trim(Lines[0]);
  finally
    Lines.Free;
  end;

  { A binary that answers --version with nothing is not the one we want, and
    saying so here is cheaper than the confusion of an empty version box. }
  if Result.Version = '' then
    Result.Diagnostic := 'it ran but said nothing to --version; is this phosphor?'
  else
    Result.Ok := True;
end;

end.
