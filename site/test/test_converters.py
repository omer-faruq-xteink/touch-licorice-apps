"""The web converters against the Python ones: the same input must give the same files.

  python -I site/test/test_converters.py [STARDICT_DIR_OR_ZIP ...]

Builds small Anki decks (.apkg with HTML, entities, cloze and two note types; a .tsv with quotes;
a .csv) and small StarDict dictionaries (HTML, dictd-style plain text, typed parts), runs
apps/anki/apkg2cards.py and apps/dict/stardict2shards.py, then site/test/node_cli.mjs, and
compares every file (Anki's "built=" line aside). Real dictionaries given on the command line are
compared too. Needs Node 24.
"""
import gzip, json, os, shutil, sqlite3, struct, subprocess, sys, tempfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PY = sys.executable
NODE = shutil.which('node')
TMP = tempfile.mkdtemp(prefix='convtest-')


def run(*args):
    r = subprocess.run(list(args), capture_output=True, text=True, encoding='utf-8')
    assert r.returncode == 0, (args, r.stdout, r.stderr)
    return r.stdout


def same(a, b, skip_built=False):
    fa, fb = sorted(os.listdir(a)), sorted(os.listdir(b))
    assert fa == fb, (fa, fb)
    for f in fa:
        x = open(os.path.join(a, f), encoding='utf-8').read()
        y = open(os.path.join(b, f), encoding='utf-8').read()
        if skip_built:
            x = '\n'.join(l for l in x.split('\n') if not l.startswith('built='))
            y = '\n'.join(l for l in y.split('\n') if not l.startswith('built='))
        if x != y:
            for k, (p, q) in enumerate(zip(x.split('\n'), y.split('\n'))):
                if p != q:
                    raise AssertionError(f'{f} line {k + 1}:\n  py: {p!r}\n  js: {q!r}')
            raise AssertionError(f'{f}: lengths differ')
    return len(fa)


# ------------------------------------------------------------------ Anki

def make_apkg(path, notes, models):
    db = os.path.join(TMP, 'collection.anki2')
    if os.path.exists(db):
        os.remove(db)
    con = sqlite3.connect(db)
    con.execute('create table col (models text)')
    con.execute('create table notes (id integer, mid integer, flds text)')
    con.execute('create table cards (nid integer, type integer, due integer)')
    con.execute('insert into col values (?)', (json.dumps(models),))
    for nid, mid, flds, typ, due in notes:
        con.execute('insert into notes values (?, ?, ?)', (nid, mid, '\x1f'.join(flds)))
        con.execute('insert into cards values (?, ?, ?)', (nid, typ, due))
    con.commit()
    con.close()
    with zipfile.ZipFile(path, 'w') as z:
        z.write(db, 'collection.anki2')
        z.writestr('media', '{}')


MODELS = {
    '1001': {'name': 'Basic', 'flds': [{'name': 'Back', 'ord': 1}, {'name': 'Front', 'ord': 0}, {'name': 'Note', 'ord': 2}]},
    '1002': {'name': 'Cloze', 'flds': [{'name': 'Text', 'ord': 0}, {'name': 'Extra', 'ord': 1}]},
}
NOTES = [
    (1600000000001, 1001, ['<b>der Hund</b>', 'the dog&nbsp;<br>a pet', '12'], 0, 3),
    (1600000000002, 1001, ['die Katze', '<div>the cat</div><div><br></div><div>&lt;feline&gt; &amp; co &eacute;&#233;&#x20AC;</div>', 'x'], 2, 1),
    (1600000000003, 1001, ['das Haus', '<ul><li>house</li><li>home</li></ul>[sound:haus.mp3]', ''], 1, 7),
    (1600000000004, 1001, ['  ', 'empty front', 'y'], 0, 1),
    (1600000000005, 1002, ['The {{c1::Rhine::river}} flows to the {{c2::North Sea}}.', 'Geography'], 0, 2),
    (1600000000006, 1002, ['<style>.x{}</style>Berlin is the capital of {{c1::Germany}}', ''], 0, 5),
    (1600000000007, 1001, ['lang', 'long ' * 300, 'z'], 0, 9),
    (1600000000008, 1001, ['Straße\twith tab', 'back\\slash', 'q'], 0, 4),
]


def compare_anki(deck, *opts, update_from=None):
    py_out, js_out = os.path.join(TMP, 'py_' + os.path.basename(deck)), os.path.join(TMP, 'js_' + os.path.basename(deck))
    if update_from:
        for d in (py_out, js_out):
            shutil.rmtree(d, ignore_errors=True)
            shutil.copytree(update_from, d)
    run(PY, '-I', '-X', 'utf8', os.path.join(ROOT, 'apps', 'anki', 'apkg2cards.py'), deck, py_out, *opts)
    run(NODE, os.path.join(HERE, 'node_cli.mjs'), 'anki', deck, js_out, *opts)
    return same(py_out, js_out, skip_built=True)


apkg = os.path.join(TMP, 'German_Words_123456789.apkg')
make_apkg(apkg, NOTES, MODELS)
n = compare_anki(apkg)
compare_anki(apkg, '--reverse', '--name', 'Deutsch', '--max-chars', '40')
compare_anki(apkg, '--front', 'Back', '--back', 'Front,Note', '--prefix', 'gw')
# an update: a note removed, one changed, two added; places are kept
first = os.path.join(TMP, 'py_German_Words_123456789.apkg')
keep = shutil.copytree(first, os.path.join(TMP, 'first'))
notes2 = [x for x in NOTES if x[0] != 1600000000002]
notes2[0] = (notes2[0][0], 1001, ['der Hund', 'the dog (changed)', '1'], 0, 3)
notes2 += [(1600000000009, 1001, ['neu', 'new', 'n'], 0, 10), (1600000000010, 1001, ['noch', 'still', 'n'], 0, 11)]
make_apkg(apkg, notes2, MODELS)
compare_anki(apkg, '--update', update_from=keep)
print(f'anki: .apkg, --reverse, --front/--back, --update: same files ({n} files)')

tsv = os.path.join(TMP, 'list words.tsv')
open(tsv, 'w', encoding='utf-8-sig', newline='').write(
    '# a comment\nfront one\tback one\n\n"quoted\tfield"\tback "two"\nthree\t<b>bold</b>\textra\n"multi\nline"\tok\n  \tskipped\nlast\n')
compare_anki(tsv)
csv_ = os.path.join(TMP, 'words.csv')
open(csv_, 'w', encoding='utf-8', newline='').write('a,b\n"c, d","e ""quoted"""\nf,g,h\r\ni,"j\r\nk"\n')
compare_anki(csv_)
print('anki: .tsv and .csv lists: same files')

# ------------------------------------------------------------------ StarDict

def make_stardict(d, name, entries, types, bits=32, dz=True):
    os.makedirs(d, exist_ok=True)
    blob, idx = b'', b''
    for word, data in sorted(entries, key=lambda e: e[0].encode('utf-8').lower()):
        idx += word.encode('utf-8') + b'\0' + struct.pack('>QI' if bits == 64 else '>II', len(blob), len(data))
        blob += data
    ifo = f"StarDict's dict ifo file\nversion=3.0.0\nbookname={name}\nwordcount={len(entries)}\nidxfilesize={len(idx)}\n"
    if types:
        ifo += f'sametypesequence={types}\n'
    if bits == 64:
        ifo += 'idxoffsetbits=64\n'
    open(os.path.join(d, name + '.ifo'), 'w', encoding='utf-8', newline='\n').write(ifo)
    open(os.path.join(d, name + '.idx'), 'wb').write(idx)
    if dz:
        with gzip.open(os.path.join(d, name + '.dict.dz'), 'wb') as f:
            f.write(blob)
    else:
        open(os.path.join(d, name + '.dict'), 'wb').write(blob)


def compare_dict(src, *opts):
    tag = os.path.basename(src.rstrip('/\\')) + '_'.join(opts)
    py_out, js_out = os.path.join(TMP, 'dpy_' + tag), os.path.join(TMP, 'djs_' + tag)
    run(PY, '-I', '-X', 'utf8', os.path.join(ROOT, 'apps', 'dict', 'stardict2shards.py'), src, py_out, *opts)
    run(NODE, os.path.join(HERE, 'node_cli.mjs'), 'stardict', src, js_out, *opts)
    return same(py_out, js_out)


html_entries = [(f'word{k:03d}', f'<p>meaning <b>{k}</b></p><ul><li>one&nbsp;</li><li>two &amp; three</li></ul><br/>end'.encode()) for k in range(300)]
html_entries += [('word005', b'<div>second sense</div>'), ('İstanbul', 'şehir — city'.encode()), ('tab\tword', b'x')]
make_stardict(os.path.join(TMP, 'h'), 'Html Dict', html_entries, 'h')
plain = [('apple', b'apple\n     n 1: fruit with red or green skin\n          [syn: {orchard apple}]\n     2: the tree 3: something\n     v 1: to apple'),
         ('bank', b'bank\n  n 1: sloping land 2: a financial\n     institution adj 1: banked'),
         ('long', ('long ' * 400).encode())]
make_stardict(os.path.join(TMP, 'm'), 'Plain', plain, 'm', bits=64, dz=False)
mixed = [('alpha', b'mfirst part\0hsecond <b>part</b>\0'), ('beta', b'W' + struct.pack('>I', 3) + b'abcmtext after a picture\0')]
make_stardict(os.path.join(TMP, 'x'), 'Mixed', mixed, '')
compare_dict(os.path.join(TMP, 'h'))
compare_dict(os.path.join(TMP, 'h'), '--prefix', 'hd', '--shard-kb', '4', '--max-def', '30')
compare_dict(os.path.join(TMP, 'm'), '--prefix', 'pl')
compare_dict(os.path.join(TMP, 'x'))
print('stardict: HTML, dictd text, typed parts, 64-bit offsets, small shards: same files')

for real in sys.argv[1:]:
    src = real
    if real.lower().endswith('.zip'):
        src = os.path.join(TMP, 'real_' + os.path.basename(real)[:-4])
        zipfile.ZipFile(real).extractall(src)
        inner = [os.path.join(dp, f) for dp, _, fs in os.walk(src) for f in fs if f.endswith('.ifo')]
        src = os.path.dirname(inner[0])
    k = compare_dict(src, '--prefix', 'real')
    print(f'stardict: {os.path.basename(real)}: same files ({k})')

shutil.rmtree(TMP, ignore_errors=True)
print('converters: all tests passed')
