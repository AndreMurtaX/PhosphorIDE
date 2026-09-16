unit udebugsession;

{ The editor's side of a debug session: the state machine, the sequence numbers,
  and the rule about which command may be sent when.

  WHAT CHANGED ON 2026-09-15, because this header used to say the opposite in
  four confident paragraphs and every one of them is now false. It claimed the
  engine's BREAKPOINT seam "must not block", that the VM had no step API, that the
  frame stack was private with no accessor, and that the console host installed no
  seam at all. All four were true when they were written and none is true now:
  Phosphor has TPhosphorDebugProc, which RETURNS an action and may block; it has
  ArmDebug, DebugVM and the four step actions; it has DbgFrameDepth, DbgFrameFunc,
  DbgLocal and DbgGlobal; and `phosphor debug --port N file.bas` speaks this
  protocol today and is driven end to end by a 39-assertion contract test in the
  sibling repository. A document that describes a limitation which has been lifted
  sends the next reader to solve a problem that no longer exists.

  THE SHAPE. This unit owns the protocol and the state; udebugtransport owns the
  socket; the CALLER owns the child process. That last split is deliberate and
  this repository's rule requires it: every interaction with the host is a process
  and asynchronous ones go through TPhosphorRunner, so a unit that spawned its own
  would be a second way in. BeginListen returns the port; the caller starts
  `phosphor debug --port <that> <file>` however it starts anything else; the
  handshake begins by itself when the debuggee connects.

  It also keeps the unit headless: nothing here needs a widgetset, a form or a
  display, which is what lets the state machine be tested without any of them.

  A COMMAND IN THE WRONG STATE IS REFUSED HERE, and never sent. Not caution --
  measured behaviour: while the program is running the host answers nothing at
  all, so an editor that sent `continue` mid-run would wait for a reply that is
  not coming and look hung. Refusing locally turns that into an immediate, visible
  no rather than a silence.

  SEQUENCE NUMBERS ARE MATCHED, NOT ASSUMED. A response can arrive after an event
  -- the host emits `stopped` whenever it likes -- so "the next frame answers my
  request" desyncs on the first interleave. Every request is remembered by its seq
  until its answer arrives.

  MIT License. Copyright (c) 2026 Andre Murta. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, udebugproto, udebugtransport;

type
  { Where a session is in its life. }
  TDebugState = (
    dsUnavailable,  // this host cannot debug; nothing else is reachable
    dsIdle,         // it could, but no session is running
    dsStarting,     // listening, or connected and mid-handshake
    dsRunning,      // the program is executing
    dsStopped,      // paused at a line
    dsTerminating
  );

  TDebugStopEvent = procedure(Sender: TObject; const APath: String;
    ALine: Integer; AReason: TPdbpStopReason) of object;
  TDebugExitEvent = procedure(Sender: TObject; AExitCode: Integer) of object;
  TDebugNoteEvent = procedure(Sender: TObject; const AText: String) of object;
  TDebugLinesEvent = procedure(Sender: TObject; const APath: String;
    const AInstalled: TPdbpLines) of object;
  { AFrame is the frame the answer belongs to, carried alongside the request
    rather than remembered in a single field: two reads in flight at once would
    otherwise both be labelled with the second one's frame. }
  TDebugVariablesEvent = procedure(Sender: TObject; AFrame: Integer;
    const AVars: TPdbpVariables) of object;
  TDebugStackEvent = procedure(Sender: TObject;
    const AFrames: TPdbpFrames) of object;

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

    FTransport: TDebugTransport;
    FSeq: Integer;
    FPendingSeq: array of Integer;          // seq -> which command it asked
    FPendingCmd: array of TPdbpCommand;
    { ...and with what argument. Only `variables` has one today -- the frame --
      and the answer does not repeat it, so an editor that asked for frame 1 and
      frame 0 in quick succession could not tell the replies apart. }
    FPendingArg: array of Integer;
    FProgramPath: String;
    FWantLines: TPdbpLines;
    FWantEntry: Boolean;
    FHandshakeDone: Boolean;

    FOnStateChange: TNotifyEvent;
    FOnStopped: TDebugStopEvent;
    FOnExited: TDebugExitEvent;
    FOnNote: TDebugNoteEvent;
    FOnLinesInstalled: TDebugLinesEvent;
    FOnVariables: TDebugVariablesEvent;
    FOnStackTrace: TDebugStackEvent;

    procedure SetUnavailable(const AReason: String);
    procedure SetState(AState: TDebugState);
    function NextSeq(ACommand: TPdbpCommand; AArg: Integer = 0): Integer;
    function TakePending(ASeq: Integer; out ACommand: TPdbpCommand;
      out AArg: Integer): Boolean;
    function SendRaw(const AFrame: String): Boolean;
    procedure HandleFrame(Sender: TObject; const AFrame: String);
    procedure HandleConnect(Sender: TObject);
    procedure HandleDisconnect(Sender: TObject);
    procedure HandleResponse(const AMsg: TPdbpMessage);
    procedure HandleEvent(const AMsg: TPdbpMessage);
    procedure Desync(const AWhy: String);
    procedure Note(const AText: String);
    procedure SendSetBreakpoints;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Ask AHostPath what it can do. Safe to call with '' (no host found), and
      safe to call repeatedly. }
    procedure Probe(const AHostPath: String);

    { Open the listener and remember what to do once the debuggee connects.
      Returns the port to put on its command line, or 0 if the socket failed. The
      CALLER spawns the process; this never does. }
    function BeginListen(const AProgramPath: String; const ALines: TPdbpLines;
      AStopAtEntry: Boolean): Word;

    { The caller could not start the child after all. }
    procedure AbandonListen(const AWhy: String);

    { Drive the transport. The caller decides the cadence -- a TTimer at 40 ms in
      the editor, a loop in a test -- because a TTimer needs a widgetset and this
      unit must not. }
    procedure Poll;

    { Commands. Each answers False when the state forbids it, having sent
      nothing, and says why through OnNote. }
    function Resume: Boolean;
    function StepOver: Boolean;
    function StepInto: Boolean;
    function StepOut: Boolean;
    function Pause: Boolean;
    function SetBreakpoints(const APath: String; const ALines: TPdbpLines): Boolean;
    function RequestStackTrace: Boolean;
    function RequestVariables(AFrame: Integer): Boolean;

    { End the session. Terminate kills the program; otherwise it is let go and
      runs to completion undebugged. }
    procedure Stop(ATerminate: Boolean);

    property Available: Boolean read FAvailable;
    property UnavailableReason: String read FUnavailableReason;
    property State: TDebugState read FState;
    property Capabilities: TPdbpCapabilities read FCapabilities;
    property HostPath: String read FHostPath;
    property CurrentPath: String read FCurrentPath;
    property CurrentLine: Integer read FCurrentLine;
    property Live: Boolean read FHandshakeDone;

    property OnStateChange: TNotifyEvent read FOnStateChange write FOnStateChange;
    property OnStopped: TDebugStopEvent read FOnStopped write FOnStopped;
    property OnExited: TDebugExitEvent read FOnExited write FOnExited;
    property OnNote: TDebugNoteEvent read FOnNote write FOnNote;
    property OnLinesInstalled: TDebugLinesEvent read FOnLinesInstalled
      write FOnLinesInstalled;
    property OnVariables: TDebugVariablesEvent read FOnVariables
      write FOnVariables;
    property OnStackTrace: TDebugStackEvent read FOnStackTrace
      write FOnStackTrace;
  end;

implementation

uses
  LazFileUtils, uphosphorhost;

const
  { What the host's --help must show for this editor to offer stepping. It is a
    cheap PRE-FILTER and nothing more: the usage block advertises `phosphor debug`
    but says nothing about `--port`, so a host with only the terminal debugger
    looks identical here. Available is not set from this -- it is set when the
    handshake succeeds, which is the only thing that actually proves it. }
  DebugSubcommandMarker = 'phosphor debug';

  NoHostReason =
    'No phosphor binary was found, so nothing is known about what it can do. ' +
    'Set one in Tools > Preferences.';

  NoDebugSupportReason =
    'The phosphor binary in use does not advertise a `debug` subcommand, so this ' +
    'editor has nothing to connect to.' + LineEnding + LineEnding +
    'Stepping needs a host that speaks the protocol in docs/debug-protocol.md -- ' +
    '`phosphor debug --port <n> <file.bas>`. Recent builds of the sibling ' +
    'Phosphor repository have it; an older one will not.' + LineEnding + LineEnding +
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
  FSeq := 0;
end;

destructor TDebugSession.Destroy;
begin
  if FTransport <> nil then
  begin
    FTransport.Stop();
    FreeAndNil(FTransport);
  end;
  inherited Destroy;
end;

procedure TDebugSession.SetUnavailable(const AReason: String);
begin
  FAvailable := False;
  FUnavailableReason := AReason;
  FCapabilities := Default(TPdbpCapabilities);
  FCurrentPath := '';
  FCurrentLine := 0;
  FHandshakeDone := False;
  SetState(dsUnavailable);
end;

procedure TDebugSession.SetState(AState: TDebugState);
begin
  if FState = AState then Exit;
  FState := AState;
  if Assigned(FOnStateChange) then FOnStateChange(Self);
end;

procedure TDebugSession.Note(const AText: String);
begin
  if Assigned(FOnNote) then FOnNote(Self, AText);
end;

function TDebugSession.NextSeq(ACommand: TPdbpCommand; AArg: Integer): Integer;
var
  n: Integer;
begin
  Inc(FSeq);
  Result := FSeq;
  n := Length(FPendingSeq);
  SetLength(FPendingSeq, n + 1);
  SetLength(FPendingCmd, n + 1);
  SetLength(FPendingArg, n + 1);
  FPendingSeq[n] := Result;
  FPendingCmd[n] := ACommand;
  FPendingArg[n] := AArg;
end;

function TDebugSession.TakePending(ASeq: Integer;
  out ACommand: TPdbpCommand; out AArg: Integer): Boolean;
var
  i, last: Integer;
begin
  Result := False;
  ACommand := pcInitialize;
  AArg := 0;
  for i := 0 to High(FPendingSeq) do
    if FPendingSeq[i] = ASeq then
    begin
      ACommand := FPendingCmd[i];
      AArg := FPendingArg[i];
      last := High(FPendingSeq);
      FPendingSeq[i] := FPendingSeq[last];
      FPendingCmd[i] := FPendingCmd[last];
      FPendingArg[i] := FPendingArg[last];
      SetLength(FPendingSeq, last);
      SetLength(FPendingCmd, last);
      SetLength(FPendingArg, last);
      Exit(True);
    end;
end;

function TDebugSession.SendRaw(const AFrame: String): Boolean;
begin
  Result := (FTransport <> nil) and FTransport.SendFrame(AFrame);
  if not Result then Note('the debugger connection would not take the message');
end;

{ ---------------------------------------------------------------- the probe - }

procedure TDebugSession.Probe(const AHostPath: String);
var
  Output: String;
  Lines: TStringList;
  I: Integer;
  Advertises: Boolean;
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
    { RunAndCapture, not the RTL's RunCommand: the path came from a setting and a
      setting can name anything, so the wait needs a deadline and the child needs
      the LCL's UTF-8 handling of its own name. }
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

  Advertises := False;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for I := 0 to Lines.Count - 1 do
      if Pos(DebugSubcommandMarker, LowerCase(Trim(Lines[I]))) = 1 then
      begin
        Advertises := True;
        Break;
      end;
  finally
    Lines.Free;
  end;

  if not Advertises then
  begin
    SetUnavailable(NoDebugSupportReason);
    Exit;
  end;

  { The pre-filter passed. A session may be ATTEMPTED; whether it works is
    answered by the handshake and by nothing else, which is why Available is set
    there and not here. }
  FAvailable := True;
  FUnavailableReason := '';
  SetState(dsIdle);
end;

{ -------------------------------------------------------------- the session - }

function TDebugSession.BeginListen(const AProgramPath: String;
  const ALines: TPdbpLines; AStopAtEntry: Boolean): Word;
var
  i: Integer;
begin
  Result := 0;
  if FState = dsUnavailable then
  begin
    Note('this host cannot be debugged; nothing was started');
    Exit;
  end;
  if FTransport <> nil then
  begin
    FTransport.Stop();
    FreeAndNil(FTransport);
  end;

  FProgramPath := AProgramPath;
  SetLength(FWantLines, Length(ALines));
  for i := 0 to High(ALines) do FWantLines[i] := ALines[i];
  FWantEntry := AStopAtEntry;
  FHandshakeDone := False;
  FCurrentPath := '';
  FCurrentLine := 0;
  SetLength(FPendingSeq, 0);
  SetLength(FPendingCmd, 0);
  FSeq := 0;

  FTransport := TDebugTransport.Create();
  FTransport.OnFrame := @HandleFrame;
  FTransport.OnConnect := @HandleConnect;
  FTransport.OnDisconnect := @HandleDisconnect;
  Result := FTransport.Listen();
  if Result = 0 then
  begin
    FreeAndNil(FTransport);
    Note('the editor could not open a loopback port to debug on');
    Exit;
  end;
  SetState(dsStarting);
end;

procedure TDebugSession.AbandonListen(const AWhy: String);
begin
  if FTransport <> nil then
  begin
    FTransport.Stop();
    FreeAndNil(FTransport);
  end;
  FHandshakeDone := False;
  Note(AWhy);
  SetState(dsIdle);
end;

procedure TDebugSession.Poll;
begin
  if FTransport <> nil then FTransport.Poll();
end;

procedure TDebugSession.HandleConnect(Sender: TObject);
begin
  { The debuggee is on the wire. Nothing else may be sent before `initialize`,
    and the host enforces that from its side too. }
  SendRaw(EncodeInitialize(NextSeq(pcInitialize), 'PhosphorIDE'));
end;

procedure TDebugSession.SendSetBreakpoints;
begin
  SendRaw(EncodeSetBreakpoints(NextSeq(pcSetBreakpoints), FProgramPath,
                               FWantLines));
end;

procedure TDebugSession.HandleDisconnect(Sender: TObject);
begin
  { A closed socket IS the end of a session, not an error. The program may have
    finished perfectly well; the exit code arrives on `exited` when there is one,
    and the caller's process watcher has the rest. }
  FHandshakeDone := False;
  FCurrentPath := '';
  FCurrentLine := 0;
  if FState <> dsUnavailable then SetState(dsIdle);
end;

procedure TDebugSession.Desync(const AWhy: String);
begin
  { REPORT AND DISCONNECT. There is no recovering a line protocol whose framing
    has been lost: every following frame would be read against the wrong
    expectation, and the editor would show the user a debugger that is quietly
    describing something else. }
  Note('the debug connection went out of step (' + AWhy + '); disconnecting');
  SetState(dsTerminating);
  if FTransport <> nil then
  begin
    FTransport.Stop();
    FreeAndNil(FTransport);
  end;
  FHandshakeDone := False;
  SetState(dsIdle);
end;

procedure TDebugSession.HandleFrame(Sender: TObject; const AFrame: String);
var
  msg: TPdbpMessage;
begin
  msg := DecodePdbp(AFrame);
  if not msg.Valid then
  begin
    Desync(msg.ParseError);
    Exit;
  end;
  if msg.IsEvent then HandleEvent(msg)
  else if msg.IsResponse then HandleResponse(msg);
end;

procedure TDebugSession.HandleResponse(const AMsg: TPdbpMessage);
var
  cmd: TPdbpCommand;
  arg: Integer;
begin
  if not TakePending(AMsg.Seq, cmd, arg) then
  begin
    { An answer to something nobody asked. Not fatal on its own -- a late reply
      to a request abandoned by a disconnect looks exactly like this -- so it is
      logged and dropped rather than treated as a desync. }
    Note(Format('the debugger answered a request the editor does not remember ' +
                'making (seq %d); ignored', [AMsg.Seq]));
    Exit;
  end;

  if not AMsg.Ok then
  begin
    Note(Format('%s was refused: %s',
                [PdbpCommandName(cmd), AMsg.ErrorText]));
    Exit;
  end;

  case cmd of
    pcInitialize:
      begin
        if AMsg.Protocol <> 1 then
        begin
          { A VERSION THIS EDITOR DOES NOT SPEAK IS NOT SOMETHING TO GUESS AT.
            Carrying on would mean interpreting frames by a contract the other
            end has not agreed to. }
          Note(Format('the debugger speaks protocol %d and this editor speaks 1; ' +
                      'disconnecting', [AMsg.Protocol]));
          Stop(True);
          Exit;
        end;
        FCapabilities := AMsg.Capabilities;
        { THE HANDSHAKE IS WHAT PROVES IT, not the --help line that got us here. }
        FHandshakeDone := True;
        SendSetBreakpoints();
      end;

    pcSetBreakpoints:
      begin
        { The reply carries the set the host INSTALLED, which may be smaller than
          the one asked for. Handing it on is what lets the gutter show a mark
          that will never fire differently from one that will. }
        if Assigned(FOnLinesInstalled) then
          FOnLinesInstalled(Self, FProgramPath, AMsg.Lines);
        if not FWantEntry and (FState = dsStarting) then
          SendRaw(EncodeLaunch(NextSeq(pcLaunch), FProgramPath, False))
        else if FState = dsStarting then
          SendRaw(EncodeLaunch(NextSeq(pcLaunch), FProgramPath, True));
      end;

    pcLaunch:
      { THE ACKNOWLEDGEMENT IS THE START, NOT THE FINISH. The program's progress
        arrives as events; an editor that read this as a stop would repaint its
        current-line marker before there is a line to paint. }
      SetState(dsRunning);

    pcContinue, pcStepOver, pcStepInto, pcStepOut:
      SetState(dsRunning);

    pcPause:
      { Acknowledged, but not stopped yet: the `stopped` event is what says the
        program actually came to rest, and it arrives at the next statement
        boundary. }
      ;
    pcVariables:
      { Data, not state. It is handed straight on: the editor formats NOTHING --
        the host has already rendered each value the way PRINT would, and a second
        renderer here would be a second set of rules to keep in step. }
      if Assigned(FOnVariables) then
        FOnVariables(Self, arg, AMsg.Variables);

    pcStackTrace:
      if Assigned(FOnStackTrace) then
        FOnStackTrace(Self, AMsg.Frames);
  else
    { evaluate is refused by every host that reports evaluate:false, which is
      every host today, so its answer is a refusal handled above. }
    ;
  end;
end;

procedure TDebugSession.HandleEvent(const AMsg: TPdbpMessage);
begin
  case AMsg.Event of
    peStopped:
      begin
        FCurrentPath := AMsg.Path;
        FCurrentLine := AMsg.Line;
        SetState(dsStopped);
        if Assigned(FOnStopped) then
          FOnStopped(Self, AMsg.Path, AMsg.Line, AMsg.StopReason);
      end;
    peContinued:
      begin
        FCurrentPath := '';
        FCurrentLine := 0;
        SetState(dsRunning);
      end;
    peExited:
      begin
        FCurrentPath := '';
        FCurrentLine := 0;
        SetState(dsTerminating);
        if Assigned(FOnExited) then FOnExited(Self, AMsg.ExitCode);
      end;
    peTrace, peError:
      Note(AMsg.Text);
  end;
end;

{ ------------------------------------------------------------- the commands - }

function TDebugSession.Resume: Boolean;
begin
  Result := False;
  if FState <> dsStopped then
  begin
    Note('Continue is only possible while the program is stopped');
    Exit;
  end;
  Result := SendRaw(EncodeSimple(NextSeq(pcContinue), pcContinue));
end;

function TDebugSession.StepOver: Boolean;
begin
  Result := False;
  if FState <> dsStopped then
  begin
    Note('Step Over is only possible while the program is stopped');
    Exit;
  end;
  Result := SendRaw(EncodeSimple(NextSeq(pcStepOver), pcStepOver));
end;

function TDebugSession.StepInto: Boolean;
begin
  Result := False;
  if FState <> dsStopped then
  begin
    Note('Step Into is only possible while the program is stopped');
    Exit;
  end;
  Result := SendRaw(EncodeSimple(NextSeq(pcStepInto), pcStepInto));
end;

function TDebugSession.StepOut: Boolean;
begin
  Result := False;
  if FState <> dsStopped then
  begin
    Note('Step Out is only possible while the program is stopped');
    Exit;
  end;
  if not FCapabilities.StepOut then
  begin
    Note('this debugger does not offer Step Out');
    Exit;
  end;
  Result := SendRaw(EncodeSimple(NextSeq(pcStepOut), pcStepOut));
end;

function TDebugSession.Pause: Boolean;
begin
  Result := False;
  if FState <> dsRunning then
  begin
    Note('Pause is only possible while the program is running');
    Exit;
  end;
  if not FCapabilities.Pause then
  begin
    { The capability is asked rather than assumed. It said True for a year while
      the host could not answer a pause at all; believing the handshake is right,
      but believing it blindly is how the editor grew a button that did nothing. }
    Note('this debugger does not offer Pause');
    Exit;
  end;
  Result := SendRaw(EncodeSimple(NextSeq(pcPause), pcPause));
end;

function TDebugSession.SetBreakpoints(const APath: String;
  const ALines: TPdbpLines): Boolean;
var
  i: Integer;
begin
  Result := False;
  if not FHandshakeDone then
  begin
    Note('breakpoints can only be sent to a running debug session');
    Exit;
  end;
  SetLength(FWantLines, Length(ALines));
  for i := 0 to High(ALines) do FWantLines[i] := ALines[i];
  FProgramPath := APath;
  Result := SendRaw(EncodeSetBreakpoints(NextSeq(pcSetBreakpoints), APath, ALines));
end;

function TDebugSession.RequestStackTrace: Boolean;
begin
  Result := False;
  if FState <> dsStopped then
  begin
    Note('the call stack is only readable while the program is stopped');
    Exit;
  end;
  Result := SendRaw(EncodeStackTrace(NextSeq(pcStackTrace)));
end;

function TDebugSession.RequestVariables(AFrame: Integer): Boolean;
begin
  Result := False;
  if FState <> dsStopped then
  begin
    Note('variables are only readable while the program is stopped');
    Exit;
  end;
  Result := SendRaw(EncodeVariables(NextSeq(pcVariables, AFrame), AFrame));
end;

procedure TDebugSession.Stop(ATerminate: Boolean);
begin
  if FTransport = nil then Exit;
  SetState(dsTerminating);
  { Sent best-effort. `disconnect` while the program RUNS is never answered --
    the caller kills the process instead -- so this neither waits nor cares. }
  if FHandshakeDone then
    SendRaw(EncodeDisconnect(NextSeq(pcDisconnect), ATerminate));
  FTransport.Stop();
  FreeAndNil(FTransport);
  FHandshakeDone := False;
  FCurrentPath := '';
  FCurrentLine := 0;
  SetState(dsIdle);
end;

end.
