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


def main():
    args = sys.argv[1:]
    grep = None
    invoke = None
    if args and args[0] == '--invoke':
        if len(args) < 2:
            sys.stderr.write('readtext: --invoke needs something to act on\n')
            return 2
        invoke = args[1]
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
        for node, _ in nodes:
            if grep in text_of(node) or grep in label_of(node):
                print('found in %s %r' % (role_of(node), label_of(node)[:40]))
                return 0
        sys.stderr.write('readtext: %r is in no control this program shows\n' % grep)
        return 1

    if invoke is not None:
        for node, _ in nodes:
            if label_of(node) != invoke:
                continue
            try:
                n = Atspi.Action.get_n_actions(node)
            except Exception:
                n = 0
            if n < 1:
                continue
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
