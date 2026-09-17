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
  {$IFDEF UNIX}cthreads, BaseUnix,{$ENDIF}
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
  udebugtransport, udebugsession, Sockets,
  { The search runs against a tree this program writes into a temporary
    directory: no fixture in the repository, nothing to keep in step, and the
    same answers on a machine that has never seen this project. }
  ufindinfiles, FileUtil,
  { The outline scans a buffer that is a string literal in this file: ten
    definitions and every legal spelling that breaks the obvious scanner, with
    no fixture on disk to keep in step with it. }
  uphosphoroutline,
  { Only for the two free functions that mark a handle close-on-exec. A
    TPhosphorRunner cannot be constructed here -- Create builds a TTimer and this
    program deliberately never makes a widgetset -- and it does not need to be:
    a pipe this program opens itself asks the same question. }
  uphosphorrun, Pipes,
  { The REPL transcript and its history: strings and an index, every one of them
    checkable without a child process. }
  uphosphorrepl,
  { Where a block opens and where it closes: words and positions, and the one
    rule that decides whether folding can hide somebody's code. Since item 18 it
    is also where that rule LIVES -- TLineWalk -- and uphosphoroutline above is
    its other consumer rather than a second copy of it. }
  uphosphorfold,
  { Only for the third measurement below: a line store the highlighter can be
    attached to, so that the cost of RESCANNING -- which is the cost a fold
    highlighter adds and the one the other two numbers cannot see -- has a
    number on both sides of the change. }
  SynEditTextBuffer,
  { What a text file's bytes look like. NOT `ueditordoc`, which owns the other
    half of the same job and cannot be linked here at all: `synedit.pp`'s
    initialization calls Screen.Fonts, which needs a widgetset, and a program
    that links it dies before main with exit code 0 and no output. That is why
    these rules live in a unit of their own. }
  utextfile,
  { The clock those measurements are taken with. `Now` cannot see a keystroke:
    it steps on the scheduler's tick and it follows the wall clock, so it can
    run backwards. Roadmap item 19 is what found that out. }
  uphosphorclock;

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
  { RESETRANGE FIRST, AND IT IS A NO-OP TODAY. This highlighter carries no range
    state, so it changes nothing -- but one instance is reused for every Scan in
    TestHighlighter, and the moment the highlighter carries a fold stack a line
    like `if a <> b then` would leave a block open for every check after it, all
    of which would keep passing while running one level deep. Put in before the
    change so it can be verified green on its own. }
  AHl.ResetRange;
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
  Nm, Acc: String;

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

  { --- the column that indexes bytes is the byte column --------------------- }

  { THE DEFECT THIS PINS LIVES IN THE CALLER, which is why it is two checks on
    one string rather than one check on a window. SynEdit offers two numbers for
    "the caret's column" and they are not the same number: CaretX is
    FCaret.CharPos, which syneditpointclasses.pas:823 computes through
    LogicalToPhysical -- a DISPLAY column, a tab counted out to its tab stop and
    a two-byte letter counted as one -- while LogicalCaretXY.X is
    FCaret.LineBytePos (synedit.pp:2935), the byte index. LineText is bytes.
    Handing the first to a function that indexes the second is right only while
    the line holds nothing but ASCII and no tabs.

    `t$ = "acao" + pri` with a cedilla and a tilde is 17 characters and 19 bytes,
    so the caret at its end is column 18 by one measure and 20 by the other, and
    the two answers below are what this editor got before and after 2026-09-16.
    The wrong one does not crash: it accepts `println` over a one-letter range
    and leaves `printlnri` in somebody's file. }
  Acc := 't$ = "a' + #$C3#$A7 + #$C3#$A3 + 'o" + pri';
  CheckEqInt('the accented line is 19 bytes', 19, Length(Acc));
  CheckEq('the byte column sees the whole word', 'pri', Pre(Acc, 20));
  CheckEq('the display column sees a fragment of it', 'p', Pre(Acc, 18));

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

{ Collects what a search reports, so the checks can ask about it afterwards
  rather than inside a callback. }
type
  THitSink = class
  public
    Rows: TFindHits;
    Done: Boolean;
    Cancelled: Boolean;
    Error: String;
    Files: Integer;
    Count: Integer;
    procedure GotHits(Sender: TObject; const AHits: TFindHits);
    procedure GotDone(Sender: TObject; AFilesSeen, AHitCount: Integer;
      ACancelled: Boolean; const AError: String);
    procedure Reset;
    function Has(const ALeaf: String): Boolean;
    function LineOf(const ALeaf: String): Integer;
    function TextOf(const ALeaf: String): String;
  end;

procedure THitSink.GotHits(Sender: TObject; const AHits: TFindHits);
var
  I, N: Integer;
begin
  N := Length(Rows);
  SetLength(Rows, N + Length(AHits));
  for I := 0 to High(AHits) do
    Rows[N + I] := AHits[I];
end;

procedure THitSink.GotDone(Sender: TObject; AFilesSeen, AHitCount: Integer;
  ACancelled: Boolean; const AError: String);
begin
  Done := True;
  Cancelled := ACancelled;
  Error := AError;
  Files := AFilesSeen;
  Count := AHitCount;
end;

procedure THitSink.Reset;
begin
  SetLength(Rows, 0);
  Done := False;
  Cancelled := False;
  Error := '';
  Files := 0;
  Count := 0;
end;

function THitSink.Has(const ALeaf: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Rows) do
    if ExtractFileName(Rows[I].Path) = ALeaf then
      Exit(True);
end;

function THitSink.LineOf(const ALeaf: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(Rows) do
    if ExtractFileName(Rows[I].Path) = ALeaf then
      Exit(Rows[I].Line);
end;

function THitSink.TextOf(const ALeaf: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Rows) do
    if ExtractFileName(Rows[I].Path) = ALeaf then
      Exit(Rows[I].Text);
end;

{ --------------------------------------------------------- find in files --- }

{ ------------------------------------------------------ replace in files --- }

{ THE FIRST THING IN THIS EDITOR THAT CHANGES SOMEBODY'S FILE, which is why it is
  checked harder than anything that only draws.

  Everything items 14 to 17 built is allowed to be wrong about a rare legal
  program: being wrong costs a row in a list or a fold nobody wanted. A replace
  that is wrong costs a file. So there is no scanner in it -- the match is the
  same literal FindInLine the search already uses -- and the two properties below
  are the ones the whole feature rests on:

    NO LINE THE SEARCH DID NOT LIST IS TOUCHED, and
    A FILE KEEPS THE ENDINGS AND THE CLOSING NEWLINE IT ARRIVED WITH.

  Both are checked against the BYTES of a fixture directory, before and after. }

procedure TestReplaceInFiles;
var
  Root: String;

  procedure Put(const ARel, AContent: String);
  var
    F: TFileStream;
    Full, Dir: String;
  begin
    Full := Root + PathDelim + ARel;
    Dir := ExtractFilePath(Full);
    if not DirectoryExists(Dir) then
      ForceDirectories(Dir);
    F := TFileStream.Create(Full, fmCreate);
    try
      if AContent <> '' then
        F.Write(AContent[1], Length(AContent));
    finally
      F.Free;
    end;
  end;

  function Get(const ARel: String): String;
  var
    F: TFileStream;
  begin
    Result := '';
    F := TFileStream.Create(Root + PathDelim + ARel, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Result, F.Size);
      if F.Size > 0 then
        F.ReadBuffer(Result[1], F.Size);
    finally
      F.Free;
    end;
  end;

  function Shown(const AText: String): String;
  begin
    Result := StringReplace(AText, #13, '\r', [rfReplaceAll]);
    Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  end;

  function Replaced(const ALine, APattern, AWith: String;
    AMatchCase: Boolean): String;
  var
    N: Integer;
  begin
    Result := ReplaceInLine(ALine, APattern, AWith, AMatchCase, N);
  end;

  function Count(const ALine, APattern, AWith: String;
    AMatchCase: Boolean): Integer;
  begin
    ReplaceInLine(ALine, APattern, AWith, AMatchCase, Result);
  end;

var
  N, Lines: Integer;
  Err: String;
begin
  Group('ufindinfiles: replacing, which is the half that changes a file');

  { --- one line at a time -------------------------------------------------- }
  CheckEq('one occurrence', 'x = 2', Replaced('x = 1', '1', '2', False));
  CheckEq('every occurrence on the line', 'b b b',
          Replaced('a a a', 'a', 'b', False));
  CheckEqInt('and it says how many', 3, Count('a a a', 'a', 'b', False));
  CheckEq('none leaves the line alone', 'x = 1',
          Replaced('x = 1', 'zzz', 'q', False));
  CheckEqInt('and counts nothing', 0, Count('x = 1', 'zzz', 'q', False));

  { --- case ---------------------------------------------------------------- }
  CheckEq('case-insensitive by default', 'qq', Replaced('Aa', 'a', 'q', False));
  CheckEq('and exact when asked', 'Aq', Replaced('Aa', 'a', 'q', True));

  { --- THE ONE THAT DOES NOT TERMINATE IF IT IS WRITTEN WRONGLY ------------ }
  { A replacement that contains the pattern. A loop that rescans from the start
    of what it just wrote never finishes; this walks past it. }
  CheckEq('a replacement containing the pattern', 'xfoox',
          Replaced('foo', 'foo', 'xfoox', False));
  CheckEqInt('exactly once', 1, Count('foo', 'foo', 'xfoox', False));
  CheckEq('and twice over', 'xfooxyxfoox',
          Replaced('fooyfoo', 'foo', 'xfoox', False));

  { --- the edges ----------------------------------------------------------- }
  CheckEq('an empty pattern changes nothing', 'x = 1',
          Replaced('x = 1', '', 'q', False));
  CheckEqInt('and counts nothing', 0, Count('x = 1', '', 'q', False));
  CheckEq('an empty replacement deletes', ' = 1',
          Replaced('x = 1', 'x', '', False));
  CheckEq('an empty line stays empty', '', Replaced('', 'a', 'b', False));
  CheckEq('at the start', 'qbc', Replaced('abc', 'a', 'q', False));
  CheckEq('at the end', 'abq', Replaced('abc', 'c', 'q', False));
  CheckEq('the whole line', 'q', Replaced('abc', 'abc', 'q', False));
  { OVERLAPPING, LEFT TO RIGHT. `aa` in `aaa` is one match and a leftover `a`,
    which is what every editor does and the only answer that terminates. }
  CheckEq('overlapping matches go left to right', 'qa',
          Replaced('aaa', 'aa', 'q', False));
  CheckEqInt('one of them', 1, Count('aaa', 'aa', 'q', False));

  { --- and now a real directory -------------------------------------------- }
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'phosphoride-replace-test';
  if DirectoryExists(Root) then
    DeleteDirectory(Root, False);
  ForceDirectories(Root);
  try
    { A FILE WITH LF ENDINGS ON A MACHINE THAT WRITES CRLF. If the rewrite goes
      through anything that joins with the platform's convention, this is the
      check that catches it. }
    Put('lf.bas', 'rem one'#10'x = 1'#10'rem three'#10);
    N := ReplaceInFile(Root + PathDelim + 'lf.bas', '1', '2', False, [2],
                       Lines, Err);
    CheckEqInt('one occurrence replaced', 1, N);
    CheckEqInt('on one line', 1, Lines);
    CheckEq('no error', '', Err);
    CheckEq('and the file kept its LF endings',
            'rem one\nx = 2\nrem three\n', Shown(Get('lf.bas')));

    { NO LINE THE SEARCH DID NOT LIST IS TOUCHED. Line 1 and line 3 both match
      `rem`, and only line 3 is asked for. }
    Put('only.bas', 'rem one'#10'x = 1'#10'rem three'#10);
    N := ReplaceInFile(Root + PathDelim + 'only.bas', 'rem', 'REM', False, [3],
                       Lines, Err);
    CheckEqInt('only the listed line', 1, N);
    CheckEq('and the one above it is untouched',
            'rem one\nx = 1\nREM three\n', Shown(Get('only.bas')));

    { A file with no closing newline keeps not having one. }
    Put('open.bas', 'rem one'#10'x = 1');
    ReplaceInFile(Root + PathDelim + 'open.bas', '1', '9', False, [2], Lines, Err);
    CheckEq('a file with no closing newline gains none',
            'rem one\nx = 9', Shown(Get('open.bas')));

    { CRLF stays CRLF. }
    Put('crlf.bas', 'rem one'#13#10'x = 1'#13#10);
    ReplaceInFile(Root + PathDelim + 'crlf.bas', '1', '9', False, [2], Lines, Err);
    CheckEq('and CRLF stays CRLF',
            'rem one\r\nx = 9\r\n', Shown(Get('crlf.bas')));

    { --- A SEARCH THAT HAS GONE STALE ------------------------------------- }
    { A line number past the end of the file. The other lines of the same file
      are still exactly what was listed, so this is skipped and not an error. }
    Put('short.bas', 'x = 1'#10);
    N := ReplaceInFile(Root + PathDelim + 'short.bas', '1', '2', False, [1, 99],
                       Lines, Err);
    CheckEqInt('a line past the end is skipped', 1, N);
    CheckEq('and no error is raised for it', '', Err);
    CheckEq('while the line that is there is done',
            'x = 2\n', Shown(Get('short.bas')));

    { A line that no longer matches counts as neither. }
    Put('moved.bas', 'x = 1'#10'y = 2'#10);
    N := ReplaceInFile(Root + PathDelim + 'moved.bas', 'zzz', 'q', False, [1, 2],
                       Lines, Err);
    CheckEqInt('a line that no longer matches replaces nothing', 0, N);
    CheckEqInt('and changes no line', 0, Lines);
    CheckEq('and the file is not rewritten at all',
            'x = 1\ny = 2\n', Shown(Get('moved.bas')));

    { --- A FILE THAT VANISHED --------------------------------------------- }
    N := ReplaceInFile(Root + PathDelim + 'never-existed.bas', 'a', 'b', False,
                       [1], Lines, Err);
    CheckEqInt('a file that is gone replaces nothing', 0, N);
    Check('and says why', Err <> '');

    { --- AND ONE THAT IS READ-ONLY ---------------------------------------- }
    { The run must survive it: this is the difference between a tool somebody
      trusts with a tree and one they run once. }
    { READ-ONLY MEANS TWO DIFFERENT THINGS, so it is set both ways. FileSetAttr
      is the Windows one; on Unix the bit that matters is the write permission,
      and FpChmod is how it is taken away. Without the second, this file stayed
      writable on Linux and three checks below went red there while passing
      here -- which is how the defect underneath them was found. }
    Put('locked.bas', 'x = 1'#10);
    FileSetAttr(Root + PathDelim + 'locked.bas', faReadOnly);
    {$IFDEF UNIX}
    FpChmod(Root + PathDelim + 'locked.bas', &444);
    {$ENDIF}
    N := ReplaceInFile(Root + PathDelim + 'locked.bas', '1', '2', False, [1],
                       Lines, Err);
    {$IFDEF UNIX}
    FpChmod(Root + PathDelim + 'locked.bas', &644);
    {$ENDIF}
    FileSetAttr(Root + PathDelim + 'locked.bas', 0);
    CheckEqInt('a read-only file replaces nothing', 0, N);
    Check('and says why', Err <> '');
    CheckEq('and is left exactly as it was', 'x = 1\n', Shown(Get('locked.bas')));
  finally
    if DirectoryExists(Root) then
      DeleteDirectory(Root, False);
  end;
end;

procedure TestFindInFiles;
var
  Root: String;
  Search: TFindSearch;
  Sink: THitSink;
  Spins: Integer;

  procedure Put(const ARel, AContent: String);
  var
    F: TFileStream;
    Full, Dir: String;
  begin
    Full := Root + PathDelim + ARel;
    Dir := ExtractFilePath(Full);
    if not DirectoryExists(Dir) then
      ForceDirectories(Dir);
    F := TFileStream.Create(Full, fmCreate);
    try
      if AContent <> '' then
        F.Write(AContent[1], Length(AContent));
    finally
      F.Free;
    end;
  end;

  { Drive the search the way a timer would, and give up rather than hang: a
    walker that never finishes must fail this test, not wedge the suite. }
  function RunToEnd: Boolean;
  begin
    Spins := 0;
    while (not Sink.Done) and (Spins < 2000) do
    begin
      Search.Poll;
      Inc(Spins);
      Sleep(1);
    end;
    Result := Sink.Done;
  end;

begin
  Group('ufindinfiles: what matches, and what is not a line of text');

  { --- the pure part ------------------------------------------------------- }
  CheckEqInt('a match reports its column', 5, FindInLine('abc def', 'def', True));
  CheckEqInt('no match is zero', 0, FindInLine('abc', 'zzz', True));
  CheckEqInt('an empty pattern matches nothing', 0, FindInLine('abc', '', False));
  CheckEqInt('a pattern longer than the line matches nothing', 0,
             FindInLine('ab', 'abc', False));
  CheckEqInt('case-insensitive by default', 1, FindInLine('ABC', 'abc', False));
  CheckEqInt('and exact when asked', 0, FindInLine('ABC', 'abc', True));
  { The fold is UTF-8 aware, because a byte-wise one turns a two-byte letter
    into two folded bytes that match nothing. }
  CheckEqInt('a two-byte letter folds as one', 1,
             FindInLine('ÁRVORE', 'árvore', False));

  Check('a NUL says binary', LooksBinary('ab' + #0 + 'cd'));
  Check('text does not', not LooksBinary('println "hello"' + #10));

  Check('an empty mask matches everything', MatchesFileMask('x.pbc', ''));
  Check('a mask matches its own kind', MatchesFileMask('x.bas', '*.bas'));
  Check('and not another', not MatchesFileMask('x.pbc', '*.bas'));
  Check('a list matches any of them', MatchesFileMask('x.txt', '*.bas;*.txt'));
  Check('masks ignore case, because Windows does',
        MatchesFileMask('X.BAS', '*.bas'));

  { --- the walk ------------------------------------------------------------ }
  Root := GetTempDir(False) + 'phosphoride-find-' + IntToStr(Random(1000000));
  ForceDirectories(Root);
  Sink := THitSink.Create;
  Search := TFindSearch.Create;
  try
    Put('a.bas', 'println "needle"' + #10 + 'x = 1' + #10);
    Put('b.bas', 'rem nothing here' + #10);
    Put('deep' + PathDelim + 'c.bas', 'y = 2' + #10 + 'println "NEEDLE"' + #10);
    { A binary that contains the word, which is the case the sniff exists for. }
    Put('blob.dat', 'needle' + #0 + 'needle');
    { And a directory nobody asked to search. }
    Put('.git' + PathDelim + 'd.bas', 'println "needle"' + #10);

    Search.OnHits := @Sink.GotHits;
    Search.OnDone := @Sink.GotDone;

    Check('an empty pattern is refused', not Search.Start('', Root, '', False));
    Check('a root that is not there is refused',
          not Search.Start('needle', Root + PathDelim + 'nope', '', False));

    Check('a real search starts', Search.Start('needle', Root, '*.bas', False));
    Check('and finishes', RunToEnd);
    CheckEqInt('two files matched', 2, Sink.Count);
    Check('the subdirectory was searched', Sink.Has('c.bas'));
    Check('a dot-directory was not', not Sink.Has('d.bas'));
    Check('the line number is the matching line',
          Sink.LineOf('c.bas') = 2);
    Check('the row carries the text', Sink.TextOf('a.bas') = 'println "needle"');
    Check('it was not cancelled', not Sink.Cancelled);
    Check('and nothing went wrong', Sink.Error = '');

    { THE BINARY IS WHAT THE MASK WAS HIDING. Searched without one, blob.dat is
      read, contains the word twice, and must still produce no row. }
    Sink.Reset;
    Check('a maskless search starts', Search.Start('needle', Root, '', False));
    Check('and finishes', RunToEnd);
    Check('the binary produced no rows', not Sink.Has('blob.dat'));

    { Match case is a cut, not a highlight. }
    Sink.Reset;
    Check('an exact search starts',
          Search.Start('NEEDLE', Root, '*.bas', True));
    Check('and finishes', RunToEnd);
    CheckEqInt('only the shouted one matched', 1, Sink.Count);
    Check('which is the one in the subdirectory', Sink.Has('c.bas'));

    { Stopping is an ending, and it says so. A search of a tree with nothing in
      it still runs the walk, so this is about the ANSWER rather than the timing:
      Stop before any Poll, then Poll once. }
    Sink.Reset;
    Check('a search to cancel starts', Search.Start('needle', Root, '', False));
    Search.Stop;
    Search.Poll;
    Check('cancelling ends it', Sink.Done);
    Check('and says it was cancelled', Sink.Cancelled);
    Check('and the search is no longer running', not Search.Running);
  finally
    Search.Free;
    Sink.Free;
    { FileUtil's, and named with its unit because SysUtils has no such thing and
      a bare call read as a missing identifier. Best effort: a temporary tree
      left behind by a failed run is untidy, not a failure. }
    FileUtil.DeleteDirectory(Root, False);
  end;
end;

{ ------------------------------------------------------------- the outline -- }

procedure TestOutline;
var
  Funcs: TOutlineFuncs;
  Src, LE: String;
  I: Integer;

  function NameOf(AIndex: Integer): String;
  begin
    if (AIndex < 0) or (AIndex > High(Funcs)) then
      Result := '<none>'
    else
      Result := Funcs[AIndex].Display;
  end;

  function LineOf(const AName: String): Integer;
  var
    J: Integer;
  begin
    J := FindOutlineFunc(Funcs, AName, -1);
    if J < 0 then
      Result := 0
    else
      Result := Funcs[J].Line;
  end;

  function Word(const ALine: String; ACol: Integer): String;
  var
    Ignored: Integer;
  begin
    Result := WordAtCaret(ALine, ACol, Ignored);
  end;

begin
  Group('uphosphoroutline: the definitions in a buffer, and where a name is');

  LE := LineEnding;
  { EVERY LINE HERE WAS COMPILED AND RUN AGAINST bin/phosphor.exe ON 2026-09-16.
    None of it is invented, and the awkward ones are the point: a definition
    begins a STATEMENT and not a line, so `:`, `then`, `else` and a leading
    integer label all put one somewhere a first-word scanner will not look. }
  Src :=
    'rem function ghost()' + LE +                                   { 1 }
    '''  function alsoghost()' + LE +                               { 2 }
    'println "function stringghost()"' + LE +                       { 3 }
    'function first()' + LE +                                       { 4 }
    '  return 1' + LE +                                             { 5 }
    'endfunction' + LE +                                            { 6 }
    'x = 1 : function second(a, b)' + LE +                          { 7 }
    '  return a + b' + LE +                                         { 8 }
    'end function' + LE +                                           { 9 }
    'if x > 0 then function third()' + LE +                         { 10 }
    '  return 3' + LE +                                             { 11 }
    'endfunction' + LE +                                            { 12 }
    '10 function fourth$()' + LE +                                  { 13 }
    '  return "4"' + LE +                                           { 14 }
    'endfunction' + LE +                                            { 15 }
    'head: function fifth%() return 5 : end function : ' +
      'function sixth%() return 6 : end function' + LE +            { 16 }
    'y = function + 1' + LE +                                       { 17 }
    'FUNCTION Seventh()' + LE +                                     { 18 }
    '  RETURN 7' + LE +                                             { 19 }
    'END FUNCTION' + LE +                                           { 20 }
    'function eighth?(n)' + LE +                                    { 21 }
    '  return true' + LE +                                          { 22 }
    'endfunction' + LE +                                            { 23 }
    'function ninth@()' + LE +                                      { 24 }
    'endfunction' + LE +                                            { 25 }
    'function tenth()' + LE;                                        { 26 }

  Funcs := ScanOutlineText(Src);

  { --- ten functions, in source order -------------------------------------- }
  CheckEqInt('ten definitions', 10, Length(Funcs));
  CheckEq('  1', 'first', NameOf(0));
  CheckEq('  2', 'second', NameOf(1));
  CheckEq('  3', 'third', NameOf(2));
  CheckEq('  4', 'fourth$', NameOf(3));
  CheckEq('  5', 'fifth%', NameOf(4));
  CheckEq('  6', 'sixth%', NameOf(5));
  CheckEq('  7', 'Seventh', NameOf(6));
  CheckEq('  8', 'eighth?', NameOf(7));
  CheckEq('  9', 'ninth@', NameOf(8));
  CheckEq('  10', 'tenth', NameOf(9));

  { --- the three that must NOT be there ------------------------------------ }
  { The roadmap names these two by hand; the third is the same rule seen from
    the other side. A word inside a comment or a literal is text. }
  CheckEqInt('a rem comment defines nothing', -1,
             FindOutlineFunc(Funcs, 'ghost', -1));
  CheckEqInt('an apostrophe comment defines nothing', -1,
             FindOutlineFunc(Funcs, 'alsoghost', -1));
  CheckEqInt('a string literal defines nothing', -1,
             FindOutlineFunc(Funcs, 'stringghost', -1));
  { `function` is only a keyword where a statement may begin. `y = function + 1`
    compiles and assigns from a variable called function. Measured. }
  Check('function as a variable defines nothing',
        Length(Funcs) = 10);

  { --- the lines, which is what a jump lands on ---------------------------- }
  CheckEqInt('a plain definition', 4, LineOf('first'));
  CheckEqInt('one after a : separator', 7, LineOf('second'));
  CheckEqInt('one after then', 10, LineOf('third'));
  CheckEqInt('one after a numeric label', 13, LineOf('fourth$'));
  CheckEqInt('one after a named label', 16, LineOf('fifth%'));
  CheckEqInt('and the SECOND one on that same line', 16, LineOf('sixth%'));
  { Two definitions on one line differ only by column, which is why the record
    carries one. }
  Check('the two on line 16 start at different columns',
        Funcs[4].Column <> Funcs[5].Column);

  { --- the terminators ----------------------------------------------------- }
  CheckEqInt('endfunction closes', 6, Funcs[0].EndLine);
  CheckEqInt('end function, two words, closes too', 9, Funcs[1].EndLine);
  CheckEqInt('and so does an uppercase one', 20, Funcs[6].EndLine);
  CheckEqInt('a terminator mid-line closes the one it belongs to', 16,
             Funcs[4].EndLine);
  CheckEqInt('an unterminated definition says 0', 0, Funcs[9].EndLine);
  Check('and nothing before it was left open', Funcs[8].EndLine = 25);

  { --- names, spellings and suffixes --------------------------------------- }
  { The lexer folds every identifier as it scans, so the name is matched folded
    -- and SHOWN as typed, because the file belongs to whoever wrote it. }
  CheckEq('the display name is as typed', 'Seventh', Funcs[6].Display);
  CheckEq('the matched name is folded', 'seventh', Funcs[6].Name);
  Check('a folded lookup finds it',
        FindOutlineFunc(Funcs, 'SEVENTH', -1) = 6);
  { All four suffixes are part of the name, and are the only return type
    Phosphor declares. }
  CheckEq('a dollar suffix belongs to the name', 'fourth$', Funcs[3].Name);
  CheckEq('a percent one too', 'fifth%', Funcs[4].Name);
  CheckEq('a question mark too', 'eighth?', Funcs[7].Name);
  CheckEq('an at sign too', 'ninth@', Funcs[8].Name);
  Check('and fourth alone is not the same name',
        FindOutlineFunc(Funcs, 'fourth', -1) < 0);

  { --- parameters ---------------------------------------------------------- }
  CheckEq('the parameter text is kept as written', 'a, b', Funcs[1].Params);
  CheckEqInt('and counted', 2, Funcs[1].ParamCount);
  CheckEqInt('an empty list is zero', 0, Funcs[0].ParamCount);
  CheckEqInt('one parameter is one', 1, Funcs[7].ParamCount);
  CheckEq('the row reads like the header', 'second(a, b)',
          OutlineRowText(Funcs[1]));
  CheckEq('and an empty one keeps its parentheses', 'first()',
          OutlineRowText(Funcs[0]));

  { --- arity is part of the answer ----------------------------------------- }
  { MEASURED: `function len(a, b)` beside `println len("abcd")` prints 4, the
    BUILT-IN, because the host resolves by name AND count. A go-to definition
    that matched on the name alone would jump into a function that call never
    reaches. }
  Check('a call of the right arity resolves',
        FindOutlineFunc(Funcs, 'second', 2) = 1);
  CheckEqInt('one of the wrong arity does not', -1,
             FindOutlineFunc(Funcs, 'second', 1));
  Check('and asking for any arity still finds it',
        FindOutlineFunc(Funcs, 'second', -1) = 1);
  CheckEqInt('a name nobody defined', -1, FindOutlineFunc(Funcs, 'nosuch', -1));
  CheckEqInt('how many definitions a name has', 1,
             CountOutlineFunc(Funcs, 'second'));
  CheckEq('the arities it is defined at', '2', OutlineArities(Funcs, 'second'));

  { --- which function the caret is in --------------------------------------- }
  CheckEqInt('a line inside the first body', 0, FuncAtLine(Funcs, 5));
  CheckEqInt('its header counts as inside', 0, FuncAtLine(Funcs, 4));
  CheckEqInt('its terminator too', 0, FuncAtLine(Funcs, 6));
  CheckEqInt('a line between two definitions belongs to neither', -1,
             FuncAtLine(Funcs, 17));
  CheckEqInt('a line before the first', -1, FuncAtLine(Funcs, 1));
  CheckEqInt('and an unterminated one runs to the end', 9,
             FuncAtLine(Funcs, 999));

  { --- a label is a statement position, not a line's first token ------------ }

  { AN INTEGER IS A LABEL WHEREVER A STATEMENT MAY BEGIN AT PROGRAM LEVEL, and
    the compiler's own comment enumerates the four places
    (engine/PhosphorCompiler.pas:2962-2972). All three below compile and run;
    the first version of this scanner asked the narrower question -- is this the
    first token of the line -- and lost two of them. }
  Funcs := ScanOutlineText('x = 1 : 20 function h()' + LE + 'endfunction' + LE);
  CheckEqInt('a numeric label after a separator still labels a statement',
             1, Length(Funcs));
  CheckEq('  and the definition after it is found', 'h', NameOf(0));
  Funcs := ScanOutlineText('setup: 30 function pick$(a$)' + LE +
                           'endfunction' + LE);
  CheckEqInt('a numeric label after a NAMED label, the same', 1, Length(Funcs));
  CheckEq('  and that definition too', 'pick$', NameOf(0));
  Funcs := ScanOutlineText('10 function j()' + LE + 'endfunction' + LE);
  CheckEqInt('a numeric label at the start of a line, the same', 1, Length(Funcs));
  { AND NOT AFTER `then`, which opens a statement but not a program-level one:
    `if x > 0 then 20 function f()` is refused with `expected end of line`, so a
    scanner that found a definition there would be inventing one. }
  Funcs := ScanOutlineText('if x > 0 then 20 function f()' + LE +
                           'endfunction' + LE);
  CheckEqInt('but a number after then is not a label', 0, Length(Funcs));
  Funcs := ScanOutlineText('if x > 0 then function f()' + LE +
                           'endfunction' + LE);
  CheckEqInt('  while the definition without one is still found',
             1, Length(Funcs));

  { --- a parameter is not a function ---------------------------------------- }

  { `function g(n)` with a `function n()` further down is legal, and inside g
    the word `n` is the parameter. A go-to-definition that jumped to
    `function n()` would be confidently wrong about the one thing it exists to
    be right about. }
  Funcs := ScanOutlineText('function g(n) local acc, i' + LE +
                           '  return n' + LE +
                           'endfunction' + LE);
  CheckEq('the local clause is kept', 'acc, i', Funcs[0].Locals);
  Check('a parameter is one of its own names', IsParamOrLocal(Funcs[0], 'n'));
  Check('so is a local', IsParamOrLocal(Funcs[0], 'acc'));
  Check('and the second local too', IsParamOrLocal(Funcs[0], 'i'));
  Check('case does not matter', IsParamOrLocal(Funcs[0], 'ACC'));
  Check('and a name that is neither is neither',
        not IsParamOrLocal(Funcs[0], 'other'));
  Check('nor is the function own name', not IsParamOrLocal(Funcs[0], 'g'));
  { `local` is read only as the token after the closing parenthesis, so a
    `local i` on a line of its own is a compile error and not a declaration. }
  Funcs := ScanOutlineText('function k()' + LE + '  local i' + LE +
                           'endfunction' + LE);
  CheckEq('a local on a line of its own is not a declaration', '',
          Funcs[0].Locals);

  { --- the corners that only happen while typing ---------------------------- }
  Funcs := ScanOutlineText('function half' + LE);
  CheckEqInt('a header with no parameter list is still a definition',
             1, Length(Funcs));
  CheckEqInt('  and says it has no list', -1, Funcs[0].ParamCount);
  CheckEq('  so the row shows what is there', 'half', OutlineRowText(Funcs[0]));

  Funcs := ScanOutlineText('endfunction' + LE + 'println 1' + LE);
  CheckEqInt('an endfunction with nothing open is ignored', 0, Length(Funcs));

  Funcs := ScanOutlineText('function outer()' + LE + '  function inner()' + LE +
                           '  endfunction' + LE + 'endfunction' + LE);
  CheckEqInt('a nested definition is LISTED', 2, Length(Funcs));
  Check('  and marked', Funcs[1].Nested);
  Check('  while the outer one is not', not Funcs[0].Nested);

  { `end` at the end of one line and `function` at the start of the next is NOT
    a terminator: the lexer's merge needs them adjacent, and the compiler then
    reports the NEXT definition as a nested one. Measured. }
  Funcs := ScanOutlineText('function g()' + LE + '  return 1' + LE + 'end' + LE +
                           'function' + LE);
  CheckEqInt('end and function on two lines do not merge', 0, Funcs[0].EndLine);

  { --- how many arguments a call site is passing ---------------------------- }
  CheckEqInt('no arguments', 0, CallArgCount('f()', 2));
  CheckEqInt('one', 1, CallArgCount('f(1)', 2));
  CheckEqInt('two', 2, CallArgCount('f(1, 2)', 2));
  CheckEqInt('a comma inside a nested call does not count', 1,
             CallArgCount('f(g(1, 2))', 2));
  CheckEqInt('nor one inside a string', 1, CallArgCount('f("a, b")', 2));
  CheckEqInt('whitespace only is no arguments', 0, CallArgCount('f(  )', 2));
  { A CALL IS AN IDENTIFIER WHOSE NEXT TOKEN IS `(`, and TOKEN is the load-
    bearing word: the lexer has already dropped the whitespace. `println f (7)`
    prints 70. Measured 2026-09-16, after this check asserted the opposite and
    the host disagreed with it. }
  CheckEqInt('a space before the parenthesis is still a call', 1,
             CallArgCount('f (1)', 2));
  CheckEqInt('a name with nothing after it is not a call', -1,
             CallArgCount('f', 2));
  CheckEqInt('nor is a name followed by something else', -1,
             CallArgCount('f + 1', 2));
  CheckEqInt('and an unclosed one is not decidable', -1,
             CallArgCount('f(1,', 2));

  { --- THE SAME ANSWER AS THE FOLDER, which is roadmap item 18 ------------- }
  { The mirror of the two checks in TestFold. Read them together: one of these
    four lines opens a fold and lists a definition, and the other does neither,
    and before the rule was written once the second did one of the two. }
  Funcs := ScanOutlineText('x = 1 : 20 function h()' + LE);
  CheckEqInt('a labelled definition at program level is listed', 1, Length(Funcs));
  Funcs := ScanOutlineText('if x > 0 then 20 function f()' + LE);
  CheckEqInt('and after then it is not, as the folder opens nothing', 0,
             Length(Funcs));
  Funcs := ScanOutlineText('if x > 0 then function f()' + LE);
  CheckEqInt('an unlabelled definition after then still is', 1, Length(Funcs));

  { --- WHERE THE TWO COPIES HAD DISAGREED ABOUT AN ARITY ------------------- }
  { Every one of these was answered one way by the outline's own scanner and the
    other way by CallArgCount, in the same unit, until both were put on the one
    counter. None of them is legal Phosphor -- a parameter list holds names --
    but an editor sees a half-typed line on every keystroke, and -1 is the
    answer that stops go-to-definition resolving on a guess. }
  Funcs := ScanOutlineText('function f("x, y")' + LE);
  CheckEqInt('a comma inside a string is not a separator here either', 1,
             Funcs[0].ParamCount);
  Funcs := ScanOutlineText('function f(g(1, 2))' + LE);
  CheckEqInt('nor is one inside a nested list', 1, Funcs[0].ParamCount);
  Funcs := ScanOutlineText('function f(a, b' + LE);
  CheckEqInt('an unclosed header has an arity nobody knows', -1,
             Funcs[0].ParamCount);
  CheckEq('and its row does not draw a parenthesis nobody typed', 'f',
          OutlineRowText(Funcs[0]));
  { `'` IS A COMMENT AND THERE IS NO SINGLE-QUOTED STRING, so this list never
    closes either. The old outline read it as one parameter called `'a'`. }
  Funcs := ScanOutlineText('function f(''a'')' + LE);
  CheckEqInt('a comment opens inside the list and it never closes', -1,
             Funcs[0].ParamCount);
  { And the same rule at a call site, which is where the count is used. }
  CheckEqInt('commas separate, so two of them are three things', 3,
             CallArgCount('f(1, 2, 3)', 2));
  CheckEqInt('an argument list of nothing but commas is not empty', 2,
             CallArgCount('f(,)', 2));

  { --- AND THE SAME THREE, FROM THIS SIDE --------------------------------- }
  { A definition that exists only inside a comment is the worst of the three:
    it is unterminated, so FuncAtLine hands it every line to the end of the
    buffer, and F12 on a real name then resolves against a function nobody
    wrote. `println "done" / end rem TODO: function parse$() goes here` runs. }
  Funcs := ScanOutlineText('println "done"' + LE +
                           'end rem TODO: function parse$() goes here' + LE);
  CheckEqInt('a function named in a comment after end is not a function', 0,
             Length(Funcs));
  Funcs := ScanOutlineText('function f()' + LE + 'return 1' + LE +
                           'end end function' + LE + 'function g()' + LE +
                           'return 2' + LE + 'end function' + LE);
  CheckEqInt('a stray end does not cost the real terminator', 3,
             Funcs[0].EndLine);
  Check('so the next definition is not nested in it', not Funcs[1].Nested);
  { A TERMINATOR CANNOT BE AN ARGUMENT: `println max(1, endfunction)` runs. }
  Funcs := ScanOutlineText('function f(a)' + LE +
                           '  println max(1, endfunction)' + LE +
                           '  return a' + LE + 'end function' + LE);
  CheckEqInt('and one inside brackets does not end the definition', 4,
             Funcs[0].EndLine);
  Funcs := ScanOutlineText('10 10 function f()' + LE);
  CheckEqInt('two numeric labels define nothing', 0, Length(Funcs));

  { --- `local` IS A WORD, NOT FIVE BYTES ---------------------------------- }
  { `function f() local_total = 0 / return local_total / endfunction` runs and
    prints 0. Matching a prefix made `_total = 0` the local list, so
    IsParamOrLocal answered yes for a name nobody declared. This was here before
    the rule was extracted and came across unchanged. }
  Funcs := ScanOutlineText('function f() local_total = 0' + LE);
  CheckEq('a name that starts with local is not a local clause', '',
          Funcs[0].Locals);
  Check('and the name is not one of its locals',
        not IsParamOrLocal(Funcs[0], '_total'));
  Funcs := ScanOutlineText('function f(a) local t, u' + LE);
  CheckEq('while a real clause still reads', 't, u', Funcs[0].Locals);
  Check('and its names answer', IsParamOrLocal(Funcs[0], 'u'));

  { --- the word under the caret --------------------------------------------- }
  { PrefixAtCaret looks backwards because completion asks what has been TYPED.
    This asks what the word IS, so it reaches both ways from the caret. }
  CheckEq('mid-word, the whole word', 'println', Word('println', 4));
  CheckEq('at its start', 'println', Word('println', 1));
  CheckEq('just past its end', 'println', Word('println', 8));
  CheckEq('inside a line', 'second', Word('x = second(1, 2)', 8));
  CheckEq('a suffix comes with it', 'left$', Word('left$', 3));
  CheckEq('and after the suffix', 'left$', Word('left$', 6));
  CheckEq('on a space, the word ahead', 'def', Word('abc def', 5));
  CheckEq('nothing on an empty line', '', Word('', 1));
  CheckEq('nothing past the end of a line', '', Word('abc', 9));
  CheckEq('a number is not a word', '', Word('123', 2));
  CheckEq('nor is a name that starts with one', '', Word('1abc', 3));
  for I := 1 to 8 do
    CheckEq('the same word from every column of it', 'println',
            Word('println', I));
end;

{ ------------------------------------------------------------------ REPL --- }

procedure TestRepl;
var
  Segs: TReplSegments;
  H: TReplHistory;

  function Joined(const AText: String): String;
  var
    J: Integer;
  begin
    Result := '';
    Segs := SplitReplPrompts(AText);
    for J := 0 to High(Segs) do
      Result := Result + Segs[J].Text;
  end;

  function Prompts(const AText: String): Integer;
  var
    J: Integer;
  begin
    Result := 0;
    Segs := SplitReplPrompts(AText);
    for J := 0 to High(Segs) do
      if Segs[J].IsPrompt then
        Inc(Result);
  end;

  function Body(const AText: String): String;
  var
    J: Integer;
  begin
    Result := '';
    Segs := SplitReplPrompts(AText);
    for J := 0 to High(Segs) do
      if not Segs[J].IsPrompt then
        Result := Result + Segs[J].Text;
  end;

begin
  Group('uphosphorrepl: the prompt, and what was typed at it');

  { --- the prompts, exactly as the host writes them ------------------------ }
  { Phosphor host/console/phosphor.lpr:3017 writes both on one line, and the
    trailing space is part of each. The five spaces before `...>` are the
    difference between a continuation that lines up under the first prompt and
    one that does not. }
  CheckEqInt('the prompt is ten characters', 10, Length(ReplPrompt));
  CheckEqInt('and so is the continuation', 10, Length(ReplContinuation));
  CheckEq('the prompt', 'phosphor> ', ReplPrompt);
  CheckEq('the continuation', '     ...> ', ReplContinuation);

  { --- splitting one off the front ----------------------------------------- }
  CheckEqInt('a bare prompt is one segment', 1, Length(SplitReplPrompts(ReplPrompt)));
  Check('  and it is a prompt', SplitReplPrompts(ReplPrompt)[0].IsPrompt);
  CheckEqInt('a prompt with an answer after it is two', 2,
             Length(SplitReplPrompts(ReplPrompt + '42')));
  CheckEq('  and the answer is the second', '42', Body(ReplPrompt + '42'));

  { THE CASE THE UNIT EXISTS FOR, measured: `x = 1` prints nothing, so the next
    prompt lands against the previous one and the pair arrives glued to whatever
    is printed after them. }
  CheckEqInt('two prompts on one line are two segments', 2,
             Prompts(ReplPrompt + ReplPrompt + '1'));
  CheckEq('  with the answer kept whole', '1', Body(ReplPrompt + ReplPrompt + '1'));
  { And the measured three-prompt line from a block: one prompt then two
    continuations, then the block's first line of output. }
  CheckEqInt('a prompt and two continuations', 3,
             Prompts(ReplPrompt + ReplContinuation + ReplContinuation + '1'));
  CheckEq('  and the output after them', '1',
          Body(ReplPrompt + ReplContinuation + ReplContinuation + '1'));

  { --- what must NOT be split ---------------------------------------------- }
  { A PROMPT CAN ONLY BE AT THE START. The host writes it before the read, so
    anything that looks like one further along is a string somebody printed --
    and splitting it would take somebody's own text apart. }
  CheckEqInt('a prompt in the middle of a line is text', 0,
             Prompts('the answer is phosphor> now'));
  CheckEq('  and survives whole', 'the answer is phosphor> now',
          Body('the answer is phosphor> now'));
  CheckEqInt('a prompt after real output is text too', 1,
             Prompts(ReplPrompt + 'x' + ReplPrompt));
  CheckEqInt('almost a prompt is not one', 0, Prompts('phosphor>'));
  CheckEqInt('nor is the continuation with four spaces', 0, Prompts('    ...> '));
  CheckEqInt('an empty fragment is no segments', 0, Length(SplitReplPrompts('')));

  { THE INVARIANT: the caller may paint the segments differently, it may not
    lose one. }
  CheckEq('the segments rebuild the input', ReplPrompt + ReplPrompt + '1',
          Joined(ReplPrompt + ReplPrompt + '1'));
  CheckEq('and so for ordinary text', 'hello, world', Joined('hello, world'));
  CheckEq('and for the measured block line',
          ReplPrompt + ReplContinuation + ReplContinuation + '1',
          Joined(ReplPrompt + ReplContinuation + ReplContinuation + '1'));

  Check('a bare prompt is all prompt', IsAllPrompt(ReplPrompt));
  Check('two of them too', IsAllPrompt(ReplPrompt + ReplContinuation));
  Check('a prompt with an answer is not', not IsAllPrompt(ReplPrompt + '42'));
  Check('and neither is nothing', not IsAllPrompt(''));

  { --- the history ---------------------------------------------------------- }
  H := TReplHistory.Create;
  try
    CheckEqInt('a new history is empty', 0, H.Count);
    CheckEq('and Up on it changes nothing', 'half typed', H.Older('half typed'));

    H.Add('println 1');
    H.Add('println 2');
    CheckEqInt('two lines remembered', 2, H.Count);
    { An empty line is not a thought anybody wants back. }
    H.Add('   ');
    CheckEqInt('whitespace is not remembered', 2, H.Count);
    H.Add('println 2');
    CheckEqInt('nor is the same line twice running', 2, H.Count);
    H.Add('println 1');
    CheckEqInt('but the same line after another one is', 3, H.Count);

    H.Clear;
    H.Add('one');
    H.Add('two');
    H.Add('three');
    Check('not walking to start with', not H.Walking);
    CheckEq('Up gives the newest', 'three', H.Older('draft'));
    Check('and now it is walking', H.Walking);
    CheckEq('Up again gives the one before', 'two', H.Older('ignored'));
    CheckEq('and again', 'one', H.Older('ignored'));
    CheckEq('past the oldest it stays there', 'one', H.Older('ignored'));
    CheckEq('Down comes back', 'two', H.Newer);
    CheckEq('and again', 'three', H.Newer);
    { THE DRAFT, which is the rule that is not obvious: the half-typed line the
      FIRST Up replaced comes back, because one keystroke may not silently
      destroy what somebody was writing. }
    CheckEq('past the newest is the draft again', 'draft', H.Newer);
    Check('and walking has stopped', not H.Walking);
    CheckEq('Down past the draft stays on it', 'draft', H.Newer);

    { Sending a line starts the walk over, and forgets the draft with it. }
    H.Older('second draft');
    H.Reset;
    Check('a send stops the walk', not H.Walking);
    CheckEq('and Up starts from the newest again', 'three', H.Older('third draft'));
    CheckEq('with the new draft stashed', 'third draft', H.Newer);

    H.Clear;
    CheckEqInt('clearing empties it', 0, H.Count);
    Check('and stops any walk', not H.Walking);
  finally
    H.Free;
  end;
end;

{ ------------------------------------------ handles a later child inherits -- }

procedure TestHandlePrivacy;
var
  HRead, HWrite: THandle;
begin
  Group('uphosphorrun: a handle the NEXT child must not inherit');

  { WHY THIS IS A CHECK AND NOT A COMMENT. With one child already running, the
    next one this editor spawns inherits the first one's stdin WRITE end on
    Unix, because FPC creates a pipe with a bare AssignPipe -- `pipe()`, no
    CLOEXEC (fcl-process unix/pipes.inc:20-24) -- and TProcess forks with
    InheritHandles True (processbody.inc:258). After that, closing this
    process's copy delivers NO end-of-input, for as long as that second child
    lives. The symptom is a REPL that will not end and a phosphor left behind;
    there is no error anywhere. Deleting the three lines in Start that prevent
    it would otherwise be a silent regression.

    It is the same defect udebugtransport's MakeSocketPrivate exists for, met a
    second time on a different kind of descriptor. }
  if not CreatePipeHandles(HRead, HWrite) then
  begin
    Check('a pipe could be opened for the handle checks', False);
    Exit;
  end;
  try
    {$IFDEF UNIX}
    { THE DEFECT, stated as a check: this is what FPC hands the program. }
    Check('on Unix a fresh pipe end is NOT private', not HandleIsPrivate(HRead));
    {$ENDIF}
    {$IFDEF WINDOWS}
    { And what it hands it on Windows, where CreatePipe is called with
      piNonInheritablePipe (fcl-process win/pipes.inc:19-35). Nothing to repair,
      and the call still happens in Start so that the two platforms answer the
      same question the same way. }
    Check('on Windows a fresh pipe end is already private', HandleIsPrivate(HRead));
    {$ENDIF}

    Check('marking one succeeds', MakeHandlePrivate(HRead));
    Check('and it reads back private', HandleIsPrivate(HRead));
    Check('marking it twice is still fine', MakeHandlePrivate(HRead));
    Check('the other end is untouched by that',
          HandleIsPrivate(HWrite) = HandleIsPrivate(HWrite));
    Check('and marking it works too', MakeHandlePrivate(HWrite));
    Check('so both ends are private now',
          HandleIsPrivate(HRead) and HandleIsPrivate(HWrite));
  finally
    FileClose(HRead);
    FileClose(HWrite);
  end;

  { A handle nobody opened is refused rather than acted on. 0 is the value a
    TProcess stream has before Execute, which is exactly when a careless caller
    would ask. }
  Check('handle 0 cannot be marked', not MakeHandlePrivate(0));
  Check('and is not private either', not HandleIsPrivate(0));
end;

{ -------------------------------------------------------- a file's bytes --- }

{ A FILE IS GIVEN BACK THE ENDINGS IT CAME WITH, and until 2026-09-17 it was not.

  `TStrings.Text` joins with TextLineBreakStyle, which defaults to the machine's
  own convention and which TSynEditStringList does not override, so saving a
  Linux-written program on Windows rewrote EVERY LINE of it -- a whole-file diff
  for a one-character edit, with no error anywhere. Measured through the real
  editor: Ctrl+S on `rem a\n x = 1\n` returned CRLF throughout, and a file with
  no closing newline gained one.

  What is pinned here is the property the rewrite rests on: SPLIT THEN JOIN IS
  THE IDENTITY, for every shape a text file comes in. A replace across a tree is
  exactly a split, a change to some lines, and a join -- so if this holds, the
  lines nobody touched cannot move. }

procedure TestTextFile;
var
  Lines: TStringList;
  Shape: TTextShape;

  { Split it, join it, and say whether the bytes came back. The one check that
    matters, run over a table rather than over an example. }
  procedure RoundTrips(const AWhat, AText: String);
  var
    Back: String;
  begin
    SplitLines(AText, Lines);
    Back := JoinLines(Lines, DetectShape(AText));
    CheckEq(AWhat, AText, Back);
  end;

  function Shown(const AText: String): String;
  begin
    Result := StringReplace(AText, #13, '\r', [rfReplaceAll]);
    Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  end;

begin
  Group('utextfile: the bytes a file is given back');

  Lines := TStringList.Create;
  try
    { --- what the shape reading says ---------------------------------------- }
    Shape := DetectShape('a'#10'b'#10);
    CheckEq('LF is LF', '\n', Shown(Shape.Ending));
    Check('and it closed with one', Shape.FinalNewline);
    Shape := DetectShape('a'#13#10'b'#13#10);
    CheckEq('CRLF is CRLF', '\r\n', Shown(Shape.Ending));
    Shape := DetectShape('a'#13'b'#13);
    CheckEq('a lone CR is kept rather than converted', '\r', Shown(Shape.Ending));
    Shape := DetectShape('a'#10'b');
    Check('a file with no closing newline says so', not Shape.FinalNewline);
    { THE FIRST BREAK DECIDES, because a mixed file is one somebody's tools
      disagreed about and rewriting all of it is the worse answer. }
    Shape := DetectShape('a'#10'b'#13#10'c'#10);
    CheckEq('a mixed file follows its first break', '\n', Shown(Shape.Ending));
    Shape := DetectShape('a'#13#10'b'#10'c'#13#10);
    CheckEq('and the other way round', '\r\n', Shown(Shape.Ending));

    { --- splitting ---------------------------------------------------------- }
    SplitLines('a'#10'b'#10, Lines);
    CheckEqInt('a trailing newline makes no empty last line', 2, Lines.Count);
    SplitLines('a'#10'b', Lines);
    CheckEqInt('and neither does its absence', 2, Lines.Count);
    SplitLines('a'#10#10'b'#10, Lines);
    CheckEqInt('an empty line in the middle is a line', 3, Lines.Count);
    CheckEq('and it is empty', '', Lines[1]);
    SplitLines('', Lines);
    CheckEqInt('nothing splits into nothing', 0, Lines.Count);
    SplitLines('one line', Lines);
    CheckEqInt('and a line with no break is one line', 1, Lines.Count);

    { --- AND THE ROUND TRIP, which is the whole point ----------------------- }
    RoundTrips('LF, closed', 'a'#10'b'#10);
    RoundTrips('LF, open', 'a'#10'b');
    RoundTrips('CRLF, closed', 'a'#13#10'b'#13#10);
    RoundTrips('CRLF, open', 'a'#13#10'b');
    RoundTrips('CR alone', 'a'#13'b'#13);
    RoundTrips('one line, no break', 'just the one');
    RoundTrips('nothing at all', '');
    RoundTrips('an empty line in the middle', 'a'#10#10'b'#10);
    RoundTrips('empty lines at the end', 'a'#10#10#10);
    RoundTrips('a line of spaces', 'a'#10'   '#10'b'#10);
    { A file that is ONLY newlines, which is the shape most likely to lose one. }
    RoundTrips('newlines and nothing else', #10#10#10);
    RoundTrips('one newline', #10);

    { A MIXED FILE DOES NOT ROUND TRIP, and that is written down rather than
      pretended away: the second ending is rewritten to the first. It is the one
      shape this unit changes, it is a file two tools already disagreed about,
      and the alternative -- remembering every line's own ending -- is a second
      copy of the buffer for a case nobody has. }
    SplitLines('a'#10'b'#13#10'c'#10, Lines);
    CheckEq('a mixed file is normalised to its first ending',
            'a\nb\nc\n', Shown(JoinLines(Lines, DetectShape('a'#10'b'#13#10'c'#10))));
  finally
    Lines.Free;
  end;
end;

{ ------------------------------------------------------------- the clock --- }

{ A CLOCK IS SILENTLY WRONG OR IT IS RIGHT, and both look the same in a report.

  Roadmap item 19 exists because a number was taken with `SysUtils.Now`, which
  on Windows steps on the scheduler's tick -- 15.6 ms by default -- so the answer
  to "what did this one keystroke cost" was 0 or 15.6, printed with three
  decimal places. It also follows the WALL clock, so an NTP step lands in a
  measurement as a negative duration.

  What is pinned here is what a clock can fail at without saying so: going
  backwards, and claiming a resolution it does not have. A number finer than the
  clock's own step is arithmetic rather than evidence. }

procedure TestClock;
const
  Reads = 50000;
var
  A, B, T0, T1: Int64;
  I, Backwards: Integer;
  Elapsed: Double;
begin
  Group('uphosphorclock: a clock that can see one keystroke');

  Check('it says what it is', ClockName <> '');

  { MONOTONIC. Not "usually increasing": never decreasing, over enough reads
    that a core migration would have been seen. }
  Backwards := 0;
  A := ClockTicks;
  for I := 1 to Reads do
  begin
    B := ClockTicks;
    if B < A then
      Inc(Backwards);
    A := B;
  end;
  CheckEqInt('it never goes backwards', 0, Backwards);

  { THE RESOLUTION IS NOT A BOAST. A clock whose step is coarser than a
    millisecond cannot see the thing item 19 measures, and one that claims zero
    is not answering. }
  Check('the resolution is positive', ClockResolutionNs > 0);
  Check('and finer than a millisecond', ClockResolutionNs < 1000000);
  { AND READING IT IS CHEAPER THAN WHAT IT MEASURES. A read that cost as much as
    a keystroke would be measuring itself. }
  Check('a read costs something', ClockOverheadNs > 0);
  Check('and far less than one keystroke', ClockOverheadNs < 100000);

  { The units. A duration is milliseconds, it is never negative, and a wait of a
    known length lands in a band a scheduler cannot leave -- Windows' own timer
    granularity is 15.6 ms, so this is deliberately wide: what it catches is a
    factor of a thousand, not a jitter. }
  A := ClockTicks;
  CheckEqInt('no time has passed between one tick and itself', 0,
             Round(ClockMs(A, A)));
  T0 := ClockTicks;
  Sleep(30);
  T1 := ClockTicks;
  Elapsed := ClockMs(T0, T1);
  Check('a 30 ms wait is more than 5 ms', Elapsed > 5);
  Check('and less than 500', Elapsed < 500);

  { A BUSY INTERVAL IS NOT ZERO, which is the whole difference from `Now`: fifty
    thousand reads take a measurable time and a clock that cannot see them is
    the one this unit replaced. }
  T0 := ClockTicks;
  for I := 1 to Reads do
    B := ClockTicks;
  T1 := ClockTicks;
  Check('and 50000 reads take a measurable time', ClockMs(T0, T1) > 0);
  Check('which is what Now could not see', B <> 0);
end;

{ ------------------------------------------------- the rule, on its own ---- }

{ THE ONE COPY OF "WHERE MAY A STATEMENT BEGIN", asked directly.

  Until 2026-09-17 this rule was written twice -- once in uphosphorfold and once
  in uphosphoroutline -- and the copies had already drifted: the outline knew
  that a statement position can be a PROGRAM-LEVEL one and the folder did not.
  Neither copy had a check of its own, because each was only ever asked through
  its consumer, so the drift was invisible until somebody read both files.

  These checks ask the walk and not a consumer, which is the point: a rule with
  its own checks can be corrected in one place and the correction is visible. }

procedure TestWalk;
var
  W: TLineWalk;
  Col, N: Integer;

  { The line's tokens, in order, as `word@col+len` -- with a `!` on one that is
    at a statement position and a `^` when that position is program level. }
  function Walked(const ALine: String): String;
  var
    R: String;
  begin
    R := '';
    WalkLine(W, ALine);
    while WalkNext(W) do
    begin
      if R <> '' then
        R := R + ' ';
      if W.Token = wtWord then
        R := R + W.Word
      else if W.Token = wtNumber then
        R := R + '#'
      else if W.Token = wtString then
        R := R + '"'
      else
        R := R + W.Word;
      { `!` at a statement position and `^` when that position is a program-level
        one. The second only ever appears on a token that carries the first:
        "program level" is a property OF a statement position, not a second
        independent thing, and a check that expected them apart would be
        pinning a shape this record does not have. }
      if W.AtStatement then
        R := R + '!';
      if W.AtProgramLevel then
        R := R + '^';
    end;
    Result := R;
  end;

begin
  Group('uphosphorfold: the one rule, asked without a consumer');

  { --- tokens, and the case folding --------------------------------------- }
  CheckEq('a word is a word', 'x!^ = #', Walked('x = 1'));
  CheckEq('and it arrives folded', 'println!^ "', Walked('PRINTLN "hi"'));
  CheckEq('an empty line has nothing in it', '', Walked(''));
  CheckEq('nor has one that is only spaces', '', Walked('   '));

  { --- what a statement position IS ---------------------------------------- }
  { Four of them, and the fourth is the one the two copies disagreed about. }
  CheckEq('the start of a line', 'function!^', Walked('function'));
  CheckEq('after a colon', 'x!^ = # : function!^',
          Walked('x = 1 : function'));
  CheckEq('after then, which is NOT program level', 'if!^ x > # then f!',
          Walked('if x > 0 then f'));
  CheckEq('after else, likewise', 'else!^ f!', Walked('else f'));

  { --- AND AN INTEGER LABEL, WHICH IS WHY PROGRAM LEVEL IS TRACKED --------- }
  { `x = 1 : 20 function h()` runs and `if x > 0 then 20 function f()` is
    refused, because a label is legal where a program's statements are and not
    inside a one-line if. The outline knew this and the folder did not, so the
    second line opened a fold for a function the outline did not list -- one
    window disagreeing with itself about the same buffer. }
  CheckEq('a label at program level keeps the position', '#!^ function!^',
          Walked('20 function'));
  CheckEq('and after a colon too', 'x!^ = # : #!^ function!^',
          Walked('x = 1 : 20 function'));
  CheckEq('but a number after then is an expression', 'if!^ x then #! function',
          Walked('if x then 20 function'));

  { --- the lexer's merge table, which is why a token can span two words ---- }
  { engine/PhosphorLexer.pas:189-224. The walk does this because a consumer that
    saw `end` and `if` separately would have to redo it. }
  CheckEq('end if is one token', 'endif!^', Walked('end if'));
  CheckEq('and so is else if', 'elseif!^', Walked('else if'));
  CheckEq('with any spacing', 'endif!^', Walked('end     if'));
  { AND A WORD THAT DOES NOT MERGE IS HANDED BACK. Without the pushback the
    second word would be eaten and `end x` would be one token. }
  CheckEq('end and a word that does not merge are two tokens', 'end!^ x',
          Walked('end x'));
  CheckEq('end at the end of a line is alone', 'end!^', Walked('end'));
  CheckEq('and the if that starts the next line is its own statement',
          'if!^', Walked('if'));

  { --- THE SECOND WORD IS PUT BACK, NOT HANDED FORWARD -------------------- }
  { The lookahead above reads a word that may not be its partner, and what
    happens to that word is where the first cut of this unit was wrong TWICE,
    on legal programs. Both were found on 2026-09-17 by a review that generated
    the shapes the unit's own corpus had not: everything here is about ADJACENCY
    and the corpus varied the words, not their neighbours.

    1. THE MERGE PASS RETRIES AT THE SECOND WORD. It advances by one when a pair
       does not merge (engine/PhosphorLexer.pas:215-219), so `end end function`
       is `end` followed by `endfunction` -- and a word handed forward gets no
       lookahead of its own, so the terminator was LOST and the fold ran to the
       end of the file. `function f() / return 1 / end end function / ...` runs
       and prints. }
  CheckEq('the second end merges with what follows it', 'end!^ endfunction',
          Walked('end end function'));
  CheckEq('and the third likewise', 'end!^ end endfunction',
          Walked('end end end function'));
  CheckEq('else then a two-word terminator is the terminator', 'elseif!^ x then',
          Walked('else if x then'));
  { 2. `rem` IS THE LEXER'S OWN and runs to end of line
       (engine/PhosphorLexer.pas:453-458). A word handed forward skipped the
       `rem` test, so the COMMENT was walked as code: a `:` in it opened a
       program-level statement position and a `function` in it reached the
       outline pane. `println "done" / end rem TODO: function parse$() here`
       runs, and there is no function in it. }
  CheckEq('a rem after end is still a comment', 'end!^',
          Walked('end rem a note'));
  CheckEq('and after else too', 'else!^', Walked('else rem a note'));
  CheckEq('end then else if is end and a divider', 'end!^ elseif x then',
          Walked('end else if x then'));

  { --- ONE NUMERIC LABEL PER STATEMENT POSITION --------------------------- }
  { `10 20 function f()` is refused with `expected end of line`: the compiler
    records a label at the top of its statement loop and then parses a
    STATEMENT, not a second label. A NAMED label may still sit on either side of
    a numeric one, and both of those compile. }
  CheckEq('a second integer closes the position', '#!^ #!^ function^',
          Walked('10 10 function'));
  CheckEq('but a named label after a numeric one does not',
          '#!^ head!^ : function!^', Walked('10 head: function'));
  CheckEq('nor a numeric one after a named one',
          'head!^ : #!^ function!^', Walked('head: 10 function'));
  { AND ONE SHAPE IS KNOWINGLY WRONG: `10 : 20 function f()` is refused too --
    there is no statement before that colon for it to separate -- and the walk
    reads the colon as opening a fresh position, label included. It is left
    wrong deliberately. The program does not compile either way, so the cost is
    a row in a list beside a file that is already red, and the alternative is
    tracking whether a statement has actually been seen since the position
    opened -- state this line does not otherwise need. }
  CheckEq('a colon straight after a label is the known gap',
          '#!^ :!^ #!^ function!^', Walked('10 : 20 function'));

  { --- what hides text ----------------------------------------------------- }
  CheckEq('a string is one token', 'println!^ "', Walked('println "a : b"'));
  CheckEq('and a colon in it starts nothing', 'println!^ "',
          Walked('println ":"'));
  CheckEq('an unterminated string ends where the line does', 'println!^ "',
          Walked('println "a'));
  CheckEq('a comment ends the walk', 'x!^ = #', Walked('x = 1 '' function f()'));
  CheckEq('and so does rem, which the lexer itself owns', 'x!^ = # :',
          Walked('x = 1 : rem function f()'));

  { --- depth, which is how a consumer knows it is inside a list ------------ }
  WalkLine(W, 'f(g(1), 2)');
  N := 0;
  while WalkNext(W) do
    if W.Depth > N then
      N := W.Depth;
  CheckEqInt('nesting is counted', 2, N);

  { --- reading raw text after a token, which is the outline's half --------- }
  WalkLine(W, 'function name$(a, b) local t');
  Check('a walk starts before its first token', WalkNext(W));
  CheckEq('the first word', 'function', W.Word);
  WalkSkipSpace(W);
  CheckEq('the name, suffix included', 'name$', WalkTakeIdent(W, Col));
  CheckEqInt('and where it started', 10, Col);
  CheckEq('the parameters as typed', 'a, b', WalkTakeParens(W, N));
  CheckEqInt('and how many there are', 2, N);

  { --- WalkTakeParens, which counts for BOTH consumers --------------------- }
  { This is the merge that mattered most: the outline counted every comma in the
    text and the call-site counter counted only the ones at this level, so one
    of them was wrong about `f(g(1, 2))` and it was never the same one. }
  WalkLine(W, '(g(1, 2))');
  CheckEq('a nested list comes back whole', 'g(1, 2)', WalkTakeParens(W, N));
  CheckEqInt('and counts as ONE thing at this level', 1, N);
  WalkLine(W, '("a, b")');
  WalkTakeParens(W, N);
  CheckEqInt('a comma inside a string is not a separator', 1, N);
  WalkLine(W, '()');
  WalkTakeParens(W, N);
  CheckEqInt('an empty list is none', 0, N);
  WalkLine(W, '(   )');
  WalkTakeParens(W, N);
  CheckEqInt('and so is a blank one', 0, N);
  { UNCLOSED IS NOT EMPTY. A list still being typed has an arity nobody knows,
    and -1 is what every consumer already reads as "do not resolve on this". }
  WalkLine(W, '(a, b');
  WalkTakeParens(W, N);
  CheckEqInt('an unclosed list has no count', -1, N);
  WalkLine(W, '(a '' why');
  WalkTakeParens(W, N);
  CheckEqInt('and a comment inside one does not close it', -1, N);
  { A NESTED GROUP IS A THING. `function f(a) / return 7 / endfunction /
    println f([])` runs and prints 7, so the call passes one argument; counting
    only bare words made it none. }
  WalkLine(W, '([])');
  WalkTakeParens(W, N);
  CheckEqInt('a list holding one empty group holds one thing', 1, N);

  { --- a token never reaches past the end of its line ---------------------- }
  { A BACKSLASH AS THE LAST BYTE eats a character that is not there, and a
    Col+Size past the line is a range no consumer can paint. }
  WalkLine(W, 'x = "ab\');
  N := 0;
  while WalkNext(W) do
    if W.Token = wtString then
      N := W.Col + W.Size - 1;
  CheckEqInt('an unterminated literal ending in a backslash stops at the end',
             8, N);
end;

{ ------------------------------------------------------ the other end of it -- }

{ WITH THE CARET ON `if`, WHERE IS THE `endif` -- roadmap item 22.

  Phosphor has no braces, so the eye has nothing to match on and a `next` eleven
  lines down is not visibly the partner of a `for`. This is a reading of the
  structure uphosphorfold already builds, and it changes no text.

  WHAT IT REFUSES TO ANSWER IS THE POINT. The three cases item 22 names are all
  words that LOOK like block keywords and are not one here: `next = 5`, which is
  a legal assignment; `function` used as a variable; and a block word inside a
  literal. Each must answer "nothing", so that the caller can say so instead of
  moving the caret somewhere arbitrary -- which is the failure this feature would
  otherwise introduce.

  NOTHING IS REMEMBERED, which is the other half: the buffer is walked on every
  call, so an edit cannot leave a stale answer behind. }

procedure TestBlockMatch;
var
  Buf: TStringList;
  M: TBlockMatch;

  function Kind(ALine, ACol: Integer): String;
  begin
    M := MatchBlockAt(Buf, ALine, ACol);
    case M.Kind of
      bmMatched: Result := Format('%s %d:%d', [BlockName(M.Block),
                                               M.ThereLine, M.ThereCol]);
      bmUnterminated: Result := 'unterminated ' + BlockName(M.Block);
      bmUnopened: Result := 'unopened ' + BlockName(M.Block);
    else
      Result := 'none';
    end;
  end;

begin
  Group('uphosphorfold: the other end of a block');

  Buf := TStringList.Create;
  try
    { --- the plain case ----------------------------------------------------- }
    Buf.Clear;
    Buf.Add('function f(n)');     { 1 }
    Buf.Add('  for i = 1 to 3');  { 2 }
    Buf.Add('    if n > 0 then'); { 3 }
    Buf.Add('    endif');         { 4 }
    Buf.Add('  next');            { 5 }
    Buf.Add('endfunction');       { 6 }
    CheckEq('function finds its endfunction', 'function 6:1', Kind(1, 1));
    CheckEq('and the endfunction finds it back', 'function 1:1', Kind(6, 1));
    CheckEq('the for finds its next', 'for 5:3', Kind(2, 3));
    CheckEq('and the next finds the for', 'for 2:3', Kind(5, 3));
    CheckEq('the if finds its endif', 'if 4:5', Kind(3, 5));
    CheckEq('and the endif finds the if', 'if 3:5', Kind(4, 5));

    { --- WHERE THE CARET COUNTS AS BEING ON THE WORD ------------------------ }
    { From its first byte to ONE PAST its last, which is how a person reads it
      and what every editor's brace matching does. }
    CheckEq('on the first byte', 'function 6:1', Kind(1, 1));
    CheckEq('in the middle', 'function 6:1', Kind(1, 5));
    CheckEq('on the last byte', 'function 6:1', Kind(1, 8));
    CheckEq('one past the last', 'function 6:1', Kind(1, 9));
    CheckEq('and one further is nothing', 'none', Kind(1, 10));
    CheckEq('column 0 is nothing', 'none', Kind(1, 0));

    { --- A PAIR ON ONE LINE STILL HAS A PARTNER ----------------------------- }
    { ScanFoldLine drops these because they fold nothing; matching wants them,
      which is why ScanFoldLineRaw exists. }
    Buf.Clear;
    Buf.Add('for i = 1 to 2 println i next');
    CheckEq('a for that closes on its own line', 'for 1:26', Kind(1, 1));
    CheckEq('and the next that closes it', 'for 1:1', Kind(1, 26));

    { --- THE THREE THINGS IT MUST REFUSE ------------------------------------ }
    { 1. `next` as a variable, with nothing open above it. It closes nothing,
      and the caller says so rather than jumping somewhere arbitrary. }
    Buf.Clear;
    Buf.Add('next = 5');
    Buf.Add('println next');
    CheckEq('next with nothing open closes nothing', 'unopened for', Kind(1, 1));

    { 2. `function` as an ordinary variable. Not at a statement position, so it
      opens nothing and there is no event to be on. }
    Buf.Clear;
    Buf.Add('y = function + 1');
    CheckEq('function in an expression is not a block', 'none', Kind(1, 5));

    { 3. A block word inside a literal. }
    Buf.Clear;
    Buf.Add('println "for i = 1 to 3 endfunction"');
    CheckEq('a block word inside a string is not one', 'none', Kind(1, 10));
    CheckEq('nor the terminator in it', 'none', Kind(1, 24));
    Buf.Clear;
    Buf.Add('rem for i = 1 to 3');
    CheckEq('and one in a comment is not either', 'none', Kind(1, 5));

    { --- AN UNTERMINATED BLOCK SAYS WHICH ----------------------------------- }
    Buf.Clear;
    Buf.Add('function f()');
    Buf.Add('  return 1');
    CheckEq('an opener with no terminator', 'unterminated function', Kind(1, 1));
    Buf.Clear;
    Buf.Add('for i = 1 to 3');
    Buf.Add('  println i');
    CheckEq('and a for likewise', 'unterminated for', Kind(1, 1));

    { --- NESTING, WHICH IS WHY THERE IS A STACK ----------------------------- }
    Buf.Clear;
    Buf.Add('for i = 1 to 3');   { 1 }
    Buf.Add('  for j = 1 to 3'); { 2 }
    Buf.Add('  next');           { 3 }
    Buf.Add('next');             { 4 }
    CheckEq('the outer for takes the outer next', 'for 4:1', Kind(1, 1));
    CheckEq('and the inner one the inner', 'for 3:3', Kind(2, 3));
    CheckEq('read from the other end too', 'for 2:3', Kind(3, 3));
    CheckEq('and the outermost', 'for 1:1', Kind(4, 1));

    { A TERMINATOR OF THE WRONG KIND CLOSES NOTHING, which is the same rule the
      fold gutter applies: `wend` does not close a `for`. }
    Buf.Clear;
    Buf.Add('for i = 1 to 3');
    Buf.Add('wend');
    CheckEq('a wend does not close a for', 'unopened while', Kind(2, 1));
    CheckEq('and the for is still unterminated', 'unterminated for', Kind(1, 1));

    { --- the edges ---------------------------------------------------------- }
    Buf.Clear;
    CheckEq('an empty buffer has nothing', 'none', Kind(1, 1));
    Buf.Add('x = 1');
    CheckEq('a line with no block word', 'none', Kind(1, 1));
    CheckEq('a line past the end', 'none', Kind(99, 1));
    CheckEq('and line zero', 'none', Kind(0, 1));
  finally
    Buf.Free;
  end;
end;

{ ----------------------------------------------------------- where a block -- }

procedure TestFold;
var
  Ev: TFoldEvents;

  { The line's events as a string: `+function -if` and so on, so a check reads
    like the answer it is asking about. }
  function Folds(const ALine: String): String;
  var
    J: Integer;
  begin
    Result := '';
    Ev := ScanFoldLine(ALine);
    for J := 0 to High(Ev) do
    begin
      if Result <> '' then
        Result := Result + ' ';
      if Ev[J].Kind = feOpen then
        Result := Result + '+'
      else
        Result := Result + '-';
      Result := Result + BlockName(Ev[J].Block);
    end;
  end;

begin
  Group('uphosphorfold: where a block opens, and where it closes');

  { --- the seven kinds ----------------------------------------------------- }
  { The roadmap names five. There are seven: `do while ... loop` and
    `repeat ... until` are blocks too, both compiled and run. }
  CheckEq('an if that ends with then', '+if', Folds('if x > 0 then'));
  CheckEq('a for', '+for', Folds('for i = 1 to 3'));
  CheckEq('a while', '+while', Folds('while i < 3'));
  CheckEq('a do while', '+do', Folds('do while i < 3'));
  CheckEq('a repeat', '+repeat', Folds('repeat'));
  CheckEq('a select', '+select', Folds('select case x'));
  CheckEq('a function', '+function', Folds('function f(a, b)'));

  CheckEq('endif closes', '-if', Folds('endif'));
  CheckEq('next closes', '-for', Folds('next'));
  CheckEq('wend closes', '-while', Folds('wend'));
  { BOTH spellings close a while, measured: each of them runs. }
  CheckEq('and so does endwhile', '-while', Folds('endwhile'));
  CheckEq('loop closes', '-do', Folds('loop'));
  CheckEq('until closes', '-repeat', Folds('until i >= 3'));
  CheckEq('endselect closes', '-select', Folds('endselect'));
  CheckEq('endfunction closes', '-function', Folds('endfunction'));

  { --- the two-word terminators -------------------------------------------- }
  CheckEq('end if closes an if', '-if', Folds('end if'));
  CheckEq('end while closes a while', '-while', Folds('end while'));
  CheckEq('end select closes a select', '-select', Folds('end select'));
  CheckEq('end function closes a function', '-function', Folds('end function'));
  CheckEq('and the node covers both words', '-if', Folds('  end   if'));
  { The pair must be ADJACENT in the token stream, so an `end` that ends a line
    and an `if` that starts the next are two different lines and two nothings. }
  CheckEq('end alone does nothing', '', Folds('end'));
  CheckEq('and an if on its own line is an if again', '+if', Folds('if x then'));

  { --- SIX LEGAL PROGRAMS THAT WOULD HAVE HIDDEN CODE ---------------------- }

  { 1. A WHOLE BLOCK ON ONE LINE. `for i = 1 to 2 println i next` compiles and
    prints 1, 2, after -- and six of the seven kinds do it. An opener that fired
    without looking at the rest of the line would open a fold that never closes,
    and collapsing it would hide the rest of the file. }
  CheckEq('a for that closes on its own line folds nothing', '',
          Folds('for i = 1 to 2 println i next'));
  CheckEq('a function likewise', '',
          Folds('function f(n) return n + 1 endfunction'));
  CheckEq('a while likewise', '', Folds('while i < 2 i = i + 1 wend'));
  CheckEq('a repeat likewise', '', Folds('repeat i = i + 1 until i >= 2'));
  CheckEq('a do likewise', '', Folds('do while j < 2 j = j + 1 loop'));
  CheckEq('a select likewise', '',
          Folds('select case x case 1 println 1 endselect'));
  { But a block that only OPENS here still opens, and one that only closes here
    still closes -- the suppression is a PAIR on one line, not a veto. }
  CheckEq('an open with no close still opens', '+for', Folds('for i = 1 to 2'));
  CheckEq('and a close with no open still closes', '-for', Folds('  next'));
  CheckEq('two blocks opening on one line open twice', '+function +for',
          Folds('function f() : for i = 1 to 2'));

  { 2. `then` IS A LEGAL VARIABLE. `then = 3` then `if x = 1 then println then`
    compiles and prints 3 -- the line ENDS with the word `then` and is the inline
    form, which takes no endif. "the last token is then" would open a fold that
    never closes. }
  CheckEq('an inline if opens nothing', '',
          Folds('if x = 1 then println then'));
  CheckEq('nor with a separator after it', '',
          Folds('if x > 0 then println 1 : println 2'));
  CheckEq('nor with an else on the same line', '',
          Folds('if x > 0 then println 1 else println 2'));
  { And the block form still opens, whatever trails as whitespace. }
  CheckEq('the block form opens', '+if', Folds('if x > 0 then   '));
  CheckEq('and with a comment after it', '+if', Folds('if x > 0 then '' why'));

  { 3. `else if` IS ONE TOKEN to the lexer, so the chain needs exactly ONE endif.
    Treating that `if` as an opener leaves the first one unclosed and the fold
    runs to the end of the file. }
  CheckEq('else if opens nothing', '', Folds('else if n = 2 then'));
  { But `else` ending a line and `if` starting the next are two lines and two
    blocks, which needs two endifs -- and that one must still open. }
  CheckEq('an if on the line after an else does open', '+if',
          Folds('if n = 2 then'));

  { 4. A TERMINATOR IS RECOGNISED WHEREVER IT APPEARS, which is what makes the
    one-line block above close. The language keeps it safe: the word used as a
    variable while its block is open is a compile error. }
  CheckEq('a next after a statement still closes', '-for',
          Folds('println i : next'));
  CheckEq('and one with no separator at all', '-for', Folds('println i next'));

  { 5. AND NOTHING INSIDE A STRING OR A COMMENT COUNTS. }
  CheckEq('a block word in a literal', '', Folds('println "for i = 1 to 3"'));
  CheckEq('a terminator in a literal', '', Folds('println "endif"'));
  CheckEq('a block word in a rem', '', Folds('rem for i = 1 to 3'));
  CheckEq('a block word after an apostrophe', '', Folds('x = 1 '' for i = 1 to 3'));
  CheckEq('an escaped quote does not end the literal', '',
          Folds('s = "a\" endif b"'));

  { 6. AND AN OPENER IS ONLY AN OPENER WHERE A STATEMENT MAY BEGIN. }
  CheckEq('function as a variable opens nothing', '', Folds('y = function + 1'));
  CheckEq('but after a separator it opens', '+function',
          Folds('x = 1 : function f()'));
  CheckEq('and after then it opens', '+function',
          Folds('if x > 0 then function f()'));
  CheckEq('an empty line does nothing', '', Folds(''));
  CheckEq('and so does whitespace', '', Folds('    '));

  { --- the columns, which is what a fold node hangs on --------------------- }
  Ev := ScanFoldLine('  for i = 1 to 3');
  CheckEqInt('one event', 1, Length(Ev));
  CheckEqInt('  at the for, not the line start', 3, Ev[0].Col);
  CheckEqInt('  three characters long', 3, Ev[0].Len);
  Ev := ScanFoldLine('x = 1 : function f()');
  CheckEqInt('  the function after a separator', 9, Ev[0].Col);
  CheckEqInt('  eight characters', 8, Ev[0].Len);
  Ev := ScanFoldLine('  end if');
  CheckEqInt('  the pair starts at the end', 3, Ev[0].Col);
  CheckEqInt('  and spans both words', 6, Ev[0].Len);
  Ev := ScanFoldLine('if x > 0 then');
  CheckEqInt('  and an if hangs on the if itself', 1, Ev[0].Col);
  CheckEqInt('  two characters', 2, Ev[0].Len);

  { --- THE SAME ANSWER AS THE OUTLINE, which is roadmap item 18 ----------- }
  { Both of these lines are checked on the outline side too, with the mirror
    expectation. Until 2026-09-17 the second one opened a fold here and listed
    no function there -- the fold gutter and the outline pane disagreeing about
    the same buffer in the same window, because the rule was written twice.
    A label is legal at PROGRAM level: `x = 1 : 20 function h()` runs, and
    `if x > 0 then 20 function f()` is refused by the compiler. }
  CheckEq('a labelled definition at program level opens', '+function',
          Folds('x = 1 : 20 function h()'));
  CheckEq('and after then it opens nothing, as the outline lists nothing', '',
          Folds('if x > 0 then 20 function f()'));
  { The label is not what stops it -- the position is. }
  CheckEq('an unlabelled definition after then still opens', '+function',
          Folds('if x > 0 then function f()'));
  CheckEq('and every other opener behaves the same way', '',
          Folds('if x > 0 then 20 for i = 1 to 3'));

  { --- ADJACENCY, which is where the shared walk was wrong twice ---------- }
  { Every line here RUNS. See the long block in TestWalk for the two mechanisms;
    these are the same facts seen from the consumer, because a lost terminator
    here is the failure this unit exists to prevent -- a fold that runs to the
    end of the file and hides everything under it. }
  CheckEq('a stray end before the real terminator loses nothing', '-function',
          Folds('end end function'));
  CheckEq('and the same for an if', '-if', Folds('end end if'));
  CheckEq('else then a terminator still terminates', '-if',
          Folds('else end if'));
  CheckEq('and for a function', '-function', Folds('else end function'));
  CheckEq('a comment after end is a comment', '',
          Folds('end rem so end function closes'));
  CheckEq('and end then else if opens no phantom if', '',
          Folds('end else if x = 2 then'));
  { AND A TERMINATOR CANNOT BE AN ARGUMENT. `println max(1, end function)`
    compiles and runs: inside the brackets the words are ordinary variables. }
  CheckEq('a terminator inside brackets is a variable', '',
          Folds('  println max(1, end function)'));

  { --- one numeric label, and the two that still compile ------------------- }
  CheckEq('two numeric labels define nothing', '', Folds('10 10 function f()'));
  CheckEq('a named label after a numeric one still does', '+function',
          Folds('10 head: function f()'));
  CheckEq('and a numeric one after a named one', '+function',
          Folds('head: 10 function f()'));

  { --- the tables, for a caller that wants to ask directly ----------------- }
  Check('if opens', BlockOpenedBy('if') = pbIf);
  Check('and an ordinary word does not', BlockOpenedBy('println') = pbNone);
  Check('endfunction closes a function', BlockClosedBy('endfunction') = pbFunction);
  Check('and an ordinary word closes nothing', BlockClosedBy('println') = pbNone);
  CheckEq('end if is endif', 'endif', MergedWithEnd('if'));
  CheckEq('there is no end next', '', MergedWithEnd('next'));
  CheckEq('a name for a message', 'while', BlockName(pbWhile));
  CheckEq('and none for none', '', BlockName(pbNone));
end;

{ -------------------------------------------------------- folding, wired ---- }

{ THAT THE HIGHLIGHTER ACTUALLY FOLDS, which is a different question from
  whether uphosphorfold answers correctly.

  The base class can be promoted, the overrides written, the stack balanced --
  and nothing fold at all, silently, because TSynCustomFoldHighlighter's
  GetFoldConfigInstance sets Enabled := False and a highlighter that does not
  turn it back on scans perfectly and offers no fold node anywhere
  (synedithighlighterfoldbase.pas:2030-2035).

  READING FoldBlockEndLevel NEEDS THE LINES ATTACHED. SetCurrentLines fills the
  range list from AValue.Ranges[...], which is nil until AttachToLines has run,
  and ScanAllRanges is what fills it -- without both, this either dies inside
  Lazarus or, worse, scans every line as if nothing were open above it and
  passes while verifying that openers open at depth zero forever. }

procedure TestFoldWired;
var
  Hl: TSynPhosphorSyn;
  L: TSynEditStringList;

  function EndLevel(ALine: Integer): Integer;
  begin
    Result := Hl.FoldBlockEndLevel(ALine);
  end;

begin
  Group('usynphosphor: that it folds, and where');

  Hl := TSynPhosphorSyn.Create(nil);
  L := TSynEditStringList.Create;
  try
    L.Text :=
      'rem a header'         + LineEnding +   { 0 }
      'function f(a)'        + LineEnding +   { 1 }
      '  for i = 1 to 3'     + LineEnding +   { 2 }
      '    if a > 0 then'    + LineEnding +   { 3 }
      '      println i'      + LineEnding +   { 4 }
      '    endif'            + LineEnding +   { 5 }
      '  next'               + LineEnding +   { 6 }
      '  return a'           + LineEnding +   { 7 }
      'end function'         + LineEnding +   { 8 }
      'println f(1)'         + LineEnding;    { 9 }

    Hl.AttachToLines(L);
    Hl.CurrentLines := L;
    Hl.ScanAllRanges;

    CheckEqInt('nothing is open on the header', 0, EndLevel(0));
    CheckEqInt('the function opens one', 1, EndLevel(1));
    CheckEqInt('the for makes two', 2, EndLevel(2));
    CheckEqInt('the if makes three', 3, EndLevel(3));
    CheckEqInt('the body stays at three', 3, EndLevel(4));
    CheckEqInt('endif closes back to two', 2, EndLevel(5));
    CheckEqInt('next closes back to one', 1, EndLevel(6));
    CheckEqInt('the return is still inside', 1, EndLevel(7));
    { `end function`, two words, and it must close as surely as `endfunction`. }
    CheckEqInt('end function closes the last one', 0, EndLevel(8));
    CheckEqInt('and the line after it is outside', 0, EndLevel(9));

    { --- AND THE NEGATIVE CASE, so that an all-flat answer cannot pass ------- }
    { Every one of these is a legal program that must fold NOTHING. If the
      numbers above ever go flat because folding quietly stopped working, these
      would keep passing -- which is why they are here with them rather than
      instead of them. }
    L.Text :=
      'for i = 1 to 2 println i next'         + LineEnding +   { 0 one line }
      'if x = 1 then println then'            + LineEnding +   { 1 inline }
      'y = function + 1'                      + LineEnding +   { 2 a variable }
      'println "function g()"'                + LineEnding +   { 3 a literal }
      'rem for i = 1 to 3'                    + LineEnding +   { 4 a comment }
      'println 1'                             + LineEnding;    { 5 }
    Hl.ScanAllRanges;
    CheckEqInt('a whole block on one line opens nothing', 0, EndLevel(0));
    CheckEqInt('an inline if opens nothing', 0, EndLevel(1));
    CheckEqInt('function as a variable opens nothing', 0, EndLevel(2));
    CheckEqInt('a block word in a literal opens nothing', 0, EndLevel(3));
    CheckEqInt('and one in a comment opens nothing', 0, EndLevel(4));
    CheckEqInt('so the file is flat', 0, EndLevel(5));

    { --- an unmatched terminator must not pop somebody else's block --------- }
    L.Text :=
      'function f()'   + LineEnding +   { 0 }
      '  next'         + LineEnding +   { 1 a `next` with no `for` }
      '  endselect'    + LineEnding +   { 2 and an endselect with no select }
      'endfunction'    + LineEnding +   { 3 }
      'println 1'      + LineEnding;    { 4 }
    Hl.ScanAllRanges;
    CheckEqInt('the function opens', 1, EndLevel(0));
    CheckEqInt('a next with no for pops nothing', 1, EndLevel(1));
    CheckEqInt('nor does an endselect with no select', 1, EndLevel(2));
    CheckEqInt('and the endfunction still closes it', 0, EndLevel(3));
    CheckEqInt('leaving the file flat', 0, EndLevel(4));

    Hl.DetachFromLines(L);
  finally
    L.Free;
    Hl.Free;
  end;
end;

{ ------------------------------------------------ what scanning costs ------- }

{ MEASURED, NOT ASSUMED, and printed rather than asserted.

  Roadmap item 17 asks for folding and says, in as many words, that adopting
  SynEdit's fold support changes the highlighter's cost model -- and that the
  comparison must be "measured before and after rather than assumed". A number
  nobody wrote down before the change cannot be compared with one written down
  after it, so this runs on both sides of that change and prints what it found.

  TWO NUMBERS, because they are the two ends of what typing costs.

    ONE LINE is the best case and the common one: a highlighter with no range
    state repaints only the line that changed, so this is what a keystroke costs
    today.

    THE WHOLE BUFFER is the worst case: with range state, a change on line 10
    forces a rescan until the range stops changing, which in the pathological
    case is every line after it. It is also what opening a file costs.

  The fixture is 5000 lines of the shape the item names -- nested blocks,
  strings and comments -- because a buffer of blank lines would measure nothing.
  There is one check, and it is only there so that a scan which silently stopped
  doing anything cannot pass as a fast one. }

procedure MeasureHighlighter;
const
  Lines = 5000;
  Passes = 3;
var
  Hl: TSynPhosphorSyn;
  Buf: TStringList;
  I, P, Tokens: Integer;
  T0: Int64;
  Whole, Single, Rescan, Quiet: Double;
  L: TSynEditStringList;
begin
  Group('usynphosphor: what a scan costs, printed for the record');

  { THESE FOUR NUMBERS USED TO BE TAKEN WITH `Now`, and roadmap item 19 is what
    that cost. They survived only because each divides a loop of fifty or two
    thousand passes by its count; the same clock asked about ONE edit answers 0
    or 15.6 ms. They are taken with uphosphorclock now, and the numbers did not
    move -- which is the point: the method was sound and the instrument was not
    good enough to prove it. What one KEYSTROKE costs is measured somewhere
    else entirely, in the editor, by `phosphoride --measure-typing`. }

  Buf := TStringList.Create;
  Hl := TSynPhosphorSyn.Create(nil);
  try
    I := 0;
    while Buf.Count < Lines do
    begin
      Inc(I);
      Buf.Add(Format('rem block %d -- a comment with the word function in it', [I]));
      Buf.Add(Format('function f%d(a, b) local acc', [I]));
      Buf.Add('  acc = 0');
      Buf.Add(Format('  for i = 1 to %d', [I mod 7 + 1]));
      Buf.Add('    if a > b then');
      Buf.Add(Format('      acc = acc + left$("a string with endif in it", %d)', [I mod 5]));
      Buf.Add('    endif');
      Buf.Add('  next');
      Buf.Add('  return acc');
      Buf.Add('endfunction');
    end;
    while Buf.Count > Lines do
      Buf.Delete(Buf.Count - 1);

    { --- the whole buffer ---------------------------------------------------- }
    Tokens := 0;
    T0 := ClockTicks;
    for P := 1 to Passes do
    begin
      Hl.ResetRange;
      for I := 0 to Buf.Count - 1 do
      begin
        Hl.SetLine(Buf[I], I);
        while not Hl.GetEol do
        begin
          Inc(Tokens);
          Hl.Next;
        end;
      end;
    end;
    Whole := ClockMs(T0, ClockTicks) / Passes;

    { --- one line, the keystroke case ---------------------------------------- }
    T0 := ClockTicks;
    for P := 1 to 2000 do
    begin
      Hl.SetLine(Buf[P mod Buf.Count], P mod Buf.Count);
      while not Hl.GetEol do
        Hl.Next;
    end;
    Single := ClockMs(T0, ClockTicks) / 2000;

    { --- the one that actually moves --------------------------------------- }
    { THE OTHER TWO NUMBERS CANNOT SEE WHAT FOLDING COSTS, and that is the trap
      this third one exists for. The cost a fold highlighter adds is not in
      SetLine/Next at all -- it is in PerformScan, which calls GetRange once per
      line and keeps going until a line's range matches the one already stored
      (synedithighlighter.pp:1752-1770). Today no line's range ever differs, so
      an edit stops one line later; with a fold stack, typing `function` at the
      top of a file makes every line below it differ and rescans to the end.

      Reading "one line 0.0120 ms, unchanged" after the change and writing "not
      measurably slower" would be true of the wrong thing. }
    L := TSynEditStringList.Create;
    try
      L.Assign(Buf);
      Hl.AttachToLines(L);
      Hl.CurrentLines := L;
      Hl.ScanAllRanges;
      T0 := ClockTicks;
      for P := 1 to 50 do
      begin
        { AN EDIT AT THE TOP THAT OPENS OR CLOSES A BLOCK, alternating, because
          that is the only edit that cascades. The first version of this loop
          rewrote the comment on line 0 into another comment: the structure was
          unchanged, every line's range still matched the stored one, the scan
          stopped at once and the number was nothing -- before AND after the
          promotion. It measured the balanced case and called it the worst one. }
        if Odd(P) then
          L[0] := 'function measured()'
        else
          L[0] := 'rem block 1 -- a comment again';
        Hl.ScanRanges;
      end;
      Rescan := ClockMs(T0, ClockTicks) / 50;

      { AND THE SAME EDIT THAT DOES NOT CHANGE THE STRUCTURE, because that is
        what almost every keystroke is. `fun`, `func`, `funct` are identifiers;
        only the keystroke that COMPLETES or BREAKS a block word cascades, and
        the pair of numbers is what makes that honest rather than alarming. }
      L[0] := 'rem block 1 -- a comment';
      Hl.ScanRanges;
      T0 := ClockTicks;
      for P := 1 to 50 do
      begin
        L[0] := Format('rem block 1 -- edit %d', [P]);
        Hl.ScanRanges;
      end;
      Quiet := ClockMs(T0, ClockTicks) / 50;
      Hl.DetachFromLines(L);
    finally
      L.Free;
    end;

    WriteLn(Format('      %d lines, %d tokens: whole buffer %.1f ms, one line %.4f ms',
                   [Buf.Count, Tokens div Passes, Whole, Single]));
    WriteLn(Format('      an edit at the top: %.3f ms when it opens or closes a block, ' +
                   '%.3f ms when it does not',
                   [Rescan, Quiet]));
    Check('the 5000-line scan produced tokens', (Tokens div Passes) > 10000);
  finally
    Hl.Free;
    Buf.Free;
  end;
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

  { --- AND THE RULE ON ITS OWN, which is now shared ----------------------- }
  { TrackEdit applies TrackLine to a whole set; roadmap item 24 applies it to the
    single line a failed run blamed. Two copies of a three-branch rule is how the
    two would come to disagree about where a line went, so there is one, and it
    is checked without a set around it. }
  CheckEqInt('a line above an insertion does not move', 3, TrackLine(3, 5, 2));
  CheckEqInt('a line at the insertion moves', 7, TrackLine(5, 5, 2));
  CheckEqInt('and one below it', 9, TrackLine(7, 5, 2));
  CheckEqInt('a line above a deletion does not move', 3, TrackLine(3, 5, -2));
  CheckEqInt('a line inside a deletion is dropped', 0, TrackLine(5, 5, -2));
  CheckEqInt('and the last line of it too', 0, TrackLine(6, 5, -2));
  CheckEqInt('the first line after a deletion moves up', 5, TrackLine(7, 5, -2));
  CheckEqInt('an edit that changes no count moves nothing', 4, TrackLine(4, 2, 0));
  { NOTHING IS NOT A LINE, and asking about it must not invent one: the blame is
    0 when there is none, and every edit in a session would otherwise shift that
    0 into a line number. }
  CheckEqInt('zero stays zero', 0, TrackLine(0, 1, 5));
  CheckEqInt('and is not dragged by a deletion either', 0, TrackLine(0, 1, -5));
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
  TestTextFile;
  TestClock;
  TestWalk;
  TestFold;
  TestBlockMatch;
  TestFoldWired;
  MeasureHighlighter;
  TestBreakpoints;
  TestCompletion;
  TestOutline;
  TestFindInFiles;
  TestReplaceInFiles;
  TestHandlePrivacy;
  TestRepl;
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
