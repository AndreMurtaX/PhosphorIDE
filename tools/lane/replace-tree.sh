#!/usr/bin/env bash
# Replace in files, end to end, against a fixture directory -- roadmap item 21,
# under gtk2. The counterpart of replace-tree.ps1; see that file for why this is
# a script rather than a steps-*.txt (it CHANGES files, and a case that rewrites
# something under tools/lane leaves the repository dirty after every run).
#
#   bash tools/lane/replace-tree.sh
#
# The four files and what each is for are the same as on Windows:
#
#   a.bas      OPEN in the editor, so it takes the BUFFER route. Its bytes ON
#              DISK must NOT change.
#   b.bas      CRLF, not open. Rewritten, and CRLF must survive.
#   sub/c.bas  LF with NO closing newline. Rewritten, and it must not gain one.
#   d.bas      matches nothing. Byte-identical, and never opened.
#
# THE CLICKS ARE MEASURED UP FROM THE BOTTOM (`bot`), like every other Linux
# script here except the folding ones: the find pane is anchored to the bottom of
# the window and mutter gives this window a different height on different runs.
# The three rows sit at 151 (Find), 123 (In) and 95 (Replace).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
ROOT="${TMPDIR:-/tmp}/phosphoride-replace-tree"

rm -rf "$ROOT"
mkdir -p "$ROOT/sub"

printf 'rem alpha one\nx = alpha\nrem three\n' > "$ROOT/a.bas"
printf 'rem alpha\r\ny = 2\r\n'                > "$ROOT/b.bas"
printf 'z = alpha'                             > "$ROOT/sub/c.bas"
printf 'nothing here\n'                        > "$ROOT/d.bas"

FILES="a.bas b.bas sub/c.bas d.bas"
declare -A BEFORE
for f in $FILES; do
    BEFORE[$f]="$(od -An -tx1 "$ROOT/$f" | tr -s ' ' | tr -d '\n')"
done

cat > "$ROOT/steps.txt" <<STEPS
raise
key ctrl+shift+f
wait 800
type alpha
wait 300
bot 210 123
wait 400
key ctrl+a
type $ROOT
wait 400
bot 210 151
wait 400
key Return
wait 2000
shot 340-the-rows-the-search-listed
bot 210 95
wait 400
type beta
wait 400
bot 550 95
wait 900
shot 341-the-question-with-the-counts
key Return
wait 1500
raise
wait 500
shot 342-replaced-and-the-tab-is-modified
at 300 120
wait 500
key ctrl+z
wait 900
raise
wait 400
shot 343-one-undo-took-it-all-back
STEPS

bash "$HERE/lane-linux.sh" "$ROOT/a.bas" "$ROOT/steps.txt" 2>&1 |
    grep -E 'done|\.png' | tail -6

declare -A EXPECT
EXPECT[a.bas]=INTACTO      # open in a tab: the change is in the buffer
EXPECT[b.bas]=MUDOU
EXPECT['sub/c.bas']=MUDOU
EXPECT[d.bas]=INTACTO

bad=0
echo
printf '%-12s %-9s %-9s %s\n' file expected got 'bytes now'
for f in $FILES; do
    now="$(od -An -tx1 "$ROOT/$f" | tr -s ' ' | tr -d '\n')"
    if [ "$now" = "${BEFORE[$f]}" ]; then got=INTACTO; else got=MUDOU; fi
    [ "$got" = "${EXPECT[$f]}" ] || bad=$((bad + 1))
    printf '%-12s %-9s %-9s %s\n' "$f" "${EXPECT[$f]}" "$got" "$now"
done
echo
if [ "$bad" -eq 0 ]; then
    echo 'REPLACE TREE OK'
else
    echo "REPLACE TREE FAILED: $bad file(s) wrong"
    exit 1
fi
