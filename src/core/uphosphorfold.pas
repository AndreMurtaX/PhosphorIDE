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
  2a. AND A STATEMENT POSITION HAS A LEVEL. An integer is a LABEL where a
     statement may begin at PROGRAM level -- a line's start, or after a `:`
     (`engine/PhosphorCompiler.pas:3004-3013`) -- and a label leaves the
     position open, so `x = 1 : 20 function h()` runs. After `then` or `else`
     the position is a statement's but not the program's, an integer there is an
     expression rather than a label, and `if x > 0 then 20 function f()` is
     refused. This is what the two copies of the rule disagreed about; see the
     paragraph on item 18 below.
  2b. AND THERE IS ONLY ONE NUMERIC LABEL PER POSITION. `10 20 function f()` is
     refused with `expected end of line`, because the compiler records a label
     and then parses a STATEMENT rather than a second label. A NAMED label sits
     on either side of a numeric one quite happily: `10 head: function f()` and
     `head: 10 function f()` both compile. ONE SHAPE IS KNOWINGLY WRONG HERE --
     `10 : 20 function f()` is refused too, because there is no statement before
     that colon for it to separate, and this reads the colon as opening a fresh
     position. Left wrong deliberately: the program does not compile either way,
     so the cost is a row beside a file that is already red, and the alternative
     is state this line does not otherwise need.
  3. `end` merges with an adjacent `if`, `while`, `select` or `function`, and the
     pair is one terminator.
  3a. A TERMINATOR is recognised wherever it appears AT BRACKET DEPTH 0, and an
     OPENER only at a statement position. The asymmetry is deliberate and it is
     what rule 6 rests on: in `for i = 1 to 2 println i next` the `next` follows
     `println i` and is not at a statement position, and a folder that missed it
     would leave the `for` open to the end of the file -- which hides text just
     as surely as opening one that should not have opened. The language makes it
     safe: a terminator word as the TARGET of a statement while its block is
     open is a compile error (`for i = 1 to 2 / next = 5 / ... / next` is
     `expected end of line`), and where its block is not open the caller's stack
     rejects it.

     THE DEPTH IS NOT A DETAIL, and the sentence above said "wherever" until
     2026-09-17 because nobody had tried it: `println max(1, end function)`
     compiles and runs, and so does `y = next + 1` inside the loop. Inside
     brackets a terminator word is an ordinary variable -- a terminator is a
     statement and a statement is not an argument -- and closing a block there
     hid the rest of the file.
  4. An `if` after an `else` is `elseif`: a divider, never an opener.
  5. An `if` opens a block only when a `then` consumed it AND NOTHING FOLLOWS
     that `then` on the line. Anything after it makes the line the inline form.
  6. A block that opens and closes on the SAME line is dropped, both events. It
     folds nothing and there is nothing to hide.

  AND THE WALK ITSELF IS PUBLIC, WHICH IS ROADMAP ITEM 18. `uphosphoroutline`
  used to carry its own copy of all of it -- the statement positions, the `end`
  merge, the string and comment skipping -- and the two had already drifted
  apart: the outline tracked whether a statement position was a PROGRAM-LEVEL
  one, so that an integer after `then` closes it, and this unit did not. The
  cost then was a fold marker on `if x > 0 then 20 function f()`, which the
  compiler refuses, in a file the outline listed no function for.

  That cost was nothing. The cost that was coming is the shape
  `uphosphorcomplete`'s header names at its own `WordAtCaret` -- two questions,
  two functions, ONE set of character rules, because a second copy of them
  somewhere else is a defect waiting -- and which `docs/roadmap.md` item 18
  calls "two scanners that agree until they do not". Phosphor's
  compound-keyword table is a moving part,
  `gen-keywords.py --check` does not extract it, and a change there would have
  been fixed in ONE of the copies. From then on the outline pane and the fold
  gutter would have disagreed about where the same `function` ends, in the same
  window, on the same buffer.

  So `TLineWalk` is the rule and both panes are consumers of it. What they do
  NOT share is what they do with the answer, and that is not an oversight: a
  block that opens and closes on one line folds nothing and is dropped here,
  while `function f(n) return n endfunction` on one line IS a definition and the
  outline must still list it.

  AND THE EXTRACTION WAS MEASURED RATHER THAN ASSERTED, on 2026-09-17, because
  "I only moved it" is the claim every refactor makes. A harness linked the two
  units as they were before the change and as they are after, and ran both over
  4524 inputs -- every block word in every statement position, every spelling of
  every terminator, and the 176 real `.bas` programs in this repository and in
  `../Phosphor`. 920000 field comparisons. On the 176 real programs: NO
  DIFFERENCE, in any field, anywhere. Every remaining difference is on input
  that is illegal or half-typed, in eight classes, and in all eight the answer
  after the change is the better one -- five of them cases where the outline's
  copy and this one had already given different answers to the same question.
  Each is a check in `tests/phosphoridetest.lpr`.

  AND THE MEASUREMENT WAS NOT ENOUGH, which is the part worth carrying. The
  first cut of this walk carried TWO REGRESSIONS ON LEGAL PROGRAMS that the
  harness above ran straight past, because a corpus generated by varying the
  WORDS cannot find a defect about their NEIGHBOURS: `end end function` lost its
  terminator and `end rem a note` walked the comment as code. Both are in rule
  3's paragraph on the pushback, both were found the same day by a review that
  generated adjacency instead, and the corpus that missed them had 4229 cases in
  it. A harness answers "did the answers move"; it does not answer "are the
  inputs the ones that would move them". Generate the shapes, not the tokens.

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

type
  TWalkToken = (wtNone, wtWord, wtNumber, wtString, wtSymbol);

  { ONE LINE, ONE TOKEN AT A TIME, with the two questions every consumer here
    has asked: what is this token, and may a statement begin where it is.

    The record is public in both directions. A consumer that needs to read RAW
    TEXT after a token takes over through `At` and hands back -- the outline
    reads a function's name, its parameter list and its `local` clause that way,
    because none of those is a token this walk has an opinion about. }
  TLineWalk = record
    Line: String;
    Len: Integer;
    At: Integer;               // 1-based, the next byte to look at
    Depth: Integer;            // open ( [ {

    { The token WalkNext just returned. }
    Token: TWalkToken;
    Word: String;              // folded, and MERGED for `end if` / `else if`
    Col: Integer;              // 1-based byte column of its first character
    Size: Integer;             // its length, spanning both words when merged
    { Was THIS token at a statement position, and was that position a
      program-level one? The second is what tells `x = 1 : 20 function h()`,
      which runs, from `if x > 0 then 20 function f()`, which is refused. }
    AtStatement: Boolean;
    AtProgramLevel: Boolean;

    { Where the next token would be. Not a consumer's business, but a record
      has no private part. }
    NextStatement: Boolean;
    NextProgramLevel: Boolean;
    NextLabelOk: Boolean;
  end;

{ Start a line. Nothing is read until WalkNext. }
procedure WalkLine(out AWalk: TLineWalk; const ALine: String);

{ The next token, or False at the end of the line -- which a comment also is,
  because `'` and `rem` run to the end of it and there is nothing after them a
  consumer of this walk would want. }
function WalkNext(var AWalk: TLineWalk): Boolean;

{ Step over whitespace, for a consumer reading raw text after a token. }
procedure WalkSkipSpace(var AWalk: TLineWalk);

{ The identifier at the walk's position, suffix included, or '' -- by the
  scanner's own rule, where one trailing `$ % @ ?` is part of the name. }
function WalkTakeIdent(var AWalk: TLineWalk; out ACol: Integer): String;

{ The text between the parentheses at the walk's position, and how many
  comma-separated things are in it -- commas AT THIS LEVEL and outside strings,
  so `(g(1, 2))` is one. The walk is left past the closing one.

  A LIST THAT DOES NOT CLOSE COUNTS -1, which is "nobody knows" and not "none":
  it ends where the line does, or at a `'`, which opens a comment and so ends
  the line early. }
function WalkTakeParens(var AWalk: TLineWalk; out ACount: Integer): String;

{ What this line does to the block structure, in the order it does it.

  ONE LINE IS ENOUGH STATE for the decisions, which is a property of the
  language and not a simplification -- see rule 1 in the header. The caller
  keeps the stack across lines; this answers only what this line contributes. }
function ScanFoldLine(const ALine: String): TFoldEvents;

{ THE SAME, WITHOUT RULE 6 -- the pairs that open and close on one line are still
  in it.

  Folding drops them because they fold nothing and there is nothing to hide.
  MATCHING wants them: in `for i = 1 to 2 println i next` the `for` and the
  `next` are partners, a person with the caret on one wants to be shown the
  other, and a jump between two words eleven characters apart is as useful as one
  between two lines. So the rule is applied in ONE place, by ScanFoldLine, over
  what this returns. }
function ScanFoldLineRaw(const ALine: String): TFoldEvents;

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

{ ------------------------------------------------------- matching a block --- }

type
  TBlockMatchKind = (
    bmNone,         // the caret is not on a word that opens or closes anything
    bmMatched,      // it is, and the partner is where There* says
    bmUnterminated, // an opener whose block never closes in this buffer
    bmUnopened      // a terminator with nothing open above it to close
  );

  { Where the word under the caret is, and where its partner is. Lines are
    1-based and columns are 1-based BYTE columns -- the same units ScanFoldLine
    reports and the same ones SynEdit's logical caret uses. }
  TBlockMatch = record
    Kind: TBlockMatchKind;
    Block: TPhosphorBlock;
    HereLine, HereCol, HereLen: Integer;
    ThereLine, ThereCol, ThereLen: Integer;
  end;

{ THE PARTNER OF THE BLOCK WORD UNDER THE CARET, or why there is not one.

  ALine and ACol are 1-based; the caret counts as ON a word when it is anywhere
  from its first byte to one past its last, which is how a person reads "the
  caret is on that word" and what every editor's brace matching does.

  NOTHING IS REMEMBERED. The whole buffer is walked on every call, which is what
  makes the answer survive an edit: there is no cached structure to go stale, and
  a Phosphor program is under nine hundred lines (roadmap item 19 measured the
  corpus). A scan of the largest one costs well under a millisecond.

  WHAT IT REFUSES TO ANSWER is the point of it. `next = 5` is a legal assignment,
  and on a line with no `for` open above it that `next` closes nothing --
  bmUnopened, and the caller says so rather than moving the caret somewhere
  arbitrary. `y = function + 1` is not at a statement position, so it opens
  nothing -- bmNone. A block word inside a string or a comment is not a word at
  all -- bmNone. Those three are exactly roadmap item 22's done-when. }
function MatchBlockAt(ALines: TStrings; ALine, ACol: Integer): TBlockMatch;

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

{ ------------------------------------------------------------- the walk ---- }

procedure WalkSkipSpace(var AWalk: TLineWalk);
begin
  while (AWalk.At <= AWalk.Len) and (AWalk.Line[AWalk.At] in Space) do
    Inc(AWalk.At);
end;

function WalkTakeIdent(var AWalk: TLineWalk; out ACol: Integer): String;
var
  Start: Integer;
begin
  Result := '';
  ACol := AWalk.At;
  if (AWalk.At > AWalk.Len) or not (AWalk.Line[AWalk.At] in IdentStart) then
    Exit;
  Start := AWalk.At;
  while (AWalk.At <= AWalk.Len) and (AWalk.Line[AWalk.At] in IdentChar) do
    Inc(AWalk.At);
  { THE SUFFIX CAN ONLY BE THE LAST CHARACTER, so it is stepped over once and
    never looked for again: `a$b` is `a$` then `b`, which is what the lexer
    makes of it too. }
  if (AWalk.At <= AWalk.Len) and (AWalk.Line[AWalk.At] in SuffixChar) then
    Inc(AWalk.At);
  Result := Copy(AWalk.Line, Start, AWalk.At - Start);
end;

{ Step over a string literal, the walk sitting on its opening quote. A backslash
  eats whatever follows it, including a quote; a doubled quote closes and
  reopens, which lands in the same place. An unterminated literal ends where the
  line does, because that is where the language ends it too. }
procedure WalkSkipString(var AWalk: TLineWalk);
begin
  Inc(AWalk.At);
  while AWalk.At <= AWalk.Len do
  begin
    if AWalk.Line[AWalk.At] = '\' then
    begin
      { A BACKSLASH AS THE LAST BYTE eats a character that is not there, and a
        Col+Size that runs past the line is a range a consumer cannot paint. }
      Inc(AWalk.At, 2);
      if AWalk.At > AWalk.Len + 1 then
        AWalk.At := AWalk.Len + 1;
    end
    else if AWalk.Line[AWalk.At] = '"' then
    begin
      Inc(AWalk.At);
      Exit;
    end
    else
      Inc(AWalk.At);
  end;
end;

function WalkTakeParens(var AWalk: TLineWalk; out ACount: Integer): String;
var
  Start, D, Commas: Integer;
  Any: Boolean;
begin
  Result := '';
  ACount := -1;
  if (AWalk.At > AWalk.Len) or (AWalk.Line[AWalk.At] <> '(') then
    Exit;
  Inc(AWalk.At);
  Start := AWalk.At;
  D := 1;
  Commas := 0;
  Any := False;
  while (AWalk.At <= AWalk.Len) and (D > 0) do
  begin
    { A comment inside an unclosed list: the line has ended as far as this is
      concerned, and the list did not close. }
    if AWalk.Line[AWalk.At] = '''' then
      Break;
    if AWalk.Line[AWalk.At] = '"' then
    begin
      Any := True;
      WalkSkipString(AWalk);
      Continue;
    end;
    if AWalk.Line[AWalk.At] in ['(', '[', '{'] then
    begin
      Inc(D);
      { A NESTED GROUP IS A THING, so `f([])` passes ONE argument and prints
        what the function returns. Counting only bare words made it none. }
      if D > 1 then
        Any := True;
    end
    else if AWalk.Line[AWalk.At] in [')', ']', '}'] then
      Dec(D)
    { AT THIS LEVEL ONLY. `f(g(1, 2))` is ONE argument, and counting every comma
      in the text would make it two -- which for a go-to-definition that
      resolves by name AND arity is a jump into the wrong function. }
    else if (AWalk.Line[AWalk.At] = ',') and (D = 1) then
      Inc(Commas)
    else if not (AWalk.Line[AWalk.At] in Space) then
      Any := True;
    if D > 0 then
      Inc(AWalk.At);
  end;

  Result := Copy(AWalk.Line, Start, AWalk.At - Start);
  if D > 0 then
  begin
    { NEVER CLOSED. The line is still being typed, and how many arguments it
      will have is genuinely not known -- which is a different answer from
      "none". }
    ACount := -1;
    Exit;
  end;
  Inc(AWalk.At);              // past the ')'
  if Any or (Commas > 0) then
    ACount := Commas + 1
  else
    ACount := 0;
end;

procedure WalkLine(out AWalk: TLineWalk; const ALine: String);
begin
  AWalk.Line := ALine;
  AWalk.Len := Length(ALine);
  AWalk.At := 1;
  AWalk.Depth := 0;
  AWalk.Token := wtNone;
  AWalk.Word := '';
  AWalk.Col := 0;
  AWalk.Size := 0;
  AWalk.AtStatement := False;
  AWalk.AtProgramLevel := False;
  { A LINE STARTS WHERE A STATEMENT MAY BEGIN, and at program level -- which is
    the only place an integer is a label. Nothing is held: the lexer's merge
    needs its two words adjacent in the TOKEN stream, and an end-of-line token
    is between them, so an `end` at the end of one line and an `if` at the start
    of the next are two separate nothings. }
  AWalk.NextStatement := True;
  AWalk.NextProgramLevel := True;
  AWalk.NextLabelOk := True;
end;

{ Hand back a word as the current token and work out where the next one stands. }
procedure WalkEmitWord(var AWalk: TLineWalk; const AWord: String;
  ACol, ASize: Integer; AMerged: Boolean);
begin
  AWalk.Token := wtWord;
  AWalk.Word := AWord;
  AWalk.Col := ACol;
  AWalk.Size := ASize;
  AWalk.AtStatement := AWalk.NextStatement;
  AWalk.AtProgramLevel := AWalk.NextProgramLevel;
  { `then` and `else` open a statement, and NOT a program-level one: an integer
    after either is not a label and the line is refused. A merged token opens
    nothing -- `endif` is a terminator and `elseif` is a divider. }
  AWalk.NextStatement := (not AMerged) and ((AWord = 'then') or (AWord = 'else'));
  AWalk.NextProgramLevel := False;
  AWalk.NextLabelOk := False;
end;

function WalkNext(var AWalk: TLineWalk): Boolean;
var
  W, W2: String;
  Col, Size, Col2: Integer;
  Merged: String;
begin
  Result := False;
  AWalk.Token := wtNone;

  WalkSkipSpace(AWalk);
  if AWalk.At > AWalk.Len then
    Exit;

  { A comment runs to the end of the line, and so there is nothing after it. }
  if AWalk.Line[AWalk.At] = '''' then
    Exit;

  if AWalk.Line[AWalk.At] = '"' then
  begin
    Col := AWalk.At;
    WalkSkipString(AWalk);
    AWalk.Token := wtString;
    AWalk.Word := '';
    AWalk.Col := Col;
    AWalk.Size := AWalk.At - Col;
    AWalk.AtStatement := AWalk.NextStatement;
    AWalk.AtProgramLevel := AWalk.NextProgramLevel;
    AWalk.NextStatement := False;
    AWalk.NextProgramLevel := False;
    Exit(True);
  end;

  if AWalk.Line[AWalk.At] in IdentStart then
  begin
    W := LowerCase(WalkTakeIdent(AWalk, Col));
    Size := AWalk.At - Col;
    if W = 'rem' then
      Exit;

    { THE LEXER'S MERGE PASS, mirrored: `end if` is `endif` and `else if` is
      `elseif`, and both need their two words ADJACENT in the token stream
      (engine/PhosphorLexer.pas:189-224). Reading the second one here is what
      makes that adjacency testable; if it does not merge it is held and handed
      back on the next call, so nothing is lost and nothing is read twice. }
    if (W = 'end') or (W = 'else') then
    begin
      WalkSkipSpace(AWalk);
      if (AWalk.At <= AWalk.Len) and (AWalk.Line[AWalk.At] in IdentStart) then
      begin
        W2 := LowerCase(WalkTakeIdent(AWalk, Col2));
        Merged := '';
        if W = 'end' then
          Merged := MergedWithEnd(W2)
        else if W2 = 'if' then
          Merged := 'elseif';
        if Merged <> '' then
        begin
          WalkEmitWord(AWalk, Merged, Col, AWalk.At - Col, True);
          Exit(True);
        end;
        { IT DID NOT MERGE, SO THE SECOND WORD IS PUT BACK AND READ AGAIN FROM
          SCRATCH -- not handed forward as a token already decided.

          The first cut handed it forward, and that was wrong twice, on legal
          programs, measured 2026-09-17 by a review that generated the shapes
          this unit's own corpus had not:

            end end function   The lexer's merge pass advances by ONE when a
                               pair does not merge (PhosphorLexer.pas:215-219),
                               so it retries at the SECOND `end`, which merges
                               with `function`. A word handed forward gets no
                               lookahead of its own, so the terminator was lost
                               and the fold ran to the end of the file --
                               exactly the failure this unit exists to prevent.

            end rem a note      `rem` is the lexer's own (PhosphorLexer.pas:453-
                               458) and runs to end of line. A word handed
                               forward skipped the `rem` test below, so the
                               COMMENT was walked as code: a `:` in it opened a
                               program-level statement position and a `function`
                               in it was listed in the outline pane.

          Rewinding costs one identifier re-scanned and has neither hole,
          because the second word then arrives by the one path every other word
          takes. }
        AWalk.At := Col2;
      end;
    end;

    WalkEmitWord(AWalk, W, Col, Size, False);
    Exit(True);
  end;

  if AWalk.Line[AWalk.At] in DigitChar then
  begin
    Col := AWalk.At;
    while (AWalk.At <= AWalk.Len) and (AWalk.Line[AWalk.At] in DigitChar) do
      Inc(AWalk.At);
    AWalk.Token := wtNumber;
    AWalk.Word := '';
    AWalk.Col := Col;
    AWalk.Size := AWalk.At - Col;
    AWalk.AtStatement := AWalk.NextStatement;
    AWalk.AtProgramLevel := AWalk.NextProgramLevel;
    { AN INTEGER AT A PROGRAM-LEVEL STATEMENT POSITION IS A LABEL and does not
      close the statement it labels: `10 function h()`,
      `x = 1 : 20 function h()` and `setup: 30 function pick$(a$)` all define a
      function and all compile, while `if x > 0 then 20 function f()` is
      refused. Anywhere else the position is already closed.

      AND THERE IS ONLY ONE OF THEM. `10 20 function f()` is refused with
      `expected end of line`, because the compiler records a label at the top of
      its statement loop and then parses a STATEMENT, not a second label
      (engine/PhosphorCompiler.pas:3004-3013). A named label may still follow --
      `10 head: function f()` compiles, and so does `head: 10 function f()`. }
    AWalk.NextStatement := AWalk.AtStatement and AWalk.AtProgramLevel and
                           AWalk.NextLabelOk;
    AWalk.NextLabelOk := False;
    Exit(True);
  end;

  Col := AWalk.At;
  case AWalk.Line[AWalk.At] of
    '(', '[', '{': Inc(AWalk.Depth);
    ')', ']', '}': if AWalk.Depth > 0 then Dec(AWalk.Depth);
  end;
  Inc(AWalk.At);
  AWalk.Token := wtSymbol;
  AWalk.Word := Copy(AWalk.Line, Col, 1);
  AWalk.Col := Col;
  AWalk.Size := 1;
  AWalk.AtStatement := AWalk.NextStatement;
  AWalk.AtProgramLevel := AWalk.NextProgramLevel;
  { A `:` AT TOP LEVEL SEPARATES STATEMENTS, and it is also what puts the walk
    back at a statement after a label: `head: function a%()` reaches the
    definition through this rule and not through a rule about labels. It opens a
    FRESH position, label included -- `x = 1 : 20 function h()` runs, and so
    does `10 head: function f()`, where the named label's own colon is this
    token. }
  if (AWalk.Word = ':') and (AWalk.Depth = 0) then
  begin
    AWalk.NextStatement := True;
    AWalk.NextProgramLevel := True;
    AWalk.NextLabelOk := True;
  end
  else
  begin
    AWalk.NextStatement := False;
    AWalk.NextProgramLevel := False;
    AWalk.NextLabelOk := False;
  end;
  Result := True;
end;

{ ------------------------------------------------------------- the line ---- }

function ScanFoldLineRaw(const ALine: String): TFoldEvents;
var
  W: TLineWalk;
  N: Integer;
  IfCol, IfLen: Integer;
  IfSeen, ThenSeen: Boolean;
  Blk: TPhosphorBlock;

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
  IfSeen := False;
  ThenSeen := False;
  IfCol := 0;
  IfLen := 0;

  WalkLine(W, ALine);
  while WalkNext(W) do
  begin
    if W.Token <> wtWord then
    begin
      CancelPendingIf;
      Continue;
    end;

    { A TERMINATOR ANYWHERE -- rule 3a. }
    Blk := BlockClosedBy(W.Word);
    if (Blk <> pbNone) and (W.Depth = 0) then
    begin
      Emit(feClose, Blk, W.Col, W.Size);
      CancelPendingIf;
      Continue;
    end;

    { --- rule 5: the `then` that makes an `if` a block -------------------- }
    if IfSeen and (not ThenSeen) and (W.Word = 'then') then
    begin
      ThenSeen := True;
      Continue;
    end;
    CancelPendingIf;

    if W.AtStatement then
    begin
      Blk := BlockOpenedBy(W.Word);
      if Blk = pbIf then
      begin
        { Held back until the end of the line -- rule 5. }
        IfSeen := True;
        ThenSeen := False;
        IfCol := W.Col;
        IfLen := W.Size;
      end
      else if Blk <> pbNone then
        Emit(feOpen, Blk, W.Col, W.Size);
    end;
  end;

  { --- rule 5, decided now that the line has ended ------------------------- }
  if IfSeen and ThenSeen then
    Emit(feOpen, pbIf, IfCol, IfLen);

end;

function ScanFoldLine(const ALine: String): TFoldEvents;
var
  I, J, N: Integer;
  Keep: array of Boolean;
  Stack: array of Integer;
begin
  Result := ScanFoldLineRaw(ALine);

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

function MatchBlockAt(ALines: TStrings; ALine, ACol: Integer): TBlockMatch;
type
  { Every event in the buffer, flattened, with the index of its partner or -1. }
  TNode = record
    Line, Col, Len: Integer;
    Kind: TFoldEventKind;
    Block: TPhosphorBlock;
    Partner: Integer;
  end;
var
  Nodes: array of TNode;
  Stack: array of Integer;
  Ev: TFoldEvents;
  L, I, J, N, Here: Integer;
begin
  Result := Default(TBlockMatch);
  Result.Kind := bmNone;
  Result.Block := pbNone;
  if (ALines = nil) or (ALine < 1) or (ALine > ALines.Count) then
    Exit;

  { --- every event in the buffer, in order -------------------------------- }
  { RAW, so that a block opened and closed on one line still has a partner --
    ScanFoldLine drops those because they fold nothing, and a person with the
    caret on the `for` of `for i = 1 to 2 println i next` still wants the
    `next`. }
  Nodes := nil;
  for L := 1 to ALines.Count do
  begin
    Ev := ScanFoldLineRaw(ALines[L - 1]);
    for I := 0 to High(Ev) do
    begin
      N := Length(Nodes);
      SetLength(Nodes, N + 1);
      Nodes[N].Line := L;
      Nodes[N].Col := Ev[I].Col;
      Nodes[N].Len := Ev[I].Len;
      Nodes[N].Kind := Ev[I].Kind;
      Nodes[N].Block := Ev[I].Block;
      Nodes[N].Partner := -1;
    end;
  end;
  if Length(Nodes) = 0 then
    Exit;

  { --- pair them, by the same rule the fold gutter uses -------------------- }
  { A terminator closes the innermost open block ONLY when it is the same kind.
    That is what keeps `next = 5` from closing a `while`, and it is the rule
    `DrainFoldEvents` already applies in the highlighter: a close whose kind does
    not match the top of the stack closes nothing at all. }
  Stack := nil;
  for I := 0 to High(Nodes) do
  begin
    if Nodes[I].Kind = feOpen then
    begin
      SetLength(Stack, Length(Stack) + 1);
      Stack[High(Stack)] := I;
    end
    else if (Length(Stack) > 0) and
            (Nodes[Stack[High(Stack)]].Block = Nodes[I].Block) then
    begin
      J := Stack[High(Stack)];
      Nodes[J].Partner := I;
      Nodes[I].Partner := J;
      SetLength(Stack, Length(Stack) - 1);
    end;
  end;

  { --- which event is under the caret ------------------------------------- }
  { ON the word means anywhere from its first byte to one past its last, which
    is how a person reads it and what every editor's brace matching does. The
    events of a line arrive in column order, so the first hit is the answer. }
  Here := -1;
  for I := 0 to High(Nodes) do
    if (Nodes[I].Line = ALine) and (ACol >= Nodes[I].Col) and
       (ACol <= Nodes[I].Col + Nodes[I].Len) then
    begin
      Here := I;
      Break;
    end;
  if Here < 0 then
    Exit;

  Result.Block := Nodes[Here].Block;
  Result.HereLine := Nodes[Here].Line;
  Result.HereCol := Nodes[Here].Col;
  Result.HereLen := Nodes[Here].Len;

  if Nodes[Here].Partner >= 0 then
  begin
    J := Nodes[Here].Partner;
    Result.Kind := bmMatched;
    Result.ThereLine := Nodes[J].Line;
    Result.ThereCol := Nodes[J].Col;
    Result.ThereLen := Nodes[J].Len;
  end
  else if Nodes[Here].Kind = feOpen then
    Result.Kind := bmUnterminated
  else
    Result.Kind := bmUnopened;
end;

end.
