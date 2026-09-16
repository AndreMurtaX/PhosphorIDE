unit uphosphoroutline;

{ The `function` definitions in a buffer, and where a name is defined.

  NO LCL IN HERE, for the reason `ubreakpoints`, `uphosphorcomplete` and
  `ufindinfiles` have none: every decision below is about characters, columns and
  line numbers, and `tests/phosphoridetest.lpr` pins all of them without a
  window. The pane, the timer and the jump are the form's business.

  THIS IS A SCANNER AND NOT A PARSER, AND THAT IS A TRADE WITH A BILL ATTACHED.
  Phosphor's lexer has no keyword table at all: every keyword reaches the parser
  as an ordinary identifier and is decided by POSITION
  (engine/PhosphorLexer.pas:444-470), so `then = 5` is a legal assignment and
  `function if(a)` is a legal definition of a function called `if` -- both
  measured against the real host on 2026-09-16. A scanner that reads a word and
  concludes "this is the keyword" is therefore wrong about some legal program,
  and nothing can fix that short of being the compiler.

  The trade is the one `usynphosphor` already records for colour, and it is
  acceptable here for the same reason and ONLY for that reason: being wrong costs
  a spurious row in a list, or a jump that goes somewhere unhelpful. So --

      NOTHING IN THIS UNIT MAY BE USED BY ANY CODE PATH THAT CHANGES A BUFFER.

  No reformat, no reindent, no rename. Being wrong about a rare legal program
  may cost a row in a list; it may never cost a character of somebody's file.

  FOLDING IS A THIRD THING AND IT IS NOT DECIDED HERE. It changes no character
  but it HIDES lines, which `docs/roadmap.md` item 17 weighs at length and
  answers "only on a structural scanner, and only because a fold is visible and
  reversible". If that item is ever taken up, this is the scanner it meant --
  and whoever takes it up owes the reader the same paragraph about what it gets
  wrong, in the place where the folding happens.

  WHAT WAS MEASURED RATHER THAN ASSUMED. Every one of these was compiled and run
  against `bin/phosphor.exe` on 2026-09-16, because each one breaks the obvious
  scanner -- the one that takes the first word of a line:

    - `x = 1 : function f()` is legal. A definition begins a STATEMENT, not a
      line (engine/PhosphorCompiler.pas:2359 dispatches it from ParseStatement),
      and `:` is what separates two of them (:3009-3010).
    - `if x > 0 then function f()` and `... else function f()` are legal too, so
      `then` and `else` open a statement as surely as `:` does.
    - `head: function a%() return 1 : end function : function b%() return 2 :
      end function` is ONE legal line holding TWO complete definitions, and it
      runs. A scanner that stops at the first match per line finds half of it.
    - `10 function h()` is legal, and so are `x = 1 : 20 function h()` and
      `setup: 30 function pick$(a$)`: an integer is a label wherever a statement
      may begin AT PROGRAM LEVEL, which the compiler's own comment enumerates as
      a line's start, after a `:`, after a numeric label and after a named one
      (engine/PhosphorCompiler.pas:2939-2948 and the note at :2962-2972). The
      first version of this unit asked the narrower question -- is this the first
      token of the line -- and lost both of those definitions.
      But `if x > 0 then 20 function f()` is REFUSED (`expected end of line`),
      because `then` opens a statement and not a program-level one. That is the
      whole reason this scanner tracks WHY it is at a statement position and not
      merely that it is.
    - `end function`, two words, is the same token as `endfunction` -- the lexer
      merges them, but ONLY when they are adjacent, so an `end` at the end of one
      line and a `function` at the start of the next is not a terminator
      (engine/PhosphorLexer.pas:189-224, verified: it reports the next definition
      as a nested one).
    - `function m%()`, `n?()`, `o@()` and `g$()` are all legal: the type suffix
      is part of the name (engine/PhosphorLexer.pas:448-451) and it is the only
      declaration of a return type the language has.
    - `FUNCTION Upper()` ... `END FUNCTION` is legal: the lexer lowercases every
      identifier as it scans (engine/PhosphorLexer.pas:452). So the name is
      matched folded and shown as the user typed it, because the fold is the
      language's and the spelling is theirs.
    - `rem function ghost()`, `' function ghost()` and `println "function
      ghost()"` define nothing. Comments run to end of line and a string that
      reaches one is a hard error rather than a continuation, which is why a
      LINE AT A TIME is enough state for all of this.

  AND ARITY IS PART OF THE ANSWER, which is the finding that decides what
  FindOutlineFunc takes. `function len(a, b)` beside a call to `len("abcd")`
  does NOT shadow the built-in: the host resolves a call by name AND argument
  count, so that call prints 4 and `len(1, 2)` prints 99. Measured. A go-to
  definition that matches on the name alone therefore sends the caret,
  confidently, into a function the call never reaches.

  WHAT IS DELIBERATELY ABSENT. Labels (`setup:`, `10`) are not collected and
  `gosub`/`goto` targets are not resolved. They are a second table in the
  compiler that never consults the function table, they would need a reserved-
  word test this repository does not extract, and the roadmap item asks about
  functions. An absence that is written down beats a jump that is wrong and
  looks right.

  MIT License. Copyright (c) 2026 Andre Murta.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  { A buffer with more definitions than this is not a program anybody is reading
    an outline of. The bound is here because a buffer is an input. }
  MaxOutlineFuncs = 4096;

type
  TOutlineFunc = record
    { Folded, suffix included -- the form a call is matched against. }
    Name: String;
    { As the user typed it. The fold is the language's; the spelling is theirs,
      and a list that renamed their functions to lower case would be lying about
      their file. }
    Display: String;
    { The text between the parentheses, exactly as written, or '' for none. }
    Params: String;
    { The `local` clause, exactly as written, or '' -- and it is on the HEADER
      line or it does not exist: `local` is read only when it is the token right
      after the closing parenthesis (engine/PhosphorCompiler.pas:634-645), and a
      `local i` on a line of its own is a compile error rather than a
      declaration. It is here so that F12 can tell a function's own parameter
      from a function of the same name somewhere else in the file. }
    Locals: String;
    { How many names are in it: 0 for `()`, and -1 when there is no parameter
      list on the line at all -- which is what `function f` looks like for the
      second it takes to type the rest, and which the compiler refuses. }
    ParamCount: Integer;
    Line: Integer;       // 1-based, the line the `function` word is on
    Column: Integer;     // 1-based BYTE column where the NAME starts
    EndLine: Integer;    // 1-based line of its endfunction, or 0 if unterminated
    Nested: Boolean;     // opened while another was still open
  end;
  TOutlineFuncs = array of TOutlineFunc;

{ Every definition in the buffer, in SOURCE ORDER.

  ALines is the LOGICAL buffer -- `TSynEdit.Lines`, never the viewed one -- for
  the same reason breakpoints and diagnostics are: every line number this editor
  passes around is a logical one. }
function ScanOutline(ALines: TStrings): TOutlineFuncs;

{ The same over one string, splitting on #10 and dropping a trailing #13. It
  exists so that a test fixture is a literal rather than a file. }
function ScanOutlineText(const AText: String): TOutlineFuncs;

{ `twice%(n%)`, `noargs()`, or `half` for a header with no parameter list yet. }
function OutlineRowText(const AFunc: TOutlineFunc): String;

{ The index of the first definition of AName taking AArgCount parameters, or -1.

  FIRST IN SOURCE ORDER, because that is what the host does: it walks its own
  registration table and takes the first match, so a file defining `pick()`
  twice runs the first one and an editor that jumped to the second would be
  pointing at code that never executes.

  AArgCount = -1 means "any arity", and answers the first definition of the name.
  Use it when the call site does not say -- which is most of the time a name is
  merely mentioned rather than called. }
function FindOutlineFunc(const AFuncs: TOutlineFuncs; const AName: String;
  AArgCount: Integer): Integer;

{ How many definitions of AName there are, at any arity. }
function CountOutlineFunc(const AFuncs: TOutlineFuncs; const AName: String): Integer;

{ `1, 2 or 3` -- the arities AName is defined at, for a message that has to say
  why a call did not resolve. '' when there are none. }
function OutlineArities(const AFuncs: TOutlineFuncs; const AName: String): String;

{ Is AName one of AFunc's own parameters or locals?

  It is what tells a name that is a VARIABLE HERE from a function of the same
  name elsewhere in the file. `function g(n)` with a `function n()` further down
  is legal, and inside g the word `n` is the parameter -- so a go-to-definition
  that jumped to `function n()` would be a confident wrong answer about the one
  thing it is supposed to be right about.

  It does NOT decide calls. A parameter shadows a name as a VALUE; a call is
  resolved against the function tables and never against the locals, so `len(s)`
  inside a function whose parameter is called `len` still calls the built-in. }
function IsParamOrLocal(const AFunc: TOutlineFunc; const AName: String): Boolean;

{ The innermost definition whose body contains ALine, or -1. An unterminated
  definition runs to the end of the buffer, which is what it looks like on
  screen. }
function FuncAtLine(const AFuncs: TOutlineFuncs; ALine: Integer): Integer;

{ How many arguments the call whose name ENDS at byte column ANameEnd is being
  passed, counting on this line only.

  ANameEnd is the column just past the last character of the name, which is what
  WordAtCaret's start plus its length gives. Answers -1 when what follows is not
  a call at all, and -1 again when the parentheses do not close on this line --
  and that second one is not a limitation worth removing: a call cannot span
  lines in Phosphor (`println f(1,` then `2)` is `unexpected token in
  expression`, measured), so an unclosed paren means the line is still being
  typed and the arity is genuinely not known yet.

  WHITESPACE BEFORE THE PARENTHESIS IS SKIPPED, and the first version of this did
  not skip it, on a rule the language does not have. `FLex.Peek().Kind = tkLParen`
  (engine/PhosphorCompiler.pas:996) is a test on the TOKEN STREAM, and the lexer
  has already thrown the spaces away: `println f (7)` prints 70. Measured on
  2026-09-16, after a review said so and the host agreed with the review. }
function CallArgCount(const ALine: String; ANameEnd: Integer): Integer;

implementation

const
  IdentStart = ['A'..'Z', 'a'..'z', '_'];
  IdentChar = ['A'..'Z', 'a'..'z', '0'..'9', '_'];
  SuffixChar = ['$', '%', '@', '?'];
  DigitChar = ['0'..'9'];
  Space = [' ', #9, #13];

{ ------------------------------------------------------------ the scanner --- }

type
  { One line's worth of position. A line is all the state this needs, which is a
    property of the language and not a simplification: `'` and `rem` run to end
    of line, and a string literal that reaches one is the error `unterminated
    string` rather than a continuation (engine/PhosphorLexer.pas:420-435). }
  TLineScan = record
    Line: String;
    Pos: Integer;        // 1-based, the next byte to look at
    Len: Integer;
    Depth: Integer;      // open ( [ {
    AtStatement: Boolean;
    { And WHY: a statement that begins a line, or follows a `:`, is at PROGRAM
      LEVEL and may be labelled by an integer; one that follows `then` or `else`
      is not, and `if x > 0 then 20 function f()` is a compile error. Two flags
      because the difference is only ever visible to the digit branch. }
    AtProgramLevel: Boolean;
  end;

{ Step over whitespace. }
procedure SkipSpace(var S: TLineScan);
begin
  while (S.Pos <= S.Len) and (S.Line[S.Pos] in Space) do
    Inc(S.Pos);
end;

{ The identifier starting at S.Pos, suffix included, or '' -- and S.Pos is left
  just past it. The rule is the scanner's and the lexer's: one trailing
  `$ % @ ?` is part of the name and there can only be one, so `a$b` is two
  words. }
function TakeIdent(var S: TLineScan; out AStart: Integer): String;
begin
  Result := '';
  AStart := S.Pos;
  if (S.Pos > S.Len) or not (S.Line[S.Pos] in IdentStart) then
    Exit;
  while (S.Pos <= S.Len) and (S.Line[S.Pos] in IdentChar) do
    Inc(S.Pos);
  if (S.Pos <= S.Len) and (S.Line[S.Pos] in SuffixChar) then
    Inc(S.Pos);
  Result := Copy(S.Line, AStart, S.Pos - AStart);
end;

{ Step over a string literal, S.Pos sitting on its opening quote. A backslash
  eats whatever follows it, including a quote, and a doubled quote closes and
  reopens -- which lands in the same place. An unterminated literal simply ends
  at the end of the line, because that is where the language ends it too. }
procedure SkipString(var S: TLineScan);
begin
  Inc(S.Pos);
  while S.Pos <= S.Len do
  begin
    if S.Line[S.Pos] = '\' then
      Inc(S.Pos, 2)
    else if S.Line[S.Pos] = '"' then
    begin
      Inc(S.Pos);
      Exit;
    end
    else
      Inc(S.Pos);
  end;
end;

{ Take the parameter list, S.Pos on its opening parenthesis. Answers the raw
  text between the parentheses and how many names are in it; S.Pos is left past
  the closing one. An unclosed list ends at the end of the line. }
function TakeParams(var S: TLineScan; out ACount: Integer): String;
var
  Start, D: Integer;
begin
  Inc(S.Pos);
  Start := S.Pos;
  D := 1;
  while (S.Pos <= S.Len) and (D > 0) do
  begin
    if S.Line[S.Pos] = '"' then
    begin
      SkipString(S);
      Continue;
    end;
    if S.Line[S.Pos] in ['(', '[', '{'] then
      Inc(D)
    else if S.Line[S.Pos] in [')', ']', '}'] then
      Dec(D);
    if D > 0 then
      Inc(S.Pos);
  end;
  Result := Copy(S.Line, Start, S.Pos - Start);
  if S.Pos <= S.Len then
    Inc(S.Pos);          // past the ')'

  if Trim(Result) = '' then
    ACount := 0
  else
  begin
    { Commas at the top level of the list. A parameter list holds names and
      nothing else (engine/PhosphorCompiler.pas:601-645), so there is no nesting
      to allow for -- but counting this way costs nothing and does not care. }
    ACount := 1;
    for Start := 1 to Length(Result) do
      if Result[Start] = ',' then
        Inc(ACount);
  end;
end;

procedure AddFunc(var AFuncs: TOutlineFuncs; const AFunc: TOutlineFunc);
var
  N: Integer;
begin
  N := Length(AFuncs);
  if N >= MaxOutlineFuncs then
    Exit;
  SetLength(AFuncs, N + 1);
  AFuncs[N] := AFunc;
end;

function ScanOutline(ALines: TStrings): TOutlineFuncs;
var
  S: TLineScan;
  LineNo, I, NameAt, IdentAt, Open: Integer;
  { W and not Word: Word is a type in this dialect, and a local that shadows one
    compiles and then reads as a mistake to everybody who meets it. }
  W, Nm: String;
  F: TOutlineFunc;
  PendingEnd: Boolean;
begin
  Result := nil;
  if ALines = nil then
    Exit;
  Open := 0;

  for LineNo := 1 to ALines.Count do
  begin
    S.Line := ALines[LineNo - 1];
    S.Len := Length(S.Line);
    S.Pos := 1;
    S.Depth := 0;
    S.AtStatement := True;
    S.AtProgramLevel := True;
    { `end` seen as the previous token, waiting for a `function` NEXT TO IT. The
      lexer's merge pass requires the two to be adjacent in the token stream, so
      this is cleared by any other token and does not survive the line. }
    PendingEnd := False;

    while S.Pos <= S.Len do
    begin
      if S.Line[S.Pos] in Space then
      begin
        Inc(S.Pos);
        Continue;
      end;

      { A comment ends the line, whichever of the two it is. }
      if S.Line[S.Pos] = '''' then
        Break;

      if S.Line[S.Pos] = '"' then
      begin
        SkipString(S);
        S.AtStatement := False;
        PendingEnd := False;
        Continue;
      end;

      if S.Line[S.Pos] in IdentStart then
      begin
        W := LowerCase(TakeIdent(S, IdentAt));

        if W = 'rem' then
          Break;

        { --- a terminator ------------------------------------------------- }
        if (W = 'endfunction') or (PendingEnd and (W = 'function')) then
        begin
          { CLOSES WHEREVER IT APPEARS, not only at a statement position.
            `function a() return 1 : end function` puts it after a complete
            statement, and the word can otherwise only be a function NAME --
            which the header reader below has already eaten -- or a variable
            nobody writes. }
          if Open > 0 then
          begin
            for I := High(Result) downto 0 do
              if Result[I].EndLine = 0 then
              begin
                Result[I].EndLine := LineNo;
                Break;
              end;
            Dec(Open);
          end;
          S.AtStatement := False;
          PendingEnd := False;
          Continue;
        end;

        if W = 'end' then
        begin
          { Not a terminator on its own, and not a statement opener either; it
            is one half of a token that may be completed by the next one. }
          PendingEnd := True;
          S.AtStatement := False;
          Continue;
        end;
        PendingEnd := False;

        { --- a definition ------------------------------------------------- }
        if S.AtStatement and (W = 'function') and (S.Depth = 0) then
        begin
          SkipSpace(S);
          Nm := TakeIdent(S, NameAt);
          if Nm <> '' then
          begin
            F := Default(TOutlineFunc);
            F.Name := LowerCase(Nm);
            F.Display := Nm;
            F.Line := LineNo;
            F.Column := NameAt;
            F.Nested := Open > 0;
            SkipSpace(S);
            if (S.Pos <= S.Len) and (S.Line[S.Pos] = '(') then
            begin
              F.Params := TakeParams(S, F.ParamCount);
              SkipSpace(S);
              if LowerCase(Copy(S.Line, S.Pos, 5)) = 'local' then
              begin
                Inc(S.Pos, 5);
                { To the end of the line, or to the `:` that ends the header's
                  statement. Whatever is here is a list of names. }
                IdentAt := S.Pos;
                while (S.Pos <= S.Len) and (S.Line[S.Pos] <> ':') and
                      (S.Line[S.Pos] <> '''') do
                  Inc(S.Pos);
                F.Locals := Trim(Copy(S.Line, IdentAt, S.Pos - IdentAt));
              end;
            end
            else
              F.ParamCount := -1;
            AddFunc(Result, F);
            Inc(Open);
          end;
          S.AtStatement := False;
          Continue;
        end;

        { --- the words that open a statement ------------------------------ }
        S.AtStatement := (W = 'then') or (W = 'else');
        S.AtProgramLevel := False;
        Continue;
      end;

      if S.Line[S.Pos] in DigitChar then
      begin
        { AN INTEGER AT A PROGRAM-LEVEL STATEMENT POSITION IS A LABEL, so it
          does not close the statement it labels: `10 function h()`,
          `x = 1 : 20 function h()` and `setup: 30 function pick$(a$)` all
          define a function and all compile. After `then` it is not a label and
          the whole line is refused, so the position does not survive there; and
          a number anywhere else is an ordinary token, where AtStatement is
          already False. }
        while (S.Pos <= S.Len) and (S.Line[S.Pos] in DigitChar) do
          Inc(S.Pos);
        S.AtStatement := S.AtStatement and S.AtProgramLevel;
        PendingEnd := False;
        Continue;
      end;

      case S.Line[S.Pos] of
        '(', '[', '{': Inc(S.Depth);
        ')', ']', '}': if S.Depth > 0 then Dec(S.Depth);
      end;
      { A `:` AT TOP LEVEL SEPARATES STATEMENTS, and that is also what puts the
        scanner back at a statement after a label: `head: function a%()` reaches
        the definition through this line and not through a label rule. }
      if (S.Line[S.Pos] = ':') and (S.Depth = 0) then
      begin
        S.AtStatement := True;
        S.AtProgramLevel := True;
      end
      else
        S.AtStatement := False;
      PendingEnd := False;
      Inc(S.Pos);
    end;
  end;
end;

function ScanOutlineText(const AText: String): TOutlineFuncs;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := AText;
    Result := ScanOutline(L);
  finally
    L.Free;
  end;
end;

{ ------------------------------------------------------------- the answers -- }

function OutlineRowText(const AFunc: TOutlineFunc): String;
begin
  if AFunc.ParamCount < 0 then
    Result := AFunc.Display
  else
    Result := AFunc.Display + '(' + Trim(AFunc.Params) + ')';
end;

function FindOutlineFunc(const AFuncs: TOutlineFuncs; const AName: String;
  AArgCount: Integer): Integer;
var
  I: Integer;
  Want: String;
begin
  Result := -1;
  if AName = '' then
    Exit;
  Want := LowerCase(AName);
  for I := 0 to High(AFuncs) do
    if (AFuncs[I].Name = Want) and
       ((AArgCount < 0) or (AFuncs[I].ParamCount = AArgCount)) then
      Exit(I);
end;

function CountOutlineFunc(const AFuncs: TOutlineFuncs; const AName: String): Integer;
var
  I: Integer;
  Want: String;
begin
  Result := 0;
  if AName = '' then
    Exit;
  Want := LowerCase(AName);
  for I := 0 to High(AFuncs) do
    if AFuncs[I].Name = Want then
      Inc(Result);
end;

function OutlineArities(const AFuncs: TOutlineFuncs; const AName: String): String;
var
  I: Integer;
  Want, Each: String;
  Seen: array of Integer;
  J: Integer;
  Known: Boolean;
begin
  Result := '';
  Seen := nil;
  Want := LowerCase(AName);
  for I := 0 to High(AFuncs) do
  begin
    if (AFuncs[I].Name <> Want) or (AFuncs[I].ParamCount < 0) then
      Continue;
    Known := False;
    for J := 0 to High(Seen) do
      if Seen[J] = AFuncs[I].ParamCount then
        Known := True;
    if Known then
      Continue;
    SetLength(Seen, Length(Seen) + 1);
    Seen[High(Seen)] := AFuncs[I].ParamCount;
    Each := IntToStr(AFuncs[I].ParamCount);
    if Result = '' then
      Result := Each
    else
      Result := Result + ', ' + Each;
  end;
  { `1, 2 or 3` rather than `1, 2, 3`, because this goes into a sentence. }
  I := LastDelimiter(',', Result);
  if I > 0 then
    Result := Copy(Result, 1, I - 1) + ' or' + Copy(Result, I + 1, MaxInt);
end;

function IsParamOrLocal(const AFunc: TOutlineFunc; const AName: String): Boolean;
var
  L: TStringList;
  I: Integer;
  Want: String;
begin
  Result := False;
  Want := LowerCase(Trim(AName));
  if (Want = '') or ((AFunc.Params = '') and (AFunc.Locals = '')) then
    Exit;
  L := TStringList.Create;
  try
    L.Delimiter := ',';
    L.StrictDelimiter := True;
    L.DelimitedText := AFunc.Params + ',' + AFunc.Locals;
    for I := 0 to L.Count - 1 do
      if LowerCase(Trim(L[I])) = Want then
        Exit(True);
  finally
    L.Free;
  end;
end;

function FuncAtLine(const AFuncs: TOutlineFuncs; ALine: Integer): Integer;
var
  I, Last: Integer;
begin
  Result := -1;
  for I := 0 to High(AFuncs) do
  begin
    if AFuncs[I].Line > ALine then
      Continue;
    Last := AFuncs[I].EndLine;
    { AN UNTERMINATED DEFINITION RUNS TO THE END, which is what it looks like on
      screen and what the compiler will say about it. }
    if Last = 0 then
      Last := MaxInt;
    if ALine <= Last then
      Result := I;         // the innermost wins: later entries overwrite
  end;
end;

function CallArgCount(const ALine: String; ANameEnd: Integer): Integer;
var
  S: TLineScan;
  D: Integer;
  Any: Boolean;
begin
  Result := -1;
  S.Line := ALine;
  S.Len := Length(ALine);
  S.Pos := ANameEnd;
  if (S.Pos < 1) or (S.Pos > S.Len) then
    Exit;
  { A CALL IS AN IDENTIFIER WHOSE NEXT TOKEN IS `(`, and "token" is the word that
    matters: the lexer has already dropped the whitespace, so `f (7)` is a call
    and prints 70. Measured. The first version of this required the parenthesis
    to be the very next BYTE, which is a rule Phosphor does not have and which
    cost the arity of every call written with a space. }
  while (S.Pos <= S.Len) and (S.Line[S.Pos] in Space) do
    Inc(S.Pos);
  if (S.Pos > S.Len) or (S.Line[S.Pos] <> '(') then
    Exit;

  Inc(S.Pos);
  D := 1;
  Any := False;
  Result := 0;
  while (S.Pos <= S.Len) and (D > 0) do
  begin
    if S.Line[S.Pos] = '''' then
      Break;               // a comment inside an unclosed call: not decidable
    if S.Line[S.Pos] = '"' then
    begin
      Any := True;
      SkipString(S);
      Continue;
    end;
    if S.Line[S.Pos] in ['(', '[', '{'] then
      Inc(D)
    else if S.Line[S.Pos] in [')', ']', '}'] then
      Dec(D)
    else if (S.Line[S.Pos] = ',') and (D = 1) then
      Inc(Result)
    else if not (S.Line[S.Pos] in Space) then
      Any := True;
    if D > 0 then
      Inc(S.Pos);
  end;

  if D > 0 then
    Exit(-1);              // it never closed on this line
  if Any then
    Inc(Result)            // n commas at this level means n+1 arguments
  else
    Result := 0;           // `f()`
end;

end.
