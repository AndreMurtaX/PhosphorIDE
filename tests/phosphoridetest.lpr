program phosphoridetest;

{ The parts of PhosphorIDE that can be wrong without anyone noticing.

  A console program, on purpose: it links the SynEdit and LCL units it needs but
  never `Interfaces`, so no widgetset is created and it runs identically on a
  desktop, over a pipe, and on a headless CI machine. That distinction -- linking
  the LCL is not what connects to a display -- is the same one the Phosphor host
  rests on, and it is what lets the highlighter be tested without a window.

  WHAT IS TESTED HERE is the logic that has no visible failure mode: a diagnostic
  parser that silently stops matching, a highlighter that quietly paints a bad
  escape as ordinary text, a protocol encoder that emits a frame the other end
  will not accept. A form that fails to build is caught by `phosphoride
  --selftest`; a colour that is slightly wrong is caught by looking. These are
  neither.

  Exit code 0 means every check passed. Anything else means the count of failures,
  and every failure has already been printed with what it expected and what it
  got. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  { LINKING THE LCL IS NOT WHAT CONNECTS TO A DISPLAY. `Interfaces` is: its
    initialization section calls CreateWidgetset, and on gtk2 that opens the X
    display before main, which kills a process that merely LISTED the unit on a
    machine with no session. Naming the widgetset unit directly links the same
    code -- which is what satisfies the WSRegister* symbols the LCL's registration
    tables reference -- while leaving the call unmade.

    The technique is Phosphor's, and the reason it is used here is the same: this
    program must run identically on a desktop and on a headless CI machine. It
    creates no window and touches no canvas; it only needs Graphics to compile,
    because a highlighter's colours are TColor. }
  InterfaceBase,
  {$IFDEF WINDOWS}Win32Int,{$ELSE}Gtk2Int,{$ENDIF}
  SysUtils, Classes,
  uphosphorlang, uphosphormsg, usynphosphor, udebugproto, ubreakpoints,
  uphosphorcomplete,
  { The transport is exercised against a socket this program opens itself:
    no host is started, nothing is spawned, and the test runs the same on a
    headless machine as on a desktop. Sockets and ExtCtrls come with it. }
  udebugtransport, udebugsession, Sockets;

var
  Checks: Integer = 0;
  Failures: Integer = 0;
  Section: String = '';

procedure Group(const AName: String);
begin
  Section := AName;
  WriteLn;
  WriteLn('-- ', AName);
end;

procedure Check(const AWhat: String; ACondition: Boolean);
begin
  Inc(Checks);
  if ACondition then
    Exit;
  Inc(Failures);
  WriteLn('FAIL  [', Section, '] ', AWhat);
end;

procedure CheckEq(const AWhat, AExpected, AGot: String);
begin
  Inc(Checks);
  if AExpected = AGot then
    Exit;
  Inc(Failures);
  WriteLn('FAIL  [', Section, '] ', AWhat);
  WriteLn('        expected: ', AExpected);
  WriteLn('        got:      ', AGot);
end;

procedure CheckEqInt(const AWhat: String; AExpected, AGot: Integer);
begin
  CheckEq(AWhat, IntToStr(AExpected), IntToStr(AGot));
end;

{ ------------------------------------------------------- diagnostic parsing - }

procedure TestMessages;
var
  M: TPhosphorMessage;
begin
  Group('uphosphormsg: the shapes the host actually emits');

  { Every string below was captured from bin/phosphor.exe, not invented. }

  Check('a compile error is a source location',
    ParsePhosphorMessage('phosphor: bad.bas:2: unexpected token in expression', M));
  Check('  kind', M.Kind = pmkSourceError);
  CheckEqInt('  line', 2, M.Line);
  CheckEq('  path', 'bad.bas', M.Path);
  CheckEq('  message', 'unexpected token in expression', M.Text);

  ParsePhosphorMessage('phosphor: C:\Dev\x\dz.bas:4: division by zero', M);
  Check('a Windows drive letter is not the line separator', M.Kind = pmkSourceError);
  CheckEqInt('  line past the drive colon', 4, M.Line);
  CheckEq('  path keeps its backslashes', 'C:\Dev\x\dz.bas', M.Path);

  ParsePhosphorMessage('phosphor: ./bad.bas:2: unexpected token in expression', M);
  CheckEq('a relative path is echoed verbatim', './bad.bas', M.Path);

  { The message itself contains a colon, which is what breaks a parser that
    splits on the last one. }
  ParsePhosphorMessage('phosphor: badfn.bas:2: no function nosuchfunc$:%', M);
  Check('a message may contain colons', M.Kind = pmkSourceError);
  CheckEqInt('  line', 2, M.Line);
  CheckEq('  whole message survives', 'no function nosuchfunc$:%', M.Text);

  ParsePhosphorMessage(
    'phosphor: openerr.bas:1: cannot open "cafe.txt" for input: no such file', M);
  CheckEq('  message with a quoted path and a colon',
    'cannot open "cafe.txt" for input: no such file', M.Text);

  { A packed executable has no path to print. }
  ParsePhosphorMessage('phosphor: 4: division by zero', M);
  Check('a packed executable reports line only', M.Kind = pmkPackedError);
  CheckEqInt('  line', 4, M.Line);
  CheckEq('  path is empty', '', M.Path);
  Check('  and it is still somewhere to jump to', HasSourceLocation(M));

  { The REPL uses another shape entirely. }
  ParsePhosphorMessage('error: unexpected token in expression', M);
  Check('the REPL shape is recognised', M.Kind = pmkReplError);
  CheckEqInt('  and carries no line', 0, M.Line);
  Check('  so it is not a jump target', not HasSourceLocation(M));

  { A refusal is NOT a source location -- this is the case that turns into a
    jump to line 0 of a file called "file not". }
  ParsePhosphorMessage('phosphor: file not found: nope.bas', M);
  Check('a host refusal is not a source error', M.Kind = pmkHostError);
  Check('  and is not a jump target', not HasSourceLocation(M));
  CheckEq('  message', 'file not found: nope.bas', M.Text);

  ParsePhosphorMessage('phosphor: --out needs a path', M);
  Check('a usage refusal is a host error', M.Kind = pmkHostError);

  ParsePhosphorMessage(
    'phosphor: warning: 1 function name(s) this host does not provide:', M);
  Check('a --check warning is a warning', M.Kind = pmkWarning);
  Check('  and is not a jump target', not HasSourceLocation(M));

  { Ordinary program output must survive untouched. }
  Check('program output is not a diagnostic',
    not ParsePhosphorMessage('hello, world', M));
  Check('  kind', M.Kind = pmkPlain);
  CheckEq('  text is passed through', 'hello, world', M.Text);

  { A program is free to print something that looks like one. It is still only
    stderr that is parsed, but the parser must not corrupt it. }
  ParsePhosphorMessage('phosphor: 0: not really a line number', M);
  Check('line 0 is not a location', not HasSourceLocation(M));

  { A LINE THE PARSER DOES NOT RECOGNISE MUST NOT BECOME A JUMP TARGET. The shapes
    below do not exist yet -- the host will start emitting the first one when the
    BREAKPOINT seam is wired (see docs/phosphor-engine-work-order.md, B0). Until the
    parser learns them, the property that has to hold is the safe one: whatever they
    are classified as, they carry no location, so nothing sends the caret anywhere. }
  ParsePhosphorMessage('phosphor: breakpoint at line 7: checkpoint x=5', M);
  Check('an unrecognised phosphor: line is a host error', M.Kind = pmkHostError);
  Check('  and never a jump target', not HasSourceLocation(M));
  ParsePhosphorMessage('phosphor: trace on at line 3', M);
  Check('and so is any other new shape', not HasSourceLocation(M));

  Group('uphosphormsg: exit codes');
  CheckEq('0', 'finished', PhosphorExitCodeText(0));
  CheckEq('1 is the program''s fault', 'the program failed', PhosphorExitCodeText(1));
  CheckEq('2 means nothing ran', 'the host refused to run it', PhosphorExitCodeText(2));
  CheckEq('3 is the interpreter itself', 'the interpreter itself faulted',
    PhosphorExitCodeText(3));
  Check('anything else is named as foreign',
    Pos('exit code', PhosphorExitCodeText(137)) > 0);
end;

{ ------------------------------------------------------------ the word lists - }

procedure TestLanguage;
var
  Tier: TPhosphorTier;
begin
  Group('uphosphorlang: generated word lists');

  CheckEqInt('keyword count matches the constant',
    PhosphorKeywordCount, Length(PhosphorKeywords));
  CheckEqInt('core count matches the constant',
    PhosphorBuiltinCoreCount, Length(PhosphorBuiltins(ptCore)));
  CheckEqInt('package count matches the constant',
    PhosphorBuiltinPackageCount, Length(PhosphorBuiltins(ptPackage)));
  CheckEqInt('gui count matches the constant',
    PhosphorBuiltinGuiCount, Length(PhosphorBuiltins(ptGui)));

  Check('println is a keyword', IsPhosphorKeyword('println'));
  Check('endfunction is a keyword', IsPhosphorKeyword('endfunction'));
  Check('lookup is case-insensitive', IsPhosphorKeyword('PrintLn'));
  Check('and so is a mixed-case terminator', IsPhosphorKeyword('EndIf'));
  Check('mod is a word operator', IsPhosphorOperatorWord('mod'));
  Check('true is a literal', IsPhosphorLiteralWord('true'));
  Check('null is a literal (JSON only, but still a word)',
    IsPhosphorLiteralWord('null'));

  Check('a suffix is part of the name: left$ is a built-in',
    IsPhosphorBuiltin('left$'));
  Check('  and left alone is not', not IsPhosphorBuiltin('left'));
  Check('dim@ is a built-in, not the dim statement', IsPhosphorBuiltin('dim@'));
  Check('dim is a keyword even though it is unimplemented',
    IsPhosphorKeyword('dim'));

  Check('eof is a built-in (a compiler special form, in no registry)',
    IsPhosphorBuiltin('eof'));
  Check('input$ likewise', IsPhosphorBuiltin('input$'));

  Check('ucase$ is core', PhosphorBuiltinTier('ucase$', Tier) and (Tier = ptCore));
  Check('zip_open@ is a package name',
    PhosphorBuiltinTier('zip_open@', Tier) and (Tier = ptPackage));
  Check('form@ is a GUI name', PhosphorBuiltinTier('form@', Tier) and (Tier = ptGui));

  Check('an invented name is nothing', not IsPhosphorBuiltin('nosuchfunc$'));
  Check('and neither is the empty string', not IsPhosphorBuiltin(''));
end;

{ ---------------------------------------------------------------- the colours - }

type
  TKindArray = array of TPhosphorTokenKind;

function Tokenize(AHl: TSynPhosphorSyn; const ALine: String;
  out ATexts: TStringList): TKindArray;
begin
  Result := nil;
  ATexts := TStringList.Create;
  AHl.SetLine(ALine, 0);
  while not AHl.GetEol do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := TPhosphorTokenKind(AHl.GetTokenKind);
    ATexts.Add(AHl.GetToken);
    AHl.Next;
  end;
end;

procedure TestHighlighter;
var
  Hl: TSynPhosphorSyn;
  Kinds: TKindArray;
  Texts: TStringList;

  procedure Scan(const ALine: String);
  begin
    FreeAndNil(Texts);
    Kinds := Tokenize(Hl, ALine, Texts);
  end;

begin
  Group('usynphosphor: what the scanner emits');
  Hl := TSynPhosphorSyn.Create(nil);
  Texts := nil;
  try
    CheckEq('the language names itself', 'Phosphor BASIC',
      TSynPhosphorSyn.GetLanguageName);

    Scan('println "hi"');
    CheckEqInt('println "hi" is three tokens', 3, Length(Kinds));
    Check('  println is a keyword', Kinds[0] = ptkKeyword);
    Check('  the gap is space', Kinds[1] = ptkSpace);
    Check('  the literal is a string', Kinds[2] = ptkString);
    CheckEq('  and the string keeps its quotes', '"hi"', Texts[2]);

    Scan('name$ = ucase$(x%)');
    Check('name$ is one identifier, suffix included', Kinds[0] = ptkIdentifier);
    CheckEq('  including the $', 'name$', Texts[0]);
    Check('ucase$ is a core built-in', Kinds[4] = ptkBuiltinCore);
    CheckEq('  including the $', 'ucase$', Texts[4]);

    { The trap the highlighter exists to make visible. }
    Scan('println "C:\temp"');
    Check('a known escape stays part of the string',
      (Length(Kinds) = 3) and (Kinds[2] = ptkString));

    Scan('println "C:\qemu"');
    Check('an UNKNOWN escape is split out as an error',
      Length(Kinds) >= 4);
    Check('  the text before it is still a string', Kinds[2] = ptkString);
    Check('  the two offending characters are an error', Kinds[3] = ptkError);
    CheckEq('  and they are exactly the escape', '\q', Texts[3]);

    Scan('s$ = "never closed');
    Check('an unterminated string is an error, not a continuation',
      Kinds[High(Kinds)] = ptkError);

    Scan('s$ = "a doubled "" quote"');
    Check('a doubled quote does not close the literal',
      (Kinds[High(Kinds)] = ptkString));
    CheckEq('  the whole literal is one token', '"a doubled "" quote"',
      Texts[High(Kinds)]);

    Scan('rem this is a comment');
    CheckEqInt('rem swallows the line', 1, Length(Kinds));
    Check('  as a comment', Kinds[0] = ptkComment);

    Scan('remark = 5');
    Check('but remark is an ordinary identifier', Kinds[0] = ptkIdentifier);

    Scan('x = 5 '' trailing comment');
    Check('an apostrophe comment can follow code',
      Kinds[High(Kinds)] = ptkComment);

    Scan('n = 1.5e-3');
    Check('a full number is one token', Kinds[4] = ptkNumber);
    CheckEq('  including the exponent', '1.5e-3', Texts[4]);

    Scan('n = 1.');
    Check('a trailing dot is NOT part of the number', Kinds[4] = ptkNumber);
    CheckEq('  the number stops at the digits', '1', Texts[4]);

    Scan('retry:');
    Check('a name followed by a colon at line start is a label',
      Kinds[0] = ptkLabelName);

    Scan('  x = retry:');
    Check('but not in the middle of a line',
      Kinds[Length(Kinds) - 2] = ptkIdentifier);

    Scan('a += 1');
    Check('a compound assignment is one symbol', Kinds[2] = ptkSymbol);
    CheckEq('  both characters', '+=', Texts[2]);

    Scan('if a <> b then');
    Check('<> is one symbol', Kinds[4] = ptkSymbol);
    CheckEq('  both characters', '<>', Texts[4]);

    { x, space, =, space, a, space, \, space, b -- the operator is token 6. }
    Scan('x = a \ b');
    CheckEq('a backslash outside a string is integer division', '\', Texts[6]);
    Check('  and it is a symbol', Kinds[6] = ptkSymbol);

    Scan('');
    CheckEqInt('an empty line has no tokens', 0, Length(Kinds));
  finally
    Texts.Free;
    Hl.Free;
  end;
end;

{ ------------------------------------------------------------- completion --- }

procedure TestCompletion;
var
  Items: TCompletionItems;
  Sigs: TPhosphorWordList;
  CoreN, PkgN, GuiN, I, Arg: Integer;
  Sorted, Cut: Boolean;
  Nm: String;

  { CallAtCaret has two out parameters, which a Check cannot hold. }
  function CallAt(const ALine: String; ACol: Integer;
    out AName: String; out AArg: Integer): Boolean;
  begin
    Result := CallAtCaret(ALine, ACol, AName, AArg);
  end;

  function Pre(const ALine: String; ACol: Integer): String;
  var
    Ignored: Integer;
  begin
    Result := PrefixAtCaret(ALine, ACol, Ignored);
  end;

  function Start(const ALine: String; ACol: Integer): Integer;
  begin
    PrefixAtCaret(ALine, ACol, Result);
  end;

  function Has(const AItems: TCompletionItems; const AWord: String): Boolean;
  var
    J: Integer;
  begin
    Result := False;
    for J := 0 to High(AItems) do
      if AItems[J].Word = AWord then
        Exit(True);
  end;

begin
  Group('uphosphorcomplete: the word at the caret, and what to offer');

  { --- the prefix, by the highlighter's rule ------------------------------- }
  CheckEq('a partial name is the prefix', 'lef', Pre('  lef', 6));
  CheckEqInt('and it starts where it starts', 3, Start('  lef', 6));
  { THE SUFFIX IS PART OF THE NAME. Miss this and accepting `left$` after `lef`
    writes four characters over three, leaving a second $ behind. }
  CheckEq('a suffix belongs to the word', 'x$', Pre('x$', 3));
  CheckEq('so does a percent', 'count%', Pre('count%', 7));
  CheckEq('a whole name is its own prefix', 'println', Pre('println', 8));
  CheckEq('mid-word, only what is behind the caret', 'pri', Pre('println', 4));
  { A number is not a name, and a suffix with nothing in front of it is not
    either -- both are what the scanner decides, and this has to agree. }
  CheckEq('a number is not a prefix', '', Pre('123', 4));
  CheckEq('nor is a name that starts with one', '', Pre('1abc', 5));
  CheckEq('nor a bare suffix', '', Pre('= $', 4));
  CheckEq('nothing at the start of a line', '', Pre('abc', 1));
  CheckEq('nothing after a space', '', Pre('abc ', 5));
  { A suffix can only be LAST: `a$b` is two words here and two words to the
    scanner. }
  CheckEq('a suffix does not glue two names', 'b', Pre('a$b', 4));

  { --- where completion must stay quiet ------------------------------------ }
  Check('open code is not a literal', not InLiteralOrComment('x = 1', 6));
  Check('inside a string it is', InLiteralOrComment('x = "abc', 8));
  Check('after the closing quote it is not',
        not InLiteralOrComment('x = "abc" + y', 14));
  { Both sides of the opening quote, because an off-by-one here is a popup that
    will not open on the character after a string. }
  Check('the opening quote itself is outside', not InLiteralOrComment('x = "ab', 5));
  Check('one past it is inside', InLiteralOrComment('x = "ab', 6));
  { A backslash eats whatever follows, including a quote -- the same rule the
    highlighter paints a bad escape by. }
  Check('an escaped quote does not close the string',
        InLiteralOrComment('s = "a\" + b', 12));
  Check('an apostrophe comment silences it',
        InLiteralOrComment('x = 1 '' why', 12));
  { `rem` is the LEXER's word; `remark` is an ordinary identifier. }
  Check('rem silences it', InLiteralOrComment('rem a note', 8));
  Check('remark does not', not InLiteralOrComment('remark = 1', 10));
  Check('and a rem inside a string is just text',
        not InLiteralOrComment('s = "rem" + t', 13));

  { --- the candidates ------------------------------------------------------ }
  Items := CompletionCandidates('lef', ptGui);
  Check('lef offers something', Length(Items) > 0);
  Check('and left$ is in it', Has(Items, 'left$'));
  Check('printl finds println',
        Has(CompletionCandidates('printl', ptCore), 'println'));
  Check('an unknown prefix offers nothing',
        Length(CompletionCandidates('zzq', ptGui)) = 0);
  Check('lookup is case-insensitive like the lexer',
        Has(CompletionCandidates('PRINTL', ptCore), 'println'));

  CoreN := Length(CompletionCandidates('', ptCore));
  PkgN := Length(CompletionCandidates('', ptPackage));
  GuiN := Length(CompletionCandidates('', ptGui));
  Check('core is the smallest list', CoreN < PkgN);
  Check('package is smaller than gui', PkgN < GuiN);
  Check('core is at least the core built-ins',
        CoreN >= PhosphorBuiltinCoreCount);

  { THE TIER IS A CUT, NOT A LABEL. A core-only list carrying a GUI name is the
    editor recommending a program that runs on its author's desktop and fails on
    a server -- which is the whole reason uphosphorlang keeps three lists. }
  Items := CompletionCandidates('', ptCore);
  Cut := True;
  for I := 0 to High(Items) do
    if Items[I].Kind in [ckBuiltinPackage, ckBuiltinGui] then
      Cut := False;
  Check('a core list holds nothing above core', Cut);

  { Sorted and unique, because the popup shows them in order and one name twice
    is a choice with no difference in it. }
  Items := CompletionCandidates('a', ptGui);
  Sorted := Length(Items) > 0;
  for I := 1 to High(Items) do
    if Items[I - 1].Word >= Items[I].Word then
      Sorted := False;
  Check('the list is sorted and has no repeats', Sorted);


  { --- the signatures, which are facts about the other repository ---------- }
  Sigs := PhosphorSignatures('mid$');
  { mid$ IS THE CASE THE WHOLE TABLE EXISTS FOR: Reg.Add overwrites by
    signature, not by name, so `mid$:$n` and `mid$:$nn` are two slots. An editor
    that showed one arity for a name that has two would be worse than one that
    showed none. }
  CheckEqInt('mid$ has two arities', 2, Length(Sigs));
  if Length(Sigs) = 2 then
  begin
    CheckEq('the shorter one comes first', '$n', Sigs[0]);
    CheckEq('and then the longer', '$nn', Sigs[1]);
  end;

  { ABSENT AND EMPTY ARE DIFFERENT ANSWERS. dirseparator$ is registered as
    `dirseparator$:` -- it is KNOWN, and takes nothing. }
  Sigs := PhosphorSignatures('dirseparator$');
  CheckEqInt('a zero-argument name has one signature', 1, Length(Sigs));
  if Length(Sigs) = 1 then
    CheckEq('and it is the empty string', '', Sigs[0]);

  { ...whereas a name whose signature is assembled at run time has NONE, and the
    difference is the whole reason the table can say either. callfunc registers
    one slot per arity from a loop, so the literal in the source says `$` and the
    truth is nine different things. }
  CheckEqInt('callfunc carries no signature at all', 0,
             Length(PhosphorSignatures('callfunc')));
  { The four compiler special forms are in no registry, so there is nothing to
    extract and nothing is claimed. }
  CheckEqInt('eof carries none either', 0, Length(PhosphorSignatures('eof')));
  CheckEqInt('and a word that is not a built-in carries none', 0,
             Length(PhosphorSignatures('zzqzz')));
  Check('lookup is case-insensitive here too',
        Length(PhosphorSignatures('MID$')) = 2);
  CheckEqInt('the table holds what the unit says it holds',
             PhosphorSignatureNameCount, 1136);

  { --- which call the caret is in ------------------------------------------ }
  Check('inside a call', CallAt('mid$(s, 1', 10, Nm, Arg));
  CheckEq('the name is the one before the parenthesis', 'mid$', Nm);
  CheckEqInt('and the argument is counted by commas', 1, Arg);
  Check('on the first argument', CallAt('mid$(', 6, Nm, Arg));
  CheckEqInt('which is zero', 0, Arg);
  { SPACE DOES NOT BREAK THE NAME, or the popup vanishes when somebody types
    one; anything else does. }
  Check('a space before the parenthesis is the same call',
        CallAt('mid$ (s', 8, Nm, Arg));
  CheckEq('still mid$', 'mid$', Nm);
  Check('grouping is not a call', not CallAt('x = (a + b', 11, Nm, Arg));
  Check('a closed call is over', not CallAt('mid$(s, 1)', 11, Nm, Arg));
  { THE INNERMOST ONE, because that is what is being typed. }
  { COLUMN 16 IS INSIDE mid$, 17 IS NOT: the closing parenthesis at 16 ends that
    call, and a caret after it is back in left$. The first version of this asked
    for 17 and expected mid$ -- the code was right and the expectation was
    wrong, which is the good way round to find out. }
  Check('nested answers the inner call',
        CallAt('left$(mid$(s, 2), 4', 16, Nm, Arg));
  CheckEq('which is mid$', 'mid$', Nm);
  CheckEqInt('on its second argument', 1, Arg);
  Check('and after it closes, the outer one',
        CallAt('left$(mid$(s, 2), 4', 20, Nm, Arg));
  CheckEq('which is left$', 'left$', Nm);
  CheckEqInt('on its second argument too', 1, Arg);
  { The same two silences as completion, for the same reasons. }
  Check('never inside a string', not CallAt('s = "mid$(a', 12, Nm, Arg));
  Check('never inside a comment', not CallAt('mid$(s '' why', 13, Nm, Arg));
  Check('a parenthesis inside a string is not an open call',
        not CallAt('s = "(" + mid', 14, Nm, Arg));

  { --- how a signature reads ----------------------------------------------- }
  CheckEq('kinds, not parameter names', 'mid$([string], number)',
          SignatureText('mid$', '$n', 0));
  CheckEq('the caret is marked where it is', 'mid$(string, [number])',
          SignatureText('mid$', '$n', 1));
  { A signature shorter than the argument being typed no longer matches, and is
    rendered unmarked rather than hidden. }
  CheckEq('a shorter arity is left unmarked', 'mid$(string, number)',
          SignatureText('mid$', '$n', 5));
  CheckEq('no arguments is an empty pair', 'dirseparator$()',
          SignatureText('dirseparator$', '', 0));
  CheckEq('every code has a word', 'f([number], int%, string, handle, bool)',
          SignatureText('f', 'n%$@?', 0));

  { --- the insertion keeps the user's case --------------------------------- }
  CheckEq('lower stays lower', 'println', CompletionInsertion('prin', 'println'));
  CheckEq('Capitalised stays capitalised', 'Println',
          CompletionInsertion('Prin', 'println'));
  CheckEq('SHOUTED stays shouted', 'PRINTLN',
          CompletionInsertion('PRIN', 'println'));
  { A prefix with no letters has no case to preserve, and reading one into
    punctuation would answer LEFT$ to a lone dollar sign. }
  CheckEq('punctuation is not a shout', 'left$',
          CompletionInsertion('$', 'left$'));
  CheckEq('nothing typed, nothing imposed', 'println',
          CompletionInsertion('', 'println'));
end;

{ ------------------------------------------------------------ breakpoints --- }

procedure TestBreakpoints;
var
  B: TBreakpointSet;

  function Dump: String;
  var
    I: Integer;
  begin
    Result := '';
    for I := 0 to B.Count - 1 do
    begin
      if I > 0 then
        Result := Result + ',';
      Result := Result + IntToStr(B[I]);
    end;
  end;

begin
  Group('ubreakpoints: marks that follow their statement');
  B := TBreakpointSet.Create;
  try
    Check('toggling on answers True', B.Toggle(5));
    Check('  and it is there', B.Has(5));
    Check('toggling off answers False', not B.Toggle(5));
    Check('  and it is gone', not B.Has(5));

    B.Toggle(9); B.Toggle(3); B.Toggle(6);
    CheckEq('the set stays sorted whatever order they arrive in', '3,6,9', Dump);
    CheckEqInt('  and counted', 3, B.Count);

    B.Toggle(6);
    CheckEq('removing from the middle keeps the rest in order', '3,9', Dump);

    Check('line 0 is refused', not B.Toggle(0));
    Check('and so is a negative line', not B.Toggle(-1));
    CheckEq('  neither reached the set', '3,9', Dump);

    { The arithmetic. AFirstLine is the 1-based line the edit happened AT. }
    B.Clear;
    B.Toggle(5); B.Toggle(10);

    B.TrackEdit(11, 1);
    CheckEq('an insert BELOW every mark moves nothing', '5,10', Dump);

    B.TrackEdit(1, 2);
    CheckEq('two lines inserted at the top move both down', '7,12', Dump);

    B.TrackEdit(7, 1);
    CheckEq('an insert AT a mark''s own line moves it', '8,13', Dump);

    B.TrackEdit(8, -1);
    CheckEq('deleting a mark''s own line drops it, and shifts the rest', '12', Dump);

    B.Clear;
    B.Toggle(3); B.Toggle(4); B.Toggle(5); B.Toggle(20);
    B.TrackEdit(3, -3);
    CheckEq('deleting a range drops every mark inside it', '17', Dump);

    B.Clear;
    B.Toggle(5);
    B.TrackEdit(6, -1);
    CheckEq('deleting the line BELOW a mark leaves it alone', '5', Dump);

    B.TrackEdit(5, 0);
    CheckEq('a zero delta is a no-op', '5', Dump);

    B.Clear;
    B.Toggle(2);
    B.TrackEdit(1, -1);
    CheckEq('deleting line 1 with a mark on line 2 moves it to 1', '1', Dump);

    B.Clear;
    B.Toggle(1);
    B.TrackEdit(1, -1);
    CheckEq('deleting the only marked line empties the set', '', Dump);
    CheckEqInt('  and the count agrees', 0, B.Count);

    B.Clear;
    B.Toggle(4);
    CheckEqInt('ToArray copies the set', 1, Length(B.ToArray));
    CheckEqInt('  with the right line', 4, B.ToArray[0]);
  finally
    B.Free;
  end;
end;

{ ------------------------------------------------------------ the protocol --- }

procedure TestProtocol;
var
  Frame: String;
  M: TPdbpMessage;
begin
  Group('udebugproto: frames both ends must agree on');

  Frame := EncodeInitialize(1, 'PhosphorIDE test');
  Check('a frame is a single line', Pos(#10, Frame) = 0);
  Check('  it names the command', Pos('"cmd" : "initialize"', Frame) > 0);
  Check('  and the protocol version', Pos('"protocol" : 1', Frame) > 0);

  Frame := EncodeSetBreakpoints(7, 'x.bas', [3, 11]);
  Check('breakpoints carry the whole set', Pos('[3, 11]', Frame) > 0);

  Frame := EncodeSetBreakpoints(8, 'x.bas', []);
  Check('an empty set is legal -- it is how the last one is cleared',
    Pos('"lines" : []', Frame) > 0);

  Frame := EncodeSimple(9, pcStepOver);
  Check('a bare command needs nothing else', Pos('"cmd" : "stepOver"', Frame) > 0);

  CheckEq('command names match their DAP equivalents', 'stackTrace',
    PdbpCommandName(pcStackTrace));

  M := DecodePdbp('{"event":"stopped","reason":"breakpoint","path":"x.bas","line":11}');
  Check('a stopped event decodes', M.Valid and M.IsEvent);
  Check('  as the right event', M.Event = peStopped);
  Check('  with its reason', M.StopReason = psrBreakpoint);
  CheckEqInt('  and its line', 11, M.Line);
  CheckEq('  and its file', 'x.bas', M.Path);

  M := DecodePdbp('{"event":"exited","exitCode":2}');
  Check('an exit decodes', M.Valid and (M.Event = peExited));
  CheckEqInt('  with the code', 2, M.ExitCode);

  M := DecodePdbp('{"seq":1,"ok":true,"protocol":1,"capabilities":{"stepOut":true}}');
  Check('a response decodes', M.Valid and M.IsResponse);
  Check('  ok', M.Ok);
  CheckEqInt('  seq', 1, M.Seq);
  Check('  a declared capability is on', M.Capabilities.StepOut);
  Check('  an undeclared one defaults OFF, never assumed',
    not M.Capabilities.Evaluate);

  M := DecodePdbp('{"seq":2,"ok":false,"error":"no such frame"}');
  Check('a refusal decodes', M.Valid and not M.Ok);
  CheckEq('  with its reason', 'no such frame', M.ErrorText);

  M := DecodePdbp('{"seq":3,"ok":true,"frames":[' +
    '{"index":0,"name":"greet","path":"x.bas","line":4},' +
    '{"index":1,"name":"(main)","path":"x.bas","line":12}]}');
  CheckEqInt('a stack decodes', 2, Length(M.Frames));
  CheckEq('  innermost frame first', 'greet', M.Frames[0].Name);
  CheckEqInt('  with its line', 12, M.Frames[1].Line);

  M := DecodePdbp('{"seq":4,"ok":true,"variables":[' +
    '{"name":"count%","value":"3","kind":"int","scope":"local"}]}');
  CheckEqInt('variables decode', 1, Length(M.Variables));
  CheckEq('  the name keeps its suffix', 'count%', M.Variables[0].Name);
  CheckEq('  the host renders the value', '3', M.Variables[0].Value);

  { Desync must be a report, never a crash -- the other end is a separate
    program and may be any version, or not a PDBP speaker at all. }
  M := DecodePdbp('this is not json');
  Check('garbage is invalid, not fatal', not M.Valid);
  Check('  and says why', M.ParseError <> '');

  M := DecodePdbp('[1,2,3]');
  Check('a JSON array is not a frame', not M.Valid);

  M := DecodePdbp('{"event":"teleported"}');
  Check('an unknown event is refused rather than guessed at', not M.Valid);

  M := DecodePdbp('{"nothing":"useful"}');
  Check('an object that is neither event nor response is refused', not M.Valid);

  M := DecodePdbp('');
  Check('an empty line is refused', not M.Valid);
end;


{ ---------------------------------------------------------------------------
  THE TRANSPORT, WITHOUT A HOST.

  The editor listens and the debuggee connects, so a test can BE the debuggee:
  this opens a second socket in the same process, connects to the transport's own
  port, and writes bytes at it. No child process, no phosphor binary, nothing to
  find on disk -- which is what makes it honest on a machine that has neither.

  The three cases are the three ways a stream arrives, and the third is the one
  that matters: a chunk with no terminator must produce NOTHING. The runner this
  code is modelled on deliberately emits an unterminated tail after a moment of
  quiet, because a program that ends in PRINT would otherwise lose its last line;
  copying that here would hand half a frame to a JSON parser and end the session.
  --------------------------------------------------------------------------- }

type
  TFrameSink = class
    Frames: TStringList;
    Linked: Boolean;
    Ended: Boolean;
    procedure GotFrame(Sender: TObject; const AFrame: String);
    procedure GotLink(Sender: TObject);
    procedure GotEnd(Sender: TObject);
  end;

procedure TFrameSink.GotFrame(Sender: TObject; const AFrame: String);
begin
  Frames.Add(AFrame);
end;

procedure TFrameSink.GotLink(Sender: TObject);
begin
  Linked := True;
end;

procedure TFrameSink.GotEnd(Sender: TObject);
begin
  Ended := True;
end;

{ The drain is a TTimer, and this program creates no widgetset and runs no message
  loop, so nothing would ever fire it. Calling it directly is not a shortcut around
  the design: the timer's only job is to arrive on the main thread, and here we ARE
  the main thread. Give the reader a moment to deposit first. }
procedure Pump(ATransport: TDebugTransport; ASink: TFrameSink; ATimes: Integer);
var
  i: Integer;
begin
  for i := 1 to ATimes do
  begin
    Sleep(25);
    ATransport.Poll();
  end;
end;

procedure TestTransport;
var
  T: TDebugTransport;
  sink: TFrameSink;
  peer: LongInt;
  addr: TInetSockAddr;
  port: Word;
  s: String;
begin
  Group('debug transport');

  T := TDebugTransport.Create();
  sink := TFrameSink.Create();
  sink.Frames := TStringList.Create();
  try
    T.OnFrame := @sink.GotFrame;
    T.OnConnect := @sink.GotLink;
    T.OnDisconnect := @sink.GotEnd;

    port := T.Listen();
    { THE STEP fcl-net's TInetServer CANNOT TAKE. Bind on port 0 and the kernel
      picks; without fpGetSockName the number is unobtainable, and the number is
      exactly what has to go on the child's command line. }
    Check('a listener binds an ephemeral port and can say which', port <> 0);

    { NOT COSMETIC, AND NOT VISIBLE ANY OTHER WAY. The editor spawns the debuggee
      AFTER this, so a listener still in the inherit set is handed to the very
      program being debugged -- `ss -ltnp` showed exactly that on 2026-09-16,
      both processes on the same descriptor, and netstat on Windows cannot show
      it at all because it reports one owning PID. A boolean is asked for here
      rather than a handle: the invariant is the point. }
    Check('the listener is out of the set a child would inherit',
          T.HandlesArePrivate);

    peer := fpSocket(AF_INET, SOCK_STREAM, 0);
    Check('the debuggee side opens a socket', peer >= 0);
    FillChar(addr{%H-}, SizeOf(addr), 0);
    addr.sin_family := AF_INET;
    addr.sin_port := htons(port);
    addr.sin_addr.s_addr := htonl($7F000001);
    Check('and connects to the editor, not the other way round',
          fpConnect(peer, @addr, SizeOf(addr)) = 0);

    Pump(T, sink, 4);
    Check('the connection is reported on the main thread', sink.Linked);
    { And the accepted socket in its own right: POSIX does not pass the flag
      across accept, and the next process this editor starts -- a --version probe
      from Preferences, say -- would otherwise carry the live debug connection. }
    Check('and so is the accepted connection', T.HandlesArePrivate);

    { (a) two whole frames in one write }
    s := '{"a":1}' + #10 + '{"b":2}' + #10;
    fpSend(peer, @s[1], Length(s), 0);
    Pump(T, sink, 4);
    Check('two frames in one write arrive as two', sink.Frames.Count = 2);
    if sink.Frames.Count = 2 then
    begin
      Check('  the first is whole', sink.Frames[0] = '{"a":1}');
      Check('  and so is the second', sink.Frames[1] = '{"b":2}');
    end;

    { (b) one frame split across two writes }
    sink.Frames.Clear;
    s := '{"split":';
    fpSend(peer, @s[1], Length(s), 0);
    Pump(T, sink, 2);
    Check('half a frame produces nothing', sink.Frames.Count = 0);
    s := 'true}' + #10;
    fpSend(peer, @s[1], Length(s), 0);
    Pump(T, sink, 4);
    Check('the other half completes it', sink.Frames.Count = 1);
    if sink.Frames.Count = 1 then
      Check('  and it is the whole frame', sink.Frames[0] = '{"split":true}');

    { (c) a chunk with no terminator, and QUIET AFTERWARDS. This is the case the
      runner's FlushPrompt would get wrong. }
    sink.Frames.Clear;
    s := '{"never":"terminated"}';
    fpSend(peer, @s[1], Length(s), 0);
    Pump(T, sink, 8);
    Check('an unterminated tail is never emitted, however long the quiet',
          sink.Frames.Count = 0);

    { a CR before the LF is tolerated on input }
    s := #13 + #10;
    fpSend(peer, @s[1], Length(s), 0);
    Pump(T, sink, 4);
    Check('a CRLF terminator is accepted and the CR stripped',
          (sink.Frames.Count = 1) and (sink.Frames[0] = '{"never":"terminated"}'));

    { the editor writes back, and the terminator is the transport's job }
    Check('a frame can be sent to the debuggee', T.SendFrame('{"cmd":"pause"}'));

    { the peer goes away }
    CloseSocket(peer);
    Pump(T, sink, 8);
    Check('a closed peer is reported as a disconnection', sink.Ended);

    T.Stop();
    Check('stopping twice is safe', True);
    T.Stop();
  finally
    sink.Frames.Free;
    sink.Free;
    T.Free;
  end;
end;


{ ---------------------------------------------------------------------------
  THE SESSION DRIVER, WITHOUT A HOST AND WITHOUT A DISPLAY.

  What is worth testing here is the half that decides rather than the half that
  talks: which command may be sent in which state, and that one refused locally
  sends NOTHING. That rule is not caution. Measured against the real host: while
  the program runs it answers nothing at all, so an editor that sent `continue`
  mid-run would sit waiting for a reply that is not coming and look hung. A local
  refusal turns that into an immediate, visible no.

  A session with no transport is the honest fixture for it: every command must
  refuse, and none may reach a socket that does not exist.
  --------------------------------------------------------------------------- }

type
  TNoteSink = class
    Notes: TStringList;
    States: Integer;
    procedure GotNote(Sender: TObject; const AText: String);
    procedure GotState(Sender: TObject);
  end;

procedure TNoteSink.GotNote(Sender: TObject; const AText: String);
begin
  Notes.Add(AText);
end;

procedure TNoteSink.GotState(Sender: TObject);
begin
  Inc(States);
end;

procedure TestSession;
var
  S: TDebugSession;
  sink: TNoteSink;
  none: TPdbpLines;
begin
  Group('debug session: what may be asked when');

  none := nil;
  S := TDebugSession.Create(nil);
  sink := TNoteSink.Create();
  sink.Notes := TStringList.Create();
  try
    S.OnNote := @sink.GotNote;
    S.OnStateChange := @sink.GotState;

    Check('a fresh session is unavailable until a host is probed',
          S.State = dsUnavailable);
    Check('  and it says why in a sentence', S.UnavailableReason <> '');
    Check('  and nothing is stopped anywhere', (S.CurrentLine = 0) and (S.CurrentPath = ''));
    Check('  and the handshake has not happened', not S.Live);

    { EVERY command refuses, and each says which one it was. An editor that
      enabled its Debug menu on Available alone would otherwise send these into a
      socket that is not there. }
    sink.Notes.Clear;
    Check('Continue refuses when nothing is stopped', not S.Resume);
    Check('Step Over refuses', not S.StepOver);
    Check('Step Into refuses', not S.StepInto);
    Check('Step Out refuses', not S.StepOut);
    Check('Pause refuses when nothing is running', not S.Pause);
    Check('the call stack refuses', not S.RequestStackTrace);
    Check('variables refuse', not S.RequestVariables(0));
    Check('breakpoints refuse before a handshake', not S.SetBreakpoints('x.bas', none));
    Check('  and each refusal said something', sink.Notes.Count = 8);

    { A probe with no host is the state a fresh install is in. }
    S.Probe('');
    Check('probing no host at all is unavailable', S.State = dsUnavailable);
    Check('  and the reason names Preferences', Pos('Preferences', S.UnavailableReason) > 0);

    S.Probe('this-binary-does-not-exist-anywhere.exe');
    Check('probing a path that is not there is unavailable', S.State = dsUnavailable);

    { Listening is refused while unavailable, so a caller cannot spawn a child
      against a port that was never opened. }
    Check('listening refuses while unavailable',
          S.BeginListen('x.bas', none, False) = 0);

    Check('stopping an idle session is harmless', True);
    S.Stop(False);
  finally
    sink.Notes.Free;
    sink.Free;
    S.Free;
  end;
end;

begin
  WriteLn('PhosphorIDE unit checks');

  TestMessages;
  TestLanguage;
  TestHighlighter;
  TestBreakpoints;
  TestCompletion;
  TestProtocol;
  TestTransport;
  TestSession;

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn(Format('%d checks, all green.', [Checks]));
    Halt(0);
  end;

  WriteLn(Format('%d checks, %d FAILED.', [Checks, Failures]));
  Halt(Failures);
end.
