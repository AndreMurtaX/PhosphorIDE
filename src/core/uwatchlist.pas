unit uwatchlist;

{ The expressions a person is watching, and what the host last said about each.

  IT IS A UNIT OF ITS OWN, with no LCL in it, for the same reason `ubreakpoints`
  and `uphosphorcomplete` are: every decision it makes is about a string and a
  state, and `tests/phosphoridetest.lpr` can exercise all of them without a
  window. The pane is a TListView somewhere else.

  THE RULE ROADMAP ITEM 26 ASKS FOR IS THE WHOLE POINT OF THE STATE FIELD: a
  watch "says plainly when one cannot be evaluated rather than showing a stale
  value". A value and an error are therefore not two strings that a reader has to
  know which of to believe -- they are one state with three cases, and the case
  is what the pane renders:

    wsUnknown  nothing has been asked yet, or the program is not standing still.
               The EXPRESSION survives, the value does not.
    wsValue    the host answered. Value and Kind are the host's own rendering.
    wsError    the host refused, and Error is its sentence.

  A value that is merely OLD is the defect this exists to prevent, and old is
  indistinguishable from current by looking at it. So `Invalidate` empties every
  answer the moment the program moves, and the pane shows a blank rather than the
  number from the last stop. A watch pane that lies once is a watch pane nobody
  can use, because there is no way to tell which reading was the lie.

  AN ID, NOT A ROW. The `evaluate` reply carries the value and nothing else --
  not the expression, not the frame -- so the editor has to remember which
  question it is the answer to. A ROW INDEX WOULD BE THE WRONG HANDLE: a person
  can delete a watch while its answer is in flight, and the row that slides up
  would then be shown a value it never asked for. Ids are handed out from a
  counter and never reused, so a late answer for a deleted watch finds nothing
  and is dropped, which is the correct outcome. }

{$mode objfpc}{$H+}

interface

type
  TWatchState = (wsUnknown, wsValue, wsError);

  TWatchItem = record
    Id: Integer;
    Expr: String;
    Value: String;      // the host's own rendering; never formatted here
    Kind: String;       // 'number' | 'int' | 'string' | 'bool' | 'handle'
    Error: String;      // the host's own sentence
    State: TWatchState;
  end;
  TWatchItems = array of TWatchItem;

  TWatchList = class
  private
    FItems: TWatchItems;
    FNextId: Integer;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TWatchItem;
  public
    constructor Create;

    { Add an expression and answer its new id, or 0 when it was not added.

      A DUPLICATE IS NOT ADDED and is not an error: two rows asking the same
      question would answer the same thing for ever and the second is a row the
      person has to read past. An empty expression is refused for the same kind
      of reason -- there is nothing to evaluate and a blank row is a hole in the
      pane, not a watch. Both answer 0, and the caller decides whether that was
      worth saying out loud. }
    function Add(const AExpr: String): Integer;

    procedure RemoveAt(AIndex: Integer);
    procedure Clear;

    { Where an id is now, or -1. }
    function IndexOfId(AId: Integer): Integer;

    { The host answered. Silently ignored when the id is gone, which is the
      ordinary end of a watch deleted while its answer was in flight. }
    procedure SetValue(AId: Integer; const AValue, AKind: String);
    procedure SetError(AId: Integer; const AError: String);

    { EVERY ANSWER IS FORGOTTEN AND EVERY EXPRESSION IS KEPT. Called whenever the
      program is not standing still: what was true at the last stop is not known
      to be true now, and showing it anyway is the one thing a watch pane must
      never do. }
    procedure Invalidate;

    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TWatchItem read GetItem; default;
  end;

implementation

uses
  SysUtils;

constructor TWatchList.Create;
begin
  inherited Create;
  FNextId := 0;
end;

function TWatchList.GetCount: Integer;
begin
  Result := Length(FItems);
end;

function TWatchList.GetItem(AIndex: Integer): TWatchItem;
begin
  Result := FItems[AIndex];
end;

function TWatchList.Add(const AExpr: String): Integer;
var
  E: String;
  I: Integer;
begin
  Result := 0;
  E := Trim(AExpr);
  if E = '' then
    Exit;
  for I := 0 to High(FItems) do
    if FItems[I].Expr = E then
      Exit;
  Inc(FNextId);
  SetLength(FItems, Length(FItems) + 1);
  FItems[High(FItems)].Id := FNextId;
  FItems[High(FItems)].Expr := E;
  FItems[High(FItems)].Value := '';
  FItems[High(FItems)].Kind := '';
  FItems[High(FItems)].Error := '';
  FItems[High(FItems)].State := wsUnknown;
  Result := FNextId;
end;

procedure TWatchList.RemoveAt(AIndex: Integer);
var
  I: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FItems)) then
    Exit;
  for I := AIndex to High(FItems) - 1 do
    FItems[I] := FItems[I + 1];
  SetLength(FItems, Length(FItems) - 1);
end;

procedure TWatchList.Clear;
begin
  SetLength(FItems, 0);
end;

function TWatchList.IndexOfId(AId: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  if AId <= 0 then
    Exit;
  for I := 0 to High(FItems) do
    if FItems[I].Id = AId then
      Exit(I);
end;

procedure TWatchList.SetValue(AId: Integer; const AValue, AKind: String);
var
  I: Integer;
begin
  I := IndexOfId(AId);
  if I < 0 then
    Exit;
  FItems[I].Value := AValue;
  FItems[I].Kind := AKind;
  FItems[I].Error := '';
  FItems[I].State := wsValue;
end;

procedure TWatchList.SetError(AId: Integer; const AError: String);
var
  I: Integer;
begin
  I := IndexOfId(AId);
  if I < 0 then
    Exit;
  { THE VALUE IS CLEARED, not left beside the error. A row showing both is a row
    a reader has to guess about, and the guess they will make is the wrong one:
    the number is easier to read than the sentence. }
  FItems[I].Value := '';
  FItems[I].Kind := '';
  FItems[I].Error := AError;
  FItems[I].State := wsError;
end;

procedure TWatchList.Invalidate;
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
  begin
    FItems[I].Value := '';
    FItems[I].Kind := '';
    FItems[I].Error := '';
    FItems[I].State := wsUnknown;
  end;
end;

end.
