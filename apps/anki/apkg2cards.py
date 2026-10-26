"""Convert an Anki deck (.apkg) or a simple word list (.tsv / .csv / .txt) into the card files the
Xteink Anki mini app reads.

  python apkg2cards.py DECK.apkg OUT_DIR [--name NAME] [--prefix PREFIX]
                       [--front FIELD] [--back FIELD,FIELD] [--reverse] [--max-chars 800]
  python apkg2cards.py DECK.apkg --list-fields            show the fields and a sample card
  python apkg2cards.py DECK.apkg OUT_DIR --update         a new export of a deck you study

Copy the files it writes into XTApps/anki/files/ on the SD card (USB mode); the app lists every
deck it finds there. Shared decks: https://ankiweb.net/shared/decks (export or download the
.apkg, convert it here).

Only text is kept: HTML becomes plain text; pictures and sounds are left out (the reader has no
sound, and the decks' media is what makes them large). Cloze cards show "[...]" on the front and
the full text on the back. A simple list converts too: one card per line, front and back
separated by a tab (.tsv / .txt) or a comma (.csv).

Output: OUT_DIR/<prefix>_info.txt (name, card count, shard size) and OUT_DIR/<prefix>_c000.txt ...
with one card per line, "id<TAB>front<TAB>back" ("\\n" for a line break). Each shard holds a fixed
number of cards, and the app keeps your progress by a card's place, so --update keeps every card
of the old files where it was (with its new text), blanks the place of a removed card and adds new
cards at the end. Newer Anki exports (collection.anki21b) need `pip install zstandard`.
"""
import argparse, csv, html, json, os, re, sqlite3, sys, tempfile, time, zipfile

MAX_SHARDS = 300          # the app's storage holds 512 files, shared by every deck and progress
NAME_RE = re.compile(r'[^A-Za-z0-9]+')


# ------------------------------------------------------------------ text

def clean(s):
    s = re.sub(r'(?is)<(style|script)\b.*?</\1>', '', s)
    s = re.sub(r'(?i)<br\s*/?>|</(div|p|li|tr|h\d)>', '\n', s)
    s = re.sub(r'(?i)<li\b[^>]*>', '- ', s)
    s = re.sub(r'<[^>]+>', '', s)
    s = re.sub(r'\[sound:[^\]]*\]', '', s)
    s = html.unescape(s).replace('\xa0', ' ')
    lines = [re.sub(r'[ \t]+', ' ', l).strip() for l in s.split('\n')]
    out = []
    for l in lines:
        if l or (out and out[-1]):
            out.append(l)
    return '\n'.join(out).strip()


CLOZE = re.compile(r'\{\{c\d+::(.*?)(?:::(.*?))?\}\}', re.S)


def cloze(s):
    front = CLOZE.sub(lambda m: '[' + (m.group(2) or '...') + ']', s)
    back = CLOZE.sub(lambda m: m.group(1), s)
    return front, back


def cut(s, n):
    return s if len(s) <= n else s[:n - 1].rstrip() + '…'


def esc(s):
    return s.replace('\\', '\\\\').replace('\t', ' ').replace('\r', '').replace('\n', '\\n')


# ------------------------------------------------------------------ reading decks

def open_collection(path, tmp):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        for col in ('collection.anki21b', 'collection.anki21', 'collection.anki2'):
            if col in names:
                raw = z.read(col)
                break
        else:
            raise SystemExit(f'{path}: no Anki collection inside')
    if col.endswith('21b'):
        try:
            import zstandard
        except ImportError:
            raise SystemExit('this is a newer Anki export (collection.anki21b): pip install zstandard')
        raw = zstandard.ZstdDecompressor().stream_reader(raw).read()
    db = os.path.join(tmp, 'collection.db')
    open(db, 'wb').write(raw)
    return sqlite3.connect(db)


def note_types(con):
    """{model id: (name, [field names])}"""
    try:
        models = json.loads(con.execute('select models from col').fetchone()[0] or '{}')
        if models:
            return {int(k): (m['name'], [f['name'] for f in sorted(m['flds'], key=lambda f: f['ord'])])
                    for k, m in models.items()}
    except sqlite3.Error:
        pass
    out = {}
    for ntid, name in con.execute('select id, name from notetypes'):
        flds = [r[0] for r in con.execute('select name from fields where ntid = ? order by ord', (ntid,))]
        out[ntid] = (name, flds)
    return out


def read_apkg(path):
    """[(id, {field name: cleaned text}, model name)] in the deck's order"""
    with tempfile.TemporaryDirectory() as tmp:
        con = open_collection(path, tmp)
        types = note_types(con)
        rows = con.execute('select n.id, n.mid, n.flds from notes n join (select nid, min(type) t, min(due) d '
                           'from cards group by nid) c on c.nid = n.id order by c.t, c.d, n.id').fetchall()
        con.close()
    notes = []
    for nid, mid, flds in rows:
        name, fnames = types.get(mid, ('?', []))
        vals = flds.split('\x1f')
        fnames = fnames + [f'Field {k + 1}' for k in range(len(fnames), len(vals))]
        notes.append((str(nid), {fn: clean(v) for fn, v in zip(fnames, vals)}, name, [fn for fn in fnames[:len(vals)]]))
    return notes


def read_list(path):
    rows = []
    with open(path, encoding='utf-8-sig', newline='') as f:
        reader = csv.reader(f, delimiter=',' if path.lower().endswith('.csv') else '\t')
        for k, row in enumerate(reader, 1):
            if not row or not row[0].strip() or row[0].startswith('#'):
                continue
            rows.append((f'L{k}', {'Front': clean(row[0]), 'Back': clean(' / '.join(row[1:]))}, 'list', ['Front', 'Back']))
    return rows


# ------------------------------------------------------------------ cards

def useful_fields(notes):
    """per note type, its fields in order that hold text (not empty, not just a number) in at least
    80 % of its notes: the first is the default front, the rest the default back"""
    stats = {}
    for _nid, fields, model, order in notes:
        st = stats.setdefault(model, {'n': 0, 'order': order, 'ok': {}})
        st['n'] += 1
        for f in order:
            v = fields.get(f, '')
            if v and not re.fullmatch(r'[\d\s.,:#_/-]*', v):
                st['ok'][f] = st['ok'].get(f, 0) + 1
    return {m: [f for f in st['order'] if st['ok'].get(f, 0) >= 0.8 * st['n']] or st['order'] for m, st in stats.items()}


def make_cards(notes, a):
    useful, cards = useful_fields(notes), []
    for nid, fields, model, order in notes:
        good = useful[model]
        front_f = a.front if a.front in fields else good[0]
        if a.back:
            back_fs = [f for f in a.back.split(',') if f in fields]
        else:
            back_fs = [f for f in good if f != front_f]
        front = fields.get(front_f, '')
        back = '\n'.join(fields[f] for f in back_fs if fields.get(f))
        if CLOZE.search(front):
            front, filled = cloze(front)
            back = filled + ('\n' + back if back else '')
        if not front or not back:
            continue
        front, back = cut(front, a.max_chars), cut(back, a.max_chars)
        cards.append((nid, front, back))
        if a.reverse:
            cards.append((nid + 'r', back, front))
    return cards


def read_old(out, prefix):
    """ids in their old places, and the old shard size"""
    info = os.path.join(out, f'{prefix}_info.txt')
    if not os.path.exists(info):
        return [], None
    per = None
    for line in open(info, encoding='utf-8'):
        if line.startswith('per='):
            per = int(line[4:])
    ids, s = [], 0
    while os.path.exists(os.path.join(out, f'{prefix}_c{s:03d}.txt')):
        for line in open(os.path.join(out, f'{prefix}_c{s:03d}.txt'), encoding='utf-8'):
            ids.append(line.split('\t', 1)[0])
        s += 1
    return ids, per


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('deck')
    ap.add_argument('out', nargs='?')
    ap.add_argument('--name', help='the deck name the app shows (default: from the file name)')
    ap.add_argument('--prefix', help='file name prefix, letters and digits (default: from the name)')
    ap.add_argument('--front', help='field for the front (default: the first field)')
    ap.add_argument('--back', help='fields for the back, comma separated (default: all the others)')
    ap.add_argument('--reverse', action='store_true', help='also make back-to-front cards')
    ap.add_argument('--max-chars', type=int, default=800, help='longest side of a card (default 800)')
    ap.add_argument('--list-fields', action='store_true', help='show the note types, fields and a sample')
    ap.add_argument('--update', action='store_true', help='keep the cards of the old files at their places')
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

    is_list = a.deck.lower().endswith(('.tsv', '.csv', '.txt'))
    notes = read_list(a.deck) if is_list else read_apkg(a.deck)
    if a.list_fields:
        seen, useful = set(), useful_fields(notes)
        for nid, fields, model, order in notes:
            if model in seen:
                continue
            seen.add(model)
            print(f'note type "{model}" ({sum(1 for n in notes if n[2] == model)} notes):')
            for f in order:
                mark = 'front' if f == useful[model][0] else 'back ' if f in useful[model] else '     '
                print(f'  {mark} {f:24} {cut(fields[f].replace(chr(10), " / "), 70)}')
        print('front / back: the default; choose others with --front FIELD --back FIELD,FIELD')
        return
    if not a.out:
        ap.error('OUT_DIR is needed')
    base = re.sub(r'[_\s]+\d{6,}$', '', os.path.splitext(os.path.basename(a.deck))[0])   # AnkiWeb's deck number
    name = a.name or re.sub(r'[_\s]+', ' ', base).strip()
    prefix = a.prefix or (NAME_RE.sub('', name.title())[:16] or 'deck')
    if not re.fullmatch(r'[A-Za-z0-9]{1,24}', prefix) or prefix.lower() in ('my', 'en'):
        raise SystemExit(f'--prefix: 1..24 letters or digits, not "my" or "en" (the app uses those); got {prefix!r}')
    cards = make_cards(notes, a)
    if not cards:
        raise SystemExit('no cards: try --list-fields and pick --front / --back')

    os.makedirs(a.out, exist_ok=True)
    old_ids, old_per = read_old(a.out, prefix) if a.update else ([], None)
    by_id = {c[0]: c for c in cards}
    if old_ids:
        slots = [by_id.pop(i, (i, '', '')) for i in old_ids]
        slots += [c for c in cards if c[0] in by_id]
        per = old_per
    else:
        slots = cards
        per = max(100, -(-len(cards) // MAX_SHARDS))
    shards = -(-len(slots) // per)
    if shards > MAX_SHARDS:
        raise SystemExit(f'{len(slots)} cards make {shards} files, more than the app can hold ({MAX_SHARDS}); '
                         'convert without --update, or split the deck')
    for fn in os.listdir(a.out):
        if re.fullmatch(re.escape(prefix) + r'_c\d{3}\.txt', fn):
            os.remove(os.path.join(a.out, fn))
    for s in range(shards):
        with open(os.path.join(a.out, f'{prefix}_c{s:03d}.txt'), 'w', encoding='utf-8', newline='\n') as f:
            for cid, front, back in slots[s * per:(s + 1) * per]:
                f.write(f'{esc(cid)}\t{esc(front)}\t{esc(back)}\n')
    live = sum(1 for c in slots if c[1])
    with open(os.path.join(a.out, f'{prefix}_info.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(f'name={name}\ncards={live}\nshards={shards}\nper={per}\nsource={os.path.basename(a.deck)}\n'
                f'built={time.strftime("%Y-%m-%d %H:%M")}\n')
    size = sum(os.path.getsize(os.path.join(a.out, fn)) for fn in os.listdir(a.out) if fn.startswith(prefix + '_'))
    note = ''
    if old_ids:
        removed = sum(1 for c in slots[:len(old_ids)] if not c[1])
        note = f'; {len(old_ids) - removed} cards kept their places, {removed} removed, {len(slots) - len(old_ids)} new'
    print(f'{name}: {live} cards in {shards} files ({size // 1024} KB), prefix {prefix}{note}')
    print(f'copy {a.out}{os.sep}{prefix}_* into XTApps/anki/files/ on the SD card')


if __name__ == '__main__':
    main()
