#!/usr/bin/env python3
"""Tiny CC:Tweaked computer emulator for testing Phoenix OS outside Minecraft.

It boots the real CC:Tweaked bios.lua and ROM (not included: see README.md in
this folder) on a fake computer, lets a test script type and click, and saves
screenshots as PNG files.

    from emu import Emu
    e = Emu(rom_dir, computer_dir)
    e.boot(); e.run(1)
    e.type("hello"); e.key("enter"); e.click(5, 19)
    e.png("shot.png")
"""
import os
import shutil

from lupa import lua52

HERE = os.path.dirname(os.path.abspath(__file__))

# CC's font has pictures in the low character codes; map the ones we use.
LOW_CHARS = {
    1: "☺", 2: "☻", 3: "♥", 4: "♦", 5: "♣", 6: "♠", 7: "•",
    8: "◘", 11: "♂", 12: "♀", 14: "♫", 15: "☼", 16: "►",
    17: "◄", 18: "↕", 19: "‼", 20: "¶", 21: "§", 22: "▬", 23: "↨",
    24: "↑", 25: "↓", 26: "→", 27: "←", 28: "∟", 29: "↔",
    30: "▲", 31: "▼", 127: "▒",
}


class Emu:
    def __init__(self, lua_dir, root, w=51, h=19, colour=True, computer_id=0, http_dir=None,
                 http_prefix=None, capacity=1000000):
        """lua_dir: CC:Tweaked's data/computercraft/lua folder (holds bios.lua and rom/)."""
        self.w, self.h = w, h
        self.lua = lua52.LuaRuntime(unpack_returned_tuples=True, encoding="latin-1")
        L = self.lua
        os.makedirs(root, exist_ok=True)

        def listdir(p):
            return L.table_from(sorted(os.listdir(p)))

        def remove(p):
            if os.path.isdir(p) and not os.path.islink(p):
                shutil.rmtree(p)
            elif os.path.exists(p):
                os.remove(p)

        def copy(a, b):
            if os.path.isdir(a):
                shutil.copytree(a, b)
            else:
                shutil.copy2(a, b)

        def du(p):
            total = 0
            for base, _dirs, files in os.walk(p):
                for f in files:
                    total += os.path.getsize(os.path.join(base, f))
            return total

        py = L.table_from({
            "listdir": listdir, "isdir": os.path.isdir, "isfile": os.path.isfile,
            "exists": os.path.exists, "getsize": os.path.getsize,
            "mkdirs": lambda p: os.makedirs(p, exist_ok=True), "remove": remove,
            "move": lambda a, b: shutil.move(a, b) and None, "copy": copy,
            "mtime": lambda p: os.path.getmtime(p) * 1000, "du": du,
        })
        cfg = {
            "w": w, "h": h, "colour": colour, "id": computer_id, "capacity": capacity,
            "root": os.path.abspath(root), "rom": os.path.join(os.path.abspath(lua_dir), "rom"),
            "bios": os.path.join(os.path.abspath(lua_dir), "bios.lua"),
        }
        if http_dir:
            def http_map(url):
                if http_prefix and not url.startswith(http_prefix):
                    return None
                rel = url[len(http_prefix or ""):].split("?")[0].lstrip("/")
                path = os.path.join(http_dir, rel)
                return path if os.path.isfile(path) else None
            cfg["http_map"] = http_map
        with open(os.path.join(HERE, "emu.lua"), encoding="latin-1") as f:
            ctor = L.execute(f.read())
        self.E = ctor(py, L.table_from(cfg))

    # ---- power and time
    def boot(self):
        self.E.boot()
        self._check()

    def run(self, seconds=0.2):
        alive = self.E.run(seconds)
        self._check()
        return alive

    def _check(self):
        if self.E.crash:
            raise RuntimeError("computer crashed: " + str(self.E.crash))

    @property
    def powered(self):
        return bool(self.E.powered)

    # ---- input
    def queue(self, *ev):
        self.E.queue_event(*ev)

    def key(self, name, settle=0.1):
        code = self.E.key_code(name)
        if code is None:
            raise KeyError(name)
        self.queue("key", code, False)
        self.queue("key_up", code)
        self.run(settle)

    def type(self, text, settle=0.1):
        for ch in text:
            self.queue("char", ch)
        self.run(settle)

    def click(self, x, y, button=1, settle=0.1):
        self.queue("mouse_click", button, x, y)
        self.queue("mouse_up", button, x, y)
        self.run(settle)

    def double_click(self, x, y, settle=0.1):
        self.click(x, y, settle=0.05)
        self.click(x, y, settle=settle)

    def drag(self, x1, y1, x2, y2, button=1, settle=0.1):
        self.queue("mouse_click", button, x1, y1)
        steps = max(abs(x2 - x1), abs(y2 - y1), 1)
        for i in range(1, steps + 1):
            self.queue("mouse_drag", button, round(x1 + (x2 - x1) * i / steps), round(y1 + (y2 - y1) * i / steps))
        self.queue("mouse_up", button, x2, y2)
        self.run(settle)

    def eval(self, code):
        return self.E.eval(code)

    # ---- output
    def dump(self):
        text, fg, bg, pal, cx, cy, blink = self.E.dump()
        return text.split("\n"), fg.split("\n"), bg.split("\n"), [int(p, 16) for p in pal.split(",")], int(cx), int(cy), bool(blink)

    def screen(self):
        """Screen text as a list of strings (teletext/control characters shown as '#')."""
        rows = self.dump()[0]
        return ["".join(c if 32 <= ord(c) < 127 else ("#" if ord(c) != 0 else " ") for c in r) for r in rows]

    def find(self, needle):
        """(x, y) of the first place needle appears on screen, or None."""
        for y, row in enumerate(self.dump()[0]):
            x = row.find(needle)
            if x >= 0:
                return x + 1, y + 1
        return None

    def png(self, path, scale=3):
        from PIL import Image, ImageDraw, ImageFont
        text, fg, bg, pal, cx, cy, blink = self.dump()
        cw, ch = 6 * scale, 9 * scale
        img = Image.new("RGB", (self.w * cw, self.h * ch))
        d = ImageDraw.Draw(img)
        font = None
        for cand in ("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
                     "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"):
            if os.path.exists(cand):
                font = ImageFont.truetype(cand, int(ch * 0.78))
                break

        def col(c):
            v = pal[int(c, 16)]
            return (v >> 16, (v >> 8) & 255, v & 255)

        for y in range(self.h):
            for x in range(self.w):
                c = ord(text[y][x])
                f, b = col(fg[y][x]), col(bg[y][x])
                x0, y0 = x * cw, y * ch
                d.rectangle([x0, y0, x0 + cw - 1, y0 + ch - 1], fill=b)
                if 128 <= c <= 159:
                    bits = c - 128
                    for i in range(5):
                        if bits & (1 << i):
                            px, py_ = i % 2, i // 2
                            d.rectangle([x0 + px * cw // 2, y0 + py_ * ch // 3,
                                         x0 + (px + 1) * cw // 2 - 1, y0 + (py_ + 1) * ch // 3 - 1], fill=f)
                elif c not in (0, 32):
                    s = LOW_CHARS.get(c) or bytes([c]).decode("latin-1")
                    if font:
                        d.text((x0 + cw / 2, y0 + ch / 2), s, fill=f, font=font, anchor="mm")
        if blink and 1 <= cx <= self.w and 1 <= cy <= self.h:
            d.rectangle([(cx - 1) * cw, cy * ch - scale * 2, cx * cw - 1, cy * ch - scale], fill=(255, 255, 255))
        img.save(path)
        return path
