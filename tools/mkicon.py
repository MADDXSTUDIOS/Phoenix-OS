#!/usr/bin/env python3
"""Turn 8x6 pixel art into a Phoenix OS desktop icon (4x2 characters).

Each character cell is 2 pixels wide and 3 tall, and can only hold two colours
(that's how CC's teletext block characters work). Colours are CC hex digits
(0 white ... f black); '_' means "show the desktop through here".

    python3 tools/mkicon.py < art.txt      # six lines of eight characters
"""
import sys


def convert(rows):
    assert len(rows) == 6 and all(len(r) == 8 for r in rows), "need 6 rows of 8 characters"
    out = []
    for cy in range(2):
        text, fg, bg = "", "", ""
        for cx in range(4):
            px = [rows[cy * 3 + y][cx * 2 + x] for y in range(3) for x in range(2)]
            colours = sorted(set(px))
            assert len(colours) <= 2, f"cell {cx},{cy} has more than two colours: {colours}"
            b = px[5]
            f = next((c for c in colours if c != b), b)
            code = 128 + sum(1 << i for i in range(5) if px[i] != b)
            text += "\\%d" % code
            fg += f
            bg += b
        out.append('{ "%s", "%s", "%s" }' % (text, fg, bg))
    return "icon = { " + ", ".join(out) + " },"


if __name__ == "__main__":
    print(convert([line.rstrip("\n") for line in sys.stdin if line.strip()]))
