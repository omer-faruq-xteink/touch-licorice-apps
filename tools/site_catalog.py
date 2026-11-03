"""The app catalog of the site: one entry per package of the latest release, read from the package
itself (its manifest sits in the clear after the header), with the summary from README.md's app
table, the introduction of the app's own README, its icon and its screenshots (site/shots/, made
by tools/site_shots.py). build_site.py calls build(out, packages_dir), which writes

    catalog.json                 what the home page lists and the card code compares against
    packages/<app>.xtapp         the packages, served by the site itself so the page can copy them
                                 to the reader's SD card (GitHub's release downloads refuse that)
    apps/<app>/index.html        a page per app, with its own address to share
    apps/<app>/icon.png
"""
import glob, html, json, os, re, shutil, struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = 'https://github.com/omer-faruq-xteink/touch-licorice-apps'
SITE_URL = 'https://omer-faruq-xteink.github.io/touch-licorice-apps/'
RELEASE = REPO + '/releases/latest/download/'
STORE = 'https://xtapp-ai.xteink.cc/store'

# the firmware an API version first came with; older APIs run on every build the apps support
FIRMWARE = {'2.18': '26110201'}

CATEGORIES = [
    ('read', 'Reading', ['rss', 'instapaper', 'wallabag', 'readwise', 'hackernews', 'wikipedia']),
    ('tools', 'Tools and lock screens', ['tasks', 'calendar', 'weather', 'tbr', 'notes', 'calculator',
                                         'skytonight', 'litclock', 'wordclock']),
    ('learn', 'Learning', ['anki', 'dict', 'tarot']),
    ('stories', 'Stories', ['gamebook', 'textadv']),
    ('daily', 'Daily puzzles', ['wordhive', 'cryptogram', 'wordladder']),
    ('puzzles', 'Puzzles', ['sudoku', 'nonogram', 'kakuro', 'hashi', 'suguru', 'minesweeper', 'lightsout',
                            'knightstour', 'pegsolitaire', 'slidepuzzle', 'sokoban', 'chess', 'tsumego']),
    ('games', 'Games', ['delve', 'game2048', 'klondike', 'freecell', 'mahjong', 'merchant']),
]

# more than the package: (label, href, note); href is relative to the app's page
EXTRAS = {
    'dict': [('WordNet, English to English', RELEASE + 'dict-wordnet-en.zip',
              'Unzip it into XTApps/dict/files/ on the SD card.'),
             ('StarDict converter', '../../tools/dictionary/', 'Any other StarDict dictionary.')],
    'wikipedia': [('Offline pack: vital articles (English)', RELEASE + 'wikipedia-en-vital.zip',
                   'Read without Wi-Fi; see the app\'s help for where it goes.')],
    'anki': [('Anki deck converter', '../../tools/anki/', 'Your .apkg decks and word lists as cards.')],
    'gamebook': [('Story pack and converters', '../../tools/gamebook/', 'More stories, and Twine, Ink or Project Aon stories.')],
    'textadv': [('Zork I, II and III', '../../tools/textadv/', 'The free pack, and where to find more games.')],
    'rss': [('Feed lists', '../../tools/feeds/', 'Ready lists by topic, as OPML.'),
            ('Worker setup', '../../tools/worker/', 'Only for CommaFeed and full article text.')],
    'hackernews': [('Worker setup', '../../tools/worker/', 'Only for article text.')],
}

H = html.escape


def package_manifest(path):
    """the manifest of a .xtapp: offset and length at 0x10 of the header"""
    with open(path, 'rb') as f:
        head = f.read(0x18)
        off, n = struct.unpack_from('<II', head, 0x10)
        f.seek(off)
        return json.loads(f.read(n).decode('utf-8'))


def readme_table():
    """README.md's app table: display name -> summary (markdown)"""
    out = {}
    for line in open(os.path.join(ROOT, 'README.md'), encoding='utf-8'):
        m = re.match(r'\| \*\*(.+?)\*\*(?:, \*\*.+?\*\*)? \| (.+) \|\s*$', line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def inline(md):
    """**bold**, `code` and [links](url) of a line of markdown, as HTML"""
    s = H(md, quote=False)
    s = re.sub(r'`([^`]+)`', r'<code>\1</code>', s)
    s = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', s)
    s = re.sub(r'\[([^\]]+)\]\(([^)\s]+)\)', lambda m: f'<a href="{H(m.group(2))}">{m.group(1)}</a>', s)
    return s


def plain(md):
    return re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', md).replace('**', '').replace('`', '')


def intro(app):
    """the app README's text before its first section, as HTML paragraphs and lists"""
    path = os.path.join(ROOT, 'apps', app, 'README.md')
    if not os.path.exists(path):
        return ''
    lines = open(path, encoding='utf-8').read().split('\n')
    body = []
    for line in lines[1:]:
        if line.startswith('## '):
            break
        body.append(line)
    out, para, items = [], [], []

    def flush():
        if para and not para[0].startswith('**Needs firmware'):    # the page has its own notice
            out.append('<p>' + inline(' '.join(para)) + '</p>')
        para.clear()
        if items:
            out.append('<ul>' + ''.join(f'<li>{inline(i)}</li>' for i in items) + '</ul>')
            items.clear()
    for line in body:
        t = line.strip()
        if not t:
            flush()
        elif t.startswith('- '):
            if para:
                flush()
            items.append(t[2:])
        elif items and line.startswith('  '):
            items[-1] += ' ' + t
        else:
            para.append(t)
    flush()
    return '\n'.join(out)


def store_apps():
    path = os.path.join(ROOT, 'store', 'apps.json')
    return json.load(open(path, encoding='utf-8')) if os.path.exists(path) else {}


DOWNLOAD = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" '
            'stroke-linejoin="round"><path d="M12 4v11m-5-5 5 5 5-5M5 20h14"/></svg>')
WARN = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M12 3 2 20h20L12 3z"/><path d="M12 10v4m0 3h.01"/></svg>')


def app_page(e, about):
    shots = ''.join((f'<img class="photo" src="../../shots/{f}" width="480" height="800" alt="{H(e["name"])} on the reader"'
                     if f.endswith('-photo.jpg') else
                     f'<div class="device"><div class="screen"><img src="../../shots/{f}" width="480" height="800" '
                     f'alt="{H(e["name"])}, screen {n}"') + (' loading="lazy"' if n > 2 else '') +
                    ('>' if f.endswith('-photo.jpg') else '></div></div>')
                    for n, f in enumerate(e['shots'], 1))
    extras = ''.join(f'<li><a href="{H(href)}"><b>{H(label)}</b><span>{H(note)}</span></a></li>'
                     for label, href, note in EXTRAS.get(e['id'], []))
    need = (f'<div class="notice">{WARN}<div>Needs firmware <b>XT Licorice {e["firmware"]}</b> or later (API {e["api"]}). '
            'Older firmware refuses to install it and asks for an update.</div></div>') if e['firmware'] else ''
    store = (f' Also in <a href="{STORE}">Xteink&rsquo;s app store</a>, where updates arrive by themselves.' if e['store'] else '')
    og_img = f'{SITE_URL}shots/{e["shots"][0]}' if e['shots'] else f'{SITE_URL}apps/{e["id"]}/icon.png'
    firmware = f'{e["firmware"]}+' if e['firmware'] else 'any'
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{H(e["name"])} for the Xteink X4 Pro</title>
<meta name="description" content="{H(e["plain"])}">
<meta property="og:title" content="{H(e["name"])} for the Xteink X4 Pro">
<meta property="og:description" content="{H(e["plain"])}">
<meta property="og:image" content="{og_img}">
<meta property="og:url" content="{SITE_URL}apps/{e["id"]}/">
<link rel="stylesheet" href="../../assets/site.css">
<link rel="stylesheet" href="../../assets/store.css">
</head>
<body class="store">
<main class="wrap">
  <section class="app-top">
    <div class="appicon big"><img src="icon.png" alt=""></div>
    <div>
      <h1>{H(e["name"])}</h1>
      <p class="sub">{H(e["category_name"])} &middot; for the Xteink X4 Pro</p>
      <div class="acts">
        <button type="button" class="get primary big copy" data-app="{H(e["id"])}" hidden>Copy to reader</button>
        <a class="get big" href="../../packages/{H(e["file"])}" download>{DOWNLOAD} Download</a>
        <span class="status" data-app="{H(e["id"])}"></span>
      </div>
    </div>
  </section>
  <div class="facts-row">
    <div><small>Version</small><b>{H(e["version"])}</b></div>
    <div><small>Size</small><b>{e["size_text"]}</b></div>
    <div><small>Firmware</small><b>{firmware}</b></div>
    <div><small>Price</small><b>Free</b></div>
  </div>
  {need}
  <div id="reader"></div>
  {f'<div class="gallery">{shots}</div>' if shots else ''}
  <div class="section-head"><h2>About</h2></div>
  <div class="prose"><p class="lead">{inline(e["summary"])}</p>{about}</div>
  {f'<div class="section-head"><h2>More for {H(e["name"])}</h2></div><ul class="more">{extras}</ul>' if extras else ''}
  <div class="section-head"><h2>How to install</h2></div>
  <ol class="how">
    <li><strong>Copy it to the reader</strong><p>Connect the reader in USB mode and press <b>Copy to reader</b> (Chrome or
      Edge on a computer), or download <code>{H(e["file"])}</code> and copy it to the SD card yourself.</p></li>
    <li><strong>Install it on the reader</strong><p>Open <b>All Files</b>, tap <code>{H(e["file"])}</code>, then
      <b>Install</b>. An update installs over the app and keeps its settings: do not uninstall first.</p></li>
  </ol>
  <p class="fine">Help, source and release notes: <a href="{REPO}/tree/main/apps/{H(e["id"])}">{H(e["name"])} on GitHub</a>.{store}</p>
</main>
<script type="module">
  import {{ chrome }} from '../../assets/site.js';
  import {{ readerPanel }} from '../../assets/store.js';
  chrome({{ app: {json.dumps(e["name"])} }});
  readerPanel(document.getElementById('reader'), '../../', [{json.dumps(e["id"])}]);
</script>
</body>
</html>
'''


def shot_files(app):
    """the app's screenshots in site/shots/, in their order"""
    names = [os.path.basename(p) for p in glob.glob(os.path.join(ROOT, 'site', 'shots', f'{app}-*'))]
    return sorted(names, key=lambda f: int(re.match(rf'{re.escape(app)}-(\d+)', f).group(1)))


def size_text(n):
    return f'{round(n / 1024)} KB' if n < 1048576 else f'{n / 1048576:.1f} MB'


def build(out, packages):
    summaries = readme_table()
    listed = store_apps()
    cat_of = {app: (key, name) for key, name, apps in CATEGORIES for app in apps}
    order = {app: i for i, app in enumerate(app for _, _, apps in CATEGORIES for app in apps)}
    entries = []
    os.makedirs(os.path.join(out, 'packages'), exist_ok=True)
    for path in sorted(glob.glob(os.path.join(packages, '*.xtapp'))):
        app = os.path.splitext(os.path.basename(path))[0]
        if app not in cat_of:          # the developer probes are not listed
            continue
        man = package_manifest(path)
        name = man.get('display_name', app)
        summary = summaries.get(name, man.get('description', ''))
        summary = summary[:1].upper() + summary[1:]
        size = os.path.getsize(path)
        s = listed.get(app, {})
        e = {
            'id': app, 'app_id': man['app_id'], 'name': name, 'version': man.get('version', ''),
            'api': man.get('api', ''), 'firmware': FIRMWARE.get(man.get('api', '')),
            'summary': summary, 'plain': plain(summary), 'category': cat_of[app][0], 'category_name': cat_of[app][1],
            'file': os.path.basename(path), 'size': size, 'size_text': size_text(size),
            'shots': shot_files(app),
            'store': bool(s.get('live_version')),
        }
        entries.append(e)
        shutil.copyfile(path, os.path.join(out, 'packages', e['file']))
        page = os.path.join(out, 'apps', app)
        os.makedirs(page, exist_ok=True)
        icon = os.path.join(ROOT, 'apps', app, 'icon.png')
        if os.path.exists(icon):
            shutil.copyfile(icon, os.path.join(page, 'icon.png'))
        with open(os.path.join(page, 'index.html'), 'w', encoding='utf-8', newline='\n') as f:
            f.write(app_page(e, intro(app)))
    entries.sort(key=lambda e: order[e['id']])
    catalog = {
        'categories': [{'id': k, 'name': n} for k, n, _ in CATEGORIES],
        'apps': [{k: e[k] for k in ('id', 'app_id', 'name', 'version', 'api', 'firmware', 'summary', 'category',
                                    'file', 'size', 'store')} | {'summary': inline(e['summary'])} for e in entries],
    }
    with open(os.path.join(out, 'catalog.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(catalog, f, ensure_ascii=False, indent=1)
    return len(entries)
