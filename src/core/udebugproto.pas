unit udebugproto;

{ PDBP -- the Phosphor Debug Protocol, editor side.

  A line-delimited JSON protocol between this editor and a debug-capable phosphor
  host. docs/debug-protocol.md is the specification; this unit is one of its two
  ends, and it is written so that the other end can be implemented from the
  document alone without reading this code.

  NOTHING SPEAKS IT YET. The shipping phosphor host cannot pause a running
  program: its BREAKPOINT seam is documented as report-and-continue and "must
  never block" (engine/PhosphorValue.pas:73-74), the VM has no step API, and the
  console host does not install the seam at all. So this unit encodes and decodes
  a conversation that currently has no counterpart -- deliberately, because the
  wire format is the half that two independent implementations have to agree on,
  and it is the half that can be pinned down and tested now, before either end
  exists to argue with.

  WHY NOT DAP. The Debug Adapter Protocol would bring an editor-agnostic
  ecosystem, and it is the right answer if PhosphorIDE is ever not the only
  client. It is not the right answer for the FIRST implementation: DAP's framing
  is HTTP-style headers over a byte stream, its message set is large, and the half
  that has to be written in Free Pascal inside the phosphor host is the half that
  pays for that. PDBP is deliberately small enough that a host-side implementation
  is a day's work rather than a project, and its message names are DAP's, so a
  DAP bridge later is a rename and not a redesign.

  WHY NOT stdout. The obvious transport -- protocol frames on the child's own
  stdout, distinguished by a prefix -- is unusable for a language whose entire
  observable behaviour is PRINT. A program that prints a line shaped like a frame
  would drive the debugger: one PRINTLN of a forged exited-event ends the session
  from inside the program being debugged. The program's streams stay the
  program's; the protocol gets its own socket. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser;

const
  { Bumped when a change would break an existing implementation of the other end.
    The handshake exchanges it and both sides refuse a mismatch, because a
    debugger that half-works is harder to diagnose than one that will not start. }
  PdbpVersion = 1;

type
  { Editor -> host. Named after their DAP equivalents so that a later bridge is a
    mapping table rather than a translation. }
  TPdbpCommand = (
    pcInitialize,     // handshake; must be first
    pcSetBreakpoints, // replace the breakpoint set for one source file
    pcLaunch,         // begin executing; stops at entry if requested
    pcContinue,
    pcPause,
    pcStepOver,
    pcStepInto,
    pcStepOut,
    pcStackTrace,
    pcVariables,
    pcEvaluate,
    pcDisconnect
  );

  { Host -> editor, unsolicited. }
  TPdbpEvent = (
    peStopped,     // execution has paused; carries a reason and a location
    peContinued,   // execution resumed (after a pause the editor did not request)
    peExited,      // the program finished; carries its exit code
    peTrace,       // a BREAKPOINT statement reported a frame
    peError        // the host is unhappy, but still connected
  );

  TPdbpStopReason = (
    psrEntry,      // paused before the first statement
    psrBreakpoint,
    psrStep,
    psrPause,      // the editor asked
    psrException   // a runtime error; the program is done after this
  );

  { What the other end admits it can do. A host that has breakpoints but no
    expression evaluator says so here, and the editor greys out what is missing
    rather than sending a request that will be refused. }
  TPdbpCapabilities = record
    StepOut: Boolean;
    Evaluate: Boolean;
    SetVariable: Boolean;
    Pause: Boolean;
    ConditionalBreakpoints: Boolean;
  end;

  TPdbpFrame = record
    Index: Integer;
    Name: String;     // the function's name, or '(main)'
    Path: String;
    Line: Integer;
  end;
  TPdbpFrames = array of TPdbpFrame;

  TPdbpVariable = record
    Name: String;     // includes the type suffix: count%, name$, list@
    Value: String;    // already rendered by the host, as PRINT would render it
    Kind: String;     // 'number' | 'int' | 'string' | 'bool' | 'handle'
    Scope: String;    // 'local' | 'global'
  end;
  TPdbpVariables = array of TPdbpVariable;

  { A decoded inbound line. Exactly one of IsEvent / IsResponse is true. }
  TPdbpMessage = record
    Valid: Boolean;
    Raw: String;
    ParseError: String;

    IsEvent: Boolean;
    Event: TPdbpEvent;

    IsResponse: Boolean;
    Seq: Integer;
    Ok: Boolean;
    ErrorText: String;

    // peStopped
    StopReason: TPdbpStopReason;
    Path: String;
    Line: Integer;

    // peExited
    ExitCode: Integer;

    // peTrace / peError
    Text: String;

    // pcInitialize's response
    Protocol: Integer;
    Capabilities: TPdbpCapabilities;

    // pcStackTrace's response
    Frames: TPdbpFrames;

    // pcVariables' response
    Variables: TPdbpVariables;
  end;

{ ---- encoding: every request the editor can send ------------------------- }

function PdbpCommandName(ACommand: TPdbpCommand): String;
function PdbpEventName(AEvent: TPdbpEvent): String;
function PdbpStopReasonName(AReason: TPdbpStopReason): String;

function EncodeInitialize(ASeq: Integer; const AClientName: String): String;
function EncodeSetBreakpoints(ASeq: Integer; const APath: String;
  const ALines: array of Integer): String;
function EncodeLaunch(ASeq: Integer; const AProgramPath: String;
  AStopAtEntry: Boolean): String;
function EncodeSimple(ASeq: Integer; ACommand: TPdbpCommand): String;
function EncodeStackTrace(ASeq: Integer): String;
function EncodeVariables(ASeq: Integer; AFrame: Integer): String;
function EncodeEvaluate(ASeq: Integer; AFrame: Integer; const AExpr: String): String;
function EncodeDisconnect(ASeq: Integer; ATerminate: Boolean): String;

{ ---- decoding: one inbound line ------------------------------------------ }

{ Never raises. A line that is not JSON, or is JSON of the wrong shape, comes
  back with Valid=False and ParseError set -- a desync is a thing to report and
  disconnect over, not a thing to crash on. }
function DecodePdbp(const ALine: String): TPdbpMessage;

implementation

const
  CommandNames: array[TPdbpCommand] of String = (
    'initialize', 'setBreakpoints', 'launch', 'continue', 'pause',
    'stepOver', 'stepInto', 'stepOut', 'stackTrace', 'variables',
    'evaluate', 'disconnect');

  EventNames: array[TPdbpEvent] of String = (
    'stopped', 'continued', 'exited', 'trace', 'error');

  StopReasonNames: array[TPdbpStopReason] of String = (
    'entry', 'breakpoint', 'step', 'pause', 'exception');

function PdbpCommandName(ACommand: TPdbpCommand): String;
begin
  Result := CommandNames[ACommand];
end;

function PdbpEventName(AEvent: TPdbpEvent): String;
begin
  Result := EventNames[AEvent];
end;

function PdbpStopReasonName(AReason: TPdbpStopReason): String;
begin
  Result := StopReasonNames[AReason];
end;

{ One frame is one LINE, so the encoder must never emit a newline inside it.
  TJSONObject.AsJSON produces compact output with no line breaks, and JSON string
  escaping turns any newline in a value into \n -- which is the property the
  framing rests on. }
function Frame(AObj: TJSONObject): String;
begin
  try
    Result := AObj.AsJSON;
  finally
    AObj.Free;
  end;
end;

function NewRequest(ASeq: Integer; ACommand: TPdbpCommand): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('seq', ASeq);
  Result.Add('cmd', CommandNames[ACommand]);
end;

function EncodeInitialize(ASeq: Integer; const AClientName: String): String;
var
  Obj: TJSONObject;
begin
  Obj := NewRequest(ASeq, pcInitialize);
  Obj.Add('protocol', PdbpVersion);
  Obj.Add('client', AClientName);
  Result := Frame(Obj);
end;

function EncodeSetBreakpoints(ASeq: Integer; const APath: String;
  const ALines: array of Integer): String;
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Obj := NewRequest(ASeq, pcSetBreakpoints);
  Obj.Add('path', APath);
  Arr := TJSONArray.Create;
  for I := Low(ALines) to High(ALines) do
    Arr.Add(ALines[I]);
  { The whole set is replaced, never added to. An add/remove protocol needs both
    ends to agree on what is currently set, and they will not: the editor's list
    moves every time a line is inserted above a mark. }
  Obj.Add('lines', Arr);
  Result := Frame(Obj);
end;

function EncodeLaunch(ASeq: Integer; const AProgramPath: String;
  AStopAtEntry: Boolean): String;
var
  Obj: TJSONObject;
begin
  Obj := NewRequest(ASeq, pcLaunch);
  Obj.Add('program', AProgramPath);
  Obj.Add('stopAtEntry', AStopAtEntry);
  Result := Frame(Obj);
end;

function EncodeSimple(ASeq: Integer; ACommand: TPdbpCommand): String;
begin
  Result := Frame(NewRequest(ASeq, ACommand));
end;

function EncodeStackTrace(ASeq: Integer): String;
begin
  Result := Frame(NewRequest(ASeq, pcStackTrace));
end;

function EncodeVariables(ASeq: Integer; AFrame: Integer): String;
var
  Obj: TJSONObject;
begin
  Obj := NewRequest(ASeq, pcVariables);
  Obj.Add('frame', AFrame);
  Result := Frame(Obj);
end;

function EncodeEvaluate(ASeq: Integer; AFrame: Integer; const AExpr: String): String;
var
  Obj: TJSONObject;
begin
  Obj := NewRequest(ASeq, pcEvaluate);
  Obj.Add('frame', AFrame);
  Obj.Add('expr', AExpr);
  Result := Frame(Obj);
end;

function EncodeDisconnect(ASeq: Integer; ATerminate: Boolean): String;
var
  Obj: TJSONObject;
begin
  Obj := NewRequest(ASeq, pcDisconnect);
  { False leaves the program running to completion without a debugger attached,
    which is what "stop debugging but let it finish" means. }
  Obj.Add('terminate', ATerminate);
  Result := Frame(Obj);
end;

{ ------------------------------------------------------------- decoding ----- }

function GetStr(AObj: TJSONObject; const AName, ADefault: String): String;
var
  Item: TJSONData;
begin
  Item := AObj.Find(AName);
  if (Item = nil) or (Item.JSONType = jtNull) then
    Result := ADefault
  else
    Result := Item.AsString;
end;

function GetInt(AObj: TJSONObject; const AName: String; ADefault: Integer): Integer;
var
  Item: TJSONData;
begin
  Item := AObj.Find(AName);
  if (Item = nil) or (Item.JSONType = jtNull) then
    Result := ADefault
  else
    Result := Item.AsInteger;
end;

function GetBool(AObj: TJSONObject; const AName: String; ADefault: Boolean): Boolean;
var
  Item: TJSONData;
begin
  Item := AObj.Find(AName);
  if (Item = nil) or (Item.JSONType = jtNull) then
    Result := ADefault
  else
    Result := Item.AsBoolean;
end;

function ParseCapabilities(AObj: TJSONObject): TPdbpCapabilities;
var
  Caps: TJSONObject;
  Item: TJSONData;
begin
  Result := Default(TPdbpCapabilities);
  Item := AObj.Find('capabilities');
  if (Item = nil) or (Item.JSONType <> jtObject) then
    Exit;
  Caps := TJSONObject(Item);
  { Everything defaults to False. A host that does not mention a capability does
    not have it -- the editor must never assume its way into sending a request
    the other end will refuse. }
  Result.StepOut := GetBool(Caps, 'stepOut', False);
  Result.Evaluate := GetBool(Caps, 'evaluate', False);
  Result.SetVariable := GetBool(Caps, 'setVariable', False);
  Result.Pause := GetBool(Caps, 'pause', False);
  Result.ConditionalBreakpoints := GetBool(Caps, 'conditionalBreakpoints', False);
end;

procedure ParseFrames(AObj: TJSONObject; out AFrames: TPdbpFrames);
var
  Item: TJSONData;
  Arr: TJSONArray;
  I: Integer;
  Entry: TJSONObject;
begin
  AFrames := nil;
  Item := AObj.Find('frames');
  if (Item = nil) or (Item.JSONType <> jtArray) then
    Exit;
  Arr := TJSONArray(Item);
  SetLength(AFrames, Arr.Count);
  for I := 0 to Arr.Count - 1 do
  begin
    if Arr.Items[I].JSONType <> jtObject then
      Continue;
    Entry := TJSONObject(Arr.Items[I]);
    AFrames[I].Index := GetInt(Entry, 'index', I);
    AFrames[I].Name := GetStr(Entry, 'name', '');
    AFrames[I].Path := GetStr(Entry, 'path', '');
    AFrames[I].Line := GetInt(Entry, 'line', 0);
  end;
end;

procedure ParseVariables(AObj: TJSONObject; out AVars: TPdbpVariables);
var
  Item: TJSONData;
  Arr: TJSONArray;
  I: Integer;
  Entry: TJSONObject;
begin
  AVars := nil;
  Item := AObj.Find('variables');
  if (Item = nil) or (Item.JSONType <> jtArray) then
    Exit;
  Arr := TJSONArray(Item);
  SetLength(AVars, Arr.Count);
  for I := 0 to Arr.Count - 1 do
  begin
    if Arr.Items[I].JSONType <> jtObject then
      Continue;
    Entry := TJSONObject(Arr.Items[I]);
    AVars[I].Name := GetStr(Entry, 'name', '');
    AVars[I].Value := GetStr(Entry, 'value', '');
    AVars[I].Kind := GetStr(Entry, 'kind', '');
    AVars[I].Scope := GetStr(Entry, 'scope', '');
  end;
end;

function DecodePdbp(const ALine: String): TPdbpMessage;
var
  Data: TJSONData;
  Obj: TJSONObject;
  Name: String;
  E: TPdbpEvent;
  R: TPdbpStopReason;
  Found: Boolean;
begin
  Result := Default(TPdbpMessage);
  Result.Raw := ALine;
  Result.Valid := False;

  if Trim(ALine) = '' then
  begin
    Result.ParseError := 'empty line';
    Exit;
  end;

  Data := nil;
  try
    try
      Data := GetJSON(ALine);
    except
      on Ex: Exception do
      begin
        Result.ParseError := 'not JSON: ' + Ex.Message;
        Exit;
      end;
    end;

    if (Data = nil) or (Data.JSONType <> jtObject) then
    begin
      Result.ParseError := 'not a JSON object';
      Exit;
    end;
    Obj := TJSONObject(Data);

    Name := GetStr(Obj, 'event', '');
    if Name <> '' then
    begin
      Found := False;
      for E := Low(TPdbpEvent) to High(TPdbpEvent) do
        if EventNames[E] = Name then
        begin
          Result.Event := E;
          Found := True;
          Break;
        end;
      if not Found then
      begin
        Result.ParseError := 'unknown event: ' + Name;
        Exit;
      end;

      Result.IsEvent := True;
      Result.Valid := True;

      case Result.Event of
        peStopped:
          begin
            Result.Path := GetStr(Obj, 'path', '');
            Result.Line := GetInt(Obj, 'line', 0);
            Name := GetStr(Obj, 'reason', 'step');
            Result.StopReason := psrStep;
            for R := Low(TPdbpStopReason) to High(TPdbpStopReason) do
              if StopReasonNames[R] = Name then
              begin
                Result.StopReason := R;
                Break;
              end;
            Result.Text := GetStr(Obj, 'text', '');
          end;
        peExited:
          Result.ExitCode := GetInt(Obj, 'exitCode', 0);
        peTrace, peError:
          begin
            Result.Text := GetStr(Obj, 'text', '');
            Result.Line := GetInt(Obj, 'line', 0);
            Result.Path := GetStr(Obj, 'path', '');
          end;
      end;
      Exit;
    end;

    if Obj.Find('seq') = nil then
    begin
      Result.ParseError := 'neither an event nor a response (no seq)';
      Exit;
    end;

    Result.IsResponse := True;
    Result.Valid := True;
    Result.Seq := GetInt(Obj, 'seq', 0);
    Result.Ok := GetBool(Obj, 'ok', False);
    Result.ErrorText := GetStr(Obj, 'error', '');
    Result.Protocol := GetInt(Obj, 'protocol', 0);
    Result.Text := GetStr(Obj, 'result', '');
    Result.Capabilities := ParseCapabilities(Obj);
    ParseFrames(Obj, Result.Frames);
    ParseVariables(Obj, Result.Variables);
  finally
    Data.Free;
  end;
end;

end.
