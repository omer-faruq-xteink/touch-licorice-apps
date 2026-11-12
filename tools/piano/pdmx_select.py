"""Candidates for the Piano Follow catalog from PDMX (https://zenodo.org/records/15571083).

  python -I tools/piano/pdmx_select.py --pdmx DIR [--out dist/piano/candidates.csv] [--per-composer 6]
  python -I tools/piano/pdmx_select.py --pdmx DIR --extract dist/piano/candidates.csv

DIR holds PDMX.csv and mxl.tar.gz. The first form reads PDMX.csv and keeps scores that are:
  - public domain or CC0 (or CC BY / BY-SA, credited), without PDMX's license_conflict flag;
  - deduplicated (PDMX's best unique arrangement), rated, solo piano (every track a piano program);
  - by a composer in composers.json (died before 1955, or traditional), and with no title or
    composer text from title_block.txt (modern songs, film and game music);
  - 8 to 160 bars long, without lyrics;
ranked by rating and views, at most N per composer. The second form unpacks those scores'
.mxl files from mxl.tar.gz into DIR/mxl/... (one pass over the archive). Every candidate is still
reviewed by hand (tools/piano/catalog.yaml) before it is published.
"""
import argparse, csv, json, math, os, re, sys, tarfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
LICENSES = {'publicdomain': 'Public domain', 'cc-zero': 'CC0', 'cc0': 'CC0', 'cc-by': 'CC BY 4.0',
            'cc-by-sa': 'CC BY-SA 4.0', 'by': 'CC BY 4.0', 'by-sa': 'CC BY-SA 4.0'}
csv.field_size_limit(10 ** 8)


def load_rules():
    comps = json.load(open(os.path.join(HERE, 'composers.json'), encoding='utf-8'))['composers']
    block = [l.strip().lower() for l in open(os.path.join(HERE, 'title_block.txt'), encoding='utf-8')
             if l.strip() and not l.startswith('#')]
    return comps, block


def words(s):
    return ' ' + re.sub(r'[^\w.\'-]+', ' ', (s or '').lower()) + ' '


def composer_of(row, comps):
    """the allowed composer a row names (composer field first, then the title), or None"""
    for field in ('composer_name', 'artist_name', 'title'):
        w = words(row.get(field))
        for c in comps:
            for m in c['match']:
                if ' ' + m + ' ' in w:
                    return c
    return None


def piano_only(tracks):
    # PDMX's tracks: General MIDI programs joined by '-'; 0-7 are the pianos
    try:
        progs = [int(t) for t in (tracks or '').split('-') if t != '']
    except ValueError:
        return False
    return bool(progs) and all(0 <= p <= 7 for p in progs) and len(progs) <= 2


def truthy(v):
    return str(v).strip().lower() == 'true'


def num(v, d=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return d


def select(pdmx, per_composer=6):
    comps, block = load_rules()
    by_comp = {}
    with open(os.path.join(pdmx, 'PDMX.csv'), encoding='utf-8', newline='') as f:
        for row in csv.DictReader(f):
            lic = LICENSES.get((row.get('license') or '').lower())
            if not lic or truthy(row.get('license_conflict')):
                continue
            if not truthy(row.get('is_best_unique_arrangement')) or not truthy(row.get('is_rated')):
                continue
            if not piano_only(row.get('tracks')) or truthy(row.get('has_lyrics')):
                continue
            bars = num(row.get('song_length.bars'))
            if not 8 <= bars <= 160:
                continue
            text = ' '.join((row.get(k) or '') for k in ('title', 'song_name', 'subtitle', 'composer_name', 'artist_name')).lower()
            if any(b in text for b in block):
                continue
            c = composer_of(row, comps)
            if not c:
                continue
            score = num(row.get('rating')) * math.log1p(num(row.get('n_ratings'))) + 0.3 * math.log1p(num(row.get('n_views')))
            by_comp.setdefault(c['name'], []).append((score, c, lic, row))
    out = []
    for name, rows in by_comp.items():
        rows.sort(key=lambda r: -r[0])
        out += rows[:per_composer]
    out.sort(key=lambda r: (r[1]['name'], -r[0]))
    return out


def slug(s):
    s = re.sub(r'[^a-z0-9]+', '-', (s or '').lower()).strip('-')
    return s[:48].strip('-') or 'piece'


def write(cands, path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    seen = set()
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(['id', 'title', 'composer', 'license', 'rating', 'n_ratings', 'views', 'complexity', 'bars', 'mxl', 'url'])
        for score, c, lic, r in cands:
            title = r.get('title') or r.get('song_name') or ''
            cid = slug(title)
            k = 2
            base = cid
            while cid in seen:
                cid = f'{base}-{k}'; k += 1
            seen.add(cid)
            meta = r.get('metadata', '')
            mid = re.search(r'(\d+)\.json$', meta)
            url = f'https://musescore.com/score/{mid.group(1)}' if mid else ''
            w.writerow([cid, title, c['name'], lic, r.get('rating'), r.get('n_ratings'), r.get('n_views'),
                        r.get('complexity'), r.get('song_length.bars'), r.get('mxl', '').lstrip('./'), url])
    return len(seen)


def extract(pdmx, cand_csv):
    want = set()
    with open(cand_csv, encoding='utf-8', newline='') as f:
        for row in csv.DictReader(f):
            want.add(row['mxl'])
    got = 0
    with tarfile.open(os.path.join(pdmx, 'mxl.tar.gz'), 'r|gz') as t:
        for m in t:
            name = m.name.lstrip('./')
            if m.isfile() and name in want:
                dest = os.path.join(pdmx, *name.split('/'))
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with t.extractfile(m) as src, open(dest, 'wb') as out:
                    out.write(src.read())
                got += 1
                if got == len(want):
                    break
    return got, len(want)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--pdmx', required=True)
    ap.add_argument('--out', default=os.path.join(ROOT, 'dist', 'piano', 'candidates.csv'))
    ap.add_argument('--per-composer', type=int, default=6)
    ap.add_argument('--extract', metavar='CANDIDATES_CSV')
    a = ap.parse_args()
    if a.extract:
        got, n = extract(a.pdmx, a.extract)
        print(f'extracted {got} of {n} scores')
        return
    n = write(select(a.pdmx, a.per_composer), a.out)
    print(f'{n} candidates -> {a.out}')


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
