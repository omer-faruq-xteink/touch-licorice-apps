"""Put Sokoban level packs into sokoban/data/ for the package, with a level index per pack, and
refresh the built-in fallback pack in index.lua.

  python sokoban/prepare_data.py PACK_OR_DIR [PACK_OR_DIR ...] [--builtin 12] [--builtin-from NAME]
  python sokoban/prepare_data.py --clean PACK_OR_DIR ...        # empty data/ first

Accepts single files or whole folders of .txt / .sok / .xsb packs (XSB text: a level is a run of
lines made of "# @ + $ * . - _" and spaces containing a '#'; a following "Title:" line names it).
For each pack it writes:

  data/<name>.txt       the pack, line ends normalised to LF, otherwise unchanged
  data/<name>.idx.tsv   one line per level: "<byte offset of the first board line>\t<title>"

The app seeks to the offset, so a pack of any size is read one level at a time instead of being
loaded whole into the 1 MB Lua heap. Names are made to fit the firmware's rule (letters, digits,
'-', '.', '_', lowercase .txt): "Original & Extra.sok" becomes "original_extra.txt". The data
section holds at most 128 files, so up to 63 packs (two files each plus banks.tsv).
"""
import argparse, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'data')
BOARD = re.compile(r'^[ #@+$*.\-_]*$')
EXTS = ('.txt', '.sok', '.xsb')


def safe_name(fn):
    stem = os.path.splitext(os.path.basename(fn))[0].lower()
    stem = re.sub(r'[^a-z0-9._-]+', '_', stem).strip('._-') or 'pack'
    stem = re.sub(r'\.idx$', '_idx', stem)             # never collide with the index suffix
    return stem[:56]


def norm_title(t):
    """Strip a leading comment marker and surrounding quotes; a bare number becomes "Level N"."""
    t = re.sub(r'^[;\s]+', '', t or '').strip()
    if len(t) >= 2 and t[0] == t[-1] and t[0] in "'\"":
        t = t[1:-1].strip()
    if re.fullmatch(r'\d+', t):
        t = 'Level ' + t
    return t


def levels_of(lines):
    """[(first_line_index, rows, title)] for the lines of a pack. The title is a "Title:" line right
    after the level (sokobano.de style) or else the last non-empty, non-board line before it
    ("; 12", "Level 12", "'MICROCOSMOS 12'")."""
    out, cur, start, before, pending = [], [], None, None, None
    for i, line in enumerate(lines + ['']):
        if '#' in line and BOARD.match(line):
            if not cur:
                start, before = i, pending
            cur.append(line)
        else:
            if cur:
                m = re.match(r'^Title:\s*(.*?)\s*$', line)
                title = m.group(1) if m else before
                out.append((start, cur, norm_title(title))); cur, start, before = [], None, None
                pending = None if m else (line.strip() or None)
            elif line.strip():
                pending = line.strip()
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('sources', nargs='+')
    ap.add_argument('--builtin', type=int, default=12)
    ap.add_argument('--builtin-from', default=None, help='pack name whose first levels become the fallback')
    ap.add_argument('--clean', action='store_true')
    a = ap.parse_args()
    os.makedirs(DATA, exist_ok=True)
    if a.clean:
        for fn in os.listdir(DATA):
            os.remove(os.path.join(DATA, fn))
    paths = []
    for src in a.sources:
        if os.path.isdir(src):
            paths += [os.path.join(src, f) for f in sorted(os.listdir(src)) if f.lower().endswith(EXTS)]
        else:
            paths.append(src)
    used, packs = set(), []
    for p in paths:
        name = safe_name(p)
        base = name; k = 2
        while name in used:
            name = f'{base}{k}'; k += 1
        used.add(name)
        raw = open(p, 'rb').read().decode('utf-8', 'surrogateescape').replace('\r\n', '\n').replace('\r', '\n')
        lines = raw.split('\n')
        if lines and lines[-1] == '':
            lines.pop()
        lv = levels_of(lines)
        if not lv:
            print(f'{p}: no levels found, skipped'); continue
        # byte offsets on the normalised file (LF after every line)
        offsets, off = [], 0
        for line in lines:
            offsets.append(off); off += len(line.encode('utf-8', 'surrogateescape')) + 1
        with open(os.path.join(DATA, name + '.txt'), 'wb') as f:
            f.write(('\n'.join(lines) + '\n').encode('utf-8', 'surrogateescape'))
        with open(os.path.join(DATA, name + '.idx.tsv'), 'w', encoding='utf-8', newline='\n') as f:
            for start, rows, title in lv:
                f.write(f'{offsets[start]}\t{(title or "").replace(chr(9), " ")}\n')
        packs.append((name, lv))
        print(f'data/{name}.txt + .idx.tsv: {len(lv)} levels from {os.path.basename(p)}')
    if not packs:
        sys.exit('nothing packed')
    if len(packs) > 63:
        print(f'WARNING: {len(packs)} packs = {2 * len(packs) + 1} data files; the firmware allows 128')
    # the embedded fallback
    src_name = a.builtin_from or packs[0][0]
    lv = next((l for n, l in packs if n == src_name), packs[0][1])
    lua_path = os.path.join(HERE, 'index.lua')
    src = open(lua_path, encoding='utf-8').read()
    s, e = src.index('-- BUILTIN-BEGIN'), src.index('-- BUILTIN-END')
    body = [f'-- BUILTIN-BEGIN (generated by prepare_data.py: the first levels of {src_name})', 'local BUILTIN_PACK = [[']
    for _, rows, title in lv[:a.builtin]:
        body += rows; body.append('Title: ' + (title or '')); body.append('')
    body.append(']]')
    open(lua_path, 'w', encoding='utf-8', newline='\n').write(src[:s] + '\n'.join(body) + '\n' + src[e:])
    print(f'index.lua: embedded {min(a.builtin, len(lv))} fallback levels from {src_name}')


if __name__ == '__main__':
    main()
