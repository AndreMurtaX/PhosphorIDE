#!/usr/bin/env python3
"""Regenerate src/core/uphosphorlang.pas from a Phosphor checkout.

The word lists an editor highlights are FACTS ABOUT ANOTHER REPOSITORY. Typing
them by hand here would put those facts in two places, and the second copy is the
one that goes stale. So they are extracted from the Phosphor sources and this file
is the only place that knows how.

    python tools/gen-keywords.py ../Phosphor            # rewrite the unit
    python tools/gen-keywords.py ../Phosphor --check    # fail if it would change

--check is what CI runs: it regenerates into memory and diffs. A Phosphor release
that adds a built-in therefore shows up as a red build here, which is the point --
silence would mean the editor quietly stopped knowing about the new name.

Two extraction traps, both already paid for:

1. A naive grep for Reg.Add('name:sig') UNDERCOUNTS the engine by 23 names,
   because two libraries register from a const array in a loop and the names never
   appear next to a Reg.Add call: PhosphorCallLib (callfunc and its four suffixed
   forms x 9 arities) and PhosphorSysLib (18 mobile shared-path names). Both are
   handled below by reading the const arrays.
2. A stale agent worktree under .claude/worktrees/ holds a full duplicate copy of
   engine/libs, so scanning the repo ROOT doubles every count. Only the three
   known directories are scanned.

SIGNATURES ARE EXTRACTED TOO, AND SOME ARE DELIBERATELY NOT. Phosphor registers
as Reg.Add('name:sig'), where the codes are one character per argument -- n
numeric, % an exact int% that does not widen, $ string, @ handle, ? bool -- and a
zero-argument function is 'name:'. One name can carry SEVERAL signatures, because
Reg.Add overwrites by signature rather than by name: mid$:$n and mid$:$nn are two
slots and not a conflict. So the table maps a name to a LIST.

The exception is a registration whose signature is BUILT AT RUN TIME.
PhosphorCallLib registers callfunc and its four suffixed forms once per arity,
with the argument codes accumulated in a loop variable, so the literal in the
source says ':$' and the real set is ':$', ':$*', ':$**' ... up to eight. Taking
the literal would tell an editor that callfunc takes one string, which is a WRONG
fact rather than a missing one -- and the project's own rule is that showing one
arity for a name that has nine is worse than showing none. Those names are
therefore recorded with NO signature at all, and the unit says absent rather than
empty.

The counts are asserted, not assumed: engine 534, packages 181, gui 426, and
1136 names carrying 1226 signatures between them. If a Phosphor release moves
any of them, this script fails and a human decides what the new numbers are
before the unit changes.
"""

import os
import re
import sys

EXPECTED = {'core': 534, 'package': 181, 'gui': 426}
# Names carrying at least one extractable signature, and (name, signature) pairs.
EXPECTED_SIG_NAMES = 1136
EXPECTED_SIG_PAIRS = 1226

TIER_DIRS = [
    ('core', 'engine/libs'),
    ('package', 'host/packages'),
    ('gui', 'host/gui/libs'),
]

# Reg.Add('name:sig', @fn) / Reg.AddHost(...) / Registry.Add(...) -- the name is
# everything before the first ':' inside the literal.
REG_RE = re.compile(r"""\b(?:Reg|Registry)\.Add(?:Host)?\s*\(\s*'([^']*?)(?::[^']*)?'""")

# A loop registration: Reg.Add(SomeArray[i] + ':...', @fn). The built-in names
# are then the elements of SomeArray, declared as a const array in the same unit.
# Matching the ARRAY REFERENCE rather than the file name is what makes this
# general: a loop registration added to some other library tomorrow is found the
# same way, instead of silently going missing until a count assertion fires.
LOOP_REG_RE = re.compile(r"""\b(?:Reg|Registry)\.Add(?:Host)?\s*\(\s*([A-Za-z_]\w*)\s*\[""")
QUOTED_RE = re.compile(r"'([^']*)'")

# The whole registration literal, name and signature together. Separate from
# REG_RE because that one throws the signature away by design and is the thing
# every count has always been measured with.
SIG_RE = re.compile(r"""\b(?:Reg|Registry)\.Add(?:Host)?\s*\(\s*'([^']*)'""")

# A loop registration whose signature IS a plain literal: Reg.Add(Arr[i] + ':n',
# @fn). The trailing group says what follows the literal -- a comma means the
# expression ended there and the signature is exactly what it says; a `+` means
# it is built from something this script cannot see, and the name gets none.
LOOP_SIG_RE = re.compile(
    r"""\b(?:Reg|Registry)\.Add(?:Host)?\s*\(\s*([A-Za-z_]\w*)\s*\[[^\]]*\]"""
    r"""\s*\+\s*'([^']*)'\s*(,|\+)""")


def const_array_items(src, ident):
    """The quoted elements of `ident: array[...] of String = (...)`."""
    pattern = re.compile(
        r"\b" + re.escape(ident) + r"\s*:\s*array\s*\[[^\]]*\]\s*of\s+String\s*=\s*\(",
        re.I)
    match = pattern.search(src)
    if not match:
        return []
    depth, i = 1, match.end()
    while i < len(src) and depth:
        if src[i] == '(':
            depth += 1
        elif src[i] == ')':
            depth -= 1
        i += 1
    return QUOTED_RE.findall(src[match.end():i - 1])


def names_in_file(path):
    """Every built-in name a single library unit registers."""
    with open(path, 'r', encoding='utf-8', errors='replace') as fh:
        src = fh.read()

    found = set(REG_RE.findall(src))
    for ident in set(LOOP_REG_RE.findall(src)):
        found.update(const_array_items(src, ident))
    return found


def signatures_in_file(path, sigs, unknown):
    """Add this unit's (name -> set of code strings) to sigs.

    A name whose signature cannot be read STATICALLY goes into `unknown`, and
    the caller drops whatever else was collected for it: a partial answer about
    arity is a wrong answer, and the unit has a way to say nothing."""
    with open(path, 'r', encoding='utf-8', errors='replace') as fh:
        src = fh.read()

    for literal in SIG_RE.findall(src):
        if ':' not in literal:
            # Every registration in Phosphor today carries one. If that ever
            # stops being true, the name is recorded WITHOUT a signature rather
            # than with a guessed empty one -- those mean different things.
            unknown.add(literal)
            continue
        name, sig = literal.split(':', 1)
        sigs.setdefault(name, set()).add(sig)

    for ident, literal, tail in LOOP_SIG_RE.findall(src):
        items = const_array_items(src, ident)
        for name in items:
            if tail == ',' and literal.startswith(':'):
                sigs.setdefault(name, set()).add(literal[1:])
            else:
                unknown.add(name)


def collect(phosphor_root):
    tiers = {}
    sigs = {}
    unknown = set()
    for tier, rel in TIER_DIRS:
        directory = os.path.join(phosphor_root, rel)
        if not os.path.isdir(directory):
            sys.exit('not a Phosphor checkout: missing %s' % directory)
        names = set()
        for entry in sorted(os.listdir(directory)):
            if entry.lower().endswith('.pas'):
                path = os.path.join(directory, entry)
                names |= names_in_file(path)
                signatures_in_file(path, sigs, unknown)
        tiers[tier] = sorted(names)
    for name in unknown:
        sigs.pop(name, None)
    return tiers, sigs


# ---------------------------------------------------------------------------
# The word lists that are NOT in a registry.
#
# Phosphor's lexer has no keyword table at all -- it emits every one of these as
# a plain identifier and the PARSER decides, from position, whether the word is a
# keyword (engine/PhosphorLexer.pas:444-470). So there is nothing to extract:
# the authority is TPhosphorCompiler.IsReservedWord, and these lists are checked
# against it by hand when Phosphor changes. `rem` and `mod` are the only two
# words the lexer itself owns.
# ---------------------------------------------------------------------------

# Everything IsReservedWord holds (engine/PhosphorCompiler.pas:421-448), minus the
# word-operators and literals below, plus the words deliberately left OUT of that
# list so they stay usable as label names but which are still keywords in context:
# as, output, append, binary (inside OPEN), using (after PRINT), error (in ON
# ERROR), call (in ON ERROR CALL).
KEYWORDS = """
    append as binary break breakpoint call case close const continue data dim do
    else elseif end endfunction endif endselect endwhile error for function gosub
    goto if input let line local loop next on open output print println read
    repeat restore resume return seek select step swap then to trace until using
    wend while
""".split()

# Word operators. `mod` is special: the lexer turns it into an operator token, so
# unlike every other word here it can never be a variable (PhosphorLexer.pas:459-460).
OPERATORS = 'and mod not or'.split()

# `true` and `false` are parser-level (PhosphorCompiler.pas:796-797). `null` is a
# keyword ONLY inside a JSON literal (PhosphorCompiler.pas:932-936).
LITERALS = 'false null true'.split()

# Four names the compiler handles as special forms rather than registry lookups,
# and which a user function may not shadow (engine/PhosphorCompiler.pas:461-469,
# 800-832). They are in no registry, so nothing above finds them.
#
# AND THEY CARRY NO SIGNATURE, deliberately. There is none to extract: the
# compiler parses them in its own code rather than looking them up, so writing
# one here would be a hand-typed copy of a fact from the other repository --
# which is the mistake this whole file exists to prevent. The unit therefore
# answers "nothing known" for them, and an editor says nothing rather than
# something it made up.
SPECIAL_FORMS = 'eof input$ loc lof'.split()

HEADER = """unit uphosphorlang;

{ GENERATED FILE -- DO NOT EDIT.

  Rewrite it with:  python tools/gen-keywords.py <path-to-Phosphor-checkout>

  Every name here is a fact about the Phosphor repository, not about this one:
  the keyword lists come from TPhosphorCompiler.IsReservedWord and the built-in
  lists from the Reg.Add registrations in engine/libs, host/packages and
  host/gui/libs. Editing this file by hand puts those facts in two places, and
  the copy that is edited is the one that goes stale.

  The three built-in tiers are not interchangeable, which is why they are three
  lists rather than one. Core is always present. Package names exist only because
  the console host links every package -- another host need not. GUI names exist
  only where a graphical session was reachable when the program started, so a
  program that calls one is portable in a way `print` is not.

  Lookup is case-insensitive: Phosphor lowercases every identifier as it is
  scanned (engine/PhosphorLexer.pas:452), so `PrintLn` and `println` are one word.
  A name's type suffix ($ % @ ?) is PART of the name and is kept -- `left$` is the
  word, not `left` followed by an operator.
}

{$mode objfpc}{$H+}

interface

type
  { Which host a built-in needs. Ordered by how universally available it is, so
    a completion list can be filtered with a single <= test. }
  TPhosphorTier = (ptCore, ptPackage, ptGui);

  { A plain open array of words. Declared here rather than using the RTL's
    TStringArray so this unit compiles unchanged against an FPC that predates it. }
  TPhosphorWordList = array of String;

  { WHAT A WORD IS, in one answer.

    FIVE QUESTIONS, SIX INDEXES. The five questions below used to be answered by
    six sorted indexes asked in turn -- operator, literal, keyword, and one per
    built-in tier, because the tier question LOOPED over all three -- so a word
    that is none of them, which is what a person's own names are and therefore
    what most words in a program are, paid for all six before being told no. Measured at -O3 on 2026-09-17: 3,5 us for a miss and 0,9 us for
    a hit, against 0,04 us for the LowerCase(Copy(...)) that precedes it. Two
    identifiers on a line is about 7 us, paid on every line of every rescan, every
    file open and every scroll.

    ONE SORTED TABLE, one binary search, one answer. The five questions still
    exist and still mean what they meant; each is now a call to this and a compare.

    pwkNone is a word this repository knows nothing about, which is the answer for
    almost every word in almost every program -- and is now the CHEAPEST answer
    rather than the most expensive one. }
  TPhosphorWordKind = (pwkNone, pwkOperator, pwkLiteral, pwkKeyword,
                       pwkBuiltinCore, pwkBuiltinPackage, pwkBuiltinGui);

{ True when the word is one this repository knows, with AKind saying which.

  THE ORDER OF THE KINDS IS THE ORDER THE FIVE SEPARATE SEARCHES USED TO RUN IN,
  and it is load-bearing for exactly one word: `error` is both a keyword and a
  core built-in, and the old chain asked about keywords first. The generator
  applies the same priority when it merges the tables and PRINTS every word it had
  to choose for, so a second overlap arriving from Phosphor is a line of output
  rather than a colour that silently changed. }
function PhosphorClassify(const AWord: String; out AKind: TPhosphorWordKind): Boolean;

function IsPhosphorKeyword(const AWord: String): Boolean;
function IsPhosphorOperatorWord(const AWord: String): Boolean;
function IsPhosphorLiteralWord(const AWord: String): Boolean;
function IsPhosphorBuiltin(const AWord: String): Boolean;
function PhosphorBuiltinTier(const AWord: String; out ATier: TPhosphorTier): Boolean;

{ The raw lists, for a completion box or a documentation lookup. Sorted, lower
  case, suffixes included. Do not modify them in place. }
function PhosphorKeywords: TPhosphorWordList;
function PhosphorOperatorWords: TPhosphorWordList;
function PhosphorLiteralWords: TPhosphorWordList;
function PhosphorBuiltins(ATier: TPhosphorTier): TPhosphorWordList;

{ Every signature registered for AName, as CODE STRINGS: one character per
  argument, from `n` numeric, `%` an exact int% that does not widen, `$` string,
  `@` handle, `?` bool.

  ABSENT AND EMPTY ARE DIFFERENT ANSWERS, and a caller that treats them alike
  will tell somebody a lie. A result of LENGTH ZERO means nothing is known --
  either the name is not a built-in, or its signature is assembled at run time
  (callfunc and its four suffixed forms register one slot per arity from a loop),
  or it is one of the four compiler special forms that are in no registry at all.
  A result of length ONE holding the EMPTY STRING means the name is known and
  takes no arguments: `dirseparator$:` is a registration, not a gap.

  One name can have several, because Reg.Add overwrites by signature and not by
  name -- `mid$:$n` and `mid$:$nn` are two slots. Sorted, shortest first. }
function PhosphorSignatures(const AName: String): TPhosphorWordList;

const
  { What this unit was generated from, so a mismatch is legible in a bug report
    rather than a mystery. }
  PhosphorLangSource = '%(source)s';
  PhosphorKeywordCount = %(nkw)d;
  PhosphorBuiltinCoreCount = %(ncore)d;
  PhosphorBuiltinPackageCount = %(npkg)d;
  PhosphorBuiltinGuiCount = %(ngui)d;
  { Names carrying at least one signature, and the total number of signatures
    across them. Both asserted by the generator. }
  PhosphorSignatureNameCount = %(nsigname)d;
  PhosphorSignatureCount = %(nsig)d;

implementation

uses
  Classes, SysUtils;
"""


# THE MERGE, AND THE ONE WORD IT HAS TO CHOOSE FOR.
#
# The editor used to ask six separate sorted indexes in turn -- operator,
# literal, keyword, then one per built-in tier -- so a word in none of them paid
# for all six. (This sentence said FIVE until 2026-09-17 while listing six things
# in the same breath, and that wrong count reached two documents and a commit
# subject before anyone ran the old code to count.) One table answers in one
# binary search, but a table needs one kind per word and the six tables are not
# disjoint: `error` is both a keyword and a core built-in.
#
# THE MERGE THEREFORE APPLIES THE OLD CHAIN'S PRIORITY, in the order it asked,
# and PRINTS every word it had to choose for. A second overlap arriving from a
# new Phosphor release is then a line of output somebody reads, not a colour
# that silently changed in an editor -- which is the failure roadmap item 29's
# own hazard paragraph is about, and which no build and no screenshot catches.
CLASS_KINDS = ('pwkOperator', 'pwkLiteral', 'pwkKeyword',
               'pwkBuiltinCore', 'pwkBuiltinPackage', 'pwkBuiltinGui')


def merge_classes(keywords, operators, literals, core, package, gui):
    """[(word, kind_index)] sorted by the word's bytes, plus the overlaps."""
    tables = [operators, literals, keywords, core, package, gui]
    first = {}
    overlaps = []
    for kind, words in enumerate(tables):
        for w in words:
            if w in first:
                overlaps.append((w, CLASS_KINDS[first[w]], CLASS_KINDS[kind]))
            else:
                first[w] = kind
    # SORTED BY THE WORD'S BYTES, which is what CompareFolded compares and what
    # the binary search in the unit depends on. Every word is already lower case
    # and ASCII, so Python's own ordering IS that ordering; asserted rather than
    # assumed, because a table sorted one way and searched another answers "not
    # found" for real words and nothing says so.
    for w in first:
        assert w == w.lower(), 'table word is not lower case: %r' % w
        assert all(ord(c) < 128 for c in w), 'table word is not ASCII: %r' % w
    rows = sorted(first.items(), key=lambda kv: kv[0])
    return rows, overlaps


def pas_kind_array(name, kinds, indent='    '):
    """The parallel kinds, as a byte array -- one per word, same index."""
    out = ['  %s: array[0..%d] of Byte = (' % (name, len(kinds) - 1)]
    line = indent
    for i, k in enumerate(kinds):
        item = str(k)
        if i < len(kinds) - 1:
            item += ','
        if len(line) + len(item) > 78 and line.strip():
            out.append(line.rstrip())
            line = indent
        line += item + ' '
    out.append(line.rstrip())
    out.append('  );')
    return '\n'.join(out)


def pas_array(name, words, indent='    '):
    """A Pascal const array of the words, wrapped to a readable width."""
    out = ['  %s: array[0..%d] of String = (' % (name, len(words) - 1)]
    line = indent
    for i, word in enumerate(words):
        item = "'" + word.replace("'", "''") + "'"
        if i < len(words) - 1:
            item += ','
        if len(line) + len(item) > 78 and line.strip():
            out.append(line.rstrip())
            line = indent
        line += item + ' '
    out.append(line.rstrip())
    out.append('  );')
    return '\n'.join(out)


BODY = """

const
%(arrays)s

var
  { The signature index carries the row number in SignatureCodes as the object,
    so one binary search answers both "is it there" and "which codes". }
  FSignatureIndex: TStringList;
  { The initialization section's loop counter. A unit has nowhere else to put
    one. }
  SigRow: Integer;

{ COMPARE A PROBE AGAINST A TABLE ENTRY, FOLDING ASCII CASE AS IT GOES.

  This replaced `TStringList.Find` on a case-insensitive list, whose comparison
  is `AnsiCompareText` -- locale-aware, and about 100 ns for each of the ten
  probes a binary search over 1205 words makes. Here the table entries are
  already lower case (the generator writes them that way), so only the PROBE
  needs folding, and folding one character is a compare and an add.

  ASCII IS NOT AN APPROXIMATION HERE, IT IS THE LANGUAGE'S OWN RULE. A Phosphor
  identifier is ASCII letters, digits and `_` (engine/PhosphorLexer.pas:90-98)
  with one of `$ % @ ?` allowed as a suffix, and the lexer folds it with
  LowerCase (engine/PhosphorLexer.pas:452). A word that could reach this function
  with a non-ASCII letter in it is not a word the parser would accept.

  Answers <0, 0 or >0, comparing byte by byte and then by length -- which is the
  order `sorted()` gives the generator, so the table and the search agree by
  construction rather than by convention. }
function CompareFolded(const AProbe, AEntry: String): Integer;
var
  I, LP, LE, N: Integer;
  C: Char;
begin
  LP := Length(AProbe);
  LE := Length(AEntry);
  if LP < LE then N := LP else N := LE;
  for I := 1 to N do
  begin
    C := AProbe[I];
    if (C >= 'A') and (C <= 'Z') then
      C := Chr(Ord(C) + 32);
    if C < AEntry[I] then Exit(-1);
    if C > AEntry[I] then Exit(1);
  end;
  Result := LP - LE;
end;

function PhosphorClassify(const AWord: String; out AKind: TPhosphorWordKind): Boolean;
var
  Lo, Hi, Mid, C: Integer;
begin
  AKind := pwkNone;
  Result := False;
  if AWord = '' then
    Exit;
  Lo := Low(ClassWords);
  Hi := High(ClassWords);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) shr 1;
    C := CompareFolded(AWord, ClassWords[Mid]);
    if C = 0 then
    begin
      AKind := TPhosphorWordKind(ClassKinds[Mid]);
      Exit(True);
    end;
    if C < 0 then
      Hi := Mid - 1
    else
      Lo := Mid + 1;
  end;
end;

function ToArray(const AWords: array of String): TPhosphorWordList;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AWords));
  for I := Low(AWords) to High(AWords) do
    Result[I] := AWords[I];
end;

{ THE FIVE OLD QUESTIONS, EACH NOW ONE SEARCH AND ONE COMPARE. They are kept
  because they are what reads well at a call site and because other code asks
  them; what changed is that asking all five costs one search rather than six --
  six, because the tier question was a loop over three indexes of its own. }
function IsPhosphorKeyword(const AWord: String): Boolean;
var
  Kind: TPhosphorWordKind;
begin
  Result := PhosphorClassify(AWord, Kind) and (Kind = pwkKeyword);
end;

function IsPhosphorOperatorWord(const AWord: String): Boolean;
var
  Kind: TPhosphorWordKind;
begin
  Result := PhosphorClassify(AWord, Kind) and (Kind = pwkOperator);
end;

function IsPhosphorLiteralWord(const AWord: String): Boolean;
var
  Kind: TPhosphorWordKind;
begin
  Result := PhosphorClassify(AWord, Kind) and (Kind = pwkLiteral);
end;

function PhosphorBuiltinTier(const AWord: String; out ATier: TPhosphorTier): Boolean;
var
  Kind: TPhosphorWordKind;
begin
  ATier := ptCore;
  Result := False;
  if not PhosphorClassify(AWord, Kind) then
    Exit;
  case Kind of
    pwkBuiltinCore: ATier := ptCore;
    pwkBuiltinPackage: ATier := ptPackage;
    pwkBuiltinGui: ATier := ptGui;
  else
    { A keyword, an operator word or a literal is not a built-in, and `error` is
      why this arm has to exist rather than being an else-of-convenience: it is
      in BOTH the keyword table and the core table, the merge gave it to the
      keyword, and IsPhosphorBuiltin('error') must therefore answer False --
      exactly as the five-search chain answered it, which stopped at keywords. }
    Exit;
  end;
  Result := True;
end;

function IsPhosphorBuiltin(const AWord: String): Boolean;
var
  Tier: TPhosphorTier;
begin
  Result := PhosphorBuiltinTier(AWord, Tier);
end;

function PhosphorKeywords: TPhosphorWordList;
begin
  Result := ToArray(KeywordWords);
end;

function PhosphorOperatorWords: TPhosphorWordList;
begin
  Result := ToArray(OperatorWords);
end;

function PhosphorLiteralWords: TPhosphorWordList;
begin
  Result := ToArray(LiteralWords);
end;

function PhosphorBuiltins(ATier: TPhosphorTier): TPhosphorWordList;
begin
  case ATier of
    ptCore: Result := ToArray(BuiltinCoreWords);
    ptPackage: Result := ToArray(BuiltinPackageWords);
  else
    Result := ToArray(BuiltinGuiWords);
  end;
end;

function PhosphorSignatures(const AName: String): TPhosphorWordList;
var
  Row, Start, Len, I, N: Integer;
  Packed_: String;
begin
  Result := nil;
  if not FSignatureIndex.Find(AName, Row) then
    Exit;
  Packed_ := SignatureCodes[PtrInt(FSignatureIndex.Objects[Row])];

  { The codes for one name are joined with '|', which no signature can contain:
    the whole alphabet is n % $ @ ? and the empty string. A single empty entry is
    therefore a real answer -- the name takes no arguments -- and is why this
    counts separators rather than testing the string for emptiness. }
  N := 1;
  for I := 1 to Length(Packed_) do
    if Packed_[I] = '|' then
      Inc(N);
  SetLength(Result, N);
  N := 0;
  Start := 1;
  for I := 1 to Length(Packed_) + 1 do
    if (I > Length(Packed_)) or (Packed_[I] = '|') then
    begin
      Len := I - Start;
      Result[N] := Copy(Packed_, Start, Len);
      Inc(N);
      Start := I + 1;
    end;
end;

initialization
  { NOTHING IS BUILT FOR CLASSIFICATION ANY MORE. ClassWords and ClassKinds are
    constant arrays the generator sorted, so the first lookup costs what every
    later one costs and the unit brings up six fewer TStringLists. }
  FSignatureIndex := TStringList.Create;
  FSignatureIndex.CaseSensitive := False;
  for SigRow := Low(SignatureNames) to High(SignatureNames) do
    FSignatureIndex.AddObject(SignatureNames[SigRow], TObject(PtrInt(SigRow)));
  FSignatureIndex.Sorted := True;

finalization
  FreeAndNil(FSignatureIndex);

end.
"""


def signature_arrays(sigs):
    """Two parallel arrays: the names, sorted, and their codes joined by '|'.

    Joined rather than one row per pair because the popup wants all the arities
    of one name at once, and a name is looked up far more often than a signature
    is. The separator is safe by construction: a signature is made of n % $ @ ?
    and nothing else."""
    names = sorted(sigs)
    # SHORTEST FIRST inside a name, so `mid$($n)` is offered before `mid$($nn)`
    # -- the shorter arity is the one being typed when the popup first appears.
    codes = ['|'.join(sorted(sigs[n], key=lambda c: (len(c), c))) for n in names]
    return names, codes


def render(tiers, sigs, source_label):
    core = sorted(set(tiers['core']) | set(SPECIAL_FORMS))
    sig_names, sig_codes = signature_arrays(sigs)
    rows, overlaps = merge_classes(
        sorted(KEYWORDS), sorted(OPERATORS), sorted(LITERALS),
        core, sorted(tiers['package']), sorted(tiers['gui']))
    for word, kept, dropped in overlaps:
        print('  overlap: %r is %s and %s -- kept %s, the order the separate '
              'searches asked in' % (word, kept, dropped, kept))
    arrays = '\n\n'.join([
        pas_array('ClassWords', [w for w, _ in rows]),
        pas_kind_array('ClassKinds', [k + 1 for _, k in rows]),
        pas_array('KeywordWords', sorted(KEYWORDS)),
        pas_array('OperatorWords', sorted(OPERATORS)),
        pas_array('LiteralWords', sorted(LITERALS)),
        pas_array('BuiltinCoreWords', core),
        pas_array('BuiltinPackageWords', sorted(tiers['package'])),
        pas_array('BuiltinGuiWords', sorted(tiers['gui'])),
        pas_array('SignatureNames', sig_names),
        pas_array('SignatureCodes', sig_codes),
    ])
    text = HEADER
    text = text.replace('%(source)s', source_label)
    text = text.replace('%(nkw)d', str(len(KEYWORDS)))
    text = text.replace('%(ncore)d', str(len(core)))
    text = text.replace('%(npkg)d', str(len(tiers['package'])))
    text = text.replace('%(ngui)d', str(len(tiers['gui'])))
    text = text.replace('%(nsigname)d', str(len(sig_names)))
    text = text.replace('%(nsig)d', str(sum(len(v) for v in sigs.values())))
    text += BODY.replace('%(arrays)s', arrays)
    return text.replace('\r\n', '\n')


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    root = os.path.abspath(argv[1])
    check_only = '--check' in argv[2:]

    tiers, sigs = collect(root)
    for tier, expected in EXPECTED.items():
        actual = len(tiers[tier])
        if actual != expected:
            sys.exit(
                'refusing to generate: %s tier has %d names, expected %d.\n'
                'Phosphor changed. Decide what the new number is, update EXPECTED '
                'in this script, and say so in the commit message.'
                % (tier, actual, expected))

    n_names = len(sigs)
    n_pairs = sum(len(v) for v in sigs.values())
    if (n_names, n_pairs) != (EXPECTED_SIG_NAMES, EXPECTED_SIG_PAIRS):
        sys.exit(
            'refusing to generate: %d names carry %d signatures, expected '
            '%d and %d.\nPhosphor changed a registration. Decide what the new '
            'numbers are, update EXPECTED_SIG_* in this script, and say so in '
            'the commit message.'
            % (n_names, n_pairs, EXPECTED_SIG_NAMES, EXPECTED_SIG_PAIRS))

    label = 'Phosphor engine/libs + host/packages + host/gui/libs'
    text = render(tiers, sigs, label)

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       '..', 'src', 'core', 'uphosphorlang.pas')
    out = os.path.normpath(out)

    if check_only:
        if not os.path.exists(out):
            sys.exit('%s does not exist; run without --check' % out)
        with open(out, 'r', encoding='utf-8', newline='') as fh:
            current = fh.read().replace('\r\n', '\n')
        if current != text:
            sys.exit('%s is stale -- rerun tools/gen-keywords.py' % out)
        print('uphosphorlang.pas is current (%d core, %d package, %d gui, '
              '%d signatures over %d names)'
              % (len(tiers['core']) + len(SPECIAL_FORMS),
                 len(tiers['package']), len(tiers['gui']), n_pairs, n_names))
        return 0

    with open(out, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)
    print('wrote %s: %d keywords, %d core, %d package, %d gui built-ins'
          % (out, len(KEYWORDS), len(tiers['core']) + len(SPECIAL_FORMS),
             len(tiers['package']), len(tiers['gui'])))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
