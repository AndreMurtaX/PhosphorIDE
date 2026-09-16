#!/usr/bin/env python3
"""Turn an xwd dump into a PNG.

Nothing on this VM converts XWD -- no ImageMagick, no netpbm -- and installing
packages here needs its owner's say-so. PIL is present, and the format is a
100-byte big-endian header followed by the window name, an optional colour map
and then the pixels, with each row padded out to `bytes_per_line`. Decoding it
by hand is 30 lines; the two traps are the padding and the BGRA channel order.

    xwd -id <win> -out f.xwd && python3 shot.py f.xwd f.png
"""
import struct
import sys

from PIL import Image

FIELDS = ('header_size file_version pixmap_format pixmap_depth pixmap_width '
          'pixmap_height xoffset byte_order bitmap_unit bitmap_bit_order '
          'bitmap_pad bits_per_pixel bytes_per_line visual_class red_mask '
          'green_mask blue_mask bits_per_rgb colormap_entries ncolors '
          'window_width window_height window_x window_y window_bdrwidth').split()


def main(src, dst):
    with open(src, 'rb') as f:
        blob = f.read()
    h = dict(zip(FIELDS, struct.unpack('>25I', blob[:100])))
    if h['bits_per_pixel'] not in (24, 32):
        raise SystemExit('unexpected bits_per_pixel %d' % h['bits_per_pixel'])

    start = h['header_size'] + h['ncolors'] * 12
    w, ht = h['pixmap_width'], h['pixmap_height']
    stride = h['bytes_per_line']
    per = h['bits_per_pixel'] // 8
    # frombytes cannot express a stride, so the rows are trimmed first.
    rows = []
    for y in range(ht):
        off = start + y * stride
        rows.append(blob[off:off + w * per])
    raw = b''.join(rows)
    mode = 'BGRX' if per == 4 else 'BGR'
    img = Image.frombytes('RGB', (w, ht), raw, 'raw', mode)
    img.save(dst)
    print('%s -> %s (%dx%d)' % (src, dst, w, ht))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
