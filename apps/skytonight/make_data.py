"""Write Sky Tonight's data files from the star catalogue and the constellation figures.

  python -I apps/skytonight/make_data.py BSC5.tdat.gz LINES.json CONSTELLATIONS.json BOUNDS.json

BSC5: the Yale Bright Star Catalogue, 5th edition (HEASARC heasarc_bsc5p.tdat.gz; NASA, public
domain). LINES / CONSTELLATIONS: constellations.lines.json and constellations.json of d3-celestial
(c) 2015 Olaf Frohn, BSD 3-clause (see README); BOUNDS: its constellations.bounds.json (the IAU
boundaries). Writes:

  data/stars.txt   "ra dec mag" per star to magnitude 4.5, ra and dec in degrees (J2000)
  data/lines.txt   one constellation figure line per row: "ra dec ra dec ..."
  data/names.txt   "ra dec rank ABBR en|tr|de": where each constellation's name goes, its rank (1
                   the best known), its IAU abbreviation and its names in English, Turkish and German
  data/bounds.txt  "ABBR N ra dec ra dec ...": one boundary polygon a row (RA 0..360); N is 1 for
                   the one that holds the north pole (see bounds())
  data/stars_named.txt  "ra dec name": the bright stars the chart labels
"""
import gzip, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'data')
MAG = 4.5
# the stars the chart names, by their approximate place (RA hours, Dec degrees); matched to the
# catalogue's nearest bright star
NAMED = {'Sirius': (6.752, -16.72), 'Canopus': (6.399, -52.70), 'Arcturus': (14.261, 19.18), 'Vega': (18.616, 38.78),
         'Capella': (5.278, 46.00), 'Rigel': (5.242, -8.20), 'Procyon': (7.655, 5.22), 'Betelgeuse': (5.919, 7.41),
         'Achernar': (1.629, -57.24), 'Altair': (19.846, 8.87), 'Aldebaran': (4.599, 16.51), 'Antares': (16.490, -26.43),
         'Spica': (13.420, -11.16), 'Pollux': (7.755, 28.03), 'Fomalhaut': (22.961, -29.62), 'Deneb': (20.690, 45.28),
         'Regulus': (10.140, 11.97), 'Castor': (7.577, 31.89), 'Polaris': (2.530, 89.26), 'Bellatrix': (5.419, 6.35),
         'Mirfak': (3.405, 49.86), 'Algol': (3.136, 40.96), 'Dubhe': (11.062, 61.75), 'Alkaid': (13.792, 49.31),
         'Denebola': (11.818, 14.57), 'Hamal': (2.120, 23.46), 'Alphard': (9.460, -8.66), 'Rasalhague': (17.582, 12.56),
         'Alpheratz': (0.140, 29.09), 'Mira': (2.322, -2.98)}


def plain(name):
    """the name with ordinary spaces: d3-celestial joins words with U+2005, which the reader's
    fonts lack (it showed as a box)"""
    return re.sub('[  -​ ]', ' ', name)


def stars(path):
    hdr, out = None, []
    for line in gzip.open(path, 'rt', encoding='latin1'):
        if line.startswith('line[1]'):
            hdr = line.split('=', 1)[1].split()
        p = line.rstrip('\n').split('|')
        if not hdr or len(p) < len(hdr):
            continue
        r = dict(zip(hdr, p))
        try:
            ra, dec, mag = float(r['ra']), float(r['dec']), float(r['vmag'])
        except ValueError:
            continue
        if mag <= MAG:
            out.append((ra, dec, mag))
    return sorted(out, key=lambda s: s[2])


def bounds(path):
    """the boundary polygons as (abbr, north, [(ra, dec), ...]), RA in 0..360. A point is inside when
    the meridian from it up to the north pole crosses the polygon's edges (each edge the short way
    round in RA) an odd number of times; north is True for the one that holds the north pole (UMi:
    its ring runs once round in RA), where it is an even number."""
    out = []
    for feat in json.load(open(path, encoding='utf-8'))['features']:
        for ring in feat['geometry']['coordinates']:
            pts = [(lon % 360, lat) for lon, lat in ring]
            if pts[-1] == pts[0]:
                pts.pop()
            turn = sum((pts[(i + 1) % len(pts)][0] - pts[i][0] + 180) % 360 - 180 for i in range(len(pts)))
            north = abs(turn) > 180 and sum(p[1] for p in pts) > 0
            out.append((feat['id'], north, pts))
    return out


def main():
    bsc, lines_json, names_json, bounds_json = sys.argv[1:5]
    os.makedirs(DATA, exist_ok=True)
    st = stars(bsc)
    with open(os.path.join(DATA, 'stars.txt'), 'w', encoding='utf-8', newline='\n') as f:
        for ra, dec, mag in st:
            f.write(f'{ra:.3f} {dec:.3f} {mag:.1f}\n')
    with open(os.path.join(DATA, 'stars_named.txt'), 'w', encoding='utf-8', newline='\n') as f:
        for name, (rah, dec) in NAMED.items():
            ra = rah * 15
            best = min(st, key=lambda s: ((s[0] - ra + 180) % 360 - 180) ** 2 * max(0.05, (1 - (dec / 90) ** 2)) + (s[1] - dec) ** 2)
            f.write(f'{best[0]:.3f} {best[1]:.3f} {name}\n')
    lj = json.load(open(lines_json, encoding='utf-8'))
    n = 0
    with open(os.path.join(DATA, 'lines.txt'), 'w', encoding='utf-8', newline='\n') as f:
        for feat in lj['features']:
            for strip in feat['geometry']['coordinates']:
                f.write(' '.join(f'{lon % 360:.2f} {lat:.2f}' for lon, lat in strip) + '\n')
                n += 1
    nj = json.load(open(names_json, encoding='utf-8'))
    with open(os.path.join(DATA, 'names.txt'), 'w', encoding='utf-8', newline='\n') as f:
        for feat in nj['features']:
            p = feat['properties']
            lon, lat = feat['geometry']['coordinates']
            names = [plain(p['en']), plain(p.get('tr') or p['en']), plain(p.get('de') or p['en'])]
            f.write(f"{lon % 360:.2f} {lat:.2f} {p.get('rank', '3')} {feat['id']} {'|'.join(names)}\n")
    bd = bounds(bounds_json)
    with open(os.path.join(DATA, 'bounds.txt'), 'w', encoding='utf-8', newline='\n') as f:
        for ab, north, pts in bd:
            f.write(ab + (' 1 ' if north else ' 0 ') + ' '.join(f'{ra:.2f} {dec:.2f}' for ra, dec in pts) + '\n')
    print(f'{len(st)} stars to magnitude {MAG}, {len(NAMED)} named, {n} figure lines, {len(nj["features"])} names, {len(bd)} boundaries')


if __name__ == '__main__':
    main()
