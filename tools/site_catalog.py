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
import glob, html, json, os, re, shutil, struct, subprocess
from datetime import datetime, timedelta, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = 'https://github.com/omer-faruq-xteink/touch-licorice-apps'
SITE_URL = 'https://omer-faruq-xteink.github.io/touch-licorice-apps/'
RELEASE = REPO + '/releases/latest/download/'
STORE = 'https://xtapp-ai.xteink.cc/store'

# the firmware an API version first came with; older APIs run on every build the apps support
FIRMWARE = {'2.18': '26110201', '2.21': '26110501', '2.26': '26111201'}

CATEGORIES = [
    ('read', 'Reading', ['rss', 'instapaper', 'wallabag', 'readwise', 'hackernews', 'xkcd', 'wikipedia', 'bookworm']),
    ('tools', 'Tools and lock screens', ['tasks', 'notebook', 'timekeeper', 'calendar', 'weather', 'tbr', 'notes', 'calculator',
                                         'skytonight', 'litclock', 'wordclock']),
    ('learn', 'Learning', ['pianofollow', 'anki', 'dict', 'tarot']),
    ('stories', 'Stories', ['gamebook', 'textadv']),
    ('daily', 'Daily puzzles', ['wordhive', 'cryptogram', 'wordladder']),
    ('puzzles', 'Puzzles', ['sudoku', 'queens', 'casefiles', 'lamplighter', 'nonogram', 'kakuro', 'hashi', 'suguru', 'minesweeper', 'lightsout',
                            'knightstour', 'pegsolitaire', 'slidepuzzle', 'sokoban', 'chess', 'tsumego']),
    ('games', 'Games', ['chessplay', 'checkers', 'backgammon', 'delve', 'game2048', 'klondike', 'freecell', 'mahjong', 'merchant']),
]

# more than the package: (label, href, note); href is relative to the app's page
EXTRAS = {
    'dict': [('WordNet, English to English', RELEASE + 'dict-wordnet-en.zip',
              'Unzip it into XTApps/dict/files/ on the SD card.'),
             ('StarDict converter', '../../tools/dictionary/', 'Any other StarDict dictionary.')],
    'wikipedia': [('Offline pack: vital articles (English)', RELEASE + 'wikipedia-en-vital.zip',
                   'Read without Wi-Fi; see the app\'s help for where it goes.')],
    'pianofollow': [('Score converter', '../../tools/piano/', 'Your own MusicXML or ABC scores for the reader.')],
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
    s = re.sub(r'(?<![\w*])\*([^*\s][^*]*?)\*(?![\w*])', r'<em>\1</em>', s)
    s = re.sub(r'\[([^\]]+)\]\(([^)\s]+)\)', lambda m: f'<a href="{H(m.group(2))}">{m.group(1)}</a>', s)
    return s


def plain(md):
    return re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', md).replace('**', '').replace('`', '')


# sections of an app's README shown on its page after the introduction (set-up a user can't find
# on the reader): (title, folded). A folded section is a <details> the reader opens with a tap, so
# long optional or technical text does not make the page look hard; inside any section, a
# "### " sub-heading starts a folded part of its own (the steps of a set-up).
AI = ('AI questions (optional)', True)
SECTIONS = {'calendar': [('Adding a calendar', False)], 'rss': [AI], 'hackernews': [AI], 'instapaper': [('Setup', False), AI],
            'readwise': [AI], 'wallabag': [AI], 'tasks': [('Todoist, Google Tasks and TickTick', False)]}


def slug_of(title):
    return re.sub(r'[^\w\- ]', '', title.lower()).replace(' ', '-')   # as GitHub's, so README links work


def section_html(lines):
    # a README section's lines as HTML; each "### " part folded under its title
    out, part, title = [], [], None

    def close():
        if title is None:
            out.append(render(part))
        else:
            out.append(f'<details class="fold" id="{slug_of(title)}"><summary>{inline(title)}</summary>'
                       f'<div class="fold-body">{render(part)}</div></details>')
    for line in lines:
        if line.startswith('### '):
            close()
            part, title = [], line[4:].strip()
        else:
            part.append(line)
    close()
    return '\n'.join(x for x in out if x)


def intro(app):
    """the app README's text before its first section, and its SECTIONS, as HTML"""
    path = os.path.join(ROOT, 'apps', app, 'README.md')
    if not os.path.exists(path):
        return ''
    lines = open(path, encoding='utf-8').read().split('\n')
    body = []
    for line in lines[1:]:
        if line.startswith('## '):
            break
        body.append(line)
    out = [render(body)]
    for title, folded in SECTIONS.get(app, []):
        start = lines.index('## ' + title) + 1
        end = next((i for i in range(start, len(lines)) if lines[i].startswith('## ')), len(lines))
        body = section_html(lines[start:end])
        if folded:
            out.append(f'<details class="fold" id="{slug_of(title)}"><summary>{H(title)}</summary>'
                       f'<div class="fold-body">{body}</div></details>')
        else:
            out.append(f'<h3 id="{slug_of(title)}">{H(title)}</h3>' + body)
    return '\n'.join(out)


NOTES_URL = REPO + '/blob/main/RELEASE_NOTES.md'
WHATS_NEW = 6                    # changes shown on an app's page; the rest are in the release notes


def version_key(tag):
    return tuple(int(x) for x in re.findall(r'\d+', tag))


def display_names():
    """app folder -> its display name, from each app's manifest"""
    out = {}
    for p in glob.glob(os.path.join(ROOT, 'apps', '*', 'manifest.json')):
        app = os.path.basename(os.path.dirname(p))
        out[app] = json.load(open(p, encoding='utf-8')).get('display_name') or app
    return out


def names_in(text, names):
    """the apps whose display names appear in text, longer names first ("Chess puzzles" is not "Chess")"""
    hits = []
    for app, name in sorted(names.items(), key=lambda kv: -len(kv[1])):
        rx = re.compile(r'(?<!\w)' + re.escape(name) + r'(?!\w)')
        if rx.search(text):
            hits.append(app)
            text = rx.sub(lambda m: '\0' * len(m.group(0)), text)
    return hits


def lead_of(bullet):
    m = re.match(r'\*\*(.+?)\*\*', bullet)
    return m.group(1) if m else ''


def _git(*args):
    try:
        out = subprocess.run(['git', '-C', ROOT, *args], capture_output=True, timeout=20)
        return out.stdout.decode('utf-8').strip() if out.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


_dates = {}


def release_date(tag):
    """when a release came out: the date of its git tag's commit (None without the tag)"""
    if tag not in _dates:
        s = _git('log', '-1', '--format=%cI', tag)
        _dates[tag] = datetime.fromisoformat(s) if s else None
    return _dates[tag]


def app_new_in(tag, app):
    """the app arrived in this release: its manifest is at the tag but not at the release before"""
    tags = sorted((t for t in (_git('tag', '--list', 'v*') or '').split() if version_key(t) < version_key(tag)), key=version_key)
    here = _git('cat-file', '-e', f'{tag}:apps/{app}/manifest.json') is not None
    before = bool(tags) and _git('cat-file', '-e', f'{tags[-1]}:apps/{app}/manifest.json') is not None
    return here and not before


BADGE_DAYS = 7


def badges(changes, names, now, date_of=release_date, new_in=app_new_in):
    """app -> 'new' or 'updated', for a release out for at most BADGE_DAYS: New when the app arrived in
    it, Updated when one of its bullets names the app in the lead (a change about many apps, named
    only in its text, makes no badge: else a fix to every app would mark them all)"""
    out = {}
    for app, entries in changes.items():
        recent = [(t, b) for t, b in entries if (d := date_of(t)) and timedelta(0) <= now - d <= timedelta(days=BADGE_DAYS)]
        if any(new_in(t, app) for t, _ in recent):
            out[app] = 'new'
        elif any(app in names_in(lead_of(b), names) for _, b in recent):
            out[app] = 'updated'
    return out


def changes_by_app(notes, names, upto=None):
    """RELEASE_NOTES.md's bullets given to the apps they are about: app -> [(tag, bullet markdown)],
    newest first. A bullet is about the apps its bold lead names ("**Weather 1.1.1: ...**", "**New:
    Chess**"); when the lead names none ("**Back on the main screen offers to exit** in ..."), about
    the apps named anywhere in it. Longer names are matched first, so "Chess puzzles" is not "Chess".
    The Files tables are not changes; releases after `upto` (not out yet) are left out."""
    def named(text):
        return names_in(text, names)

    out = {}
    for tag, _, sections in releases(notes, upto):
        for _, bullets in sections:
            for b in bullets:
                lead = re.match(r'\*\*(.+?)\*\*', b)
                for app in named(lead.group(1) if lead else '') or named(b):
                    out.setdefault(app, []).append((tag, b))
    return out


def releases(notes, upto=None):
    """RELEASE_NOTES.md as [(tag, [intro paragraphs], [(section, [bullet markdown])])], newest first
    (the file's order); a bullet's wrapped lines are joined. The Files tables are left out, and so are
    releases after `upto` (not out yet)."""
    out, para, cur, section = [], [], None, None

    def end_para():
        if para and out and section is None:
            out[-1][1].append(' '.join(para))
        para.clear()
    for line in notes.split('\n') + ['']:
        if cur is not None and line.startswith('  ') and line.strip():
            cur.append(cur.pop() + ' ' + line.strip())
            continue
        cur = None
        m = re.match(r'# (v\d+(?:\.\d+)*)\s*$', line)
        if m:
            end_para()
            out.append((m.group(1), [], []))
            section = None
        elif not out:
            continue
        elif line.startswith('## '):
            end_para()
            section = line[3:].strip()
            if section != 'Files':
                out[-1][2].append((section, []))
        elif section is None:
            if line.strip():
                para.append(line.strip())
            else:
                end_para()
        elif section != 'Files' and line.startswith('- '):
            cur = out[-1][2][-1][1]
            cur.append(line[2:].strip())
    end_para()
    return [r for r in out if not upto or version_key(r[0]) <= version_key(upto)]


def link_names(bullet, names, pages):
    """a bullet with the app names of its bold lead linked to their pages (../apps/<app>/), longer
    names first; apps without a page (not listed) stay plain"""
    m = re.match(r'\*\*(.+?)\*\*', bullet)
    if not m:
        return bullet
    lead, keep = m.group(1), []
    for app, name in sorted(names.items(), key=lambda kv: -len(kv[1])):
        rx = re.compile(r'(?<![\w\0])' + re.escape(name) + r'(?![\w\0])')
        if not rx.search(lead):
            continue
        keep.append(f'[{name}](../apps/{app}/)' if app in pages else name)
        lead = rx.sub(lambda _: f'\0{len(keep) - 1}\0', lead, count=1)
    lead = re.sub(r'\0(\d+)\0', lambda k: keep[int(k.group(1))], lead)
    return f'**{lead}**' + bullet[m.end():]


def when_html(d):
    """a release's date and time: UTC in the page, turned into the reader's local time by the page's script"""
    return f'<time datetime="{d.isoformat()}">{d.astimezone(timezone.utc).strftime("%d %b %Y, %H:%M")} UTC</time>'


def whats_new_page(rels, names, date_of, pages):
    """the site's What's new page: every release out, newest first and open, the others folded"""
    parts = []
    for k, (tag, intro_paras, sections) in enumerate(rels):
        d = date_of(tag)
        head = f'{H(tag)}' + (f' <span class="when">&middot; {when_html(d)}</span>' if d else '')
        body = ''.join(f'<p>{inline(p)}</p>' for p in intro_paras)
        for sec, bullets in sections:
            if bullets:
                body += f'<h3>{H(sec)}</h3><ul>' + ''.join(f'<li>{inline(link_names(b, names, pages))}</li>' for b in bullets) + '</ul>'
        parts.append(f'<details class="fold release"{" open" if k == 0 else ""} id="{H(tag)}"><summary>{head}</summary>'
                     f'<div class="fold-body">{body}</div></details>')
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>What&rsquo;s new: Touch Licorice apps</title>
<meta name="description" content="What changed in each release of the Touch Licorice apps for the Xteink X4 Pro.">
<link rel="stylesheet" href="../assets/site.css">
<link rel="stylesheet" href="../assets/store.css">
</head>
<body class="store">
<main class="wrap">
  <h1>What&rsquo;s new</h1>
  <p class="sub">Every release of the apps, newest first. Packages: <a href="{REPO}/releases/latest">the latest release</a>.</p>
  <div class="prose">{''.join(parts)}</div>
</main>
<script type="module">
  import {{ chrome }} from '../assets/site.js';
  chrome('whats-new');
  for (const t of document.querySelectorAll('time[datetime]')) {{
    const d = new Date(t.getAttribute('datetime'));
    if (!isNaN(d)) t.textContent = d.toLocaleString(undefined, {{ dateStyle: 'medium', timeStyle: 'short' }});
  }}
  const d = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1)));
  if (d && d.tagName === 'DETAILS') {{ d.open = true; d.scrollIntoView(); }}
</script>
</body>
</html>
'''


_versions = {}


def app_version(tag, app, bullet, name):
    """the app's version in a release: its manifest at the release's git tag (exact; the workflow
    fetches the tags), else the version the bullet gives it ("Weather 1.1.1"), else the release"""
    key = (tag, app)
    if key not in _versions:
        try:
            out = subprocess.run(['git', '-C', ROOT, 'show', f'{tag}:apps/{app}/manifest.json'],
                                 capture_output=True, timeout=20)
            _versions[key] = json.loads(out.stdout.decode('utf-8')).get('version') if out.returncode == 0 else None
        except (OSError, ValueError, subprocess.SubprocessError):
            _versions[key] = None
    if _versions[key]:
        return _versions[key]
    m = re.search(r'(?<!\w)' + re.escape(name) + r' (\d+(?:\.\d+)+)', bullet)
    return m.group(1) if m else tag


def whats_new_html(entries, label=lambda tag, bullet: tag):
    """an app's latest changes as a folded list (empty when there are none); label(tag, bullet) is
    the badge (the app's version), the release goes in its tooltip"""
    if not entries:
        return ''
    items = ''.join(f'<li><span class="rel" title="release {H(t)}">{H(label(t, b))}</span> {inline(b)}</li>'
                    for t, b in entries[:WHATS_NEW])
    return (f'<details class="fold" id="whats-new"><summary>What&rsquo;s new</summary><div class="fold-body">'
            f'<ul class="changes">{items}</ul><p class="fine">Every change: <a href="{NOTES_URL}">the release notes</a>.</p>'
            '</div></details>')


def render(body):
    """lines of markdown: paragraphs, lists and ``` blocks, as HTML"""
    out, para, items, code = [], [], [], None
    kind = ['ul']                      # the list being collected: ul, or ol for "1. " lines

    def flush():
        if para and not para[0].startswith('**Needs firmware'):    # the page has its own notice
            out.append('<p>' + inline(' '.join(para)) + '</p>')
        para.clear()
        if items:
            out.append(f'<{kind[0]}>' + ''.join(f'<li>{inline(i)}</li>' for i in items) + f'</{kind[0]}>')
            items.clear()
    for line in body:
        t = line.strip()
        if t.startswith('```'):
            if code is None:
                flush()
                code = []
            else:
                out.append('<pre><code>' + H('\n'.join(code)) + '</code></pre>')
                code = None
        elif code is not None:
            code.append(t)
        elif not t:
            flush()
        elif t.startswith('- ') or re.match(r'^\d+\. ', t):
            if para:
                flush()
            want = 'ul' if t.startswith('- ') else 'ol'
            if items and kind[0] != want:
                flush()
            kind[0] = want
            items.append(t[2:] if want == 'ul' else re.sub(r'^\d+\. ', '', t))
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


# schema.org's application category for each site category (search engines read it from ld_json)
LD_CATEGORY = {'read': 'ReferenceApplication', 'tools': 'UtilitiesApplication', 'learn': 'EducationalApplication',
               'stories': 'GameApplication', 'daily': 'GameApplication', 'puzzles': 'GameApplication',
               'games': 'GameApplication'}


def ld_json(e):
    """an app's page described for search engines (schema.org SoftwareApplication, JSON-LD)"""
    page = f'{SITE_URL}apps/{e["id"]}/'
    d = {'@context': 'https://schema.org', '@type': 'SoftwareApplication', 'name': e['name'],
         'description': e['plain'], 'url': page, 'applicationCategory': LD_CATEGORY[e['category']],
         'applicationSubCategory': e['category_name'], 'operatingSystem': 'XTOS Licorice (Xteink X4 Pro)',
         'softwareVersion': e['version'], 'fileSize': e['size_text'],
         'downloadUrl': f'{SITE_URL}packages/{e["file"]}', 'image': f'{SITE_URL}social/{e["id"]}.png',
         'author': {'@type': 'Person', 'name': 'omer-faruq', 'url': 'https://github.com/omer-faruq'},
         'offers': {'@type': 'Offer', 'price': '0', 'priceCurrency': 'USD'},
         'isAccessibleForFree': True}
    if e['shots']:
        d['screenshot'] = f'{SITE_URL}shots/{e["shots"][0]}'
    # </ cannot end the script early
    return json.dumps(d, ensure_ascii=False).replace('</', '<\\/')


def shot_size(f):
    """(width, height) of a screenshot in site/shots/: 800x480 for a landscape app"""
    try:
        with open(os.path.join(ROOT, 'site', 'shots', f), 'rb') as fh:
            head = fh.read(24)
        if head[:8] == bytes([137, 80, 78, 71, 13, 10, 26, 10]):          # a PNG: its size is in the IHDR
            return struct.unpack('>II', head[16:24])
    except OSError:
        pass
    return 480, 800


BADGE_TEXT = {'new': 'New', 'updated': 'Updated'}


def badge_html(badge):
    return f' <span class="badge {badge}">{BADGE_TEXT[badge]}</span>' if badge in BADGE_TEXT else ''


def app_page(e, about, whats=''):
    def shot(n, f):
        if f.endswith('-photo.jpg'):
            return (f'<img class="photo" src="../../shots/{f}" width="480" height="800" alt="{H(e["name"])} on the reader"'
                    + (' loading="lazy"' if n > 2 else '') + '>')
        w, h = shot_size(f)
        return (f'<div class="device{" landscape" if w > h else ""}"><div class="screen"><img src="../../shots/{f}" '
                f'width="{w}" height="{h}" alt="{H(e["name"])}, screen {n}"' + (' loading="lazy"' if n > 2 else '') + '></div></div>')
    shots = ''.join(shot(n, f) for n, f in enumerate(e['shots'], 1))
    extras = ''.join(f'<li><a href="{H(href)}"><b>{H(label)}</b><span>{H(note)}</span></a></li>'
                     for label, href, note in EXTRAS.get(e['id'], []))
    need = (f'<div class="notice">{WARN}<div>Needs firmware <b>XT Licorice {e["firmware"]}</b> or later (API {e["api"]}). '
            'Older firmware refuses to install it and asks for an update.</div></div>') if e['firmware'] else ''
    store = (f' Also in <a href="{STORE}">Xteink&rsquo;s app store</a>, where updates arrive by themselves.' if e['store'] else '')
    firmware = f'{e["firmware"]}+' if e['firmware'] else 'any'
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{H(e["name"])}: InkApp for the Xteink X4 Pro</title>
<meta name="description" content="{H(e["plain"])}">
<script type="application/ld+json">{ld_json(e)}</script>
<link rel="stylesheet" href="../../assets/site.css">
<link rel="stylesheet" href="../../assets/store.css">
</head>
<body class="store">
<main class="wrap">
  <section class="app-top">
    <div class="appicon big"><img src="icon.png" alt=""></div>
    <div>
      <h1>{H(e["name"])}{badge_html(e["badge"])}</h1>
      <p class="sub">{H(e["category_name"])} &middot; InkApp for the Xteink X4 Pro</p>
      <div class="acts">
        <button type="button" class="get primary big copy" data-app="{H(e["id"])}" hidden>Copy to reader</button>
        <a class="get big" data-app="{H(e["id"])}" href="../../packages/{H(e["file"])}" download>{DOWNLOAD} Download</a>
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
  <div class="prose"><p class="lead">{inline(e["summary"])}</p>{about}{whats}</div>
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
  // a link to a folded section (from another page or the page itself) opens it
  const unfold = () => {{
    const d = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1)));
    if (d && d.tagName === 'DETAILS') {{ d.open = true; d.scrollIntoView(); }}
  }};
  unfold();
  addEventListener('hashchange', unfold);
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
    # What's new: the release notes up to the release the packages come from (RELEASE_TAG in the
    # workflow, else a release/vX.Y.Z folder's name), so a release not out yet stays off the site
    m = re.search(r'v\d+(?:\.\d+)+$', os.path.basename(os.path.normpath(packages)))
    upto = os.environ.get('RELEASE_TAG') or (m.group(0) if m else None)
    changes = changes_by_app(open(os.path.join(ROOT, 'RELEASE_NOTES.md'), encoding='utf-8').read(), display_names(), upto)
    badge_of = badges(changes, display_names(), datetime.now(timezone.utc))     # the daily rebuild ends them
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
            'devices': ['X4 Pro'],          # every app here is made for touch
            'badge': badge_of.get(app),
        }
        entries.append(e)
        shutil.copyfile(path, os.path.join(out, 'packages', e['file']))
        page = os.path.join(out, 'apps', app)
        os.makedirs(page, exist_ok=True)
        icon = os.path.join(ROOT, 'apps', app, 'icon.png')
        if os.path.exists(icon):
            shutil.copyfile(icon, os.path.join(page, 'icon.png'))
        with open(os.path.join(page, 'index.html'), 'w', encoding='utf-8', newline='\n') as f:
            label = lambda tag, b, app=app, name=name: app_version(tag, app, b, name)
            f.write(app_page(e, intro(app), whats_new_html(changes.get(app, []), label)))
    entries.sort(key=lambda e: order[e['id']])
    rels = releases(open(os.path.join(ROOT, 'RELEASE_NOTES.md'), encoding='utf-8').read(), upto)
    os.makedirs(os.path.join(out, 'whats-new'), exist_ok=True)
    with open(os.path.join(out, 'whats-new', 'index.html'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(whats_new_page(rels, display_names(), release_date, {e['id'] for e in entries}))
    latest = rels[0][0] if rels else None
    latest_date = release_date(latest) if latest else None
    catalog = {
        'release': {'tag': latest, 'date': latest_date.isoformat() if latest_date else None},
        'categories': [{'id': k, 'name': n} for k, n, _ in CATEGORIES],
        'apps': [{k: e[k] for k in ('id', 'app_id', 'name', 'version', 'api', 'firmware', 'summary', 'category',
                                    'file', 'size', 'store', 'devices', 'badge')} | {'summary': inline(e['summary'])} for e in entries],
    }
    with open(os.path.join(out, 'catalog.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(catalog, f, ensure_ascii=False, indent=1)
    return len(entries)
