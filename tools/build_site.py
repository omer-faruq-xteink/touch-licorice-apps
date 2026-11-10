"""Build the site (GitHub Pages) into OUT_DIR: site/ without its tests; the app catalog and a page
per app with the packages of PACKAGES_DIR (tools/site_catalog.py); the community apps found on
GitHub (tools/site_community.py); and the downloads made from the
repo, such as the Gamebook story pack and the Zork pack of Text adventures, and an OPML file per
topic of the RSS app's feed list (site/rss/catalog.json): rss/<topic>.opml and rss/all.opml.

  python -I tools/build_site.py [OUT_DIR [PACKAGES_DIR]]
                                    (defaults: dist/site, and the newest release/vX.Y.Z folder)
  python -m http.server 8765 --directory dist/site (to look at it)

The GitHub workflow .github/workflows/pages.yml runs this with the latest release's packages and
publishes OUT_DIR.
"""
import glob, hashlib, html, json, os, re, shutil, sys, zipfile
from xml.sax.saxutils import quoteattr, escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import site_catalog  # noqa: E402
import site_community  # noqa: E402
SITE = os.path.join(ROOT, 'site')
# the story pack: stories that are not built into the app
STORIES = os.path.join(ROOT, 'apps', 'gamebook', 'stories')

PACK_README = """Gamebook story pack
====================

Choose-your-own-adventure stories for the Gamebook app on the Xteink X4 Pro
(https://github.com/omer-faruq-xteink/touch-licorice-apps), more than the ones it has built in.

Copy the .story files into AppFiles/gamebook/ on the reader's SD card (USB mode), then
open Gamebook: they come first in its list.

The stories are original works by omer-faruq, licensed CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/): share and adapt them freely,
naming the author.
"""


def story_pack(out):
    """apps/gamebook/stories/*.story -> the zip, with a README"""
    names = sorted(n for n in os.listdir(STORIES) if n.endswith('.story'))
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('README.txt', PACK_README)
        for n in names:
            z.write(os.path.join(STORIES, n), n)
    return names


ZORK = os.path.join(ROOT, 'apps', 'textadv', 'games')
ZORK_README = """Zork I, II and III for the Text adventures app
================================================

The Infocom classics, released by Microsoft under the MIT licence in 2025 (see LICENSE-Zork.txt;
"Zork" is a trademark of its owners). Copy the .z3 files into AppFiles/textadv/ on the reader's
SD card (USB mode), then open Text adventures: they are listed there.

More games: any Z-machine story file (.z3, .z5, .z8) works, for example from the IF Archive
(https://ifarchive.org/indexes/if-archive/games/zcode/) or IFDB (https://ifdb.org).
"""


def zork_pack(out):
    """apps/textadv/games/ -> the zip, with a README"""
    names = sorted(n for n in os.listdir(ZORK) if n.endswith('.z3') or n.startswith('LICENSE'))
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('README.txt', ZORK_README)
        for n in names:
            z.write(os.path.join(ZORK, n), n)
    return [n for n in names if n.endswith('.z3')]


def opml(title, groups):
    """groups: [(folder or None, feeds)] -> OPML 2.0 text"""
    out = ['<?xml version="1.0" encoding="UTF-8"?>', '<opml version="2.0">', '  <head>',
           f'    <title>{escape(title)}</title>', '  </head>', '  <body>']
    for folder, feeds in groups:
        ind = '      ' if folder else '    '
        if folder:
            out.append(f'    <outline text={quoteattr(folder)} title={quoteattr(folder)}>')
        for f in feeds:
            out.append(f'{ind}<outline type="rss" text={quoteattr(f["title"])} title={quoteattr(f["title"])} xmlUrl={quoteattr(f["url"])}/>')
        if folder:
            out.append('    </outline>')
    out += ['  </body>', '</opml>', '']
    return '\n'.join(out)


def feed_lists(out_dir):
    """site/rss/catalog.json -> rss/<topic>.opml for each topic, and rss/all.opml with a folder per topic"""
    cats = json.load(open(os.path.join(SITE, 'rss', 'catalog.json'), encoding='utf-8'))['categories']
    for c in cats:
        slug = re.sub(r'[^a-z0-9]+', '-', c['name'].lower()).strip('-')
        open(os.path.join(out_dir, f'{slug}.opml'), 'w', encoding='utf-8', newline='\n').write(opml(c['name'], [(None, c['feeds'])]))
    open(os.path.join(out_dir, 'all.opml'), 'w', encoding='utf-8', newline='\n').write(
        opml('Feed list', [(c['name'], c['feeds']) for c in cats]))
    return len(cats)


def stamp_assets(out):
    """add ?v=<version of assets/> to every address of a file in assets/, in the pages and scripts:
    GitHub Pages lets browsers keep files 10 minutes, and a new page with an old stylesheet looks broken"""
    adir = os.path.join(out, 'assets')
    names = sorted(os.listdir(adir))
    h = hashlib.sha256()
    for n in names:
        h.update(n.encode() + open(os.path.join(adir, n), 'rb').read())
    v = h.hexdigest()[:10]
    pat = re.compile(r"""(?<=[/'"])(""" + '|'.join(re.escape(n) for n in names) + r""")(?=['"])""")
    for path in glob.glob(os.path.join(out, '**', '*.*'), recursive=True):
        if path.endswith(('.html', '.js')):
            s = open(path, encoding='utf-8').read()
            t = pat.sub(lambda m: f'{m.group(1)}?v={v}', s)
            if t != s:
                open(path, 'w', encoding='utf-8', newline='\n').write(t)
    return v


# Cloudflare Web Analytics (no cookies): page views, put into every page as it is built
BEACON = ("<!-- Cloudflare Web Analytics --><script type='module' src='https://static.cloudflareinsights.com/beacon.min.js' "
          "data-cf-beacon='{\"token\": \"3dfe5ef58dd642deb0588cb81fc6f979\"}'></script><!-- End Cloudflare Web Analytics -->")


def add_icons(out):
    """the site's icon (site/favicon.svg, PNGs for older browsers and phones) in the <head> of every
    page, by a path relative to the page; the count of pages"""
    n = 0
    for path in glob.glob(os.path.join(out, '**', '*.html'), recursive=True):
        s = open(path, encoding='utf-8').read()
        if 'rel="icon"' in s or '</head>' not in s:
            continue
        up = os.path.relpath(out, os.path.dirname(path)).replace(os.sep, '/')
        up = '' if up == '.' else up + '/'
        links = (f'<link rel="icon" href="{up}favicon.svg" type="image/svg+xml">\n'
                 f'<link rel="icon" href="{up}icon-32.png" sizes="32x32" type="image/png">\n'
                 f'<link rel="apple-touch-icon" href="{up}apple-touch-icon.png">\n')
        i = s.index('</head>')
        open(path, 'w', encoding='utf-8', newline='\n').write(s[:i] + links + s[i:])
        n += 1
    return n


SITE_NAME = 'Touch Licorice apps'
# what a page's title gets when it does not name the reader (search results show the title alone)
TITLE_TAIL = ' · Touch Licorice apps for the Xteink X4 Pro'
# tags a page may carry already; add_seo writes them all again
OLD_TAGS = re.compile(r'^<meta (?:property="og:|name="twitter:)[^>]*>\n|^<link rel="canonical"[^>]*>\n', re.M)


def add_seo(out):
    """in the <head> of every page search engines may list (not noindex): the full address
    (canonical), and what Facebook, X, LinkedIn, WhatsApp, Slack or Discord show when it is shared
    (Open Graph, X card): its title, description and picture, site/social/<app>.png for an app's
    page (tools/make_social.py), else social/home.png. A title that does not name the reader gets
    TITLE_TAIL. The home page also gets its schema.org WebSite. The count of pages."""
    n = 0
    for path in glob.glob(os.path.join(out, '**', '*.html'), recursive=True):
        s = open(path, encoding='utf-8').read()
        if 'noindex' in s or '</head>' not in s:
            continue
        rel = os.path.relpath(path, out).replace(os.sep, '/')
        url = site_catalog.SITE_URL + (rel[:-len('index.html')] if rel.endswith('index.html') else rel)
        m = re.search(r'<title>([^<]*)</title>', s)
        title = html.unescape(m.group(1)) if m else SITE_NAME
        if 'Xteink' not in title:
            title += TITLE_TAIL
            if m:
                s = s[:m.start()] + f'<title>{html.escape(title, quote=False)}</title>' + s[m.end():]
        d = re.search(r'<meta name="description" content="([^"]*)">', s)
        desc = html.unescape(d.group(1)) if d else 'Free InkApps for the Xteink X4 Pro.'
        app = re.fullmatch(r'apps/([^/]+)/index\.html', rel)
        card = f'social/{app.group(1)}.png' if app else 'social/home.png'
        if not os.path.exists(os.path.join(out, card)):
            card = 'social/home.png'
        img = site_catalog.SITE_URL + card
        alt = (f'{title.split(":")[0]} on the Xteink X4 Pro' if app else 'Touch Licorice apps for the Xteink X4 Pro')
        a = lambda v: html.escape(v, quote=True)
        tags = [f'<link rel="canonical" href="{a(url)}">',
                '<meta property="og:type" content="website">',
                f'<meta property="og:site_name" content="{SITE_NAME}">',
                '<meta property="og:locale" content="en_US">',
                f'<meta property="og:title" content="{a(title)}">',
                f'<meta property="og:description" content="{a(desc)}">',
                f'<meta property="og:url" content="{a(url)}">',
                f'<meta property="og:image" content="{a(img)}">',
                '<meta property="og:image:type" content="image/png">',
                '<meta property="og:image:width" content="1200">',
                '<meta property="og:image:height" content="630">',
                f'<meta property="og:image:alt" content="{a(alt)}">',
                '<meta name="twitter:card" content="summary_large_image">',
                f'<meta name="twitter:title" content="{a(title)}">',
                f'<meta name="twitter:description" content="{a(desc)}">',
                f'<meta name="twitter:image" content="{a(img)}">',
                f'<meta name="twitter:image:alt" content="{a(alt)}">']
        if rel == 'index.html':
            site = {'@context': 'https://schema.org', '@type': 'WebSite', 'name': SITE_NAME, 'url': url,
                    'description': desc, 'inLanguage': 'en'}
            tags.append(f'<script type="application/ld+json">{json.dumps(site, ensure_ascii=False)}</script>')
        s = OLD_TAGS.sub('', s)
        i = s.index('</head>')
        open(path, 'w', encoding='utf-8', newline='\n').write(s[:i] + '\n'.join(tags) + '\n' + s[i:])
        n += 1
    return n


def add_analytics(out):
    """the beacon before </body> of every page; the count of pages"""
    n = 0
    for path in glob.glob(os.path.join(out, '**', '*.html'), recursive=True):
        s = open(path, encoding='utf-8').read()
        if 'cloudflareinsights.com' in s or '</body>' not in s:
            continue
        i = s.rindex('</body>')
        open(path, 'w', encoding='utf-8', newline='\n').write(s[:i] + BEACON + '\n' + s[i:])
        n += 1
    return n


# a download counted by a path of its own (site.js count()): apps/<id>/got/ for each app, got/ for
# any other file. The beacon waits for the first paint, since Cloudflare drops views with none;
# in a 1-pixel frame the text moves into the corner the frame shows, so that paint happens.
COUNTER = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>Download counted</title>
<style>
  body { font: 16px/1.6 system-ui, sans-serif; margin: 0; padding: 2rem; }
  @media (max-width: 8px) { body { padding: 0; } }
</style>
</head>
<body>
<p>This page counts downloads{what}; nothing about who downloaded is kept.</p>
<p><a href="{home}">{back}</a></p>
<script>
  (function () {
    var started = false;
    function start() {
      if (started) return;
      started = true;
      var s = document.createElement('script');
      s.type = 'module';
      s.src = 'https://static.cloudflareinsights.com/beacon.min.js';
      s.setAttribute('data-cf-beacon', '{beacon}');
      document.body.appendChild(s);
    }
    try {
      new PerformanceObserver(function (list) {
        if (list.getEntriesByName('first-contentful-paint').length) start();
      }).observe({ type: 'paint', buffered: true });
    } catch (err) { start(); }
    setTimeout(start, 3000);
  })();
</script>
</body>
</html>
"""


def counter_pages(out):
    """apps/<id>/got/ for every app page, and got/; the count of pages"""
    beacon = re.search(r"data-cf-beacon='([^']+)'", BEACON).group(1)
    pages = [(os.path.join(out, 'got'), '', '../', 'Touch Licorice apps')]
    for page in sorted(glob.glob(os.path.join(out, 'apps', '*', 'index.html'))):
        d = os.path.dirname(page)
        pages.append((os.path.join(d, 'got'), ' of ' + os.path.basename(d), '../', 'Back to the app'))
    for d, what, home, back in pages:
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, 'index.html'), 'w', encoding='utf-8', newline='\n').write(
            COUNTER.replace('{what}', what).replace('{home}', home).replace('{back}', back).replace('{beacon}', beacon))
    return len(pages)


def sitemap(out):
    """sitemap.xml for search engines (Google Search Console takes its address): every page but
    those marked noindex (the download counters); the count of pages"""
    urls = []
    for path in sorted(glob.glob(os.path.join(out, '**', '*.html'), recursive=True)):
        if 'noindex' in open(path, encoding='utf-8').read():
            continue
        rel = os.path.relpath(path, out).replace(os.sep, '/')
        urls.append(site_catalog.SITE_URL + (rel[:-len('index.html')] if rel.endswith('index.html') else rel))
    body = ''.join(f'  <url><loc>{escape(u)}</loc></url>\n' for u in urls)
    open(os.path.join(out, 'sitemap.xml'), 'w', encoding='utf-8', newline='\n').write(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + body + '</urlset>\n')
    return len(urls)


def newest_release():
    """the newest release/vX.Y.Z folder, the local stand-in for the latest release"""
    found = glob.glob(os.path.join(ROOT, 'release', 'v*'))
    key = lambda p: tuple(int(x) for x in re.findall(r'\d+', os.path.basename(p)))
    return max(found, key=key) if found else None


def main():
    out = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'dist', 'site'))
    if os.path.exists(out):
        shutil.rmtree(out)
    shutil.copytree(SITE, out, ignore=shutil.ignore_patterns('test', '__pycache__', '*.py', '*.mjs',
                                                                    'community-blocklist.txt'))
    os.makedirs(os.path.join(out, 'downloads'), exist_ok=True)
    names = story_pack(os.path.join(out, 'downloads', 'gamebook-stories.zip'))
    games = zork_pack(os.path.join(out, 'downloads', 'zork-pack.zip'))
    topics = feed_lists(os.path.join(out, 'rss'))
    packages = sys.argv[2] if len(sys.argv) > 2 else newest_release()
    apps = site_catalog.build(out, packages) if packages else 0
    # COMMUNITY_FIXTURES: sample inkapp.json files instead of GitHub's search (tests, previews)
    community = site_community.build(out, os.environ.get('COMMUNITY_FIXTURES'))
    stamp_assets(out)
    counters = counter_pages(out)
    add_icons(out)
    seo = add_seo(out)
    pages = add_analytics(out)
    mapped = sitemap(out)
    open(os.path.join(out, '.nojekyll'), 'w').close()
    print(f'{out}: site, downloads/gamebook-stories.zip ({len(names)} stories), downloads/zork-pack.zip '
          f'({len(games)} games), rss/*.opml ({topics} topics), {apps} apps from {packages}, '
          f'{community} community apps, link previews on {seo} pages, analytics on {pages} pages, {counters} download counters, sitemap of {mapped} pages')


if __name__ == '__main__':
    main()
