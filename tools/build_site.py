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
import glob, hashlib, json, os, re, shutil, sys, zipfile
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
    open(os.path.join(out, '.nojekyll'), 'w').close()
    print(f'{out}: site, downloads/gamebook-stories.zip ({len(names)} stories), downloads/zork-pack.zip '
          f'({len(games)} games), rss/*.opml ({topics} topics), {apps} apps from {packages}, '
          f'{community} community apps')


if __name__ == '__main__':
    main()
