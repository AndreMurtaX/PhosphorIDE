#!/usr/bin/env bash
# The debugger lane under gtk2, driven rather than merely constructed.
#
# Windows proved it on 2026-09-16; this is the other half of the bar. Keys go in
# through XTest (./xdrive), frames come out through xwd and PIL (./shot.py),
# because this VM has neither xdotool nor ImageMagick.
#
# Two traps paid for here on 2026-09-16:
#
#  * `xwininfo -root -tree | grep PhosphorIDE` finds the mutter FRAME first, and
#    XGetImage on a frame is BadMatch -- xwd then writes a zero-byte file and
#    exits 1. The client window is the one whose CLASS is phosphoride. There are
#    also three decoy 10x10 windows named "phosphoride": the LCL's own hidden
#    top-levels, exactly the trap Windows has with MainWindowHandle.
#  * A background GUI holding the ssh channel's stdout keeps ssh from returning
#    even after the script ends. setsid plus a redirect, or the caller waits
#    forever for a window nobody is watching.
set -u

# This script's own directory, so it runs from the repository checkout rather
# than from wherever it was first written. $0 rather than BASH_SOURCE because it
# is never sourced.
HERE="$(cd "$(dirname "$0")" && pwd)"
# ../../bin/phosphoride, and PHOSPHORIDE overrides for a binary built elsewhere.
IDE="${PHOSPHORIDE:-$HERE/../../bin/phosphoride}"

# THE EDITOR HAS TO DESCRIBE ITSELF, or `text` and `say` find no application at
# all -- which reads exactly like a program that failed to start. A GTK2 program
# loads its widgets and tells the accessibility bus nothing unless these two
# modules are asked for by name; both are already installed here, in
# /usr/lib/x86_64-linux-gnu/gtk-2.0/modules/. Exported rather than set on the one
# launch line because the editor is started in more than one place below.
export GTK_MODULES="${GTK_MODULES:-gail:atk-bridge}\"
OUT="$HERE/shots"
mkdir -p "$OUT"
rm -f "$OUT"/*.png "$OUT"/*.xwd

export DISPLAY=:0
export XAUTHORITY=$(ls /run/user/1000/.mutter-Xwaylandauth.* 2>/dev/null | head -1)

fixture="${1:-$HERE/lane345.bas}"
script="${2:-$HERE/steps-lane.txt}"

setsid "$IDE" "$fixture" >"$OUT/ide.log" 2>&1 < /dev/null &
IDE_PID=$!
sleep 6

WIN=$(xwininfo -root -tree 2>/dev/null \
      | grep -m1 -E '\- PhosphorIDE": \("phosphoride"' \
      | sed -E 's/^ *([0-9a-fx]+) .*/\1/')
if [ -z "$WIN" ]; then
    echo "no PhosphorIDE client window found" >&2
    xwininfo -root -tree 2>&1 | grep -i phosphor >&2
    kill $IDE_PID 2>/dev/null
    exit 1
fi
echo "window $WIN  pid $IDE_PID"
xwininfo -id "$WIN" | grep -E 'Absolute upper-left|Width:|Height:'

# EVERY POPUP THIS PROGRAM OWNS, RECORDED AS "NOT YET THERE". A GTK menu, a
# completion list and a hint are override-redirect windows of their OWN, which is
# why `xwd -id $WIN` photographs the form with nothing over it -- recorded twice
# in this repository as "cannot be photographed at all", and wrong twice. They
# are in the root's tree; the only hard part is telling them from the LCL's three
# permanent decoys and from the mutter frame.
#
# So the set of the process's own top-level windows is taken once, before
# anything can pop up, and `popshot` photographs whatever is NEW. No rule about
# sizes, no guess about names.
own_windows() {
    xwininfo -root -tree 2>/dev/null | grep -E '\("phosphoride"' |
        sed -E 's/^ *(0x[0-9a-f]+).*/\1/' | sort
}
BASE_WINDOWS="$(own_windows)"

# A GTK menu is an override-redirect window of its OWN, not a child of the form,
# so `xwd -id $WIN` photographs a window with no menu in it however open the menu
# is. The whole root is the only way to see one. Paid for on 2026-09-16 by
# concluding twice that a menu had not opened when it had.
# A popup: the process's top-level window that was not there at startup.
# EVERY NEW WINDOW, NOT THE FIRST ONE. A completion list and a hint are
# override-redirect and arrive alone, so `head -1` was right for them. A MODAL
# DIALOG is an ordinary top-level, so mutter gives it a FRAME -- and the frame is
# also new, also carries the process's WM_CLASS, and comes first in the tree.
# XGetImage on a frame is BadMatch, which is the same trap the main window
# taught this lane at the top of this file, met a second time from the other
# side. Measured 2026-09-16, on the Go to Definition dialog: popshot answered
# `BadMatch (invalid parameter attributes)` and photographed nothing.
#
# So: try them in order and keep the first that actually yields an image.
popshot() {
    local new win
    new=$(comm -13 <(printf '%s\n' "$BASE_WINDOWS") <(own_windows))
    if [ -z "$new" ]; then
        echo "  NO POPUP FOUND for $1" >&2
        return
    fi
    for win in $new; do
        if xwd -id "$win" -out "$OUT/$1.xwd" 2>"$OUT/$1.err"; then
            if python3 "$HERE/shot.py" "$OUT/$1.xwd" "$OUT/$1.png"; then
                rm -f "$OUT/$1.xwd" "$OUT/$1.err"
                return
            fi
        fi
    done
    echo "  POPSHOT FAILED $1: $(head -1 "$OUT/$1.err")" >&2
}

rootshot() {
    if xwd -root -out "$OUT/$1.xwd" 2>"$OUT/$1.err"; then
        python3 "$HERE/shot.py" "$OUT/$1.xwd" "$OUT/$1.png" && rm -f "$OUT/$1.xwd" "$OUT/$1.err"
    else
        echo "  ROOTSHOT FAILED $1: $(head -1 "$OUT/$1.err")" >&2
    fi
}

shot() {
    if xwd -id "$WIN" -out "$OUT/$1.xwd" 2>"$OUT/$1.err"; then
        python3 "$HERE/shot.py" "$OUT/$1.xwd" "$OUT/$1.png" && rm -f "$OUT/$1.xwd" "$OUT/$1.err"
    else
        echo "  SHOT FAILED $1: $(head -1 "$OUT/$1.err")" >&2
    fi
}

# The Output tab, in absolute screen coordinates, because mutter chooses where
# the window goes and a fixed pair would be right until it moved it.
outtab() {
    local x y h
    x=$(xwininfo -id "$WIN" | awk '/Absolute upper-left X/{print $4}')
    y=$(xwininfo -id "$WIN" | awk '/Absolute upper-left Y/{print $4}')
    h=$(xwininfo -id "$WIN" | awk '/^  Height:/{print $2}')
    # Measured from the BOTTOM. The output panel is bottom-anchored, and a fixed
    # offset from the top hit the Name column header the first time the window
    # came up 25 pixels shorter than the run it was measured on.
    printf 'click %d %d\n' $((x + 33)) $((y + h - 184)) | "$HERE/xdrive" "$WIN" >/dev/null
}

# CONSECUTIVE KEYS GO IN ONE INVOCATION. xdrive raises and focuses the window as
# it starts, and a GTK menu holds a keyboard grab -- so a second invocation
# between `Down` and `End` took the grab away and the menu stopped listening.
# Measured on 2026-09-16: Debug > Stop Debugging never fired, twice.
#
# And NOTHING steals focus on the way in. Every invocation is `nofocus`; a script
# that wants the window focused says `raise` as its first line, which xdrive also
# understands as a command. Otherwise the keys meant for an open menu arrive
# after that menu has been dismissed by the very act of delivering them.
buf=""
flush() {
    [ -z "$buf" ] && return 0
    printf '%s' "$buf" | "$HERE/xdrive" "$WIN" nofocus >/dev/null
    buf=""
}

# `at DX DY` clicks a point given relative to the window's top-left corner, so a
# script can name a menu title or a menu row without knowing where mutter put the
# window this time.
at() {
    local x y verb
    verb="${3:-click}"
    x=$(xwininfo -id "$WIN" | awk '/Absolute upper-left X/{print $4}')
    y=$(xwininfo -id "$WIN" | awk '/Absolute upper-left Y/{print $4}')
    printf '%s %d %d\n' "$verb" $((x + $1)) $((y + $2)) | "$HERE/xdrive" "$WIN" nofocus >/dev/null
}

# `bot DX DYUP` -- the same click, measured UP FROM THE BOTTOM EDGE.
#
# Not a convenience: mutter gives this window a different height on different
# runs (700, 725 and 750 all seen on 2026-09-16), so anything below the editor
# moves between runs and an offset from the top clicks into the wrong pane. The
# output panel is bottom-anchored, so from the bottom every row is where it was.
bot() {
    local x y h verb
    verb="${3:-click}"
    x=$(xwininfo -id "$WIN" | awk '/Absolute upper-left X/{print $4}')
    y=$(xwininfo -id "$WIN" | awk '/Absolute upper-left Y/{print $4}')
    h=$(xwininfo -id "$WIN" | awk '/^  Height:/{print $2}')
    printf '%s %d %d\n' "$verb" $((x + $1)) $((y + h - $2)) | "$HERE/xdrive" "$WIN" nofocus >/dev/null
}

# READING WHAT A CONTROL SAYS, which this side could not do until roadmap item 28.
#
# Every assertion on this machine used to be a PICTURE. Windows sends WM_GETTEXT
# and reads a pane's whole transcript back word for word; here, keys went in
# through XTest and frames came out through xwd, so the Linux half of the REPL
# case checked the PROCESS TABLE while the Windows half checked the conversation
# -- a weaker question, asked because the right one could not be.
#
# `say <name>` prints what the control called <name> contains. `text <needle>`
# asserts that some control contains <needle> and FAILS THE RUN if none does,
# which is the verb worth having: a lane that only prints is a lane somebody has
# to read.
#
# Both go through readtext.py, which uses AT-SPI -- see its header for why that
# and not xdotool, xclip or python3-xlib, none of which is on this machine.
FAILURES=0

say() {
    echo "--- text of: $1 ---"
    python3 "$HERE/readtext.py" "$1" 2>&1 | sed 's/^/    /'
}

text() {
    if python3 "$HERE/readtext.py" --grep "$1" >/dev/null 2>&1; then
        echo "TEXT OK   $1"
    else
        echo "TEXT FAIL no control says: $1"
        FAILURES=$((FAILURES + 1))
    fi
}

while IFS= read -r line; do
    case "$line" in
        shot\ *) flush; shot "${line#shot }" ;;
        rootshot\ *) flush; rootshot "${line#rootshot }" ;;
        popshot\ *) flush; popshot "${line#popshot }" ;;
        at\ *) flush; at ${line#at } ;;
        at2\ *) flush; at ${line#at2 } dblclick ;;
        bot\ *) flush; bot ${line#bot } ;;
        bot2\ *) flush; bot ${line#bot2 } dblclick ;;
        outtab)  flush; outtab ;;
        say\ *) flush; say "${line#say }" ;;
        text\ *) flush; text "${line#text }" ;;
        ''|'#'*) : ;;
        *) buf="$buf$line
" ;;
    esac
done < "$script"
flush

echo "--- listening sockets held by $IDE_PID ---"
ss -ltnp 2>/dev/null | grep "pid=$IDE_PID," || echo "  none"
echo "--- phosphor children ---"
pgrep -a phosphor | grep -v phosphoride || echo "  none"
echo "--- the child's own stdio ---"
cat "$OUT/ide.log"

echo "$IDE_PID" > "$OUT/pid.txt"

# A LANE THAT ONLY PRINTS IS A LANE SOMEBODY HAS TO READ. `text` assertions are
# counted, and a run with a failed one says so in its last line and in its exit
# code -- which is what lets this be run from a script rather than watched.
if [ "$FAILURES" -gt 0 ]; then
    echo "TEXT ASSERTIONS FAILED: $FAILURES"
else
    echo "text assertions: all passed"
fi

# CLOSE BOTH, unless the caller says otherwise. Killing the editor does not kill
# the program it was debugging -- a phosphor stopped at a breakpoint simply loses
# the only thing that was going to tell it to continue -- so the child goes too.
# LANE_KEEP=1 leaves everything up for a look.
if [ "${LANE_KEEP:-0}" = "1" ]; then
    echo "done; pid $IDE_PID left running"
else
    kill "$IDE_PID" 2>/dev/null
    sleep 1
    pkill -x phosphoride 2>/dev/null
    pkill -x phosphor 2>/dev/null
    echo "done; closed"
fi

exit $((FAILURES > 0))
