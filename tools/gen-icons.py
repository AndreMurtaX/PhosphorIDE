#!/usr/bin/env python3
"""Draw the toolbar icons and write src/core/uphosphoricons.pas.

    python tools/gen-icons.py            regenerate the unit
    python tools/gen-icons.py --check    fail if the unit is not what this
                                         script would write

Both the unit and tools/icons-preview.png are written by the same run and checked
by the same --check: the sheet is the only form of these icons a person can
review, and a set that has drifted from the picture of it is worse than no
picture.

WHY A GENERATOR AND NOT A .LFM FULL OF BITMAP DATA. A TImageList streams its
images into the form file as one binary blob, and umainform.lfm is a file people
edit by hand. A blob in there cannot be reviewed, cannot be diffed, and cannot be
changed without a designer. The icons are therefore DRAWN HERE, in the one place
that knows what they mean, and the unit this writes is generated exactly the way
uphosphorlang.pas is -- for the same reason, and with the same rule on it: never
hand-edit the output.

NO PILLOW, NO IMAGEMAGICK, NOTHING. The PNG writer below is thirty lines of zlib
and struct, and it keeps this script runnable on any machine with a Python -- the
Ubuntu VM that is this project's second reality has no Pillow, and installing
packages there needs its owner's say-so.

TWO SIZES, DRAWN TWICE, NOT SCALED ONCE. The roadmap names this trap before it
was hit: a single-resolution image list is scaled by the widgetset, the two
widgetsets scale differently, one gives a blurred mark and the other a missing
one, and neither is a build failure. So every icon is rasterised at 16 and at 24
from the same geometry, and both go into the list through
TCustomImageList.AddMultipleResolutions. The geometry is written in EIGHTHS of
the icon box, which is why the pair stays crisp: 16 and 24 are both divisible by
8, so every coordinate lands on a whole pixel at both sizes with no rounding.

THE TOOLBAR IS LIGHT ON WINDOWS AND DARK ON GTK2. Measured, in this project's own
screenshots: the Win32 toolbar is near-white with dark text and the gtk2 one under
Ubuntu's default theme is near-black with light text. One icon set has to read on
both, so nothing here is drawn in near-black or near-white alone: every glyph
carries a saturated mid-tone that has contrast against either end, and where an
outline is needed it is a mid grey rather than black. A dark outline on a dark
toolbar is an icon nobody can see, and it is not a build failure either.
"""
import io
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'src', 'core', 'uphosphoricons.pas')
PREVIEW = os.path.join(ROOT, 'tools', 'icons-preview.png')
SIZES = (16, 24)

# ----------------------------------------------------------------- palette --
# Mid-tones on purpose; see the header. A is alpha.
CLEAR = (0, 0, 0, 0)
PAPER = (0xF2, 0xF2, 0xEE, 0xFF)   # a page, a label -- light but not white
INK = (0x60, 0x66, 0x70, 0xFF)     # outlines: mid grey, visible on both ends
GREEN = (0x3F, 0xA9, 0x4A, 0xFF)   # run, check
RED = (0xD0, 0x3B, 0x2F, 0xFF)     # stop
MAROON = (0xA6, 0x1B, 0x1B, 0xFF)  # a breakpoint, the colour the gutter uses
AMBER = (0xE0, 0xA0, 0x30, 0xFF)   # a folder
DARKAMBER = (0xB8, 0x7C, 0x18, 0xFF)  # ...and its tab
BLUE = (0x37, 0x7E, 0xC8, 0xFF)    # a floppy, the step arrows
DARKBLUE = (0x24, 0x5A, 0x92, 0xFF)


class Canvas(object):
    def __init__(self, size):
        self.s = size
        self.px = [[CLEAR] * size for _ in range(size)]

    def u(self, eighths):
        """A coordinate in eighths of the box -> whole pixels at every size."""
        return int(round(eighths * self.s / 8.0))

    def put(self, x, y, c):
        if 0 <= x < self.s and 0 <= y < self.s and c[3]:
            self.px[y][x] = c

    def fill(self, x0, y0, x1, y1, c):
        """Eighths, half-open: fill(1, 1, 7, 7) is a box one eighth inside."""
        for y in range(self.u(y0), self.u(y1)):
            for x in range(self.u(x0), self.u(x1)):
                self.put(x, y, c)

    def frame(self, x0, y0, x1, y1, c, t=1):
        """An outline t DEVICE pixels thick -- thickness is not scaled, because
        a one-pixel line is a one-pixel line at both sizes and a scaled one is
        the blur this whole file is avoiding."""
        px0, py0, px1, py1 = self.u(x0), self.u(y0), self.u(x1), self.u(y1)
        for y in range(py0, py1):
            for x in range(px0, px1):
                if (x < px0 + t or x >= px1 - t or
                        y < py0 + t or y >= py1 - t):
                    self.put(x, y, c)

    def poly(self, pts, c):
        """Scanline fill of a polygon given in eighths."""
        p = [(self.u(x), self.u(y)) for x, y in pts]
        ys = [y for _, y in p]
        for y in range(min(ys), max(ys)):
            xs = []
            for i in range(len(p)):
                (x0, y0), (x1, y1) = p[i], p[(i + 1) % len(p)]
                if y0 == y1:
                    continue
                if min(y0, y1) <= y < max(y0, y1):
                    xs.append(x0 + (y - y0) * (x1 - x0) / float(y1 - y0))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                for x in range(int(round(xs[i])), int(round(xs[i + 1]))):
                    self.put(x, y, c)

    def disc(self, cx, cy, r, c):
        pcx, pcy = cx * self.s / 8.0, cy * self.s / 8.0
        pr = r * self.s / 8.0
        for y in range(self.s):
            for x in range(self.s):
                if (x + 0.5 - pcx) ** 2 + (y + 0.5 - pcy) ** 2 <= pr * pr:
                    self.put(x, y, c)

    def ring(self, cx, cy, r_out, r_in, c):
        """An annulus, drawn as one shape rather than as a disc with a hole
        punched in it: `put` will not write a transparent pixel -- it is what
        keeps every glyph from squaring off its own background -- so there is no
        erasing here, and the hollow mark has to be filled as a ring."""
        pcx, pcy = cx * self.s / 8.0, cy * self.s / 8.0
        ro, ri = r_out * self.s / 8.0, r_in * self.s / 8.0
        for y in range(self.s):
            for x in range(self.s):
                d = (x + 0.5 - pcx) ** 2 + (y + 0.5 - pcy) ** 2
                if ri * ri <= d <= ro * ro:
                    self.put(x, y, c)

    def png(self):
        raw = bytearray()
        for row in self.px:
            raw.append(0)                       # filter: none
            for r, g, b, a in row:
                raw += bytes((r, g, b, a))

        def chunk(tag, data):
            return (struct.pack('>I', len(data)) + tag + data +
                    struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))

        ihdr = struct.pack('>IIBBBBB', self.s, self.s, 8, 6, 0, 0, 0)
        return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) +
                chunk(b'IDAT', zlib.compress(bytes(raw), 9)) +
                chunk(b'IEND', b''))


# ------------------------------------------------------------------ glyphs --
# Every coordinate is in eighths. The shapes are deliberately blunt: at 16 px a
# curve is three pixels and reads as a smudge, so these are rectangles,
# triangles and discs, which are the same idea at both sizes.

def new_page(c):
    c.fill(2, 1, 6, 7, PAPER)
    c.frame(2, 1, 6, 7, INK)
    c.poly([(5, 1), (6, 1), (6, 2)], INK)       # the folded corner
    c.fill(3, 3, 5, 3.5, INK)                   # two lines of text
    c.fill(3, 4.5, 5, 5, INK)


def open_folder(c):
    # A TAB AND A BODY, not an open folder with a visible back flap. The open
    # one was drawn first and judged in the preview sheet: at 16 px the flap is
    # two pixels and the paper behind it reads as a stray amber mark on the
    # right. Two rectangles survive the small size, which is the only size that
    # decides anything here.
    c.fill(1, 2, 3.5, 3, DARKAMBER)
    c.fill(1, 3, 7, 6.5, AMBER)


def save_floppy(c):
    c.fill(1, 1, 7, 7, BLUE)
    c.fill(2.5, 1, 5.5, 3, PAPER)               # the shutter
    c.fill(4, 1.5, 5, 2.5, DARKBLUE)            # ...and its slot
    c.fill(2, 4.5, 6, 7, PAPER)                 # the label
    c.fill(2.5, 5, 5.5, 5.5, INK)


def run_play(c):
    c.poly([(2.5, 1.5), (2.5, 6.5), (6.5, 4)], GREEN)


def stop_square(c):
    c.fill(2, 2, 6, 6, RED)


def check_syntax(c):
    # A tick, drawn as two thick bars rather than a stroked path: a path at
    # 16 px is anti-aliased into grey mush by anything that draws it for you.
    c.poly([(1.5, 3.5), (2.5, 2.5), (3.5, 5), (3.5, 6.5)], GREEN)
    c.poly([(3.5, 6.5), (2.75, 5.75), (6, 1.5), (6.75, 2.5)], GREEN)


def breakpoint_dot(c):
    c.disc(4, 4, 2.25, MAROON)


def step_over(c):
    # AN ARROW PASSING ABOVE THE DOT. The first version drew the conventional
    # arc -- up, across, down onto the next line -- and at 16 px the arrowhead
    # and the dot touched, which reads as one smudge rather than two things.
    # A straight arrow over a dot says the same and survives the size.
    c.fill(1.5, 2.5, 5, 3.5, BLUE)              # the shaft
    c.poly([(4.75, 1.75), (7, 3), (4.75, 4.25)], BLUE)
    c.disc(4, 6.25, 1.1, INK)                   # the line it went past


def step_into(c):
    # Down INTO the dot, and the gap between the head and the dot is the whole
    # difference from step over: the head stops a pixel short at 16 and two at
    # 24, which is enough to read as an arrow arriving rather than a blob.
    c.fill(3.5, 1.25, 4.5, 3.5, BLUE)           # the shaft
    c.poly([(2.5, 3.5), (5.5, 3.5), (4, 5.25)], BLUE)
    c.disc(4, 6.6, 0.85, INK)              # clear of the bottom edge at 16


# ------------------------------------------------------------ gutter marks --
# These do not go on the toolbar. They go in SynEdit's gutter, one per
# breakpoint, and the pair carries the one fact the editor learned from the host
# and cannot show any other way: whether the mark is bound to a statement.
#
# SOLID MEANS ARMED, HOLLOW MEANS THE HOST COULD NOT BIND IT -- the convention
# every debugger uses, and the reason it is a convention is that the two read as
# the same KIND of thing at a glance and as different states on a second look.
# A hollow ring at 16 px is a 5-pixel circle with a hole in it, which is why the
# outer radius is generous and the hole is small: at that size a one-pixel ring
# is a smudge and a two-pixel one is a dot.
#
# Both are maroon. Grey for the inert one was tried on paper and rejected: the
# gutter already greys things it considers unimportant, and a breakpoint the user
# deliberately placed is not unimportant -- it is a breakpoint that will not
# fire, which is a thing to notice rather than to overlook.

def break_armed(c):
    c.disc(4, 4, 2.4, MAROON)


def break_inert(c):
    c.ring(4, 4, 2.4, 1.15, MAROON)


# AND THE THIRD SAYS "NOT HERE -- BELOW", which is roadmap item 20. A fold can
# hide a line that carries a breakpoint, and TSynGutterMarks paints visible
# screen rows only, so the mark is simply not drawn: the picture then says a
# breakpoint the user set does not exist. This one goes on the COLLAPSED HEADER,
# which is the row they can still see.
#
# A SMALLER DISC WITH A TRIANGLE UNDER IT, and both halves are load-bearing. The
# disc keeps it in the same family as the other two -- maroon, round, a
# breakpoint -- and the triangle points at where the thing actually is. A plain
# disc would be a lie (there is no breakpoint on this line, or not only on this
# line); a plain arrow would not say what is down there.
#
# The disc is 1.7 eighths rather than 2.4 because the triangle needs the bottom
# third of the box: at 16 px that is a 7-pixel disc over a 7x4 triangle, which
# is the smallest pair that still reads as two shapes rather than as a smudge.
# Both are drawn in eighths, so both land on whole pixels at 16 and at 24.
def break_hidden(c):
    c.disc(4, 2.6, 1.7, MAROON)
    c.poly(((2.2, 4.8), (5.8, 4.8), (4, 6.8)), MAROON)


GUTTER = (
    ('BreakArmed', break_armed),
    ('BreakInert', break_inert),
    ('BreakHidden', break_hidden),
)

ICONS = (
    ('New', new_page),
    ('Open', open_folder),
    ('Save', save_floppy),
    ('Run', run_play),
    ('Stop', stop_square),
    ('CheckSyntax', check_syntax),
    ('ToggleBreakpoint', breakpoint_dot),
    ('StepOver', step_over),
    ('StepInto', step_into),
)


# ------------------------------------------------------------------ output --
def pascal_bytes(name, blob):
    out = ['  %s: array[0..%d] of Byte = (' % (name, len(blob) - 1)]
    line = '   '
    for i, b in enumerate(blob):
        piece = ' $%02X' % b
        if i < len(blob) - 1:
            piece += ','
        if len(line) + len(piece) > 78:
            out.append(line)
            line = '   '
        line += piece
    out.append(line)
    out.append('  );')
    return '\n'.join(out)


HEADER = '''unit uphosphoricons;

{ The toolbar's icons, as PNG bytes.

  GENERATED BY tools/gen-icons.py. NEVER HAND-EDIT THIS FILE. The drawing is in
  the script, which is where a change to an icon belongs; an edit here is lost
  the next time anybody regenerates, and `python tools/gen-icons.py --check` is
  what notices.

  WHY BYTES IN A UNIT rather than images in the .lfm. A TImageList streams its
  pictures into the form file as one binary blob, and src/umainform.lfm is a file
  people edit by hand: a blob there cannot be reviewed, cannot be diffed and
  cannot be changed without a designer. These are decoded into an empty list at
  FormCreate instead, which costs nine PNG decodes of a few hundred bytes each.

  TWO RESOLUTIONS, AND THAT IS THE WHOLE POINT. A single-resolution image list is
  scaled by the widgetset; the two widgetsets scale differently, one giving a
  blurred mark and the other a missing one, and neither is a build failure -- so
  nobody finds out until a screenshot arrives from the other platform.
  Application.Scaled is True (phosphoride.lpr), so a 150%% Windows machine asks
  for the 24 the first time it draws.

  MIT License. Copyright (c) 2026 Andre Murta.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, ImgList;

const
  { The .lfm carries these numbers as ImageIndex. They are named here so that a
    reordering is one edit in the generator and not nine silent ones. }
%s
  ToolbarIconCount = %d;
  GutterMarkCount = %d;

{ Fill AList with the nine icons, at both resolutions, replacing whatever was
  there. The list's own Width and Height are set to 16: the 24 is a REGISTERED
  RESOLUTION of the same list, not a second list, which is what lets the
  widgetset pick per monitor. }
procedure InstallToolbarIcons(AList: TCustomImageList);

{ The same, for the gutter's marks. SynEdit draws a TSynEditMark from the image
  list in BookMarkOptions.BookmarkImages, so this is a SECOND list rather than
  more slots in the first: mixing them would make the toolbar's indices and the
  gutter's share a numbering that nothing enforces. }
procedure InstallGutterMarks(AList: TCustomImageList);

implementation

const
'''

BODY = '''
{ One icon, two sizes. AddMultipleResolutions wants them smallest first -- its
  own comment in imglist.pp says so -- and it is the only call here that would
  still "work" with one image and quietly give back the blur this unit exists to
  avoid. }
procedure AddPair(AList: TCustomImageList; const A16, A24: array of Byte);
var
  img16, img24: TPortableNetworkGraphic;
  { TYPED, AND THAT IS NOT DECORATION. AddMultipleResolutions is overloaded on
    `array of TCustomBitmap` and `array of TRasterImage`, and a PNG is both --
    TPortableNetworkGraphic descends from TFPImageBitmap, which descends from
    TCustomBitmap, which descends from TRasterImage -- so passing a bare open
    array is "Can't determine which overloaded function to call". Naming the
    array type picks one. }
  pair: array[0..1] of TCustomBitmap;
  mem: TMemoryStream;
begin
  img16 := TPortableNetworkGraphic.Create;
  img24 := TPortableNetworkGraphic.Create;
  mem := TMemoryStream.Create;
  try
    mem.Write(A16[0], Length(A16));
    mem.Position := 0;
    img16.LoadFromStream(mem);
    mem.Clear;
    mem.Write(A24[0], Length(A24));
    mem.Position := 0;
    img24.LoadFromStream(mem);
    pair[0] := img16;
    pair[1] := img24;
    AList.AddMultipleResolutions(pair);
  finally
    mem.Free;
    img24.Free;
    img16.Free;
  end;
end;

procedure Prepare(AList: TCustomImageList);
begin
  AList.Clear;
  AList.Width := 16;
  AList.Height := 16;
  { BEFORE the first Add, because registering a resolution afterwards leaves the
    images already in the list without one. }
  AList.RegisterResolutions([16, 24]);
end;

procedure InstallToolbarIcons(AList: TCustomImageList);
begin
  Prepare(AList);
%s
end;

procedure InstallGutterMarks(AList: TCustomImageList);
begin
  Prepare(AList);
%s
end;

end.
'''


def render():
    blobs = {}
    for name, draw in ICONS + GUTTER:
        for size in SIZES:
            c = Canvas(size)
            draw(c)
            blobs['%s%d' % (name, size)] = c.png()
    return blobs


def build_unit():
    blobs = render()
    names = '\n'.join('  icon%s = %d;' % (n, i)
                      for i, (n, _) in enumerate(ICONS))
    names += '\n\n  { ...and the gutter\'s, which is a SECOND list: SynEdit\n' \
             '    takes one image list for its marks and the toolbar takes\n' \
             '    another, and an index means nothing without knowing which. }\n'
    names += '\n'.join('  mark%s = %d;' % (n, i)
                        for i, (n, _) in enumerate(GUTTER))
    consts = '\n'.join(pascal_bytes('Png' + k, v)
                       for k, v in sorted(blobs.items()))
    calls = '\n'.join('  AddPair(AList, Png%s16, Png%s24);' % (n, n)
                      for n, _ in ICONS)
    gcalls = '\n'.join('  AddPair(AList, Png%s16, Png%s24);' % (n, n)
                        for n, _ in GUTTER)
    return (HEADER % (names, len(ICONS), len(GUTTER))) + consts + \
        (BODY % (calls, gcalls))


def preview_png():
    """A magnified sheet, because an icon is judged by looking at it.

    COMMITTED, and regenerated by the same run that writes the unit. A reviewer
    cannot read a diff of PNG bytes, and an icon change that arrives as four
    hundred changed hex constants is a change nobody can see. The sheet is the
    only reviewable form this has, so it is kept in step by construction rather
    than by remembering."""
    scale = 6
    cell = 24
    all_icons = ICONS + GUTTER
    sheet_w = cell * len(all_icons) * scale
    sheet_h = cell * 2 * scale
    rows = [[(0x20, 0x20, 0x20, 0xFF)] * sheet_w for _ in range(sheet_h)]
    for col, (name, draw) in enumerate(all_icons):
        for r, size in enumerate(SIZES):
            c = Canvas(size)
            draw(c)
            for y in range(size):
                for x in range(size):
                    px = c.px[y][x]
                    if not px[3]:
                        continue
                    # a light band behind row 0 and a dark one behind row 1, so
                    # both toolbars are judged at once
                    for dy in range(scale):
                        for dx in range(scale):
                            sy = r * cell * scale + y * scale + dy
                            sx = col * cell * scale + x * scale + dx
                            rows[sy][sx] = px
    for r in range(2):
        band = (0xF0, 0xF0, 0xF0, 0xFF) if r == 0 else (0x2B, 0x2B, 0x2B, 0xFF)
        for y in range(r * cell * scale, (r + 1) * cell * scale):
            for x in range(sheet_w):
                if rows[y][x] == (0x20, 0x20, 0x20, 0xFF):
                    rows[y][x] = band
    out = Canvas(1)
    out.s = sheet_w
    out.px = rows
    # the PNG writer assumes square; write the header by hand for this one
    raw = bytearray()
    for row in rows:
        raw.append(0)
        for px in row:
            raw += bytes(px)

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data +
                struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack('>IIBBBBB', sheet_w, sheet_h, 8, 6, 0, 0, 0)
    blob = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) +
            chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b''))
    return blob, sheet_w, sheet_h


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ''
    text = build_unit()
    sheet, sw, sh = preview_png()
    sizes = ' and '.join(str(s) for s in SIZES)

    if arg == '--check':
        try:
            have = io.open(OUT, encoding='utf-8', newline='').read()
        except IOError:
            print('uphosphoricons.pas is not there; run tools/gen-icons.py')
            return 1
        if have != text:
            print('uphosphoricons.pas is NOT what tools/gen-icons.py would '
                  'write -- it has been hand-edited, or the generator changed '
                  'and nobody regenerated')
            return 1
        try:
            have_png = io.open(PREVIEW, 'rb').read()
        except IOError:
            have_png = b''
        if have_png != sheet:
            print('tools/icons-preview.png is stale -- it is the only '
                  'reviewable form these icons have, so it is not allowed to '
                  'drift from them. Rerun tools/gen-icons.py.')
            return 1
        print('uphosphoricons.pas is current (%d icons, %s px)'
              % (len(ICONS), sizes))
        return 0

    io.open(OUT, 'w', encoding='utf-8', newline='').write(text)
    io.open(PREVIEW, 'wb').write(sheet)
    print('wrote %s (%d icons at %s px)' % (OUT, len(ICONS), sizes))
    print('wrote %s (%dx%d)' % (PREVIEW, sw, sh))
    return 0


if __name__ == '__main__':
    sys.exit(main())
