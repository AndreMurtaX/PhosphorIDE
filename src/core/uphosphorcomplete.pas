unit uphosphorcomplete;

{ What to offer at the caret, and when not to offer anything.

  NO LCL IN HERE, ON PURPOSE. Everything below is a decision about a string and a
  column, and `tests/phosphoridetest.lpr` pins every one of them without a window
  -- the same reason `ubreakpoints` is its own unit. The popup, the shortcut and
  the painting are the form's business; the RULES are this unit's, because a rule
  that can only be checked by looking at a list box is a rule nobody checks.

  THE PREFIX IS SCANNED BY THE HIGHLIGHTER'S RULE, NOT BY A LOOSER ONE. A type
  suffix is part of the name -- `left$` is one word, never `left` followed by an
  operator (engine/PhosphorLexer.pas:389-392, and usynphosphor's own IdentChar /
  SuffixChar sets). Get that wrong and typing `lef`, then accepting `left$`,
  inserts a second `$`: the editor replaced three characters and wrote four.

  COMPLETION DOES NOT FIRE INSIDE A STRING OR A COMMENT, and both are decidable
  from the current line alone. That is not a simplification, it is a property of
  the language: `'` and `rem` run to end of line, nothing else starts a comment,
  and a string that reaches a newline is the hard error `unterminated string`
  rather than a continuation (engine/PhosphorLexer.pas:361-366). It is the same
  property that lets usynphosphor have no range state at all.

  NOTHING HERE IS INFERRED FROM A COLOUR. usynphosphor:24-31 records that the
  highlighter colours keywords by WORD and not by position, deliberately and
  wrongly -- `next = 5` is a legal assignment in Phosphor -- and says that nothing
  downstream may be built on "a coloured keyword IS a keyword". Completion is
  downstream, so it reads the generated word lists directly and never asks the
  highlighter what it painted.

  THE TIERS ARE NOT DECORATION. Core is always there. A package name exists only
  because the console host links every package, and another host need not. A GUI
  name exists only where a graphical session was reachable when the program
  started. Offering `form@` with the same weight as `println` invites a program
  that runs on its author's desktop and fails on a server, so the tier is carried
  on every row and a caller may cut the list at one.

  MIT License. Copyright (c) 2026 Andre Murta.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uphosphorlang;

type
  { What a candidate is, which decides both its badge and, where two lists hold
    the same word, which one wins. The order matches usynphosphor.ScanIdentifier
    exactly, so the badge in the popup and the colour in the text agree. }
  TCompletionKind = (
    ckOperatorWord,     // and, or, not, mod
    ckLiteral,          // true, false, null
    ckKeyword,          // if, while, print, ...
    ckBuiltinCore,      // always available
    ckBuiltinPackage,   // only where the host links the package
    ckBuiltinGui        // only where a graphical session was reachable
  );

  TCompletionItem = record
    Word: String;           // lower case, suffix included
    Kind: TCompletionKind;
  end;
  TCompletionItems = array of TCompletionItem;

{ The word the caret is inside or immediately after, by the highlighter's rule.

  ACol is 1-based and names the position the caret sits BEFORE, which is what
  SynEdit's CaretX is: with the caret at the end of `lef`, ACol is 4. Answers ''
  when there is no name there, and then AStart is ACol.

  A name that begins with a digit is not a name -- `123` is a number and `1abc`
  is a number followed by one -- so the body's first character is checked against
  the same IdentStart set the scanner uses. }
function PrefixAtCaret(const ALine: String; ACol: Integer;
  out AStart: Integer): String;

{ Is the caret inside a string literal or a comment, judged from this line only?
  See the unit header for why one line is enough. An unterminated literal counts:
  the program will not compile, and offering `println` in the middle of it helps
  nobody. }
function InLiteralOrComment(const ALine: String; ACol: Integer): Boolean;

{ Every name that begins with APrefix at or below AMaxTier, sorted by word and
  de-duplicated. An empty prefix is everything. The comparison is
  case-insensitive because Phosphor lowercases every identifier as it is scanned
  (engine/PhosphorLexer.pas:392): `PrintLn` and `println` are one word. }
function CompletionCandidates(const APrefix: String;
  AMaxTier: TPhosphorTier): TCompletionItems;

{ The word to INSERT for a candidate, given what the user actually typed.

  CASE-PRESERVING: the tables are lower case because the lexer is, but the file
  belongs to whoever is typing in it. `PRIN` + `println` gives `PRINTLN`, `Prin`
  gives `Println`, and anything else -- including plain `prin` -- gives the
  table's own spelling. Three rules rather than a general one, because a general
  one would have to guess at `pRiN`. }
function CompletionInsertion(const ATyped, ACandidate: String): String;

{ A short badge for the popup's second column. }
function CompletionKindName(AKind: TCompletionKind): String;

implementation

const
  IdentStart = ['A'..'Z', 'a'..'z', '_'];
  IdentChar = ['A'..'Z', 'a'..'z', '0'..'9', '_'];
  SuffixChar = ['$', '%', '@', '?'];

function CompletionKindName(AKind: TCompletionKind): String;
begin
  case AKind of
    ckOperatorWord: Result := 'operator';
    ckLiteral: Result := 'literal';
    ckKeyword: Result := 'keyword';
    ckBuiltinCore: Result := 'core';
    ckBuiltinPackage: Result := 'package';
  else
    Result := 'gui';
  end;
end;

function PrefixAtCaret(const ALine: String; ACol: Integer;
  out AStart: Integer): String;
var
  Last, I, BodyEnd, BodyStart: Integer;
begin
  Result := '';
  AStart := ACol;
  if (ACol < 2) or (ACol > Length(ALine) + 1) then
    Exit;

  Last := ACol - 1;
  I := Last;
  { THE SUFFIX CAN ONLY BE THE LAST CHARACTER, so it is stepped over once and
    never looked for again: `a$b` is `a$` then `b`, two words, which is what the
    scanner makes of it too. }
  if ALine[I] in SuffixChar then
    Dec(I);
  BodyEnd := I;

  while (I >= 1) and (ALine[I] in IdentChar) do
    Dec(I);
  BodyStart := I + 1;

  if BodyStart > BodyEnd then
    Exit;
  if not (ALine[BodyStart] in IdentStart) then
    Exit;

  AStart := BodyStart;
  Result := Copy(ALine, BodyStart, Last - BodyStart + 1);
end;

function InLiteralOrComment(const ALine: String; ACol: Integer): Boolean;
var
  I, Start, Len: Integer;
  InStr: Boolean;
  Word: String;
begin
  Result := False;
  InStr := False;
  Len := Length(ALine);
  I := 1;
  { Only what is STRICTLY BEFORE the caret decides. A caret sitting on the
    opening quote is not in the string yet; one character further in, it is. }
  while (I < ACol) and (I <= Len) do
  begin
    if InStr then
    begin
      { A BACKSLASH EATS THE NEXT CHARACTER WHATEVER IT IS, including a quote --
        that is the rule the highlighter paints a bad escape by, and skipping it
        here is what stops `"a\""` from reading as a closed literal. }
      if ALine[I] = '\' then
        Inc(I)
      else if ALine[I] = '"' then
        InStr := False;
      Inc(I);
    end
    else if ALine[I] = '"' then
    begin
      InStr := True;
      Inc(I);
    end
    else if ALine[I] = '''' then
      { To end of line, and there is no way back. }
      Exit(True)
    else if ALine[I] in IdentStart then
    begin
      Start := I;
      while (I <= Len) and (ALine[I] in IdentChar) do
        Inc(I);
      if (I <= Len) and (ALine[I] in SuffixChar) then
        Inc(I);
      { `rem` is the LEXER's, not the parser's: it swallows the rest of the line
        the moment it sees it, and `remark` is an ordinary identifier
        (engine/PhosphorLexer.pas:393-398). Scanning the whole word rather than
        matching three characters is the difference. }
      Word := LowerCase(Copy(ALine, Start, I - Start));
      if Word = 'rem' then
        Exit(True);
    end
    else
      Inc(I);
  end;
  Result := InStr;
end;

{ ---------------------------------------------------------- the candidates - }

procedure AddList(var AItems: TCompletionItems; var ACount: Integer;
  const AWords: TPhosphorWordList; AKind: TCompletionKind;
  const APrefix: String);
var
  I, N: Integer;
begin
  N := Length(APrefix);
  for I := 0 to High(AWords) do
  begin
    { The lists are lower case already and APrefix arrives lowered, so this is a
      plain compare rather than a case-insensitive one -- and a plain compare is
      what keeps a 1198-name scan from being noticeable. }
    if (N > 0) and (Copy(AWords[I], 1, N) <> APrefix) then
      Continue;
    if ACount = Length(AItems) then
      SetLength(AItems, Length(AItems) * 2 + 32);
    AItems[ACount].Word := AWords[I];
    AItems[ACount].Kind := AKind;
    Inc(ACount);
  end;
end;

function CompletionCandidates(const APrefix: String;
  AMaxTier: TPhosphorTier): TCompletionItems;
var
  Items: TCompletionItems;
  Count, I, J: Integer;
  Pref: String;
  Tmp: TCompletionItem;
begin
  Pref := LowerCase(APrefix);
  Items := nil;
  Count := 0;

  { In the precedence usynphosphor.ScanIdentifier uses, so that when two lists
    hold one word the badge agrees with the colour. }
  AddList(Items, Count, PhosphorOperatorWords, ckOperatorWord, Pref);
  AddList(Items, Count, PhosphorLiteralWords, ckLiteral, Pref);
  AddList(Items, Count, PhosphorKeywords, ckKeyword, Pref);
  AddList(Items, Count, PhosphorBuiltins(ptCore), ckBuiltinCore, Pref);
  if AMaxTier >= ptPackage then
    AddList(Items, Count, PhosphorBuiltins(ptPackage), ckBuiltinPackage, Pref);
  if AMaxTier >= ptGui then
    AddList(Items, Count, PhosphorBuiltins(ptGui), ckBuiltinGui, Pref);
  SetLength(Items, Count);

  { Insertion sort by word. Each source list is already sorted, so this is close
    to its best case, and the whole array is at most 1198 rows on an empty
    prefix -- which is the one case a person never sees, because they pressed
    Ctrl+Space having typed something. }
  for I := 1 to High(Items) do
  begin
    Tmp := Items[I];
    J := I - 1;
    while (J >= 0) and (Items[J].Word > Tmp.Word) do
    begin
      Items[J + 1] := Items[J];
      Dec(J);
    end;
    Items[J + 1] := Tmp;
  end;

  { De-duplicate, keeping the FIRST of an equal run -- which after a stable sort
    is the one the precedence above put first. }
  Count := 0;
  for I := 0 to High(Items) do
    if (Count = 0) or (Items[Count - 1].Word <> Items[I].Word) then
    begin
      Items[Count] := Items[I];
      Inc(Count);
    end;
  SetLength(Items, Count);
  Result := Items;
end;

function CompletionInsertion(const ATyped, ACandidate: String): String;
var
  I: Integer;
  AllUpper: Boolean;
begin
  Result := ACandidate;
  if ATyped = '' then
    Exit;

  AllUpper := True;
  for I := 1 to Length(ATyped) do
    if ATyped[I] in ['a'..'z'] then
    begin
      AllUpper := False;
      Break;
    end;
  { ALL CAPS ONLY COUNTS IF THERE WAS A LETTER TO CAPITALISE. `x$` has none, and
    answering PRINTLN to it would be reading a shout into punctuation. }
  if AllUpper then
  begin
    for I := 1 to Length(ATyped) do
      if ATyped[I] in ['A'..'Z'] then
        Exit(UpperCase(ACandidate));
    Exit;
  end;

  if (ATyped[1] in ['A'..'Z']) then
    Result := UpperCase(Copy(ACandidate, 1, 1)) + Copy(ACandidate, 2, MaxInt);
end;

end.
