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
  { ubreakpoints for TBreakpointItems, and DELIBERATELY not a second record of
    its own. A breakpoint on the wire is a line and the user's condition, which
    is exactly what a breakpoint in the set is; defining that pair twice is how
    the two would come to disagree about which field is which. Both units are
    LCL-free and neither knows about the other's job -- ubreakpoints has no uses
    clause at all -- so the dependency costs nothing and buys the one shape. }
  Classes, SysUtils, fpjson, jsonparser, ubreakpoints;

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

  TPdbpLines = array of Integer;

  { A CONDITION THE HOST WOULD NOT TAKE, from `setBreakpoints`' reply.

    It carries the line so the editor can put the message where the condition was
    typed, and the condition itself so it can say WHICH one when a line's text has
    moved on since. The host sends this only for a condition it could not read as
    an expression; one whose NAMES are wrong cannot be caught at reply time,
    because scope is a frame and there is no frame yet, and arrives instead as a
    stop that says why. }
  TPdbpRejection = record
    Line: Integer;
    Condition: String;
    ErrorText: String;
  end;
  TPdbpRejections = array of TPdbpRejection;

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

    // peTrace / peError -- AND pcEvaluate's answer, which arrives under the same
    // key. The host renders an evaluated value exactly as `variables` renders
    // one and exactly as PRINT would, so there is one string here and not a
    // number: the editor does not format values, does not know the rules, and a
    // second renderer is a second set of rules to keep in step.
    Text: String;

    // pcEvaluate's response: WHICH OF THE FIVE KINDS the value is --
    // 'number' | 'int' | 'string' | 'bool' | 'handle', the same alphabet
    // `variables` uses. Decoded and not derived: `Text` alone cannot say whether
    // "42" was an int% or a number, and a watch pane that guessed would be
    // inventing a fact the host already sent.
    Kind: String;

    // pcInitialize's response
    Protocol: Integer;
    Capabilities: TPdbpCapabilities;

    // pcSetBreakpoints' response: the set the host ACTUALLY INSTALLED, which
    // may be smaller than the one asked for. A line holding no executable
    // statement -- a blank line, a comment, `endif` -- has nowhere to stop, and
    // the editor draws the difference so a breakpoint that will never fire looks
    // different from one that will. Reading this is the whole point of the reply;
    // until 2026-09-15 the host echoed the request back and every mark looked
    // verified, so there was nothing here to read.
    Lines: TPdbpLines;

    // pcSetBreakpoints' response, when the host refused a condition. Empty is
    // the ordinary case and the key is omitted entirely then, so a host that has
    // never heard of conditions answers exactly what it always answered.
    Rejected: TPdbpRejections;

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
  const AItems: TBreakpointItems; AWithConditions: Boolean): String;
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
  const AItems: TBreakpointItems; AWithConditions: Boolean): String;
var
  Obj: TJSONObject;
  Arr, Conds: TJSONArray;
  I: Integer;
  Any: Boolean;
begin
  Obj := NewRequest(ASeq, pcSetBreakpoints);
  Obj.Add('path', APath);
  Arr := TJSONArray.Create;
  for I := Low(AItems) to High(AItems) do
    Arr.Add(AItems[I].Line);
  { The whole set is replaced, never added to. An add/remove protocol needs both
    ends to agree on what is currently set, and they will not: the editor's list
    moves every time a line is inserted above a mark. }
  Obj.Add('lines', Arr);

  { CONDITIONS RIDE IN A SIBLING KEY, parallel to `lines` and the same length.

    NOT AS OBJECTS INSIDE `lines`, which is the shape that suggests itself: the
    console host as it FIRST shipped read that array with fpjson's Integers[],
    which converts, and an object element raised inside its loop and took the
    debuggee down. The hardening that drops a non-integer instead arrived on
    2026-09-16 and an editor cannot know which host is on the other end. A key an
    unaware host never looks for cannot hurt it.

    AND ONLY WHEN THE HOST SAID IT UNDERSTANDS. A host that answers
    conditionalBreakpoints:false would install the line and fire on every hit --
    the condition silently ignored, which is the one outcome worse than refusing
    to send it. The caller passes what the handshake said; this function does not
    guess.

    The key is omitted when no breakpoint has one, so the ordinary frame is the
    frame it always was. }
  if not AWithConditions then
  begin
    Result := Frame(Obj);
    Exit;
  end;
  Any := False;
  for I := Low(AItems) to High(AItems) do
    if AItems[I].Condition <> '' then
    begin
      Any := True;
      Break;
    end;
  if Any then
  begin
    Conds := TJSONArray.Create;
    for I := Low(AItems) to High(AItems) do
      Conds.Add(AItems[I].Condition);
    Obj.Add('conditions', Conds);
  end;
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

{ The conditions the host would not take. Absent is the ordinary answer and is
  not an error; a malformed element is dropped rather than raising, for the same
  reason every other array here is read that way. }
procedure ParseRejections(AObj: TJSONObject; out AOut: TPdbpRejections);
var
  Item, El: TJSONData;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I, N: Integer;
begin
  AOut := nil;
  Item := AObj.Find('rejected');
  if (Item = nil) or (Item.JSONType <> jtArray) then
    Exit;
  Arr := TJSONArray(Item);
  SetLength(AOut, Arr.Count);
  N := 0;
  for I := 0 to Arr.Count - 1 do
  begin
    El := Arr.Items[I];
    if (El = nil) or (El.JSONType <> jtObject) then
      Continue;
    Obj := TJSONObject(El);
    AOut[N].Line := GetInt(Obj, 'line', 0);
    AOut[N].Condition := GetStr(Obj, 'condition', '');
    AOut[N].ErrorText := GetStr(Obj, 'error', '');
    if AOut[N].Line < 1 then
      Continue;
    Inc(N);
  end;
  SetLength(AOut, N);
end;

procedure ParseInstalledLines(AObj: TJSONObject; out ALines: TPdbpLines);
var
  Item: TJSONData;
  Arr: TJSONArray;
  I, N: Integer;
begin
  ALines := nil;
  Item := AObj.Find('lines');
  if (Item = nil) or (Item.JSONType <> jtArray) then
    Exit;
  Arr := TJSONArray(Item);
  SetLength(ALines, Arr.Count);
  N := 0;
  for I := 0 to Arr.Count - 1 do
  begin
    { A non-number is dropped rather than raising. The host it talks to drops
      malformed elements on the way in for the same reason, and neither end
      should die of the other's bug. }
    if Arr.Items[I].JSONType <> jtNumber then
      Continue;
    ALines[N] := Arr.Items[I].AsInteger;
    Inc(N);
  end;
  SetLength(ALines, N);
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
    Result.Kind := GetStr(Obj, 'kind', '');
    Result.Capabilities := ParseCapabilities(Obj);
    ParseInstalledLines(Obj, Result.Lines);
    ParseRejections(Obj, Result.Rejected);
    ParseFrames(Obj, Result.Frames);
    ParseVariables(Obj, Result.Variables);
  finally
    Data.Free;
  end;
end;

end.
