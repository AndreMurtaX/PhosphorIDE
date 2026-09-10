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
  visible and the first is not. }

{$mode objfpc}{$H+}

interface

type
  TBreakpointLines = array of Integer;

  { Sorted ascending, no duplicates, all >= 1. }
  TBreakpointSet = class
  private
    FLines: TBreakpointLines;
    function IndexOf(ALine: Integer): Integer;
    function GetCount: Integer;
    function GetLine(AIndex: Integer): Integer;
  public
    { True if the line now has a breakpoint. }
    function Toggle(ALine: Integer): Boolean;
    procedure Clear;
    function Has(ALine: Integer): Boolean;

    { Follow an edit that changed the LINE COUNT.

      AFirstLine is the 1-based line at which the change happened and ADelta the
      number of lines added (positive) or removed (negative).

      A breakpoint strictly above AFirstLine never moves: text inserted below it
      cannot change which statement it is on. One at or below it moves by ADelta,
      unless the deletion swallowed its line, in which case it is dropped. }
    procedure TrackEdit(AFirstLine, ADelta: Integer);

    { A copy, for handing to a debug adapter or a session file. }
    function ToArray: TBreakpointLines;

    property Count: Integer read GetCount;
    property Lines[AIndex: Integer]: Integer read GetLine; default;
  end;

implementation

function TBreakpointSet.IndexOf(ALine: Integer): Integer;
var
  I: Integer;
begin
  { A linear scan over a handful of numbers. This is asked once per visible line
    on every repaint, so it must be cheap -- and for the counts a person actually
    sets, a scan over a packed array beats anything with a hash in it. }
  for I := 0 to High(FLines) do
    if FLines[I] = ALine then
      Exit(I);
  Result := -1;
end;

function TBreakpointSet.GetCount: Integer;
begin
  Result := Length(FLines);
end;

function TBreakpointSet.GetLine(AIndex: Integer): Integer;
begin
  Result := FLines[AIndex];
end;

function TBreakpointSet.Has(ALine: Integer): Boolean;
begin
  Result := IndexOf(ALine) >= 0;
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
    for I := Idx to High(FLines) - 1 do
      FLines[I] := FLines[I + 1];
    SetLength(FLines, Length(FLines) - 1);
    Exit(False);
  end;

  Insert := Length(FLines);
  for I := 0 to High(FLines) do
    if FLines[I] > ALine then
    begin
      Insert := I;
      Break;
    end;
  SetLength(FLines, Length(FLines) + 1);
  for I := High(FLines) downto Insert + 1 do
    FLines[I] := FLines[I - 1];
  FLines[Insert] := ALine;
  Result := True;
end;

procedure TBreakpointSet.Clear;
begin
  SetLength(FLines, 0);
end;

procedure TBreakpointSet.TrackEdit(AFirstLine, ADelta: Integer);
var
  I, Keep: Integer;
begin
  if ADelta = 0 then
    Exit;

  Keep := 0;
  for I := 0 to High(FLines) do
  begin
    if FLines[I] < AFirstLine then
    begin
      FLines[Keep] := FLines[I];
      Inc(Keep);
    end
    else if (ADelta < 0) and (FLines[I] < AFirstLine - ADelta) then
    begin
      { Inside the deleted range. Dropped -- see the header. }
    end
    else
    begin
      FLines[Keep] := FLines[I] + ADelta;
      Inc(Keep);
    end;
  end;
  SetLength(FLines, Keep);
end;

function TBreakpointSet.ToArray: TBreakpointLines;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(FLines));
  for I := 0 to High(FLines) do
    Result[I] := FLines[I];
end;

end.
