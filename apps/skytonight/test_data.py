"""Checks of Sky Tonight's zoom data: names.txt carries the IAU abbreviations, bounds.txt the
constellation boundaries, objects.txt the deep-sky objects (each inside the constellation it names),
cards.txt one card a constellation.

  python -I apps/skytonight/test_data.py
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'data')
sys.stdout.reconfigure(encoding='utf-8')
fails = []


def check(ok, what):
    print(('ok    ' if ok else 'FAIL  ') + what)
    if not ok:
        fails.append(what)


def rows(name):
    p = os.path.join(DATA, name)
    return [l for l in open(p, encoding='utf-8').read().split('\n') if l.strip()] if os.path.exists(p) else []


# names.txt: "ra dec rank ABBR en|tr|de"
names = [l.split(' ', 4) for l in rows('names.txt')]
abbrs = [n[3] for n in names if len(n) == 5]
check(len(names) == 89 and len(abbrs) == 89, f'names.txt: 89 rows with an abbreviation ({len(abbrs)})')
check(len(set(abbrs)) == 88 and abbrs.count('Ser') == 2, 'the 88 constellations (Serpens in two parts)')

# bounds.txt: "ABBR N ra dec ra dec ...": RA 0..360; N 1 for the polygon holding the north pole
POLYS = []
for l in rows('bounds.txt'):
    p = l.split()
    v = [float(x) for x in p[2:]]
    POLYS.append((p[0], p[1] == '1', v[0::2], v[1::2]))
check(set(p[0] for p in POLYS) == set(abbrs), f'bounds.txt: every constellation has a polygon ({len(POLYS)} polygons)')
check([p[0] for p in POLYS if p[1]] == ['UMi'], 'only UMi holds the north pole')


def inside(ra, dec, north, xs, ys):
    """the meridian from (ra, dec) up to the pole: how often it crosses the edges (odd: inside)"""
    hit = north
    n = len(xs)
    for i in range(n):
        a1 = (xs[i] - ra + 180) % 360 - 180        # the edge's ends east (+) or west of the point
        a2 = (xs[(i + 1) % n] - ra + 180) % 360 - 180
        if (a1 > 0) != (a2 > 0) and abs(a1 - a2) < 180:
            y1, y2 = ys[i], ys[(i + 1) % n]
            if y1 + (y2 - y1) * a1 / (a1 - a2) > dec:
                hit = not hit
    return hit


def constellation(ra, dec):
    return [ab for ab, north, xs, ys in POLYS if inside(ra, dec, north, xs, ys)]


for ra, dec, want in ((37.95, 89.26, 'UMi'), (88.79, 7.41, 'Ori'), (10.68, 41.27, 'And'), (359.5, 60, 'Cas'),
                      (0.5, 60, 'Cas'), (0.1, 10, 'Psc'), (200, 82, 'Cam'), (200, 72, 'UMi'), (200, -89, 'Oct'), (10, 89.9, 'UMi'), (186.65, -63.10, 'Cru'),
                      (279.23, 38.78, 'Lyr'), (229.64, 2.08, 'Ser'), (271, -29, 'Sgr')):
    got = constellation(ra, dec)
    check(got == [want], f'{ra} {dec} is in {want}: {got}')
# every point of the sky lies in exactly one constellation
bad = 0
for dec in range(-88, 89, 4):
    for ra in range(0, 360, 4):
        if len(constellation(ra + 0.37, dec + 0.21)) != 1:
            bad += 1
check(bad == 0, f'a 4-degree grid: every point in exactly one constellation ({bad} not)')

# objects.txt: "ID type ra dec mag ABBR|name|note"
OBJ = {}
for l in rows('objects.txt'):
    p = l.split(' ', 5)
    ab, name, note = p[5].split('|')
    OBJ[p[0]] = (p[1], float(p[2]), float(p[3]), float(p[4]), ab, name, note)
check(30 <= len(OBJ) <= 40, f'objects.txt: {len(OBJ)} objects')
for oid, o in OBJ.items():
    got = constellation(o[1], o[2])
    if got != [o[4]]:
        check(False, f'{oid} {o[5]} is in {o[4]}: {got}')
    if o[0] not in ('gx', 'oc', 'gc', 'nb', 'pn'):
        check(False, f'{oid}: type {o[0]}')
    if not (10 <= len(o[6]) <= 90):
        check(False, f'{oid}: note of {len(o[6])} characters')
for oid, ab in (('M31', 'And'), ('M42', 'Ori'), ('M45', 'Tau'), ('M13', 'Her'), ('M44', 'Cnc'), ('M8', 'Sgr'),
                ('NGC5139', 'Cen'), ('NGC104', 'Tuc'), ('NGC869', 'Per'), ('LMC', 'Dor'), ('SMC', 'Tuc')):
    check(oid in OBJ and OBJ[oid][4] == ab, f'{oid} in {ab}')

# cards.txt: "ABBR|story|star, star|ID ID"
cards = {}
for l in rows('cards.txt'):
    p = l.split('|')
    if len(p) == 4:
        cards[p[0]] = p
check(set(cards) == set(abbrs), f'cards.txt: a card for each of the 88 ({len(cards)}; missing {sorted(set(abbrs) - set(cards))[:6]})')
used = {}
for ab, c in cards.items():
    if not (40 <= len(c[1]) <= 200):
        check(False, f'{ab}: story of {len(c[1])} characters')
    if len([s for s in c[2].split(',') if s.strip()]) > 4:
        check(False, f'{ab}: more than 4 stars')
    ids = c[3].split()
    if len(ids) > 3:
        check(False, f'{ab}: more than 3 objects')
    for oid in ids:
        if oid not in OBJ or OBJ[oid][4] != ab:
            check(False, f'{ab}: object {oid} is not in it')
        used[oid] = used.get(oid, 0) + 1
check(all(n == 1 for n in used.values()), 'each object on one card at most')

# the cards and the objects in Turkish and German: the same constellations, stars and objects
for lang in ('tr', 'de'):
    tc = [l.split('|') for l in rows(f'cards_{lang}.txt')]
    en = [l.split('|') for l in rows('cards.txt')]
    same = len(tc) == len(en) and all(len(t) == 4 and t[0] == e[0] and t[2] == e[2] and t[3] == e[3] for t, e in zip(tc, en))
    check(same, f'cards_{lang}.txt: the 88 cards, stars and objects as in English ({len(tc)})')
    long_ = [t[0] for t in tc if len(t) == 4 and not (40 <= len(t[1]) <= 230)]
    check(not long_, f'cards_{lang}.txt: stories of 40 to 230 characters {long_[:5]}')
    check(all(len(t) == 4 and t[1] != e[1] for t, e in zip(tc, en)), f'cards_{lang}.txt: every story translated')
    to = [l.split('|') for l in rows(f'objects_{lang}.txt')]
    check([t[0] for t in to] == list(OBJ) and all(len(t) == 3 and 10 <= len(t[2]) <= 110 for t in to),
          f'objects_{lang}.txt: the 40 objects in order, notes of 10 to 110 characters ({len(to)})')

print('\n' + ('all passed' if not fails else f'{len(fails)} FAILED'))
sys.exit(1 if fails else 0)
