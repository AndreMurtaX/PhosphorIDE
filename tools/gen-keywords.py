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

The counts are asserted, not assumed: engine 534, packages 181, gui 426. If a
Phosphor release moves them, this script fails and a human decides what the new
numbers are before the unit changes.
"""

import os
import re
import sys

EXPECTED = {'core': 534, 'package': 181, 'gui': 426}

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


def collect(phosphor_root):
    tiers = {}
    for tier, rel in TIER_DIRS:
        directory = os.path.join(phosphor_root, rel)
        if not os.path.isdir(directory):
            sys.exit('not a Phosphor checkout: missing %s' % directory)
        names = set()
        for entry in sorted(os.listdir(directory)):
            if entry.lower().endswith('.pas'):
                names |= names_in_file(os.path.join(directory, entry))
        tiers[tier] = sorted(names)
    return tiers


# ---------------------------------------------------------------------------
# The word lists that are NOT in a registry.
#
# Phosphor's lexer has no keyword table at all -- it emits every one of these as
# a plain identifier and the PARSER decides, from position, whether the word is a
# keyword (engine/PhosphorLexer.pas:385-408). So there is nothing to extract:
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
# unlike every other word here it can never be a variable (PhosphorLexer.pas:399).
OPERATORS = 'and mod not or'.split()

# `true` and `false` are parser-level (PhosphorCompiler.pas:796-797). `null` is a
# keyword ONLY inside a JSON literal (PhosphorCompiler.pas:932-936).
LITERALS = 'false null true'.split()

# Four names the compiler handles as special forms rather than registry lookups,
# and which a user function may not shadow (engine/PhosphorCompiler.pas:461-469,
# 800-832). They are in no registry, so nothing above finds them.
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
  scanned (engine/PhosphorLexer.pas:392), so `PrintLn` and `println` are one word.
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

const
  { What this unit was generated from, so a mismatch is legible in a bug report
    rather than a mystery. }
  PhosphorLangSource = '%(source)s';
  PhosphorKeywordCount = %(nkw)d;
  PhosphorBuiltinCoreCount = %(ncore)d;
  PhosphorBuiltinPackageCount = %(npkg)d;
  PhosphorBuiltinGuiCount = %(ngui)d;

implementation

uses
  Classes, SysUtils;
"""


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
  { Sorted, case-insensitive indexes over the arrays above, built once at unit
    load. A TStringList.Find is a binary search; the highlighter asks this
    question once per identifier token on every visible line, so a linear scan
    over 1141 names would be felt. }
  FKeywordIndex: TStringList;
  FOperatorIndex: TStringList;
  FLiteralIndex: TStringList;
  FBuiltinIndex: array[TPhosphorTier] of TStringList;

function MakeIndex(const AWords: array of String): TStringList;
var
  I: Integer;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  Result.Duplicates := dupIgnore;
  for I := Low(AWords) to High(AWords) do
    Result.Add(AWords[I]);
  Result.Sorted := True;
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

function IsPhosphorKeyword(const AWord: String): Boolean;
var
  Dummy: Integer;
begin
  Result := FKeywordIndex.Find(AWord, Dummy);
end;

function IsPhosphorOperatorWord(const AWord: String): Boolean;
var
  Dummy: Integer;
begin
  Result := FOperatorIndex.Find(AWord, Dummy);
end;

function IsPhosphorLiteralWord(const AWord: String): Boolean;
var
  Dummy: Integer;
begin
  Result := FLiteralIndex.Find(AWord, Dummy);
end;

function PhosphorBuiltinTier(const AWord: String; out ATier: TPhosphorTier): Boolean;
var
  Tier: TPhosphorTier;
  Dummy: Integer;
begin
  for Tier := Low(TPhosphorTier) to High(TPhosphorTier) do
    if FBuiltinIndex[Tier].Find(AWord, Dummy) then
    begin
      ATier := Tier;
      Exit(True);
    end;
  ATier := ptCore;
  Result := False;
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

initialization
  FKeywordIndex := MakeIndex(KeywordWords);
  FOperatorIndex := MakeIndex(OperatorWords);
  FLiteralIndex := MakeIndex(LiteralWords);
  FBuiltinIndex[ptCore] := MakeIndex(BuiltinCoreWords);
  FBuiltinIndex[ptPackage] := MakeIndex(BuiltinPackageWords);
  FBuiltinIndex[ptGui] := MakeIndex(BuiltinGuiWords);

finalization
  FreeAndNil(FKeywordIndex);
  FreeAndNil(FOperatorIndex);
  FreeAndNil(FLiteralIndex);
  FreeAndNil(FBuiltinIndex[ptCore]);
  FreeAndNil(FBuiltinIndex[ptPackage]);
  FreeAndNil(FBuiltinIndex[ptGui]);

end.
"""


def render(tiers, source_label):
    core = sorted(set(tiers['core']) | set(SPECIAL_FORMS))
    arrays = '\n\n'.join([
        pas_array('KeywordWords', sorted(KEYWORDS)),
        pas_array('OperatorWords', sorted(OPERATORS)),
        pas_array('LiteralWords', sorted(LITERALS)),
        pas_array('BuiltinCoreWords', core),
        pas_array('BuiltinPackageWords', sorted(tiers['package'])),
        pas_array('BuiltinGuiWords', sorted(tiers['gui'])),
    ])
    text = HEADER
    text = text.replace('%(source)s', source_label)
    text = text.replace('%(nkw)d', str(len(KEYWORDS)))
    text = text.replace('%(ncore)d', str(len(core)))
    text = text.replace('%(npkg)d', str(len(tiers['package'])))
    text = text.replace('%(ngui)d', str(len(tiers['gui'])))
    text += BODY.replace('%(arrays)s', arrays)
    return text.replace('\r\n', '\n')


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    root = os.path.abspath(argv[1])
    check_only = '--check' in argv[2:]

    tiers = collect(root)
    for tier, expected in EXPECTED.items():
        actual = len(tiers[tier])
        if actual != expected:
            sys.exit(
                'refusing to generate: %s tier has %d names, expected %d.\n'
                'Phosphor changed. Decide what the new number is, update EXPECTED '
                'in this script, and say so in the commit message.'
                % (tier, actual, expected))

    label = 'Phosphor engine/libs + host/packages + host/gui/libs'
    text = render(tiers, label)

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
        print('uphosphorlang.pas is current (%d core, %d package, %d gui)'
              % (len(tiers['core']) + len(SPECIAL_FORMS),
                 len(tiers['package']), len(tiers['gui'])))
        return 0

    with open(out, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)
    print('wrote %s: %d keywords, %d core, %d package, %d gui built-ins'
          % (out, len(KEYWORDS), len(tiers['core']) + len(SPECIAL_FORMS),
             len(tiers['package']), len(tiers['gui'])))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
