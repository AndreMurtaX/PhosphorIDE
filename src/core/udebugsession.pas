unit udebugsession;

{ The editor's side of a debug session -- and, for now, the one honest thing it
  can say about one.

  WHAT THIS UNIT IS FOR TODAY: deciding, from the host binary itself, whether
  stepping is possible, and giving the UI a single sentence to show when it is
  not. The Debug menu asks Available; the greyed-out items carry
  UnavailableReason as their hint; Debug > Why is stepping unavailable? shows it
  in full. Nowhere does the editor pretend.

  WHY IT CANNOT BE MORE THAN THAT YET. The shipping phosphor host has no way for
  an outside process to pause a running program. This is not an oversight in the
  console host that a flag would fix -- it is a property of the engine, recorded
  in its own source:

    - the BREAKPOINT seam "must not block: the engine treats it as a report,
      never a wait, so no confirm-answer is returned" (PhosphorValue.pas:73-74),
      and it returns void, so there is nothing for a debugger to answer with;
    - the VM has no step API at all -- no Step, OnStep, OnLine or Continue on
      TPhosphorEngine, and no opcode-level trap;
    - the frame stack is private with no accessor, so there is no call stack to
      report and no way to name a variable and read it;
    - and the console host does not install the breakpoint seam at all, with a
      recorded exemption in scripts/check-seams.py: "BREAKPOINT is
      report-and-continue; there is nowhere for a host to pause to".

  So a step debugger needs work in the Phosphor repository, and docs/debug-
  protocol.md says exactly what work, in the order it has to happen. This unit and
  udebugproto are the editor half, written first on purpose: the wire format is
  what the two ends have to agree on, and agreeing on it before either end exists
  is cheaper than discovering the disagreement afterwards.

  HOW AVAILABILITY IS DETECTED, and why not a version number. The host is asked
  for its own --help and the answer is searched for a `debug` subcommand. A
  version comparison would need this editor to know which Phosphor version first
  shipped it, which is a fact about the future; asking the binary what it can do
  is a fact about the binary in front of us. It costs one process start, at the
  same moment ProbeHost is already starting one. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, udebugproto;

type
  { Where a session is in its life. Kept even while nothing can advance past
    dsUnavailable, because the UI reads it and the state machine is part of what
    docs/debug-protocol.md specifies. }
  TDebugState = (
    dsUnavailable,  // this host cannot debug; nothing else is reachable
    dsIdle,         // it could, but no session is running
    dsStarting,     // spawned, handshake not finished
    dsRunning,      // the program is executing
    dsStopped,      // paused at a line
    dsTerminating
  );

  { TDebugSession }

  TDebugSession = class(TComponent)
  private
    FState: TDebugState;
    FHostPath: String;
    FAvailable: Boolean;
    FUnavailableReason: String;
    FCapabilities: TPdbpCapabilities;
    FCurrentPath: String;
    FCurrentLine: Integer;
    procedure SetUnavailable(const AReason: String);
  public
    constructor Create(AOwner: TComponent); override;

    { Ask AHostPath what it can do. Safe to call with '' (no host found), and
      safe to call repeatedly -- it re-runs the probe, which is what makes
      "install a newer phosphor, then reopen Preferences" work. }
    procedure Probe(const AHostPath: String);

    { True when a step session could be started. False is the normal answer
      today; UnavailableReason says why in a sentence a user can act on. }
    property Available: Boolean read FAvailable;
    property UnavailableReason: String read FUnavailableReason;

    property State: TDebugState read FState;
    property Capabilities: TPdbpCapabilities read FCapabilities;
    property HostPath: String read FHostPath;

    { Where execution is stopped, once anything can stop. Zero and '' otherwise. }
    property CurrentPath: String read FCurrentPath;
    property CurrentLine: Integer read FCurrentLine;
  end;

implementation

uses
  LazFileUtils, uphosphorhost;

const
  { What the host's --help must show for this editor to offer stepping. Chosen to
    match the shape of the existing usage block, whose lines begin `phosphor
    <verb>`; see docs/debug-protocol.md, which specifies the subcommand this is
    looking for. }
  DebugSubcommandMarker = 'phosphor debug';

  NoHostReason =
    'No phosphor binary was found, so nothing is known about what it can do. ' +
    'Set one in Tools > Preferences.';

  NoDebugSupportReason =
    'The phosphor host in use cannot pause a running program, so there is nothing ' +
    'for the editor to step.' + LineEnding + LineEnding +
    'This is a property of the interpreter, not a missing switch: the engine''s ' +
    'BREAKPOINT seam is documented as report-and-continue and must never block, ' +
    'the VM exposes no step or resume call, and the call stack is private with no ' +
    'accessor. A `phosphor debug` subcommand speaking the protocol in ' +
    'docs/debug-protocol.md is what would change that.' + LineEnding + LineEnding +
    'Everything else works meanwhile: breakpoints can be set and they follow the ' +
    'text as you edit, Run streams output live and can be stopped, Check Syntax ' +
    'compiles without running, and a diagnostic jumps to its line.';

constructor TDebugSession.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FState := dsUnavailable;
  FAvailable := False;
  FUnavailableReason := NoHostReason;
  FCurrentLine := 0;
end;

procedure TDebugSession.SetUnavailable(const AReason: String);
begin
  FAvailable := False;
  FState := dsUnavailable;
  FUnavailableReason := AReason;
  FCapabilities := Default(TPdbpCapabilities);
  FCurrentPath := '';
  FCurrentLine := 0;
end;

procedure TDebugSession.Probe(const AHostPath: String);
var
  Output: String;
  Lines: TStringList;
  I: Integer;
  Supports: Boolean;
begin
  FHostPath := AHostPath;

  if AHostPath = '' then
  begin
    SetUnavailable(NoHostReason);
    Exit;
  end;
  if not FileExistsUTF8(AHostPath) then
  begin
    SetUnavailable(Format('%s is not there.', [AHostPath]));
    Exit;
  end;

  Output := '';
  try
    { RunAndCapture, not the RTL's RunCommand: the path came from a setting and
      a setting can name anything, so the wait needs a deadline and the child
      needs the LCL's UTF-8 handling of its own name. }
    if not RunAndCapture(AHostPath, ['--help'], Output) then
    begin
      SetUnavailable(Format('%s would not answer --help.', [AHostPath]));
      Exit;
    end;
  except
    on E: Exception do
    begin
      SetUnavailable(Format('%s would not run: %s', [AHostPath, E.Message]));
      Exit;
    end;
  end;

  Supports := False;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for I := 0 to Lines.Count - 1 do
      if Pos(DebugSubcommandMarker, LowerCase(Trim(Lines[I]))) = 1 then
      begin
        Supports := True;
        Break;
      end;
  finally
    Lines.Free;
  end;

  if not Supports then
  begin
    SetUnavailable(NoDebugSupportReason);
    Exit;
  end;

  { A host that advertises the subcommand still has to complete a handshake
    before anything is really known -- Capabilities stays empty until then, and
    every capability defaults to False, so a partial host cannot be over-trusted
    by an editor that assumed. Connecting is the work docs/debug-protocol.md
    describes; until it is written, saying "available" here would be the one lie
    this unit exists to avoid. }
  FAvailable := False;
  FState := dsUnavailable;
  FUnavailableReason :=
    Format('%s advertises a `debug` subcommand, but this build of PhosphorIDE ' +
      'does not yet connect to it. The protocol is specified in ' +
      'docs/debug-protocol.md; the editor-side transport is the next piece of ' +
      'work.', [ExtractFileName(AHostPath)]);
end;

end.
