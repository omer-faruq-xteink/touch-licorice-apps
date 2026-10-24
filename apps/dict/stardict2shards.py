"""Convert a StarDict dictionary into the shard files the Xteink Dictionary mini app reads.

  python stardict2shards.py DICT_DIR_OR_IFO OUT_DIR [--prefix entr] [--shard-kb 200] [--max-def 1500]

The mini-app host (XTOS Licorice, API 2.9) can only read whole files from the app's own storage
(no byte ranges, ~1 MB Lua heap), so the dictionary is cut into sorted shards of about
--shard-kb kilobytes, each a text file of lines

    headword<TAB>definition

where the definition is plain text with "\\n" (two characters) for a line break. A lookup reads
the index, picks the one shard whose range covers the word, reads that file and scans it.

Output: OUT_DIR/<prefix>_info.txt (name, word count, shard count), OUT_DIR/<prefix>_shards.tsv
(one line per shard: "file<TAB>first word<TAB>last word"), OUT_DIR/<prefix>_d000.txt … (the
shards). Several dictionaries with different prefixes can share one folder; the app lists them.
Without --prefix the files are named info.txt / shards.tsv / d000.txt (a single dictionary).
The app's storage holds 512 files, so keep the total shard count under ~500.

Reads .ifo / .idx / .dict or .dict.dz (dictzip = gzip). sametypesequence "h" (HTML) and "m"/"t"
(plain) are handled; other type sequences are treated as text.
"""
import argparse, gzip, html, os, re, struct, sys


def read_ifo(path):
    info = {}
    for line in open(path, encoding='utf-8', errors='replace'):
        if '=' in line:
            k, v = line.rstrip('\n').split('=', 1)
            info[k.strip()] = v.strip()
    return info


def iter_idx(path, offset_bits=32):
    data = open(path, 'rb').read()
    i, n = 0, len(data)
    fmt, step = ('>QI', 12) if offset_bits == 64 else ('>II', 8)
    while i < n:
        j = data.index(b'\0', i)
        word = data[i:j].decode('utf-8', 'replace')
        off, size = struct.unpack_from(fmt, data, j + 1)
        yield word, off, size
        i = j + 1 + step


BLOCK_CLOSE = re.compile(r'</(p|div|li|h[1-6]|blockquote|tr|dd|dt)\s*>|<br\s*/?>', re.I)
TAG = re.compile(r'<[^>]+>')


def html_to_text(s):
    s = BLOCK_CLOSE.sub('\n', s)
    s = re.sub(r'<(li)\b[^>]*>', '• ', s, flags=re.I)
    s = TAG.sub('', s)
    s = html.unescape(s).replace(' ', ' ')
    s = re.sub(r'[ \t]+', ' ', s)
    s = re.sub(r' *\n+ *', '\n', s)
    return s.strip()


SENSE = re.compile(r' (?=(?:n|v|adj|adv|prep|pron|conj|interj) (?:\d+)?: )|(?<=[^\d ]) +(?=\d+: )')


def plain_text(s, word=''):
    """dictd-style plain text: the headword repeated on the first line, then hard-wrapped lines
    with deep indentation. Unwrap, drop the repeated headword, one sense per line."""
    lines = [l.rstrip() for l in s.replace('\r', '').split('\n')]
    if lines and lines[0].strip().lower() == word.strip().lower():
        lines = lines[1:]
    t = ' '.join(l.strip() for l in lines if l.strip())
    t = re.sub(r' {2,}', '  ', t)
    t = SENSE.sub('\n', t)
    t = re.sub(r'(?<=\]) (?=\d+: )|(?<=\]) (?=[a-z]+ \d+: )', '\n', t)
    # keep the part of speech on the line of its first sense: "n\n1: ..." -> "n 1: ..."
    t = re.sub(r'(^|\n)((?:n|v|adj|adv|prep|pron|conj|interj))\n(\d+: )', r'\1\2 \3', t)
    return t.strip()


def definition_text(raw, types, word=''):
    # StarDict entries may chain several typed parts; with a sametypesequence the type bytes
    # are omitted and every entry is one part.
    if types:
        if types in ('h',):
            return html_to_text(raw.decode('utf-8', 'replace'))
        return plain_text(raw.decode('utf-8', 'replace'), word)
    # no sametypesequence: parts are <type byte><data \0> ...
    out, i = [], 0
    while i < len(raw):
        t = chr(raw[i]); i += 1
        if t.islower():
            j = raw.find(b'\0', i)
            if j == -1: j = len(raw)
            part = raw[i:j]; i = j + 1
        else:
            size = struct.unpack_from('>I', raw, i)[0]; i += 4
            part = raw[i:i + size]; i += size
            continue  # binary parts (images, sounds) are skipped
        out.append(html_to_text(part.decode('utf-8', 'replace')) if t in 'hg' else part.decode('utf-8', 'replace').strip())
    return '\n'.join(p for p in out if p)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('src', help='dictionary folder or the .ifo file')
    ap.add_argument('out')
    ap.add_argument('--prefix', default='', help='file name prefix (letters/digits), e.g. entr; lets several dictionaries share the folder')
    ap.add_argument('--shard-kb', type=int, default=200, help='target shard size in KB (the app reads one whole shard per lookup)')
    ap.add_argument('--max-def', type=int, default=1500, help='truncate definitions longer than this many characters')
    a = ap.parse_args()

    ifo = a.src if a.src.endswith('.ifo') else next(os.path.join(a.src, f) for f in os.listdir(a.src) if f.endswith('.ifo'))
    base = ifo[:-4]
    info = read_ifo(ifo)
    types = info.get('sametypesequence', '')
    offset_bits = 64 if info.get('idxoffsetbits') == '64' else 32
    dict_path = base + '.dict' if os.path.exists(base + '.dict') else base + '.dict.dz'
    print(f'{info.get("bookname", base)}: {info.get("wordcount")} words, types={types or "mixed"}, dict={os.path.basename(dict_path)}')
    blob = gzip.open(dict_path, 'rb').read() if dict_path.endswith('.dz') else open(dict_path, 'rb').read()

    pre = (a.prefix + '_') if a.prefix else ''
    if a.prefix and not re.fullmatch(r'[A-Za-z0-9]+', a.prefix):
        raise SystemExit('--prefix must be letters and digits only')
    os.makedirs(a.out, exist_ok=True)
    for fn in os.listdir(a.out):
        if re.fullmatch(re.escape(pre) + r'(d\d{3}\.txt|shards\.tsv|info\.txt)', fn):
            os.remove(os.path.join(a.out, fn))
    shards, cur, cur_size, first = [], [], 0, None
    limit = a.shard_kb * 1024
    count = 0

    def flush():
        nonlocal cur, cur_size, first
        if not cur:
            return
        name = f'{pre}d{len(shards):03d}.txt'
        with open(os.path.join(a.out, name), 'w', encoding='utf-8', newline='\n') as f:
            f.write('\n'.join(cur) + '\n')
        shards.append((name, first, cur[-1].split('\t', 1)[0]))
        cur, cur_size, first = [], 0, None

    last_word = None
    for word, off, size in iter_idx(base + '.idx', offset_bits):
        text = definition_text(blob[off:off + size], types, word)
        if len(text) > a.max_def:
            text = text[:a.max_def].rsplit(' ', 1)[0] + ' …'
        word = word.replace('\t', ' ').replace('\n', ' ').strip()
        if not word or not text:
            continue
        line = word + '\t' + text.replace('\\', '\\\\').replace('\n', '\\n')
        if word == last_word and cur:
            # same headword repeated: merge into the previous line
            cur[-1] = cur[-1] + '\\n' + line.split('\t', 1)[1]
            continue
        if cur_size + len(line) + 1 > limit and cur:
            flush()
        if first is None:
            first = word
        cur.append(line); cur_size += len(line.encode('utf-8')) + 1
        last_word = word; count += 1
    flush()

    with open(os.path.join(a.out, pre + 'shards.tsv'), 'w', encoding='utf-8', newline='\n') as f:
        for name, lo, hi in shards:
            f.write(f'{name}\t{lo}\t{hi}\n')
    with open(os.path.join(a.out, pre + 'info.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(f'name={info.get("bookname", os.path.basename(base))}\nwords={count}\nshards={len(shards)}\n')
    total = sum(os.path.getsize(os.path.join(a.out, n)) for n, _, _ in shards)
    print(f'{count} entries -> {len(shards)} shards, {total / 1024 / 1024:.1f} MB in {a.out}')
    if len(shards) > 500:
        print('WARNING: more than 500 shards; the app storage allows 512 files. Raise --shard-kb.', file=sys.stderr)


if __name__ == '__main__':
    main()
