"""Tarot's data: cards.txt (the meanings) and the 1909 card scans -> data/.

  data/cards.txt    key|name|upright keywords|upright meaning|reversed keywords|reversed meaning
  data/art_l1.txt, art_l2.txt   one card a line, in cards.txt order (39 a file): a 1-bit PNG,
                                240x418, base64
  data/art_s1.txt, art_s2.txt   the same at 144x251 (the three-card spread)

Every art line is padded with spaces to the length of the longest, so the app can seek to card N
at N * stride. Two files a size, since open_text opens files of at most 1 MB. The scans are Pamela Colman Smith's 1909 deck (public domain), from Wikimedia
Commons, Category:Rider-Waite tarot deck (Roses & Lilies), files "RWS1909 - 00 Fool.jpeg",
"RWS1909 - Cups 01.jpeg" and so on (any width; the 500 px versions were used). Each is cropped
to its black frame, sharpened a little, given more contrast (the paper and the pale colours turn
white) and Atkinson-dithered, which leaves light areas clean.

  python -I apps/tarot/make_data.py SCANS_DIR
"""
import base64, io, os, sys
import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
LARGE, SMALL = (240, 418), (144, 251)
LO, HI = 45, 180                     # grey levels that become black / white before dithering
SUITS = {'w': 'Wands', 'c': 'Cups', 's': 'Swords', 'p': 'Pentacles'}


def scan_name(key):
    if key[0] == 'm':
        return None                  # found by number below
    return f'RWS1909_-_{SUITS[key[0]]}_{key[1:]}.jpeg'


def find_scan(d, key):
    if key[0] == 'm':
        pre = f'RWS1909_-_{key[1:]}_'
        hits = [f for f in os.listdir(d) if f.startswith(pre)]
        assert len(hits) == 1, (key, hits)
        return os.path.join(d, hits[0])
    return os.path.join(d, scan_name(key))


def frame_box(g):
    """The card's black frame: the first and last columns and rows that are mostly dark."""
    w, h = g.size
    a = np.array(g) < 90
    cols = a[h // 5:4 * h // 5].mean(axis=0)
    rows = a[:, w // 5:4 * w // 5].mean(axis=1)
    def first(v, rng): return next((i for i in rng if v[i] > 0.5), None)
    l, r = first(cols, range(0, w // 6)), first(cols, range(w - 1, 5 * w // 6, -1))
    t, b = first(rows, range(0, h // 8)), first(rows, range(h - 1, 7 * h // 8, -1))
    return (l or 0, t or 0, (r if r is not None else w - 1) + 1, (b if b is not None else h - 1) + 1)


def atkinson(a):
    a = a.astype(np.float32)
    h, w = a.shape
    for y in range(h):
        for x in range(w):
            old = a[y, x]
            new = 255.0 if old >= 128 else 0.0
            e = (old - new) / 8
            a[y, x] = new
            if x + 1 < w: a[y, x + 1] += e
            if x + 2 < w: a[y, x + 2] += e
            if y + 1 < h:
                if x > 0: a[y + 1, x - 1] += e
                a[y + 1, x] += e
                if x + 1 < w: a[y + 1, x + 1] += e
            if y + 2 < h: a[y + 2, x] += e
    return Image.fromarray(np.where(a >= 128, 255, 0).astype(np.uint8)).convert('1')


def art(path, size):
    g = Image.open(path).convert('L')
    g = g.crop(frame_box(g)).resize(size, Image.LANCZOS).filter(ImageFilter.UnsharpMask(1.2, 80, 2))
    g = g.point(lambda v: 0 if v <= LO else 255 if v >= HI else (v - LO) * 255 // (HI - LO))
    b = io.BytesIO()
    atkinson(np.array(g)).save(b, 'PNG', optimize=True)
    return base64.b64encode(b.getvalue()).decode('ascii')


PER_FILE = 39                        # open_text opens files of at most 1 MB: two files a size


def write_padded(prefix, lines):
    n = max(len(l) for l in lines)
    assert n < 65536, (prefix, n)
    for k in range(0, len(lines), PER_FILE):
        name = f'{prefix}{k // PER_FILE + 1}.txt'
        part = lines[k:k + PER_FILE]
        assert len(part) * (n + 1) < 1 << 20, (name, len(part) * (n + 1))
        with open(os.path.join(HERE, 'data', name), 'w', encoding='ascii', newline='\n') as f:
            f.write(''.join(l.ljust(n) + '\n' for l in part))
        print(f'data/{name}: {len(part)} cards, stride {n + 1}, {len(part) * (n + 1)} bytes')


def main(scans):
    rows = []
    for n, line in enumerate(open(os.path.join(HERE, 'cards.txt'), encoding='utf-8'), 1):
        line = line.rstrip('\n')
        if not line or line.startswith('#'):
            continue
        assert line.isascii() and line.count('|') == 5, (n, line)
        rows.append(line)
    keys = [r.split('|')[0] for r in rows]
    want = [f'm{k:02d}' for k in range(22)] + [f'{s}{k:02d}' for s in 'wcsp' for k in range(1, 15)]
    assert keys == want, [k for k in want if k not in keys]
    os.makedirs(os.path.join(HERE, 'data'), exist_ok=True)
    with open(os.path.join(HERE, 'data', 'cards.txt'), 'w', encoding='ascii', newline='\n') as f:
        f.write('\n'.join(rows) + '\n')
    print(f'data/cards.txt: {len(rows)} cards')
    for f in os.listdir(os.path.join(HERE, 'data')):
        if f.startswith('art_'):
            os.remove(os.path.join(HERE, 'data', f))
    for prefix, size in (('art_l', LARGE), ('art_s', SMALL)):
        write_padded(prefix, [art(find_scan(scans, k), size) for k in keys])


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
