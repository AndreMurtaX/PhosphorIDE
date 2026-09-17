#!/usr/bin/env python3
"""A citation that cannot rot quietly -- roadmap item 27.  citations-frozen

WHAT WENT WRONG, AND WHY A BOUNDS CHECK WOULD NOT HAVE CAUGHT IT.

CLAUDE.md's rule is that a fact about Phosphor is EXTRACTED, never retyped, and
that where extraction is impossible the source is cited with a line number. On
2026-09-16 sixteen of those citations, in eight files, pointed at the wrong lines:
the sibling file had grown by about sixty lines and every citation into it had
silently slid off its target. The worst of them, quoted in SEVEN places for "the
lexer has no keyword table", had become the backslash-escape table inside a string
literal.

Every one of those line numbers was still INSIDE the file. A checker that only
asked "does this range exist" would have been green through all of it. The thing
that changed was what the lines SAID, so that is what has to be remembered.

HOW IT WORKS, in one sentence: every citation's target text is fingerprinted into
`tools/citations.lock`, and a citation whose target no longer matches its
fingerprint is an error -- with the tool searching the file for the remembered
text so the report can say where the lines went.

    python tools/check-citations.py            # check; non-zero if anything rotted
    python tools/check-citations.py --update   # re-baseline, PRINTING every change

--update PRINTS WHAT IT CHANGED, and that is not a convenience. A re-baseline that
happens quietly is how the rot comes back: somebody runs it to make the build green
and nobody ever reads the lines again. Printing puts the old and new text in the
diff of the commit that accepted it, where a reviewer can see whether the citation
still supports the claim beside it.

WHAT THIS DOES NOT CATCH, said out loud because the item asks for it. It checks
that a citation points at the text it pointed at before. It cannot check that the
text supports the SENTENCE beside it, and it cannot see a claim with no citation at
all -- which is the second defect the same day produced: CLAUDE.md explained the
no-BOM rule by saying a BOM is a lexical error on line one, which the console host
has stripped since its first commit. The rule was right, the reason had never been
true of that path, and there was no line number in it to go stale. No mechanism
finds that one. Read the cited lines when you touch the claim.
"""
import hashlib
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
# $PHOSPHOR_SIBLING overrides where the other repository is. It exists so the
# "not there" branch can be EXERCISED -- a skip nobody has watched skip is a skip
# that might be an unnoticed pass -- and because a CI job is entitled to pin a
# checkout rather than rely on two directories being siblings.
SIBLING = os.environ.get('PHOSPHOR_SIBLING') or \
    os.path.normpath(os.path.join(ROOT, '..', 'Phosphor'))
LOCK = os.path.join(HERE, 'citations.lock')

# WHERE CITATIONS ARE WRITTEN. Not the whole tree: bin/ holds build output and
# .git holds everything that was ever true.
SCAN_DIRS = ('src', 'docs', 'tools', 'tests', 'scripts')
SCAN_ROOT_FILES = ('CLAUDE.md', 'README.md')
SCAN_EXT = ('.pas', '.lpr', '.md', '.py', '.ps1', '.sh', '.txt')

# WHERE A CITED FILE IS LOOKED FOR, in order. A citation may be written with a
# path (`engine/PhosphorLexer.pas:452`) or with a bare name (`PhosphorVM.pas:177`),
# because both spellings are already in the tree and rewriting sixty of them to
# suit a tool would be the tool deciding how people write prose.
SEARCH_DIRS = (
    (SIBLING, ('engine', 'engine/libs', 'host/console', 'host/packages',
               'lazarus/demo', 'tests', 'scripts', 'docs', '')),
    (ROOT, ('src', 'src/core', 'tests', 'tools', 'scripts', 'docs', '')),
)

# A CITATION IS A FILENAME WITH A SOURCE EXTENSION, A COLON AND A LINE NUMBER.
# The extension is required: without it every `12:34` in prose is a citation.
# A file containing this word anywhere is not scanned. Spelled in two halves so
# that writing ABOUT the marker does not silently freeze the file doing it.
FROZEN = 'citations' + '-frozen'
# ...AND ONLY IN THE HEADER. Anywhere in the file was the first rule and it was
# wrong within the hour: docs/roadmap.md EXPLAINS the marker in its item 27 entry,
# so mentioning it silently froze the file and forty-three citations stopped being
# checked -- a gate quietly switching itself off, which is worse than not having
# one. A declaration belongs where a reader looks for it.
FROZEN_HEAD = 40

CITE = re.compile(
    r'(?<![A-Za-z0-9_.-])'
    r'((?:\.\./)?(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+'
    r'\.(?:pas|lpr|inc|py|ps1|sh))'
    r':(\d+)(?:-(\d+))?'
    r'(?![0-9])')


def norm(line):
    """What counts as the same line. Trailing space and run-length of internal
    space are formatting, not content; a citation must not rot because somebody
    re-indented."""
    return ' '.join(line.split())


def fingerprint(lines):
    body = '\n'.join(norm(x) for x in lines)
    return hashlib.sha256(body.encode('utf-8')).hexdigest()[:16]


def first_real(lines):
    """The first line with something on it -- what a person reads to recognise
    the place, and what the tool searches for when the range has moved."""
    for x in lines:
        if x.strip():
            return norm(x)
    return ''


def resolve(path):
    """The file a citation names, or None. Answers the sibling repository first:
    a name that exists in both is far more likely to be the fact that is not ours
    to retype."""
    if os.path.isabs(path):
        return path if os.path.isfile(path) else None
    cleaned = path[3:] if path.startswith('../') else path
    for base, subs in SEARCH_DIRS:
        for sub in subs:
            cand = os.path.normpath(os.path.join(base, sub, cleaned))
            if os.path.isfile(cand):
                return cand
        # A bare name, looked for by basename under the same roots.
        if '/' not in cleaned:
            for sub in subs:
                cand = os.path.normpath(os.path.join(base, sub, cleaned))
                if os.path.isfile(cand):
                    return cand
    return None


def read_lines(path):
    with io.open(path, encoding='utf-8', errors='replace', newline='') as f:
        return f.read().replace('\r\n', '\n').split('\n')


def scan():
    """Every citation in the tree, as {key: (rel_target, lo, hi, [where])}."""
    found = {}
    files = [os.path.join(ROOT, n) for n in SCAN_ROOT_FILES]
    for d in SCAN_DIRS:
        for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, d)):
            dirnames[:] = [x for x in dirnames
                           if x not in ('__pycache__', 'shots', 'shots-linux',
                                        'lib', 'backup')]
            for n in filenames:
                if n.lower().endswith(SCAN_EXT):
                    files.append(os.path.join(dirpath, n))

    for f in files:
        if not os.path.isfile(f):
            continue
        rel_self = os.path.relpath(f, ROOT).replace('\\', '/')
        try:
            text = io.open(f, encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        # A DOCUMENT ABOUT CITATIONS IS FULL OF THINGS SHAPED LIKE CITATIONS.
        # This file quotes the format; the roadmap quotes the numbers that rotted,
        # BECAUSE they rotted. Neither is a claim about a source file, and a tool
        # that flagged its own manual would teach people to work around it.
        #
        # The marker is in the text rather than in a list here, so a file declares
        # itself and the declaration travels with it -- a list in this script would
        # be a second place to keep in step, which is the defect the whole tool is
        # about. The idea is taken from the unmerged branch named in the roadmap:
        # its author hit this on the first run and solved it the same way.
        if FROZEN in ''.join(text.splitlines(True)[:FROZEN_HEAD]):
            continue
        for m in CITE.finditer(text):
            path, lo, hi = m.group(1), int(m.group(2)), m.group(3)
            hi = int(hi) if hi else lo
            if hi < lo:
                continue
            target = resolve(path)
            if target is None:
                continue
            rel = os.path.relpath(target, ROOT).replace('\\', '/')
            key = '%s:%d-%d' % (rel, lo, hi)
            if key not in found:
                found[key] = [rel, lo, hi, []]
            if rel_self not in found[key][3]:
                found[key][3].append(rel_self)
    return found


def load_lock():
    if not os.path.isfile(LOCK):
        return {}
    out = {}
    for line in io.open(LOCK, encoding='utf-8'):
        line = line.rstrip('\n')
        if not line or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) >= 3:
            out[parts[0]] = (parts[1], parts[2])
    return out


def save_lock(entries):
    with io.open(LOCK, 'w', encoding='utf-8', newline='\n') as f:
        f.write('# Written by tools/check-citations.py --update. Do not hand-edit.\n')
        f.write('# <file>:<lo>-<hi>\\t<fingerprint>\\t<first line of the cited range>\n')
        f.write('#\n')
        f.write('# THE FIRST LINE IS HERE FOR A PERSON, not for the tool: when a\n')
        f.write('# citation goes red this is what it used to point at, and reading it\n')
        f.write('# beside the claim is the whole job. A hash alone would make every\n')
        f.write('# failure a mystery and every fix a re-baseline.\n')
        for key in sorted(entries):
            fp, first = entries[key]
            f.write('%s\t%s\t%s\n' % (key, fp, first))


def main():
    update = '--update' in sys.argv[1:]
    for a in sys.argv[1:]:
        if a not in ('--update',):
            sys.stderr.write('check-citations.py: unknown argument %r\n' % a)
            return 2

    if not os.path.isdir(SIBLING):
        # SKIPPED CLEANLY, because this repository builds without the sibling one
        # and a gate that fails on a machine that never had it is a gate people
        # learn to pass with a flag.
        #
        # IT STILL CHECKS THE CITATIONS IT CAN REACH -- the ones into this
        # repository's own files, which are most of them and which rot faster,
        # because they point at code somebody is editing today. Only the ones that
        # resolve into the sibling are skipped, and the line below says how many
        # so that "skipped" never reads as "there were none".
        known = load_lock()
        skipped = sum(1 for k in known if k.startswith('../Phosphor/'))
        print('citations: %s is not here, so %d citation(s) into it are NOT checked'
              % (SIBLING, skipped))
        if skipped and not update:
            print('           (run this on a machine that has it before believing a'
                  ' green build)')
        return 0

    found = scan()
    lock = load_lock()
    entries = {}
    stale, missing, oob = [], [], []

    for key in sorted(found):
        rel, lo, hi, where = found[key]
        target = os.path.join(ROOT, rel)
        lines = read_lines(target)
        if hi > len(lines):
            oob.append((key, len(lines), where))
            continue
        cited = lines[lo - 1:hi]
        fp = fingerprint(cited)
        first = first_real(cited)
        entries[key] = (fp, first)
        if key not in lock:
            missing.append((key, first, where))
            continue
        if lock[key][0] != fp:
            # WHERE DID IT GO? The remembered first line is searched for, so the
            # report can say "it is now at 511" instead of only "it moved".
            want = lock[key][1]
            moved_to = None
            if want:
                for i, x in enumerate(lines, 1):
                    if norm(x) == want:
                        moved_to = i
                        break
            stale.append((key, lock[key][1], first, moved_to, where))

    if update:
        changed = len(stale) + len(missing)
        for key, was, now, moved, where in stale:
            print('  UPDATED %s' % key)
            print('      was: %s' % was[:100])
            print('      now: %s' % now[:100])
        for key, first, where in missing:
            print('  ADDED   %s  %s' % (key, first[:80]))
        gone = [k for k in lock if k not in entries]
        for k in gone:
            print('  DROPPED %s  (no longer cited anywhere)' % k)
        save_lock(entries)
        print('citations: %d recorded, %d changed, %d dropped'
              % (len(entries), changed, len(gone)))
        return 0

    bad = 0
    for key, n, where in oob:
        print('STALE  %s -- the file has only %d lines' % (key, n))
        print('       cited in: %s' % ', '.join(where))
        bad += 1
    for key, was, now, moved, where in stale:
        print('STALE  %s -- the lines no longer say what they said' % key)
        print('       was: %s' % was[:110])
        print('       now: %s' % now[:110])
        if moved:
            print('       that text is now at line %d' % moved)
        else:
            print('       that text is nowhere in the file now')
        print('       cited in: %s' % ', '.join(where))
        bad += 1
    for key, first, where in missing:
        print('NEW    %s -- not in citations.lock' % key)
        print('       now: %s' % first[:110])
        print('       cited in: %s' % ', '.join(where))
        bad += 1

    if bad:
        print('')
        print('%d citation(s) need attention. READ THE CITED LINES and either fix the'
              % bad)
        print('number or fix the claim beside it; then run:')
        print('    python tools/check-citations.py --update')
        return 1

    print('citations: %d into %d file(s) still point at what they claimed'
          % (len(entries), len(set(k.rsplit(':', 1)[0] for k in entries))))
    return 0


if __name__ == '__main__':
    sys.exit(main())
