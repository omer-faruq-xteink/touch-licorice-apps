"""Build an offline Wikipedia pack for the Xteink Wikipedia mini app: the opening sections of a set
of articles, as plain text.

  python wiki2pack.py OUT_DIR [--lang en] [--vital 4] [--prefix wen] [--name "..."]
  python wiki2pack.py OUT_DIR --lang tr --titles my_titles.txt --prefix wtr

The articles are English Wikipedia's "vital articles" of a level (4: about 10 000, grouped by
topic on Wikipedia:Vital articles/Level/4/...), or the titles listed in a file (one per line), in
any language. Their opening sections come from the MediaWiki API (TextExtracts, plain text), 20 a
request, one request at a time with a short pause, under a User-Agent naming this project.

Output: OUT_DIR/<prefix>_info.txt (name, language, article count), OUT_DIR/<prefix>_shards.tsv
(per file: name, first title, last title, articles) and OUT_DIR/<prefix>_a000.txt ... with one
article per line, "title<TAB>text" ("\\n" for a line break), sorted by title (ASCII letters
folded to lower case, then bytes: the order the app's search expects), each file at most about
150 KB (the app reads a file whole within the ~1 MB the reader gives it). Copy the files into
XTApps/wikipedia/files/ on the SD card. Wikipedia text is CC BY-SA 4.0; the pack says so in its
info file.
"""
import argparse, json, os, re, sys, time, urllib.parse, urllib.request

UA = 'XteinkLicoriceWikipedia/1.0 (https://github.com/omer-faruq/touch-licorice-apps; offline pack builder)'
SHARD_BYTES = 150_000
VITAL_TOPICS = ['People', 'History', 'Geography', 'Arts', 'Philosophy and religion', 'Everyday life',
                'Society and social sciences', 'Biological and health sciences', 'Physical sciences',
                'Technology', 'Mathematics']


def api(lang, params, tries=4):
    q = dict(params, format='json', formatversion='2')
    url = f'https://{lang}.wikipedia.org/w/api.php?' + urllib.parse.urlencode(q)
    for k in range(tries):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode('utf-8'))
        except Exception as e:                      # a busy server: wait and try again
            if k == tries - 1:
                raise
            print(f'  retry after {e}', flush=True)
            time.sleep(5 * (k + 1))


def vital_titles(level):
    pages = [f'Wikipedia:Vital articles/Level/{level}/{t}' for t in VITAL_TOPICS]
    titles, cont = set(), {}
    while True:
        # redirects: the topic pages moved (to "Level 4/<topic>" in October 2026); links on
        # the subpages a topic page transcludes count as its own
        data = api('en', dict({'action': 'query', 'generator': 'links', 'titles': '|'.join(pages),
                               'gplnamespace': '0', 'gpllimit': 'max', 'redirects': '1'}, **cont))
        for p in data.get('query', {}).get('pages', []):
            if not p.get('missing'):
                titles.add(p['title'])
        if 'continue' not in data:
            break
        cont = data['continue']
        time.sleep(0.2)
    return sorted(titles)


def intros(lang, titles):
    """{title: opening section as plain text}, 20 titles a request"""
    out = {}
    for i in range(0, len(titles), 20):
        batch = titles[i:i + 20]
        data = api(lang, {'action': 'query', 'prop': 'extracts', 'exintro': '1', 'explaintext': '1',
                          'exlimit': '20', 'redirects': '1', 'titles': '|'.join(batch)})
        for p in data.get('query', {}).get('pages', []):
            text = (p.get('extract') or '').strip()
            if text and not p.get('missing'):
                out[p['title']] = re.sub(r'\n{3,}', '\n\n', text.replace('\r', ''))
        if (i // 20) % 25 == 0:
            print(f'  {min(i + 20, len(titles))} of {len(titles)} asked, {len(out)} with text', flush=True)
        time.sleep(0.2)
    return out


def sort_key(title):
    return title.encode('utf-8').lower()          # ASCII folded, then bytes (as the app compares)


def esc(s):
    return s.replace('\\', '\\\\').replace('\t', ' ').replace('\n', '\\n')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('out')
    ap.add_argument('--lang', default='en')
    ap.add_argument('--vital', type=int, default=4, help='English vital articles of this level (default 4)')
    ap.add_argument('--titles', help='a file of titles, one a line, instead of the vital articles')
    ap.add_argument('--prefix', default=None, help='file name prefix, letters (default w + language)')
    ap.add_argument('--name', default=None)
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    prefix = a.prefix or ('w' + re.sub(r'[^a-z]', '', a.lang))
    if not re.fullmatch(r'[A-Za-z]{2,12}', prefix):
        raise SystemExit('--prefix: 2..12 letters')
    if a.titles:
        titles = [l.strip() for l in open(a.titles, encoding='utf-8') if l.strip() and not l.startswith('#')]
        name = a.name or f'Wikipedia {a.lang}, {len(titles)} articles'
    else:
        if a.lang != 'en':
            raise SystemExit('the vital articles are English Wikipedia\'s: use --titles for another language')
        print(f'listing the vital articles of level {a.vital} ...', flush=True)
        titles = vital_titles(a.vital)
        name = a.name or f'Wikipedia English, vital articles (level {a.vital})'
    print(f'{len(titles)} titles; fetching their opening sections ...', flush=True)
    texts = intros(a.lang, titles)
    os.makedirs(a.out, exist_ok=True)
    for fn in os.listdir(a.out):
        if re.fullmatch(re.escape(prefix) + r'_(a\d{3}\.txt|shards\.tsv|info\.txt)', fn):
            os.remove(os.path.join(a.out, fn))
    items = sorted(texts.items(), key=lambda kv: sort_key(kv[0]))
    shards, cur, size = [], [], 0
    for t, x in items:
        line = esc(t) + '\t' + esc(x) + '\n'
        n = len(line.encode('utf-8'))
        if cur and size + n > SHARD_BYTES:
            shards.append(cur)
            cur, size = [], 0
        cur.append((t, line))
        size += n
    if cur:
        shards.append(cur)
    index = []
    for k, sh in enumerate(shards):
        fn = f'{prefix}_a{k:03d}.txt'
        with open(os.path.join(a.out, fn), 'w', encoding='utf-8', newline='\n') as f:
            f.write(''.join(line for _t, line in sh))
        index.append(f'{fn}\t{esc(sh[0][0])}\t{esc(sh[-1][0])}\t{len(sh)}')
    with open(os.path.join(a.out, f'{prefix}_shards.tsv'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(index) + '\n')
    with open(os.path.join(a.out, f'{prefix}_info.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(f'name={name}\nlang={a.lang}\narticles={len(items)}\nshards={len(shards)}\n'
                f'built={time.strftime("%Y-%m-%d")}\nlicence=Wikipedia text, CC BY-SA 4.0 (https://{a.lang}.wikipedia.org)\n')
    total = sum(os.path.getsize(os.path.join(a.out, fn)) for fn in os.listdir(a.out) if fn.startswith(prefix + '_'))
    print(f'{name}: {len(items)} articles in {len(shards)} files, {total // 1024} KB; '
          f'copy {a.out}{os.sep}{prefix}_* into XTApps/wikipedia/files/', flush=True)


if __name__ == '__main__':
    main()
