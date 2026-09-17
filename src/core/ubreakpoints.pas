unit ubreakpoints;

{ A set of breakpoint line numbers, and the arithmetic that keeps them pointing at
  the statement the user chose while the text around them moves.

  IT IS A UNIT OF ITS OWN because the arithmetic is the part that is easy to get
  quietly wrong and hard to notice: an off-by-one here does not crash, it moves a
  breakpoint one statement down and waits for someone to spend an afternoon
  wondering why the program stopped in the wrong place. Separated out, it has no
  LCL dependency and `tests/phosphoridetest.lpr` can exercise every boundary case
  without a window -- which a set of breakpoints living inside a TSynEdit could
  not be.

  THE ONE JUDGEMENT CALL: a breakpoint whose line is DELETED is dropped, not slid
  onto the line that takes its place. A mark that silently moves to a statement the
  user did not choose is worse than one that disappears, because the second is
  visible and the first is not.

  A BREAKPOINT ALSO CARRIES A CONDITION, and it is ONE ARRAY OF RECORDS rather
  than a line array with a string array beside it. That is not tidiness. Every
  operation here moves entries about -- Toggle shifts a hole closed or open with
  two hand-written loops, TrackEdit compacts in place -- and a parallel array is
  a rule that all of them must move both, which is a rule nothing can check. A
  record cannot be half-moved. This repository has spent four roadmap items on
  things that existed twice and drifted; a fifth would be a poor use of an
  afternoon.

  THE CONDITION IS THE USER'S TEXT AND NOTHING ELSE. It is not compiled here, not
  checked here, and this unit does not know that a host exists -- which is the
  same reason the arithmetic is here and the protocol is not. Whether a condition
  is legal is a question only the thing that runs the program can answer, and
  `TFrmMain` holds that answer beside the installed-lines answer it already
  holds. }

{$mode objfpc}{$H+}

interface

type
  TBreakpointLines = array of Integer;

  { A line and the condition the user gave it. An empty Condition is the ordinary
    breakpoint, which is why nothing has to be initialised for one. }
  TBreakpointItem = record
    Line: Integer;
    Condition: String;
  end;
  TBreakpointItems = array of TBreakpointItem;

  { Sorted ascending, no duplicates, all >= 1. }
  TBreakpointSet = class
  private
    FItems: TBreakpointItems;
    function IndexOf(ALine: Integer): Integer;
    function GetCount: Integer;
    function GetLine(AIndex: Integer): Integer;
    function GetCondition(AIndex: Integer): String;
  public
    { True if the line now has a breakpoint. }
    function Toggle(ALine: Integer): Boolean;
    procedure Clear;
    function Has(ALine: Integer): Boolean;

    { The condition on a line, or '' when it has none or has no breakpoint.
      ASKING ABOUT A LINE WITHOUT ONE IS NOT AN ERROR: the gutter asks per visible
      row on every repaint and a caller that had to test Has first would grow a
      second scan for nothing. }
    function ConditionOf(ALine: Integer): String;

    { Give a line's breakpoint a condition, or clear it with ''. Answers False if
      the line has no breakpoint -- a condition without a breakpoint is not a
      thing this set can hold, and answering rather than raising lets the caller
      decide whether that was a mistake or a race with an edit. }
    function SetCondition(ALine: Integer; const ACondition: String): Boolean;

    { How many of them carry one. The status bar and --selftest want a number, and
      counting it here keeps the field private. }
    function ConditionalCount: Integer;

    { Follow an edit that changed the LINE COUNT.

      AFirstLine is the 1-based line at which the change happened and ADelta the
      number of lines added (positive) or removed (negative).

      A breakpoint strictly above AFirstLine never moves: text inserted below it
      cannot change which statement it is on. One at or below it moves by ADelta,
      unless the deletion swallowed its line, in which case it is dropped. }
    procedure TrackEdit(AFirstLine, ADelta: Integer);

    { A copy of the lines alone. }
    function ToArray: TBreakpointLines;

    { A copy of the lines AND their conditions, which is what goes on the wire.

      THIS EXISTS BECAUSE ToArray DID NOT GET CALLED. Its comment has said "for
      handing to a debug adapter" since it was written and nothing ever did: both
      places that build the frame -- StartDebugSession and SyncBreakpoints in
      umainform -- wrote their own loop over the document's facade instead. That
      cost nothing while a breakpoint was one integer. It would cost a feature the
      moment one carried a condition, because a hand-written loop that copies the
      line and forgets the condition compiles, runs, and sends a breakpoint that
      fires on every hit. So both sites go through this one, and the only way to
      build the frame is the way that carries everything. }
    function ToItems: TBreakpointItems;

    property Count: Integer read GetCount;
    property Lines[AIndex: Integer]: Integer read GetLine; default;
    property Conditions[AIndex: Integer]: String read GetCondition;
  end;

{ WHERE ONE LINE ENDS UP after an edit that changed the line count, or 0 if the
  edit deleted it.

  This is the arithmetic TBreakpointSet.TrackEdit applies to a whole set, pulled
  out so that the ONE OTHER THING in this editor that remembers a line number can
  apply it too: roadmap item 24's mark on the line a failed run blamed. A second
  copy of a three-branch rule is how the two would come to disagree about where a
  line went, and this repository has spent two items on exactly that.

  AFirstLine is the 1-based line at which the change happened and ADelta the
  number of lines added (positive) or removed (negative). }
function TrackLine(ALine, AFirstLine, ADelta: Integer): Integer;

implementation

function TBreakpointSet.IndexOf(ALine: Integer): Integer;
var
  I: Integer;
begin
  { A linear scan over a handful of numbers. This is asked once per visible line
    on every repaint, so it must be cheap -- and for the counts a person actually
    sets, a scan over a packed array beats anything with a hash in it. }
  for I := 0 to High(FItems) do
    if FItems[I].Line = ALine then
      Exit(I);
  Result := -1;
end;

function TBreakpointSet.GetCount: Integer;
begin
  Result := Length(FItems);
end;

function TBreakpointSet.GetLine(AIndex: Integer): Integer;
begin
  Result := FItems[AIndex].Line;
end;

function TBreakpointSet.GetCondition(AIndex: Integer): String;
begin
  Result := FItems[AIndex].Condition;
end;

function TBreakpointSet.Has(ALine: Integer): Boolean;
begin
  Result := IndexOf(ALine) >= 0;
end;

function TBreakpointSet.ConditionOf(ALine: Integer): String;
var
  Idx: Integer;
begin
  Idx := IndexOf(ALine);
  if Idx < 0 then
    Exit('');
  Result := FItems[Idx].Condition;
end;

function TBreakpointSet.SetCondition(ALine: Integer;
  const ACondition: String): Boolean;
var
  Idx: Integer;
begin
  Idx := IndexOf(ALine);
  Result := Idx >= 0;
  if Result then
    FItems[Idx].Condition := ACondition;
end;

function TBreakpointSet.ConditionalCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FItems) do
    if FItems[I].Condition <> '' then
      Inc(Result);
end;

function TBreakpointSet.Toggle(ALine: Integer): Boolean;
var
  Idx, I, Insert: Integer;
begin
  Result := False;
  if ALine < 1 then
    Exit;

  Idx := IndexOf(ALine);
  if Idx >= 0 then
  begin
    { THE CONDITION GOES WITH IT, and it goes because the record does. Toggling a
      breakpoint off and on again is how a person clears a condition they cannot
      remember typing; a set that kept the old text on the old line would hand it
      back to a breakpoint nobody meant to make conditional. }
    for I := Idx to High(FItems) - 1 do
      FItems[I] := FItems[I + 1];
    SetLength(FItems, Length(FItems) - 1);
    Exit(False);
  end;

  Insert := Length(FItems);
  for I := 0 to High(FItems) do
    if FItems[I].Line > ALine then
    begin
      Insert := I;
      Break;
    end;
  SetLength(FItems, Length(FItems) + 1);
  for I := High(FItems) downto Insert + 1 do
    FItems[I] := FItems[I - 1];
  FItems[Insert].Line := ALine;
  FItems[Insert].Condition := '';
  Result := True;
end;

procedure TBreakpointSet.Clear;
begin
  SetLength(FItems, 0);
end;

function TrackLine(ALine, AFirstLine, ADelta: Integer): Integer;
begin
  if (ADelta = 0) or (ALine < 1) then
    Exit(ALine);
  { Strictly above the change: text inserted or removed below a line cannot
    change which statement that line is. }
  if ALine < AFirstLine then
    Exit(ALine);
  { Inside a deleted range: the line is gone. Dropped rather than slid onto its
    neighbour, which would point at a statement nobody chose. }
  if (ADelta < 0) and (ALine < AFirstLine - ADelta) then
    Exit(0);
  Result := ALine + ADelta;
end;

procedure TBreakpointSet.TrackEdit(AFirstLine, ADelta: Integer);
var
  I, Keep, Moved: Integer;
begin
  if ADelta = 0 then
    Exit;

  Keep := 0;
  for I := 0 to High(FItems) do
  begin
    Moved := TrackLine(FItems[I].Line, AFirstLine, ADelta);
    if Moved = 0 then
      Continue;                  { the deletion swallowed it }
    { THE WHOLE RECORD MOVES, not the line out of it. Compacting the lines and
      leaving the conditions where they were is the exact defect this unit is
      built as records to make unspellable: after one deleted breakpoint every
      remaining condition would belong to the breakpoint below the one that
      typed it, silently, and only while the program ran. }
    FItems[Keep] := FItems[I];
    FItems[Keep].Line := Moved;
    Inc(Keep);
  end;
  SetLength(FItems, Keep);
end;

function TBreakpointSet.ToArray: TBreakpointLines;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(FItems));
  for I := 0 to High(FItems) do
    Result[I] := FItems[I].Line;
end;

function TBreakpointSet.ToItems: TBreakpointItems;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(FItems));
  for I := 0 to High(FItems) do
    Result[I] := FItems[I];
end;

end.
