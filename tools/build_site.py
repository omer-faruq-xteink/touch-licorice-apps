"""Build the tools site (GitHub Pages) into OUT_DIR: site/ without its tests, plus the downloads
made from the repo, such as the Gamebook story pack, and an OPML file per topic of the RSS
app's feed list (site/rss/catalog.json): rss/<topic>.opml and rss/all.opml.

  python -I tools/build_site.py [OUT_DIR]          (default: dist/site)
  python -m http.server 8765 --directory dist/site (to look at it)

The GitHub workflow .github/workflows/pages.yml runs this and publishes OUT_DIR.
"""
import json, os, re, shutil, sys, zipfile
from xml.sax.saxutils import quoteattr, escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
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


def main():
    out = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'dist', 'site'))
    if os.path.exists(out):
        shutil.rmtree(out)
    shutil.copytree(SITE, out, ignore=shutil.ignore_patterns('test', '__pycache__', '*.py', '*.mjs'))
    os.makedirs(os.path.join(out, 'downloads'), exist_ok=True)
    names = story_pack(os.path.join(out, 'downloads', 'gamebook-stories.zip'))
    topics = feed_lists(os.path.join(out, 'rss'))
    open(os.path.join(out, '.nojekyll'), 'w').close()
    print(f'{out}: site, downloads/gamebook-stories.zip ({len(names)} stories), rss/*.opml ({topics} topics)')


if __name__ == '__main__':
    main()
