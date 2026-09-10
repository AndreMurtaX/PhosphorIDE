unit usynphosphor;

{ A SynEdit highlighter for Phosphor BASIC.

  WHY THERE IS NO RANGE STATE. A SynEdit highlighter normally has to carry state
  across lines, because a block comment or a multi-line string opened on line 10
  changes how line 400 is coloured. Phosphor has neither: `'` and `rem` run to end
  of line and nothing else starts a comment, and a string literal that reaches a
  newline is the hard lexical error `unterminated string` rather than a
  continuation (engine/PhosphorLexer.pas:361-366). So every line can be coloured
  by looking at that line alone -- GetRange/SetRange stay the base class's no-ops,
  and editing line 10 never repaints line 400.

  WHAT IT COLOURS THAT A KEYWORD LIST CANNOT. Two of Phosphor's rules are exactly
  the kind a beginner loses an hour to, and both are visible at lexing time, so
  they are painted as errors here rather than waited for:

    - AN UNKNOWN BACKSLASH ESCAPE. `"C:\temp"` is not a path, it is a tab; and
      `"\x"` is not a literal backslash-x, it is the compile error `unknown escape
      sequence`. The two offending characters get the error colour while the rest
      of the string stays a string, which is why a string can emit several tokens.
    - AN UNTERMINATED STRING. The whole run to end of line goes red.

  WHAT IT DELIBERATELY GETS WRONG. Phosphor's lexer has NO keyword table -- every
  keyword arrives at the parser as an ordinary identifier and is decided by
  POSITION (engine/PhosphorLexer.pas:385-408). `next = 5` and `elseif += 3` are
  legal assignments. Colouring those words as keywords everywhere is therefore
  wrong in a way no highlighter can fix without being the parser. It is the right
  trade -- the alternative mis-colours every ordinary program to be correct about
  a rare one -- but it is a trade, and nothing downstream (folding, indentation)
  may be built on the assumption that a coloured keyword IS a keyword.

  The two words the LEXER itself owns, `rem` and `mod`, are the exception: those
  can never be variables, and this unit treats them as absolute. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, SynEditHighlighter, SynEditTypes, uphosphorlang;

type
  TPhosphorTokenKind = (
    ptkNull,          // past the end of the line
    ptkSpace,
    ptkComment,       // ' ... and rem ...
    ptkString,
    ptkNumber,
    ptkKeyword,       // if, while, print, ...
    ptkOperatorWord,  // and, or, not, mod
    ptkLiteral,       // true, false, null
    ptkBuiltinCore,   // always available
    ptkBuiltinPkg,    // only where the host links the package
    ptkBuiltinGui,    // only where a graphical session was reachable
    ptkLabelName,     // name: at the start of a line
    ptkIdentifier,
    ptkSymbol,
    ptkError          // unknown escape, unterminated string
  );

  { TSynPhosphorSyn }

  TSynPhosphorSyn = class(TSynCustomHighlighter)
  private
    FLine: String;
    FLineLen: Integer;
    FRun: Integer;          // 1-based scan position
    FTokenPos: Integer;     // 1-based start of the current token
    FTokenKind: TPhosphorTokenKind;
    FInString: Boolean;     // mid-literal, between two emitted pieces
    FFirstOnLine: Boolean;  // no code token emitted on this line yet

    FCommentAttri: TSynHighlighterAttributes;
    FStringAttri: TSynHighlighterAttributes;
    FNumberAttri: TSynHighlighterAttributes;
    FKeywordAttri: TSynHighlighterAttributes;
    FOperatorWordAttri: TSynHighlighterAttributes;
    FLiteralAttri: TSynHighlighterAttributes;
    FBuiltinAttri: TSynHighlighterAttributes;
    FPackageAttri: TSynHighlighterAttributes;
    FGuiAttri: TSynHighlighterAttributes;
    FLabelAttri: TSynHighlighterAttributes;
    FIdentifierAttri: TSynHighlighterAttributes;
    FSymbolAttri: TSynHighlighterAttributes;
    FSpaceAttri: TSynHighlighterAttributes;
    FErrorAttri: TSynHighlighterAttributes;

    procedure ScanSpace;
    procedure ScanComment;
    procedure ScanNumber;
    procedure ScanIdentifier;
    procedure ScanString;
    procedure ScanSymbol;
    function LooksLikeLabel: Boolean;
  protected
    function GetIdentChars: TSynIdentChars; override;
    function GetSampleSource: String; override;
  public
    constructor Create(AOwner: TComponent); override;

    class function GetLanguageName: String; override;

    procedure SetLine(const NewValue: String; LineNumber: Integer); override;
    procedure Next; override;
    function GetEol: Boolean; override;
    function GetToken: String; override;
    procedure GetTokenEx(out TokenStart: PChar; out TokenLength: Integer); override;
    function GetTokenAttribute: TSynHighlighterAttributes; override;
    function GetTokenKind: Integer; override;
    function GetTokenPos: Integer; override;
    function GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes; override;

    { Repaint-safe colour swap. Both themes are defined here rather than in the
      form, so that a second window, a print preview or a future embedded viewer
      gets the same colours without copying a table. }
    procedure ApplyTheme(ADark: Boolean);
  published
    property CommentAttri: TSynHighlighterAttributes read FCommentAttri write FCommentAttri;
    property StringAttri: TSynHighlighterAttributes read FStringAttri write FStringAttri;
    property NumberAttri: TSynHighlighterAttributes read FNumberAttri write FNumberAttri;
    property KeywordAttri: TSynHighlighterAttributes read FKeywordAttri write FKeywordAttri;
    property OperatorWordAttri: TSynHighlighterAttributes read FOperatorWordAttri write FOperatorWordAttri;
    property LiteralAttri: TSynHighlighterAttributes read FLiteralAttri write FLiteralAttri;
    property BuiltinAttri: TSynHighlighterAttributes read FBuiltinAttri write FBuiltinAttri;
    property PackageAttri: TSynHighlighterAttributes read FPackageAttri write FPackageAttri;
    property GuiAttri: TSynHighlighterAttributes read FGuiAttri write FGuiAttri;
    property LabelAttri: TSynHighlighterAttributes read FLabelAttri write FLabelAttri;
    property IdentifierAttri: TSynHighlighterAttributes read FIdentifierAttri write FIdentifierAttri;
    property SymbolAttri: TSynHighlighterAttributes read FSymbolAttri write FSymbolAttri;
    property SpaceAttri: TSynHighlighterAttributes read FSpaceAttri write FSpaceAttri;
    property ErrorAttri: TSynHighlighterAttributes read FErrorAttri write FErrorAttri;
  end;

implementation

const
  { The complete escape set (engine/PhosphorLexer.pas:329-359). Anything else
    after a backslash is a compile error, which is what ptkError paints. }
  ValidEscapes = ['n', 't', 'r', '0', 'a', 'b', 'f', 'v', '\', '"'];

  IdentStart = ['A'..'Z', 'a'..'z', '_'];
  IdentChar = ['A'..'Z', 'a'..'z', '0'..'9', '_'];
  { A type suffix is PART of the name -- `left$` is one token, never `left` then a
    symbol (engine/PhosphorLexer.pas:389-392). }
  SuffixChar = ['$', '%', '@', '?'];
  DigitChar = ['0'..'9'];

constructor TSynPhosphorSyn.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FCommentAttri := TSynHighlighterAttributes.Create('Comment', 'Comment');
  AddAttribute(FCommentAttri);
  FStringAttri := TSynHighlighterAttributes.Create('String', 'String');
  AddAttribute(FStringAttri);
  FNumberAttri := TSynHighlighterAttributes.Create('Number', 'Number');
  AddAttribute(FNumberAttri);
  FKeywordAttri := TSynHighlighterAttributes.Create('Keyword', 'Keyword');
  AddAttribute(FKeywordAttri);
  FOperatorWordAttri := TSynHighlighterAttributes.Create('Word operator', 'WordOperator');
  AddAttribute(FOperatorWordAttri);
  FLiteralAttri := TSynHighlighterAttributes.Create('Literal', 'Literal');
  AddAttribute(FLiteralAttri);
  FBuiltinAttri := TSynHighlighterAttributes.Create('Built-in function', 'Builtin');
  AddAttribute(FBuiltinAttri);
  FPackageAttri := TSynHighlighterAttributes.Create('Package function', 'PackageFunc');
  AddAttribute(FPackageAttri);
  FGuiAttri := TSynHighlighterAttributes.Create('GUI function', 'GuiFunc');
  AddAttribute(FGuiAttri);
  FLabelAttri := TSynHighlighterAttributes.Create('Label', 'Label');
  AddAttribute(FLabelAttri);
  FIdentifierAttri := TSynHighlighterAttributes.Create('Identifier', 'Identifier');
  AddAttribute(FIdentifierAttri);
  FSymbolAttri := TSynHighlighterAttributes.Create('Symbol', 'Symbol');
  AddAttribute(FSymbolAttri);
  FSpaceAttri := TSynHighlighterAttributes.Create('Space', 'Space');
  AddAttribute(FSpaceAttri);
  FErrorAttri := TSynHighlighterAttributes.Create('Lexical error', 'Error');
  AddAttribute(FErrorAttri);

  ApplyTheme(False);
  SetAttributesOnChange(@DefHighlightChange);
end;

class function TSynPhosphorSyn.GetLanguageName: String;
begin
  Result := 'Phosphor BASIC';
end;

function TSynPhosphorSyn.GetIdentChars: TSynIdentChars;
begin
  { Includes the suffixes, so that double-clicking `count%` selects the whole name
    and a word-boundary search for `left$` behaves. }
  Result := IdentChar + SuffixChar;
end;

function TSynPhosphorSyn.GetSampleSource: String;
begin
  Result :=
    '''' + ' a greeting, and the traps this editor paints' + LineEnding +
    'const GREETING = "hello"' + LineEnding +
    'name$ = "world"' + LineEnding +
    'count% = 3' + LineEnding +
    LineEnding +
    'for i = 1 to count%' + LineEnding +
    '  println GREETING + ", " + ucase$(name$)' + LineEnding +
    'next' + LineEnding +
    LineEnding +
    'if count% > 2 and true = true then' + LineEnding +
    '  println "path: C:\\temp"      ' + '''' + ' doubled, because \t is a tab' + LineEnding +
    'endif' + LineEnding;
end;

procedure TSynPhosphorSyn.ApplyTheme(ADark: Boolean);
begin
  BeginUpdate;
  try
    if ADark then
    begin
      FCommentAttri.Foreground := $808080;
      FCommentAttri.Style := [fsItalic];
      FStringAttri.Foreground := $7CD68A;
      FNumberAttri.Foreground := $B5CEA8;
      FKeywordAttri.Foreground := $D69C56;
      FKeywordAttri.Style := [fsBold];
      FOperatorWordAttri.Foreground := $D69C56;
      FLiteralAttri.Foreground := $D69C56;
      FBuiltinAttri.Foreground := $DCDCAA;
      FPackageAttri.Foreground := $C586C0;
      FGuiAttri.Foreground := $D7BA7D;
      FLabelAttri.Foreground := $9CDCFE;
      FLabelAttri.Style := [fsBold];
      FIdentifierAttri.Foreground := clNone;
      FSymbolAttri.Foreground := $B4B4B4;
      FSpaceAttri.Background := clNone;
      FErrorAttri.Foreground := $5555FF;
      FErrorAttri.Style := [fsUnderline];
    end
    else
    begin
      FCommentAttri.Foreground := clGreen;
      FCommentAttri.Style := [fsItalic];
      FStringAttri.Foreground := clMaroon;
      FNumberAttri.Foreground := clNavy;
      FKeywordAttri.Foreground := clNavy;
      FKeywordAttri.Style := [fsBold];
      FOperatorWordAttri.Foreground := clNavy;
      FLiteralAttri.Foreground := clNavy;
      FBuiltinAttri.Foreground := clTeal;
      FPackageAttri.Foreground := clPurple;
      FGuiAttri.Foreground := clOlive;
      FLabelAttri.Foreground := clBlue;
      FLabelAttri.Style := [fsBold];
      FIdentifierAttri.Foreground := clNone;
      FSymbolAttri.Foreground := clBlack;
      FSpaceAttri.Background := clNone;
      FErrorAttri.Foreground := clRed;
      FErrorAttri.Style := [fsUnderline];
    end;
  finally
    EndUpdate;
  end;
end;

{ ------------------------------------------------------------------ scanning - }

procedure TSynPhosphorSyn.SetLine(const NewValue: String; LineNumber: Integer);
begin
  inherited SetLine(NewValue, LineNumber);
  FLine := NewValue;
  FLineLen := Length(FLine);
  FRun := 1;
  FInString := False;
  FFirstOnLine := True;
  Next;
end;

procedure TSynPhosphorSyn.ScanSpace;
begin
  while (FRun <= FLineLen) and (FLine[FRun] in [#1..#32]) do
    Inc(FRun);
  FTokenKind := ptkSpace;
end;

procedure TSynPhosphorSyn.ScanComment;
begin
  FRun := FLineLen + 1;
  FTokenKind := ptkComment;
end;

procedure TSynPhosphorSyn.ScanNumber;
begin
  { [0-9]+ ( . [0-9]+ )? ( [eE] [+-]? [0-9]+ )?  -- and every optional part is
    taken only when the digits that justify it are actually there, so `1.` is the
    number 1 followed by a stray dot, exactly as the lexer sees it
    (engine/PhosphorLexer.pas:219, 230-240). }
  while (FRun <= FLineLen) and (FLine[FRun] in DigitChar) do
    Inc(FRun);

  if (FRun < FLineLen) and (FLine[FRun] = '.') and (FLine[FRun + 1] in DigitChar) then
  begin
    Inc(FRun);
    while (FRun <= FLineLen) and (FLine[FRun] in DigitChar) do
      Inc(FRun);
  end;

  if (FRun <= FLineLen) and (FLine[FRun] in ['e', 'E']) then
  begin
    if (FRun < FLineLen) and (FLine[FRun + 1] in DigitChar) then
      Inc(FRun, 2)
    else if (FRun + 2 <= FLineLen) and (FLine[FRun + 1] in ['+', '-']) and
            (FLine[FRun + 2] in DigitChar) then
      Inc(FRun, 3)
    else
    begin
      FTokenKind := ptkNumber;
      Exit;
    end;
    while (FRun <= FLineLen) and (FLine[FRun] in DigitChar) do
      Inc(FRun);
  end;

  FTokenKind := ptkNumber;
end;

function TSynPhosphorSyn.LooksLikeLabel: Boolean;
var
  I: Integer;
begin
  { `name:` at the start of a line. An approximation of the compiler's rule, which
    also requires top level and excludes the reserved words -- the reserved-word
    half is checked by the caller, the top-level half cannot be known from one
    line. A label written inside a block is a no-op in Phosphor anyway
    (engine/PhosphorCompiler.pas:2406-2426), so painting one is arguably a
    service: it looks like a label and is not one. }
  Result := False;
  if not FFirstOnLine then
    Exit;
  I := FRun;
  while (I <= FLineLen) and (FLine[I] in [#1..#32]) do
    Inc(I);
  Result := (I <= FLineLen) and (FLine[I] = ':');
end;

procedure TSynPhosphorSyn.ScanIdentifier;
var
  Word: String;
  Tier: TPhosphorTier;
begin
  Inc(FRun);
  while (FRun <= FLineLen) and (FLine[FRun] in IdentChar) do
    Inc(FRun);
  if (FRun <= FLineLen) and (FLine[FRun] in SuffixChar) then
    Inc(FRun);

  Word := LowerCase(Copy(FLine, FTokenPos, FRun - FTokenPos));

  { `rem` is not a word the parser decides about: the LEXER swallows the rest of
    the line the moment it sees it, so `rem` is a comment and `remark` is not
    (engine/PhosphorLexer.pas:393-398). }
  if Word = 'rem' then
  begin
    FRun := FLineLen + 1;
    FTokenKind := ptkComment;
    Exit;
  end;

  if IsPhosphorOperatorWord(Word) then
    FTokenKind := ptkOperatorWord
  else if IsPhosphorLiteralWord(Word) then
    FTokenKind := ptkLiteral
  else if IsPhosphorKeyword(Word) then
    FTokenKind := ptkKeyword
  else if PhosphorBuiltinTier(Word, Tier) then
    case Tier of
      ptCore: FTokenKind := ptkBuiltinCore;
      ptPackage: FTokenKind := ptkBuiltinPkg;
    else
      FTokenKind := ptkBuiltinGui;
    end
  else if LooksLikeLabel then
    FTokenKind := ptkLabelName
  else
    FTokenKind := ptkIdentifier;
end;

procedure TSynPhosphorSyn.ScanString;
var
  C: Char;
begin
  { A literal can come back as SEVERAL tokens, so that a bad escape inside an
    otherwise fine string is the only thing painted red. FInString says whether
    this call is opening the literal or resuming it. }
  if not FInString then
  begin
    Inc(FRun);          // the opening quote
    FInString := True;
  end;

  while FRun <= FLineLen do
  begin
    C := FLine[FRun];

    if C = '"' then
    begin
      if (FRun < FLineLen) and (FLine[FRun + 1] = '"') then
      begin
        Inc(FRun, 2);   // "" is one quote and does NOT close the literal
        Continue;
      end;
      Inc(FRun);
      FInString := False;
      FTokenKind := ptkString;
      Exit;
    end;

    if C = '\' then
    begin
      if FRun = FLineLen then
      begin
        { A backslash as the last byte of the line: the literal cannot close. }
        Inc(FRun);
        FInString := False;
        FTokenKind := ptkError;
        Exit;
      end;
      if FLine[FRun + 1] in ValidEscapes then
      begin
        Inc(FRun, 2);
        Continue;
      end;
      { An unknown escape. Emit whatever string came before it first, then this
        call's successor emits the two offending characters on their own. }
      if FRun > FTokenPos then
      begin
        FTokenKind := ptkString;
        Exit;
      end;
      Inc(FRun, 2);
      FTokenKind := ptkError;
      Exit;
    end;

    Inc(FRun);
  end;

  { Ran off the end of the line with the literal still open. In Phosphor that is
    not a continuation, it is the error `unterminated string`. }
  FInString := False;
  FTokenKind := ptkError;
end;

procedure TSynPhosphorSyn.ScanSymbol;
var
  C, D: Char;
begin
  C := FLine[FRun];
  Inc(FRun);

  { The compound assignments are two ADJACENT characters -- `x + = 1` is not one
    (docs/language-reference.md:139-140) -- and `<=`, `>=`, `<>` likewise. }
  if FRun <= FLineLen then
  begin
    D := FLine[FRun];
    if ((C in ['+', '-', '*', '/']) and (D = '=')) or
       ((C = '<') and (D in ['=', '>'])) or
       ((C = '>') and (D = '=')) then
      Inc(FRun);
  end;

  FTokenKind := ptkSymbol;
end;

procedure TSynPhosphorSyn.Next;
var
  C: Char;
begin
  FTokenPos := FRun;

  if FRun > FLineLen then
  begin
    FTokenKind := ptkNull;
    Exit;
  end;

  if FInString then
  begin
    ScanString;
    Exit;
  end;

  C := FLine[FRun];

  if C in [#1..#32] then
  begin
    ScanSpace;
    Exit;
  end;

  { Everything below is a code token, so the "first thing on this line" window --
    which is all that makes a label a label -- closes after it. }
  try
    if C = '''' then
    begin
      ScanComment;
      Exit;
    end;
    if C = '"' then
    begin
      ScanString;
      Exit;
    end;
    if C in DigitChar then
    begin
      ScanNumber;
      Exit;
    end;
    if C in IdentStart then
    begin
      ScanIdentifier;
      Exit;
    end;
    ScanSymbol;
  finally
    FFirstOnLine := False;
  end;
end;

{ ------------------------------------------------------------ SynEdit's asks - }

function TSynPhosphorSyn.GetEol: Boolean;
begin
  Result := FTokenKind = ptkNull;
end;

function TSynPhosphorSyn.GetToken: String;
begin
  Result := Copy(FLine, FTokenPos, FRun - FTokenPos);
end;

procedure TSynPhosphorSyn.GetTokenEx(out TokenStart: PChar; out TokenLength: Integer);
begin
  TokenLength := FRun - FTokenPos;
  if TokenLength > 0 then
    TokenStart := @FLine[FTokenPos]
  else
    TokenStart := nil;
end;

function TSynPhosphorSyn.GetTokenPos: Integer;
begin
  { SynEdit wants this 0-based; the scanner works 1-based against a String. }
  Result := FTokenPos - 1;
end;

function TSynPhosphorSyn.GetTokenKind: Integer;
begin
  Result := Ord(FTokenKind);
end;

function TSynPhosphorSyn.GetTokenAttribute: TSynHighlighterAttributes;
begin
  case FTokenKind of
    ptkComment: Result := FCommentAttri;
    ptkString: Result := FStringAttri;
    ptkNumber: Result := FNumberAttri;
    ptkKeyword: Result := FKeywordAttri;
    ptkOperatorWord: Result := FOperatorWordAttri;
    ptkLiteral: Result := FLiteralAttri;
    ptkBuiltinCore: Result := FBuiltinAttri;
    ptkBuiltinPkg: Result := FPackageAttri;
    ptkBuiltinGui: Result := FGuiAttri;
    ptkLabelName: Result := FLabelAttri;
    ptkIdentifier: Result := FIdentifierAttri;
    ptkSymbol: Result := FSymbolAttri;
    ptkError: Result := FErrorAttri;
    ptkSpace: Result := FSpaceAttri;
  else
    Result := nil;
  end;
end;

function TSynPhosphorSyn.GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes;
begin
  case Index of
    SYN_ATTR_COMMENT: Result := FCommentAttri;
    SYN_ATTR_IDENTIFIER: Result := FIdentifierAttri;
    SYN_ATTR_KEYWORD: Result := FKeywordAttri;
    SYN_ATTR_STRING: Result := FStringAttri;
    SYN_ATTR_WHITESPACE: Result := FSpaceAttri;
    SYN_ATTR_SYMBOL: Result := FSymbolAttri;
  else
    Result := nil;
  end;
end;

end.
