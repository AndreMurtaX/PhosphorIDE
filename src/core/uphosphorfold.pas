unit uphosphorfold;

{ Where a Phosphor block opens and where it closes, decided a LINE at a time.

  NO LCL IN HERE, like every other unit under `core/`: everything below is a
  decision about a line of text, and `tests/phosphoridetest.lpr` pins all of them
  without a window. The highlighter is the adapter; this is the rule.

  WHY THIS UNIT EXISTS AT ALL, and it is the whole of roadmap item 17's warning.
  `usynphosphor.pas:24-31` records that Phosphor decides keywords by POSITION --
  the lexer has no keyword table, every keyword reaches the parser as an ordinary
  identifier (`engine/PhosphorLexer.pas:444-470`), and `next = 5` is a legal
  assignment. It says in as many words that nothing downstream may assume a
  coloured keyword IS a keyword. A fold engine built on the colouring would
  therefore mis-fold a legal program, and the failure mode of a mis-fold is TEXT
  HIDDEN FROM THE USER, which is worse than a wrong colour.

  AND WHY IT IS A LINE AND NOT A TOKEN. The first version of this unit answered
  one token at a time, and six legal Phosphor programs were then compiled that it
  would have folded wrongly -- every one of them hiding code below the fold. They
  are the reason for every rule here, and each is pinned as a check:

    for i = 1 to 2 println i next     A WHOLE BLOCK ON ONE LINE, no colon. Legal,
    function f(n) return n+1 endfunction   prints its answers, and six of the
    while i < 2 i = i + 1 wend         seven kinds do it. An opener that fires
                                       without looking at the rest of the line
                                       opens a fold that never closes, and
                                       collapsing it hides the file below.
                                       (The COLON form `for i = 1 to 3 : println
                                       i : next` is refused, which is what made
                                       the first version look safe.)

    if x = 1 then println then         `then` IS A LEGAL VARIABLE. The line ends
                                       with the word `then` and is an inline
                                       `if` that takes no endif. "the last token
                                       is then" opens a fold that never closes.

    else if n = 2 then ... endif       `else if` is ONE token to the lexer
                                       (`engine/PhosphorLexer.pas:207-209`), so
                                       this needs exactly ONE endif. Treating the
                                       `if` as an opener leaves the first one
                                       unclosed.

    if n = 1 then / ... / end if       THE TWO-WORD TERMINATOR is at the
                                       statement position the `end` had, not the
                                       one after it. Judging it at the `if` drops
                                       the close.

  THE RULES, then, in the order they matter:

  1. Strings and comments are stripped first. `'` and `rem` run to end of line and
     a string that reaches one is the hard error `unterminated string`
     (`engine/PhosphorLexer.pas:420-435`), which is why ONE LINE is enough state.
  2. A word counts only where a statement may begin: the line's start, after a
     `:` at bracket depth 0, after `then`, after `else`.
  3. `end` merges with an adjacent `if`, `while`, `select` or `function`, and the
     pair is one terminator.
  3a. A TERMINATOR is recognised wherever it appears, and an OPENER only at a
     statement position. The asymmetry is deliberate and it is what rule 6 rests
     on: in `for i = 1 to 2 println i next` the `next` follows `println i` and is
     not at a statement position, and a folder that missed it would leave the
     `for` open to the end of the file -- which hides text just as surely as
     opening one that should not have opened. The language makes it safe: a
     terminator word used as a VARIABLE while its block is open is a compile
     error (`for i = 1 to 2 / next = 5 / ... / next` is `expected end of line`),
     and where its block is not open the caller's stack rejects it.
  4. An `if` after an `else` is `elseif`: a divider, never an opener.
  5. An `if` opens a block only when a `then` consumed it AND NOTHING FOLLOWS
     that `then` on the line. Anything after it makes the line the inline form.
  6. A block that opens and closes on the SAME line is dropped, both events. It
     folds nothing and there is nothing to hide.

  WHAT IS DELIBERATELY NOT DECIDED HERE. `select`'s ARMS are not folded: `case`
  is a legal assignment target wherever a select is not the innermost block, so
  an arm divider would need the fold stack, which lives in the caller. And
  nothing here decides what the gutter draws or what happens to a fold when the
  text under it is edited -- those are SynEdit's.

  MIT License. Copyright (c) 2026 Andre Murta.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { The seven kinds, plus none. The roadmap names five; `do while ... loop` and
    `repeat ... until` are blocks too, both measured. }
  TPhosphorBlock = (
    pbIf,         // if <cond> then <end of line> ... endif / end if
    pbFor,        // for ... next
    pbWhile,      // while ... wend / endwhile / end while
    pbDo,         // do while ... loop
    pbRepeat,     // repeat ... until
    pbSelect,     // select case ... endselect / end select
    pbFunction,   // function ... endfunction / end function
    { LAST, AND NOT FIRST, which is a fact about SynEdit rather than about
      Phosphor. A fold highlighter's configurable block types must occupy the
      ordinals 0..FoldConfigCount-1 (synedithighlighterfoldbase.pas:2014-2022),
      and the "no block" value is the root's type -- an internal one. Putting it
      first would shift every real kind by one and silently drop the last of
      them out of the configuration array. }
    pbNone
  );

  TFoldEventKind = (feOpen, feClose);

  TFoldEvent = record
    Kind: TFoldEventKind;
    Block: TPhosphorBlock;
    { 1-based BYTE column of the word that justifies the event, and its length.
      The caller hangs a fold node on exactly that token, so a node can carry
      real bounds rather than a zero-width point at the end of the line. }
    Col: Integer;
    Len: Integer;
  end;
  TFoldEvents = array of TFoldEvent;

{ What this line does to the block structure, in the order it does it.

  ONE LINE IS ENOUGH STATE for the decisions, which is a property of the
  language and not a simplification -- see rule 1 in the header. The caller
  keeps the stack across lines; this answers only what this line contributes. }
function ScanFoldLine(const ALine: String): TFoldEvents;

{ Which block this word opens, or pbNone. `if` is answered here for the tables'
  sake; ScanFoldLine is what decides whether a particular `if` really opens. }
function BlockOpenedBy(const AWord: String): TPhosphorBlock;

{ Which block this word closes, or pbNone. }
function BlockClosedBy(const AWord: String): TPhosphorBlock;

{ The single word `end` merges with, or '' -- `end if` is `endif`, and the two
  must be ADJACENT in the token stream (engine/PhosphorLexer.pas:189-224). }
function MergedWithEnd(const AWord: String): String;

{ A name for a message and for a check. }
function BlockName(ABlock: TPhosphorBlock): String;

implementation

const
  IdentStart = ['A'..'Z', 'a'..'z', '_'];
  IdentChar = ['A'..'Z', 'a'..'z', '0'..'9', '_'];
  SuffixChar = ['$', '%', '@', '?'];
  DigitChar = ['0'..'9'];
  Space = [' ', #9, #13];

function BlockOpenedBy(const AWord: String): TPhosphorBlock;
begin
  if AWord = 'if' then
    Result := pbIf
  else if AWord = 'for' then
    Result := pbFor
  else if AWord = 'while' then
    Result := pbWhile
  else if AWord = 'do' then
    Result := pbDo
  else if AWord = 'repeat' then
    Result := pbRepeat
  else if AWord = 'select' then
    Result := pbSelect
  else if AWord = 'function' then
    Result := pbFunction
  else
    Result := pbNone;
end;

function BlockClosedBy(const AWord: String): TPhosphorBlock;
begin
  if AWord = 'endif' then
    Result := pbIf
  else if AWord = 'next' then
    Result := pbFor
  { BOTH spellings close a while, measured: `wend` and `endwhile` each run, and
    `end while` merges into the second. }
  else if (AWord = 'wend') or (AWord = 'endwhile') then
    Result := pbWhile
  else if AWord = 'loop' then
    Result := pbDo
  else if AWord = 'until' then
    Result := pbRepeat
  else if AWord = 'endselect' then
    Result := pbSelect
  else if AWord = 'endfunction' then
    Result := pbFunction
  else
    Result := pbNone;
end;

function MergedWithEnd(const AWord: String): String;
begin
  { engine/PhosphorLexer.pas:189-224 merges exactly these four. `else if` into
    `elseif` is the fifth and is handled in ScanFoldLine, because it is a
    divider rather than a terminator. }
  if AWord = 'if' then
    Result := 'endif'
  else if AWord = 'while' then
    Result := 'endwhile'
  else if AWord = 'select' then
    Result := 'endselect'
  else if AWord = 'function' then
    Result := 'endfunction'
  else
    Result := '';
end;

function BlockName(ABlock: TPhosphorBlock): String;
begin
  case ABlock of
    pbIf: Result := 'if';
    pbFor: Result := 'for';
    pbWhile: Result := 'while';
    pbDo: Result := 'do';
    pbRepeat: Result := 'repeat';
    pbSelect: Result := 'select';
    pbFunction: Result := 'function';
  else
    Result := '';
  end;
end;

{ ------------------------------------------------------------- the line ---- }

function ScanFoldLine(const ALine: String): TFoldEvents;
var
  At, Len, Depth, I, J, N: Integer;
  AtStatement, PendingElse: Boolean;
  { An `end` that is waiting for the word next to it, and the statement position
    it had -- rule 3: the pair is judged where the `end` was, not where the
    second word is. }
  PendingEnd: Boolean;
  PendingEndCol: Integer;
  { An `if` that a `then` may yet turn into a block -- rule 5. }
  IfCol, IfLen: Integer;
  IfSeen, ThenSeen: Boolean;
  W, Merged: String;
  Start, WordCol, WordLen: Integer;
  Blk: TPhosphorBlock;
  Keep: array of Boolean;
  Stack: array of Integer;

  procedure Emit(AKind: TFoldEventKind; ABlock: TPhosphorBlock;
    ACol, ALen: Integer);
  begin
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N].Kind := AKind;
    Result[N].Block := ABlock;
    Result[N].Col := ACol;
    Result[N].Len := ALen;
  end;

  { Any token that is not the `then` immediately after the pending `if` cancels
    it: the line is the inline form and opens nothing. }
  procedure CancelPendingIf;
  begin
    if ThenSeen then
    begin
      IfSeen := False;
      ThenSeen := False;
    end;
  end;

begin
  Result := nil;
  Len := Length(ALine);
  At := 1;
  Depth := 0;
  AtStatement := True;
  PendingEnd := False;
  PendingElse := False;
  PendingEndCol := 0;
  IfSeen := False;
  ThenSeen := False;
  IfCol := 0;
  IfLen := 0;

  while At <= Len do
  begin
    if ALine[At] in Space then
    begin
      Inc(At);
      Continue;
    end;

    { A comment ends the line, and so does anything after it. }
    if ALine[At] = '''' then
      Break;

    if ALine[At] = '"' then
    begin
      { Step over the literal. A backslash eats whatever follows it, including a
        quote; an unterminated one ends where the line does, because that is
        where the language ends it too. }
      Inc(At);
      while At <= Len do
      begin
        if ALine[At] = '\' then
          Inc(At, 2)
        else if ALine[At] = '"' then
        begin
          Inc(At);
          Break;
        end
        else
          Inc(At);
      end;
      AtStatement := False;
      PendingEnd := False;
      PendingElse := False;
      CancelPendingIf;
      Continue;
    end;

    if ALine[At] in IdentStart then
    begin
      Start := At;
      while (At <= Len) and (ALine[At] in IdentChar) do
        Inc(At);
      if (At <= Len) and (ALine[At] in SuffixChar) then
        Inc(At);
      W := LowerCase(Copy(ALine, Start, At - Start));
      WordCol := Start;
      WordLen := At - Start;

      if W = 'rem' then
        Break;

      { --- rule 3: `end` and the word next to it --------------------------- }
      if PendingEnd then
      begin
        Merged := MergedWithEnd(W);
        PendingEnd := False;
        if Merged <> '' then
        begin
          Emit(feClose, BlockClosedBy(Merged), PendingEndCol,
               WordCol + WordLen - PendingEndCol);
          AtStatement := False;
          PendingElse := False;
          CancelPendingIf;
          Continue;
        end;
      end;

      if W = 'end' then
      begin
        PendingEnd := True;
        PendingEndCol := WordCol;
        AtStatement := False;
        PendingElse := False;
        CancelPendingIf;
        Continue;
      end;

      { --- rule 4: `else if` is one token, and it is a divider -------------- }
      if PendingElse and (W = 'if') then
      begin
        PendingElse := False;
        AtStatement := False;
        CancelPendingIf;
        Continue;
      end;

      { --- rule 5: the `then` that makes an `if` a block -------------------- }
      if IfSeen and (not ThenSeen) and (W = 'then') then
      begin
        ThenSeen := True;
        AtStatement := True;
        PendingElse := False;
        Continue;
      end;
      CancelPendingIf;

      { A TERMINATOR ANYWHERE -- rule 3a. }
      Blk := BlockClosedBy(W);
      if (Blk <> pbNone) and (Depth = 0) then
      begin
        Emit(feClose, Blk, WordCol, WordLen);
        AtStatement := False;
        PendingElse := False;
        Continue;
      end;

      if AtStatement then
      begin
        Blk := BlockOpenedBy(W);
        if Blk = pbIf then
        begin
          { Held back until the end of the line -- rule 5. }
          IfSeen := True;
          ThenSeen := False;
          IfCol := WordCol;
          IfLen := WordLen;
          AtStatement := False;
          PendingElse := False;
          Continue;
        end;
        if Blk <> pbNone then
        begin
          Emit(feOpen, Blk, WordCol, WordLen);
          AtStatement := False;
          PendingElse := False;
          Continue;
        end;
      end;

      { `then` and `else` open a statement. `else` also arms rule 4. }
      AtStatement := (W = 'then') or (W = 'else');
      PendingElse := W = 'else';
      Continue;
    end;

    if ALine[At] in DigitChar then
    begin
      while (At <= Len) and (ALine[At] in DigitChar) do
        Inc(At);
      { A leading integer is a label and does not close the statement it labels;
        anywhere else AtStatement is already False. }
      PendingEnd := False;
      PendingElse := False;
      CancelPendingIf;
      Continue;
    end;

    case ALine[At] of
      '(', '[', '{': Inc(Depth);
      ')', ']', '}': if Depth > 0 then Dec(Depth);
    end;
    if (ALine[At] = ':') and (Depth = 0) then
      AtStatement := True
    else
      AtStatement := False;
    PendingEnd := False;
    PendingElse := False;
    CancelPendingIf;
    Inc(At);
  end;

  { --- rule 5, decided now that the line has ended ------------------------- }
  if IfSeen and ThenSeen then
    Emit(feOpen, pbIf, IfCol, IfLen);

  { --- rule 6: a block that opened and closed here folds nothing ----------- }
  if Length(Result) < 2 then
    Exit;
  SetLength(Keep, Length(Result));
  for I := 0 to High(Keep) do
    Keep[I] := True;
  Stack := nil;
  for I := 0 to High(Result) do
  begin
    if Result[I].Kind = feOpen then
    begin
      SetLength(Stack, Length(Stack) + 1);
      Stack[High(Stack)] := I;
    end
    else if Length(Stack) > 0 then
    begin
      J := Stack[High(Stack)];
      if Result[J].Block = Result[I].Block then
      begin
        { Opened and closed on this line: drop the pair. }
        Keep[J] := False;
        Keep[I] := False;
        SetLength(Stack, Length(Stack) - 1);
      end;
    end;
  end;

  N := 0;
  for I := 0 to High(Result) do
    if Keep[I] then
    begin
      Result[N] := Result[I];
      Inc(N);
    end;
  SetLength(Result, N);
end;

end.
