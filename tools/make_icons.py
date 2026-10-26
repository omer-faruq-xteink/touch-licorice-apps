"""Draw every app's icon.png (96x96, black on white, 1 bpp).

  python -I tools/make_icons.py [APP ...]

Each icon is drawn at 4x and reduced with a threshold, so edges stay clean in 1 bpp. The Ink App
grid scales the icon to its slot and rounds the corners, so nothing important goes in the outer
6 px. xtpack.py packs APP_DIR/icon.png (docs/firmware-notes.md, "App icons").
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

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


ICONS = {'game2048': game2048, 'sudoku': sudoku, 'sokoban': sokoban, 'notes': notes, 'rss': rss,
         'merchant': merchant, 'dict': dict_, 'instapaper': instapaper, 'suguru': suguru,
         'slidepuzzle': slidepuzzle, 'knightstour': knightstour, 'nonogram': nonogram,
         'lightsout': lightsout, 'pegsolitaire': pegsolitaire,
         'minesweeper': minesweeper, 'mahjong': mahjong}

if __name__ == '__main__':
    for app in sys.argv[1:] or ICONS:
        p = Pen()
        ICONS[app](p)
        p.save(os.path.join(HERE, 'apps', app, 'icon.png'))
        print('apps/%s/icon.png' % app)
