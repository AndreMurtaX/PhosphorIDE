#!/usr/bin/env python3
"""Read what a control SAYS, on the machine that could only photograph it.

    ./readtext.py                 list every text-bearing control of phosphoride
    ./readtext.py "Call Stack"    print the text under the control with that name
    ./readtext.py --grep "total"  exit 0 if any control's text contains it
    ./readtext.py --invoke "Exit" click the menu item with that name

AND --invoke CLOSES THE OTHER HALF OF THE GAP. CLAUDE.md has said since
2026-09-16 that the gtk2 MENU BAR "answers neither a synthetic click nor F10
navigation from XTest and so could not be driven at all" -- the one part of this
program no script could reach. That was true of XTest and is not true of AT-SPI:
a menu item exposes one action, and doing it opens the menu's dialog exactly as a
click would. Measured on 2026-09-17: Help > About PhosphorIDE invoked, and the
dialog it opened read back through this same script.

WHY THIS EXISTS. `tools/lane/lane-windows.ps1` asserts on TEXT: it sends
WM_GETTEXT and reads a pane's whole transcript back, which is how the REPL's
conversation was checked line by line. The gtk2 side had no equivalent -- keys go
in through XTest and frames come out through `xwd`, so every Linux assertion was a
picture somebody had to look at. That is why the Linux half of the REPL case
checked the PROCESS TABLE while the Windows half checked the words: not a
different question asked deliberately, a different question asked because the
right one could not be.

WHY AT-SPI AND NOT SOMETHING SIMPLER. This VM has no xdotool, no xclip, no xsel
and no python3-xlib, and roadmap item 28 says the route must not need a package
that is not already here. What IS here is `gi` with `Atspi` 2.0, and
`/usr/lib/x86_64-linux-gnu/gtk-2.0/modules/` holds `libgail.so` and
`libatk-bridge.so` -- the two halves a GTK2 program needs to describe itself. So
the answer was already installed; nothing had asked it.

THE ONE THING THE CALLER MUST DO: start the editor with

    GTK_MODULES=gail:atk-bridge

A GTK2 program without those loads its widgets and tells the accessibility bus
nothing, and this script then finds no application at all -- which reads exactly
like a program that failed to start. `lane-linux.sh` sets it; if you launch the
editor by hand, set it too.

WHAT IT IS NOT. It reads a control's text, not a screenshot's pixels, so it says
nothing about colour, position or whether a mark was drawn. `shot.py` is still the
only witness for those, and the gutter is still a picture. This closes the half of
the gap that was about WORDS.
"""
import sys
import time

try:
    import gi
    gi.require_version('Atspi', '2.0')
    from gi.repository import Atspi
except Exception as exc:                       # pragma: no cover - environment
    sys.stderr.write('readtext: no AT-SPI here (%s)\n' % exc)
    sys.stderr.write('          this needs python3-gi with the Atspi typelib.\n')
    sys.exit(2)

APP = 'phosphoride'


def app_root(timeout=15.0):
    """The editor's accessibility root, or None.

    POLLED, because the bus learns about an application when it registers and
    that is not the instant the process starts. A lane script that queried once
    and gave up would be timing-dependent in the way this whole directory exists
    to avoid.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        desktop = Atspi.get_desktop(0)
        for i in range(desktop.get_child_count()):
            child = desktop.get_child_at_index(i)
            if child is None:
                continue
            name = (child.get_name() or '').lower()
            if APP in name:
                return child
        time.sleep(0.25)
    return None


def walk(node, depth=0, limit=4000):
    """Every accessible under a node, breadth first enough to be readable."""
    out = []
    stack = [(node, depth)]
    while stack and len(out) < limit:
        cur, d = stack.pop(0)
        out.append((cur, d))
        try:
            n = cur.get_child_count()
        except Exception:
            continue
        for i in range(n):
            try:
                kid = cur.get_child_at_index(i)
            except Exception:
                continue
            if kid is not None:
                stack.append((kid, d + 1))
    return out


def text_of(node):
    """What this control says, or ''. Two doors, because AT-SPI has two:
    Text for anything editable or scrolling, and the NAME for a label, a tab or
    a button whose caption IS its text."""
    try:
        iface = node.get_text_iface()
    except Exception:
        iface = None
    if iface is not None:
        try:
            n = Atspi.Text.get_character_count(node)
            if n:
                return Atspi.Text.get_text(node, 0, n)
        except Exception:
            pass
    return ''


def label_of(node):
    try:
        return node.get_name() or ''
    except Exception:
        return ''


def role_of(node):
    try:
        return node.get_role_name() or '?'
    except Exception:
        return '?'


def showing(node):
    """Is this control actually on screen?

    AT-SPI WALKS THE WHOLE WIDGET TREE, INCLUDING THE PAGES NOBODY SWITCHED TO.
    A GTK notebook keeps every page's widgets alive and describable, so a `--grep`
    that only asked "is this string anywhere in the tree" answered YES for the
    Watches hint while the Output tab was showing, and YES for the call-stack rows
    while nothing had clicked the Call Stack tab. Measured 2026-09-18:

        An answer for the running program   SHOWING=True   VISIBLE=True
        An expression to watch              SHOWING=False  VISIBLE=False
        *.bas                               SHOWING=False  VISIBLE=False

    That is not a small distinction. steps-stack-linux.txt clicks a tab strip at
    a coordinate that stopped being right when the window grew, so its three
    screenshots came back BYTE-IDENTICAL -- the pane never changed -- and every
    text assertion in it passed anyway. The case believed it proved "the call
    stack pane shows five frames" and proved "the call stack list holds five
    rows, on a tab nobody went to".

    SHOWING and not VISIBLE: VISIBLE means the widget would be drawn if its
    ancestors were, SHOWING means they are. A control on a hidden notebook page
    is VISIBLE and not SHOWING, which is exactly the case that needs excluding."""
    try:
        return node.get_state_set().contains(Atspi.StateType.SHOWING)
    except Exception:
        # A control that will not answer is not one this can vouch for.
        return False


def main():
    args = sys.argv[1:]
    grep = None
    invoke = None
    where = None
    selected = None
    # `--any` drops back to the old behaviour: assert the string is somewhere in
    # the widget tree, showing or not. Kept because one legitimate use exists --
    # checking that a pane HOLDS something before the click that reveals it --
    # and named so that a case using it says so out loud.
    any_state = '--any' in args
    args = [a for a in args if a != '--any']
    if args and args[0] == '--invoke':
        if len(args) < 2:
            sys.stderr.write('readtext: --invoke needs something to act on\n')
            return 2
        invoke = args[1]
        args = args[2:]
    elif args and args[0] == '--selected':
        if len(args) < 2:
            sys.stderr.write('readtext: --selected needs a tab name\n')
            return 2
        selected = args[1]
        args = args[2:]
    elif args and args[0] == '--where':
        if len(args) < 2:
            sys.stderr.write('readtext: --where needs a control to locate\n')
            return 2
        where = args[1]
        args = args[2:]
    elif args and args[0] == '--grep':
        if len(args) < 2:
            sys.stderr.write('readtext: --grep needs something to look for\n')
            return 2
        grep = args[1]
        args = args[2:]

    root = app_root()
    if root is None:
        sys.stderr.write('readtext: no accessible application named %r.\n' % APP)
        sys.stderr.write('          Was it started with GTK_MODULES=gail:atk-bridge?\n')
        return 1

    nodes = walk(root)
    if grep is not None:
        hidden = None
        for node, _ in nodes:
            if grep not in text_of(node) and grep not in label_of(node):
                continue
            if showing(node) or any_state:
                print('found in %s %r%s' % (role_of(node), label_of(node)[:40],
                                            '' if showing(node) else '  (NOT SHOWING)'))
                return 0
            if hidden is None:
                hidden = node
        if hidden is not None:
            # THE DIAGNOSTIC THAT TURNS A SILENT PASS INTO A USEFUL RED. Finding
            # the string on a page nobody switched to is a different failure from
            # not finding it at all, and it names the one thing worth checking:
            # the click that was supposed to bring that page forward.
            sys.stderr.write(
                'readtext: %r is in a %s the program is NOT SHOWING '
                '(a closed tab, a hidden pane).\n' % (grep, role_of(hidden)))
            sys.stderr.write(
                '          Whatever was meant to bring it on screen did not.\n')
            sys.stderr.write(
                '          Pass --any to assert on the widget tree instead.\n')
            return 1
        sys.stderr.write('readtext: %r is in no control this program shows\n' % grep)
        return 1

    if selected is not None:
        # IS THIS TAB THE ONE ON SCREEN? SHOWING cannot answer it: GTK 2 leaves
        # SHOWING set on the notebook page that LEAVES, so a pane visited once
        # stays assertable for the rest of the run. Measured 2026-09-18 -- after
        # switching Outline -> REPL, both panes' contents reported SHOWING.
        # SELECTED is the state that flips, and a page tab carries it.
        tabs = [n for n, _ in nodes if role_of(n) == 'page tab']
        hits = [n for n in tabs if label_of(n) == selected] or \
               [n for n in tabs if label_of(n).startswith(selected)]
        if not hits:
            sys.stderr.write('readtext: no page tab is named %r\n' % selected)
            return 1
        if len(hits) > 1:
            sys.stderr.write('readtext: %r matches %d tabs: %s\n'
                             % (selected, len(hits),
                                ', '.join(repr(label_of(n)) for n in hits)))
            return 1
        node = hits[0]
        try:
            ok = node.get_state_set().contains(Atspi.StateType.SELECTED)
        except Exception:
            ok = False
        if ok:
            print('selected %r' % label_of(node))
            return 0
        sys.stderr.write('readtext: %r is not the selected tab\n' % label_of(node))
        return 1

    if where is not None:
        # WHERE A CONTROL ACTUALLY IS, in screen coordinates, so a script can
        # click it instead of assuming an offset. A page tab exposes no ACTION
        # under gail -- so it cannot be invoked the way a menu item can -- but it
        # does expose EXTENTS, which is the half CLAUDE.md had wrong until
        # 2026-09-18. The centre is printed, because an edge is where a border is.
        shown = [n for n, _ in nodes if showing(n)]
        exact = [n for n in shown if label_of(n) == where]
        # A PREFIX, BECAUSE A CAPTION CHANGES UNDER A SCRIPT. While a debug
        # session is live the pane tabs carry their counts -- `Call Stack (5)`,
        # `Variables (3)` -- and before it starts they do not, so an exact match
        # finds the tab only when nothing is happening. Measured 2026-09-18: the
        # same case located the tab on one run and not the next for exactly this
        # reason.
        pref = [n for n in shown if label_of(n).startswith(where)]
        hits = exact or pref
        if len(hits) > 1:
            # NOT THE FIRST OF SEVERAL. A locator that guessed would click
            # whichever the tree listed first, which is the ambiguity --invoke
            # already had to be taught about.
            sys.stderr.write('readtext: %r matches %d controls: %s\n'
                             % (where, len(hits),
                                ', '.join(repr(label_of(n)) for n in hits[:5])))
            return 1
        for node in hits:
            try:
                e = Atspi.Component.get_extents(node, Atspi.CoordType.SCREEN)
            except Exception as exc:
                sys.stderr.write('readtext: %r has no extents (%s)\n' % (where, exc))
                return 1
            if e.width <= 0 or e.height <= 0:
                sys.stderr.write('readtext: %r has an empty rectangle\n' % where)
                return 1
            print('%d %d' % (e.x + e.width // 2, e.y + e.height // 2))
            return 0
        sys.stderr.write('readtext: nothing showing is named %r\n' % where)
        return 1

    if invoke is not None:
        # A MENU AND ITS ITEM CAN CARRY THE SAME NAME, and the menu comes first in
        # the tree. Measured 2026-09-18 on the release binary: `--invoke Run`
        # matched the top-level Run MENU -- which opens it and does nothing else --
        # while the Run ITEM sat two levels down waiting. The caller asked for an
        # action, so an item that performs one is what was meant; the menu is the
        # fallback for a name that only a menu carries.
        candidates = []
        for node, _ in nodes:
            if label_of(node) != invoke:
                continue
            try:
                n = Atspi.Action.get_n_actions(node)
            except Exception:
                n = 0
            if n < 1:
                continue
            candidates.append(node)
        candidates.sort(key=lambda x: 0 if role_of(x) == 'menu item' else 1)
        for node in candidates:
            try:
                Atspi.Action.do_action(node, 0)
            except Exception as exc:
                sys.stderr.write('readtext: %r would not act (%s)\n' % (invoke, exc))
                return 1
            print('invoked %s %r' % (role_of(node), invoke))
            return 0
        sys.stderr.write('readtext: nothing named %r can be acted on\n' % invoke)
        return 1

    if args:
        want = args[0]
        hits = 0
        for node, _ in nodes:
            if label_of(node) != want:
                continue
            hits += 1
            body = text_of(node)
            if body:
                sys.stdout.write(body if body.endswith('\n') else body + '\n')
            # A container named for what it holds -- a tab sheet, a panel -- has
            # no text of its own, so its children are what was meant.
            for kid, _ in walk(node):
                if kid is node:
                    continue
                kbody = text_of(kid)
                if kbody:
                    sys.stdout.write(kbody if kbody.endswith('\n') else kbody + '\n')
        if hits == 0:
            sys.stderr.write('readtext: no control named %r\n' % want)
            return 1
        return 0

    for node, d in nodes:
        body = text_of(node)
        lab = label_of(node)
        if not body and not lab:
            continue
        one = body.replace('\n', ' | ')
        print('%s%-18s %-28s %s' % ('  ' * d, role_of(node), lab[:28], one[:90]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
