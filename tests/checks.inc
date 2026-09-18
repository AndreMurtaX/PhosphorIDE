{ The house scoreboard, in ONE copy.

  Included by tests/phosphoridetest.lpr and tests/phosphorcontract.lpr. Both
  programs answer the same way -- exit 0 or the failure count -- and they do so
  by construction rather than by two authors agreeing to keep two copies in step.
  Two counters that drift apart is the class of defect this repository writes
  rules against; this is 40 lines.

  FPC resolves an include directive relative to the including file, so no search
  path changes and neither .lpi needs to know this exists. (Spelling that
  directive out here would open a second comment level and cost a warning, in a
  repository whose bar is zero -- which is how this sentence came to be phrased
  the long way round.)

  NOT A UNIT, deliberately. A unit would have to be in both projects' unit paths
  and would give these variables an interface section somebody could reach from
  elsewhere. An include is textually private to the program that includes it,
  which is what a test's scoreboard should be. }

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
