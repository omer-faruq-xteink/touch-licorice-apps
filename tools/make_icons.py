"""Draw every app's icon.png (96x96, black on white, 1 bpp).

  python -I tools/make_icons.py [APP ...]

Each icon is drawn at 4x and reduced with a threshold, so edges stay clean in 1 bpp. The Ink App
grid scales the icon to its slot and rounds the corners, so nothing important goes in the outer
6 px. xtpack.py packs APP_DIR/icon.png (docs/firmware-notes.md, "App icons").
"""
import os, sys
from PIL import Image, ImageChops, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N, S = 96, 4                      # icon size, supersampling
FONTS = 'C:/Windows/Fonts/'


def font(name, px):
    for f in (name, 'arialbd.ttf', 'DejaVuSans-Bold.ttf'):
        try:
            return ImageFont.truetype(FONTS + f if os.path.isabs(FONTS + f) else f, px * S)
        except OSError:
            pass
    return ImageFont.load_default()


def svg_paths(path):
    """The filled paths of a simple SVG file (M L H V C S Z, absolute or relative) as lists of
    polygons in the file's own units: Bezier curves cut into short lines."""
    import re
    out = []
    for d in re.findall(r'<path(?![^>]*fill="none")[^>]*\sd="([^"]*)"', open(path, encoding='utf-8').read()):
        toks = re.findall(r'[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?', d)
        polys, poly, i, cmd = [], [], 0, None
        x = y = sx = sy = 0.0
        last_c2 = None

        def num():
            nonlocal i
            i += 1
            return float(toks[i - 1])

        def bez(p0, p1, p2, p3):
            for k in range(1, 13):
                t = k / 12
                a, b, c, e = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
                poly.append((a * p0[0] + b * p1[0] + c * p2[0] + e * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + e * p3[1]))
        while i < len(toks):
            if toks[i].isalpha():
                cmd = toks[i]
                i += 1
                if cmd in 'Zz':
                    if poly: polys.append(poly)
                    poly, x, y, last_c2 = [], sx, sy, None
                    continue
            rel = cmd.islower()
            ox, oy = (x, y) if rel else (0.0, 0.0)
            c = cmd.upper()
            if c == 'M':
                if poly: polys.append(poly)
                x, y = ox + num(), oy + num()
                sx, sy, poly = x, y, [(x, y)]
                cmd = 'l' if rel else 'L'                # more pairs after M are lines
                last_c2 = None
            elif c == 'L':
                x, y = ox + num(), oy + num(); poly.append((x, y)); last_c2 = None
            elif c == 'H':
                x = ox + num(); poly.append((x, y)); last_c2 = None
            elif c == 'V':
                y = oy + num(); poly.append((x, y)); last_c2 = None
            elif c == 'C':
                p1 = (ox + num(), oy + num()); p2 = (ox + num(), oy + num()); p3 = (ox + num(), oy + num())
                bez((x, y), p1, p2, p3); x, y = p3; last_c2 = p2
            elif c == 'S':
                p1 = (2 * x - last_c2[0], 2 * y - last_c2[1]) if last_c2 else (x, y)
                p2 = (ox + num(), oy + num()); p3 = (ox + num(), oy + num())
                bez((x, y), p1, p2, p3); x, y = p3; last_c2 = p2
            else:
                raise ValueError('path command not handled: ' + cmd)
        if poly: polys.append(poly)
        out.append(polys)
    return out


class Pen:
    """Coordinates in icon pixels; drawn at S times the size."""
    def __init__(self):
        self.im = Image.new('L', (N * S, N * S), 255)
        self.d = ImageDraw.Draw(self.im)

    def _b(self, box):
        return [v * S for v in box]

    def rect(self, box, w=0, fill=False, r=0):
        b = self._b(box)
        if r:
            self.d.rounded_rectangle(b, radius=r * S, fill=0 if fill else None, outline=0, width=max(1, int(w * S)) if w else 0)
        else:
            self.d.rectangle(b, fill=0 if fill else None, outline=0 if w else None, width=int(w * S))

    def line(self, pts, w):
        self.d.line([v * S for p in pts for v in p], fill=0, width=int(w * S), joint='curve')

    def ellipse(self, box, w=0, fill=False):
        self.d.ellipse(self._b(box), fill=0 if fill else None, outline=0 if w else None, width=int(w * S))

    def arc(self, box, a0, a1, w):
        self.d.arc(self._b(box), a0, a1, fill=0, width=int(w * S))

    def poly(self, pts, fill=True, w=0):
        self.d.polygon([v * S for p in pts for v in p], fill=0 if fill else None, outline=0 if w else None, width=int(w * S) or 1)

    def text(self, xy, s, f, white=False):
        """centred on xy"""
        self.d.text((xy[0] * S, xy[1] * S), s, font=f, fill=255 if white else 0, anchor='mm')

    def white_rect(self, box):
        self.d.rectangle(self._b(box), fill=255)

    def white_ellipse(self, box):
        self.d.ellipse(self._b(box), fill=255)

    def white_line(self, pts, w):
        self.d.line([v * S for p in pts for v in p], fill=255, width=int(w * S), joint='curve')

    def svg(self, path, box):
        """an SVG file's filled paths, their outline fitted into box (icon pixels, centred, the
        shape kept); holes by the even-odd rule"""
        paths = svg_paths(path)
        pts = [pt for polys in paths for poly in polys for pt in poly]
        minx, maxx = min(q[0] for q in pts), max(q[0] for q in pts)
        miny, maxy = min(q[1] for q in pts), max(q[1] for q in pts)
        x0, y0, x1, y1 = box
        k = min((x1 - x0) / (maxx - minx), (y1 - y0) / (maxy - miny))
        dx = x0 + ((x1 - x0) - (maxx - minx) * k) / 2 - minx * k
        dy = y0 + ((y1 - y0) - (maxy - miny) * k) / 2 - miny * k
        mask = Image.new('1', self.im.size, 0)
        for polys in paths:
            for poly in polys:
                if len(poly) < 3: continue
                layer = Image.new('1', self.im.size, 0)
                ImageDraw.Draw(layer).polygon([((dx + px * k) * S, (dy + py * k) * S) for px, py in poly], fill=1)
                mask = ImageChops.logical_xor(mask, layer)
        self.im.paste(0, mask=mask)

    def save(self, path):
        small = self.im.resize((N, N), Image.LANCZOS)
        small.point(lambda v: 0 if v < 128 else 255).convert('1').save(path)


def game2048(p):
    p.rect((8, 8, 88, 88), w=5, r=12)
    p.text((48, 50), '2048', font('arialbd.ttf', 28))


def sudoku(p):
    # 9x9 on whole pixels: 9 px cells, thin 1 px lines, thick 3 px box lines
    x0, c = 7, 9
    for k in range(10):
        v = x0 + k * c
        if k % 3:
            p.rect((v, x0, v + 1, x0 + 81), fill=True)
            p.rect((x0, v, x0 + 81, v + 1), fill=True)
    for k in range(4):
        v = x0 + k * 27 - 1
        p.rect((v, x0 - 1, v + 3, x0 + 82), fill=True)
        p.rect((x0 - 1, v, x0 + 82, v + 3), fill=True)
    f = font('arialbd.ttf', 8)
    for r, cc, n in ((0, 1, '5'), (1, 4, '3'), (2, 7, '9'), (3, 2, '8'), (4, 4, '1'), (5, 6, '6'),
                     (6, 1, '7'), (7, 4, '2'), (8, 7, '4')):
        p.text((x0 + cc * c + 5, x0 + r * c + 5.5), n, f)


def sokoban(p):
    # a crate on a target square, with floor lines
    p.rect((14, 14, 82, 82), w=5)
    p.rect((22, 22, 74, 74), w=3)
    p.line([(22, 22), (74, 74)], 5)
    p.line([(74, 22), (22, 74)], 5)


def notes(p):
    p.rect((14, 8, 72, 88), w=4, r=4)
    for y in (26, 38, 50, 62):
        p.line([(22, y), (60, y)], 3)
    # a pencil across the corner
    p.poly([(53, 80), (78, 34), (88, 40), (63, 85)], fill=True)
    p.poly([(53, 80), (63, 85), (52, 91)], fill=True)


def rss(p):
    p.rect((8, 8, 88, 88), w=5, r=14)
    cx, cy = 28, 68
    p.ellipse((cx - 7, cy - 7, cx + 7, cy + 7), fill=True)
    for r in (25, 44):
        p.arc((cx - r, cy - r, cx + r, cy + r), 270, 360, 8)


def merchant(p):
    # a coin sack with a $ sign
    p.ellipse((14, 30, 82, 92), fill=True)
    p.poly([(34, 34), (62, 34), (70, 14), (58, 22), (48, 12), (38, 22), (26, 14)], fill=True)
    p.white_rect((32, 30, 64, 33))
    p.text((48, 62), '$', font('arialbd.ttf', 34), white=True)


def dict_(p):
    # a closed book with Aa on the cover
    p.rect((16, 8, 80, 82), w=4, r=4)
    p.line([(26, 10), (26, 80)], 3)
    p.rect((16, 82, 80, 90), w=3)
    p.text((54, 44), 'Aa', font('georgiab.ttf', 26))


def instapaper(p):
    # a page with a bookmark ribbon: read later
    p.rect((14, 8, 82, 88), w=4, r=4)
    p.poly([(56, 8), (74, 8), (74, 38), (65, 30), (56, 38)], fill=True)
    for y, x1 in ((26, 48), (38, 48), (50, 72), (62, 72), (74, 60)):
        p.line([(24, y), (x1, y)], 3)


def suguru(p):
    x0, c = 10, 19
    for i in range(5):
        p.line([(x0 + i * c, x0), (x0 + i * c, x0 + 4 * c)], 1.5)
        p.line([(x0, x0 + i * c), (x0 + 4 * c, x0 + i * c)], 1.5)
    p.rect((x0, x0, x0 + 4 * c, x0 + 4 * c), w=4)
    # region borders
    for a, b in (((2, 0), (2, 2)), ((0, 2), (2, 2)), ((2, 2), (2, 4)), ((2, 2), (4, 2)), ((1, 3), (2, 3)),
                 ((3, 1), (4, 1))):
        p.line([(x0 + a[0] * c, x0 + a[1] * c), (x0 + b[0] * c, x0 + b[1] * c)], 4)
    f = font('arialbd.ttf', 11)
    for r, cc, s in ((0, 0, '1'), (0, 3, '2'), (1, 1, '3'), (2, 2, '4'), (3, 0, '2'), (3, 3, '1')):
        p.text((x0 + (cc + .5) * c, x0 + (r + .5) * c + .5), s, f)


def slidepuzzle(p):
    x0, c, g = 8, 27, 3
    f = font('arialbd.ttf', 14)
    n = 1
    for r in range(3):
        for cc in range(3):
            if r == 2 and cc == 2:
                continue
            x, y = x0 + cc * (c + g), x0 + r * (c + g)
            p.rect((x, y, x + c, y + c), w=3, r=4)
            p.text((x + c / 2, y + c / 2 + .5), str(n), f)
            n += 1


def knightstour(p):
    # checkerboard corner and a knight
    c = 16
    for r in range(6):
        for cc in range(6):
            if (r + cc) % 2:
                p.rect((cc * c, r * c, cc * c + c, r * c + c), fill=True)
    p.white_ellipse((14, 10, 82, 92))
    p.text((48, 50), '\u265e', font('seguisym.ttf', 60))


def nonogram(p):
    pic = ['.##.##.',
           '#######',
           '#######',
           '.#####.',
           '..###..',
           '...#...']
    x0, y0, c = 24, 28, 9
    for r, row in enumerate(pic):
        for cc, ch in enumerate(row):
            x, y = x0 + cc * c, y0 + r * c
            if ch == '#':
                p.rect((x + 1, y + 1, x + c - 1, y + c - 1), fill=True)
            else:
                p.rect((x, y, x + c, y + c), w=1)
    p.rect((x0, y0, x0 + 7 * c, y0 + 6 * c), w=2.5)
    # clues: a bar per run of filled cells, above each column and left of each row
    for cc, n in enumerate((1, 1, 1, 1, 1, 1, 1)):
        p.rect((x0 + cc * c + 2.5, 18, x0 + cc * c + 6.5, 22), fill=True)
    for r, n in enumerate((2, 1, 1, 1, 1, 1)):
        for k in range(n):
            p.rect((16 - k * 7, y0 + r * c + 2.5, 20 - k * 7, y0 + r * c + 6.5), fill=True)


def lightsout(p):
    for r in range(3):
        for c in range(3):
            x, y = 8 + c * 28, 8 + r * 28
            if r == 1 or c == 1:
                p.rect((x, y, x + 24, y + 24), fill=True, r=5)
            else:
                p.rect((x, y, x + 24, y + 24), w=4, r=5)


def pegsolitaire(p):
    for r in range(7):
        for c in range(7):
            if (r < 2 or r > 4) and (c < 2 or c > 4):
                continue
            cx, cy = 9 + c * 13, 9 + r * 13
            if r == 3 and c == 3:
                p.ellipse((cx - 5, cy - 5, cx + 5, cy + 5), w=2)
            else:
                p.ellipse((cx - 5, cy - 5, cx + 5, cy + 5), fill=True)


def minesweeper(p):
    # a mine: a black ball with eight spikes and a white glint
    for a, b in (((48, 12), (48, 84)), ((12, 48), (84, 48)), ((22, 22), (74, 74)), ((74, 22), (22, 74))):
        p.line([a, b], 7)
    p.ellipse((24, 24, 72, 72), fill=True)
    p.white_ellipse((34, 34, 44, 44))


def mahjong(p):
    # two stacked tiles; the front one shows a boxed stroke (the red dragon)
    p.rect((30, 8, 86, 76), w=4, r=6)
    p.white_rect((14, 22, 70, 90))
    p.rect((10, 20, 66, 88), w=5, r=6)
    p.rect((22, 40, 54, 66), w=4)
    p.rect((35, 28, 41, 80), fill=True)


def anki(p):
    # two flash cards: one behind, the front one with a question mark
    p.rect((30, 10, 86, 64), w=4, r=6)
    p.white_rect((10, 30, 66, 86))
    p.rect((10, 30, 66, 86), w=5, r=6)
    p.text((38, 59), '?', font('arialbd.ttf', 36))


def freecell(p):
    # two overlapping cards: a solid spade on the front one
    p.rect((34, 8, 86, 74), w=4, r=6)
    p.white_rect((10, 22, 62, 90))
    p.rect((10, 22, 62, 90), w=5, r=6)
    p.ellipse((22, 46, 40, 64), fill=True)
    p.ellipse((32, 46, 50, 64), fill=True)
    p.poly([(21, 55), (51, 55), (36, 34)], fill=True)
    p.poly([(36, 58), (28, 76), (44, 76)], fill=True)


def wikipedia(p):
    # lines of text under a magnifying glass (not Wikipedia's own logo)
    for y, x1 in ((14, 82), (26, 70), (38, 82), (50, 60), (62, 82), (74, 70)):
        p.line([(10, y), (x1, y)], 4)
    p.white_ellipse((26, 22, 74, 70))
    p.ellipse((26, 22, 74, 70), w=6)
    p.line([(68, 64), (88, 86)], 10)


def chess(p):
    # a knight on a corner of a board
    for r in range(2):
        for c in range(2):
            if (r + c) % 2:
                p.rect((8 + c * 40, 8 + r * 40, 48 + c * 40, 48 + r * 40), w=3)
    p.rect((8, 8, 88, 88), w=4)
    p.white_rect((22, 16, 74, 84))
    p.poly([(30, 80), (70, 80), (66, 66), (62, 40), (52, 22), (44, 22), (42, 28), (30, 40), (28, 50),
            (34, 54), (44, 46), (46, 52), (34, 66)], fill=True)
    p.white_ellipse((45, 31, 51, 37))


def calculator(p):
    # a calculator: a display and a grid of keys
    p.rect((16, 6, 80, 90), w=5, r=8)
    p.rect((26, 16, 70, 34), w=3)
    for r in range(3):
        for c in range(3):
            x, y = 26 + c * 16, 44 + r * 15
            p.rect((x, y, x + 10, y + 9), fill=True)


def klondike(p):
    # a fan of three cards, the front one with a hollow heart
    p.rect((52, 8, 88, 58), w=3, r=5)
    p.white_rect((34, 18, 72, 70))
    p.rect((34, 18, 72, 70), w=3, r=5)
    p.white_rect((10, 30, 56, 90))
    p.rect((10, 30, 56, 90), w=5, r=6)
    p.ellipse((18, 46, 33, 61), w=3)
    p.ellipse((31, 46, 46, 61), w=3)
    p.white_rect((20, 56, 44, 62))
    p.line([(19, 56), (32, 76), (45, 56)], 3)


def tasks(p):
    # a checklist: three boxes, the first two ticked, and lines
    for k in range(3):
        y = 14 + k * 26
        p.rect((12, y, 32, y + 20), w=4)
        p.rect((42, y + 8, 86 - k * 12, y + 13), fill=True)
    for k in range(2):
        y = 14 + k * 26
        p.line([(16, y + 10), (21, y + 16), (34, y - 2)], 5)


def weather(p):
    # a sun behind a cloud, with rain
    p.ellipse((14, 10, 50, 46), w=5)
    for x0, y0, x1, y1 in ((32, 0, 32, 5), (4, 28, 9, 28), (12, 8, 16, 12), (52, 8, 48, 12), (12, 48, 16, 44)):
        p.line([(x0, y0), (x1, y1)], 4)
    p.white_ellipse((26, 26, 62, 62))
    p.white_ellipse((44, 20, 86, 62))
    p.white_rect((20, 44, 92, 72))
    p.ellipse((26, 30, 58, 62), fill=True)
    p.ellipse((44, 22, 84, 62), fill=True)
    p.rect((20, 46, 90, 70), fill=True, r=12)
    for x in (34, 54, 74):
        p.line([(x, 78), (x - 6, 92)], 5)


def hackernews(p):
    # an upvote arrow over the lines of a story list
    p.rect((8, 8, 88, 88), w=5, r=10)
    p.poly([(30, 44), (48, 18), (66, 44)], fill=True)
    for k, x1 in enumerate((76, 64)):
        y = 56 + k * 14
        p.rect((20, y, x1, y + 6), fill=True)


def calendar(p):
    # a desk calendar page: two rings, a header band and a grid of days, one ringed
    p.rect((10, 16, 86, 88), w=5, r=8)
    p.rect((10, 16, 86, 34), fill=True, r=8)
    for x in (30, 66):
        p.rect((x - 3, 6, x + 3, 24), fill=True, r=2)
    for r in range(3):
        for c in range(4):
            x, y = 20 + c * 16, 42 + r * 14
            p.rect((x, y, x + 8, y + 7), fill=True)
    p.white_ellipse((44, 48, 76, 80))
    p.ellipse((48, 52, 72, 76), w=4)



def tbr(p):
    # a to-be-read pile: three books stacked, a bookmark on the top one
    for (x0, x1, y) in ((14, 82, 66), (20, 76, 46), (10, 72, 26)):
        p.rect((x0, y, x1, y + 18), w=4, r=3)
        p.line([(x0 + 8, y + 2), (x0 + 8, y + 16)], 3)
        p.line([(x1 - 8, y + 2), (x1 - 8, y + 16)], 3)
    p.poly([(56, 8), (66, 8), (66, 32), (61, 27), (56, 32)], fill=True)
    p.rect((8, 86, 88, 90), fill=True)

def wallabag(p):
    # the wallabag logo (apps/wallabag/logo-square.svg, by Maylis Agniel, Free Art License 1.3)
    p.svg(os.path.join(HERE, 'apps', 'wallabag', 'logo-square.svg'), (6, 4, 90, 92))

def readwise(p):
    # a page of text with one line highlighted: a reading queue that keeps highlights
    p.rect((14, 8, 82, 88), w=4, r=4)
    for y, x1 in ((22, 72), (34, 64), (60, 72), (72, 52)):
        p.line([(24, y), (x1, y)], 3)
    p.rect((20, 42, 76, 54), fill=True, r=2)
    p.line([(26, 48), (66, 48)], 3)
    p.white_rect((26, 47, 66, 49))

def litclock(p):
    # an open book with a clock face rising from its pages
    p.poly([(6, 62), (46, 56), (46, 90), (6, 92)], fill=False, w=4)
    p.poly([(90, 62), (50, 56), (50, 90), (90, 92)], fill=False, w=4)
    for y in (68, 76):
        p.line([(14, y), (38, y - 4)], 3)
        p.line([(82, y), (58, y - 4)], 3)
    p.white_ellipse((22, 4, 74, 56))
    p.ellipse((26, 8, 70, 52), w=5)
    p.line([(48, 30), (48, 16)], 4)
    p.line([(48, 30), (59, 37)], 4)
    p.ellipse((45, 27, 51, 33), fill=True)


def wordclock(p):
    # a grid of letters, two words lit as black bars with white letters
    f = font('arialbd.ttf', 15)
    for r in range(4):
        for c in range(4):
            if (r, c) in ((0, 0), (0, 1), (2, 1), (2, 2), (2, 3)):
                continue
            p.ellipse((18 + c * 20 - 2, 20 + r * 19 - 2, 18 + c * 20 + 2, 20 + r * 19 + 2), fill=True)
    p.rect((10, 11, 44, 29), fill=True, r=5)
    p.text((27, 20), 'IT', f, white=True)
    p.rect((30, 49, 86, 67), fill=True, r=5)
    p.text((58, 58), 'TEN', f, white=True)
    p.rect((2, 2, 94, 94), w=3, r=10)


def skytonight(p):
    # a round night sky: a black disc, white stars joined like a constellation, a crescent moon
    p.ellipse((4, 4, 92, 92), fill=True)
    stars = [(26, 34), (40, 26), (56, 32), (66, 48), (54, 62), (36, 58)]
    for a, b in zip(stars, stars[1:]):
        p.white_line([a, b], 2)
    for x, y in stars:
        p.white_ellipse((x - 3, y - 3, x + 3, y + 3))
    for x, y in ((20, 56), (74, 28), (46, 78), (70, 70)):
        p.white_ellipse((x - 1.5, y - 1.5, x + 1.5, y + 1.5))
    p.white_ellipse((60, 10, 82, 32))
    p.ellipse((66, 8, 88, 30), fill=True)


def gamebook(p):
    # an open book with a path coming out of it that forks into two arrows
    p.poly([(8, 56), (46, 64), (46, 90), (8, 82)], fill=False, w=4)
    p.poly([(88, 56), (50, 64), (50, 90), (88, 82)], fill=False, w=4)
    p.line([(48, 62), (48, 42)], 6)
    p.line([(48, 44), (26, 20)], 6)
    p.line([(48, 44), (70, 20)], 6)
    p.poly([(16, 10), (34, 14), (20, 28)], fill=True)
    p.poly([(80, 10), (62, 14), (76, 28)], fill=True)


def tsumego(p):
    # a corner of a Go board: grid lines, thick edges, a black group and two white stones
    for k in range(4):
        x = 18 + k * 22
        p.line([(x, 18), (x, 92)], 3 if k == 0 else 2)
        p.line([(18, x), (92, x)], 3 if k == 0 else 2)
    p.rect((14, 14, 22, 92), fill=True)
    p.rect((14, 14, 92, 22), fill=True)
    for (cx, cy) in ((40, 40), (62, 40), (40, 62)):
        p.ellipse((cx - 10, cy - 10, cx + 10, cy + 10), fill=True)
    for (cx, cy) in ((62, 62), (84, 40)):
        p.white_ellipse((cx - 10, cy - 10, cx + 10, cy + 10))
        p.ellipse((cx - 10, cy - 10, cx + 10, cy + 10), w=3)


ICONS = {'game2048': game2048, 'sudoku': sudoku, 'sokoban': sokoban, 'notes': notes, 'rss': rss,
         'merchant': merchant, 'dict': dict_, 'instapaper': instapaper, 'suguru': suguru,
         'slidepuzzle': slidepuzzle, 'knightstour': knightstour, 'nonogram': nonogram,
         'lightsout': lightsout, 'pegsolitaire': pegsolitaire,
         'minesweeper': minesweeper, 'mahjong': mahjong, 'anki': anki,
         'freecell': freecell, 'wikipedia': wikipedia,
         'chess': chess, 'calculator': calculator,
         'klondike': klondike, 'tasks': tasks, 'weather': weather,
         'hackernews': hackernews, 'calendar': calendar, 'tbr': tbr, 'wallabag': wallabag,
         'readwise': readwise, 'litclock': litclock,
         'wordclock': wordclock, 'skytonight': skytonight, 'gamebook': gamebook,
         'tsumego': tsumego}

if __name__ == '__main__':
    for app in sys.argv[1:] or ICONS:
        p = Pen()
        ICONS[app](p)
        p.save(os.path.join(HERE, 'apps', app, 'icon.png'))
        print('apps/%s/icon.png' % app)
