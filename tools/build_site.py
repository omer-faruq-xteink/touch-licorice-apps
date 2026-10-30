"""Build the tools site (GitHub Pages) into OUT_DIR: site/ without its tests, plus the downloads
made from the repo, such as the Gamebook story pack.

  python -I tools/build_site.py [OUT_DIR]          (default: dist/site)
  python -m http.server 8765 --directory dist/site (to look at it)

The GitHub workflow .github/workflows/pages.yml runs this and publishes OUT_DIR.
"""
import os, shutil, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = os.path.join(ROOT, 'site')
STORIES = os.path.join(ROOT, 'apps', 'gamebook', 'stories')

PACK_README = """Gamebook story pack
====================

Choose-your-own-adventure stories for the Gamebook app on the Xteink X4 Pro
(https://github.com/omer-faruq-xteink/touch-licorice-apps).

EN/ holds the stories in English, TR/ the ones in Turkish. Copy the .story files
(not the folder: the app does not look inside folders) into AppFiles/gamebook/ on
the reader's SD card (USB mode), then open Gamebook: they are in its list.

The stories are original works by omer-faruq, licensed CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/): share and adapt them freely,
naming the author.
"""


def story_pack(out):
    """apps/gamebook/stories/<lang>/*.story -> <LANG>/*.story in the zip, with a README"""
    names = []
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('README.txt', PACK_README)
        for lang in sorted(os.listdir(STORIES)):
            folder = os.path.join(STORIES, lang)
            if not os.path.isdir(folder):
                continue
            for n in sorted(os.listdir(folder)):
                if n.endswith('.story'):
                    z.write(os.path.join(folder, n), f'{lang.upper()}/{n}')
                    names.append(f'{lang.upper()}/{n}')
    return names


def main():
    out = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'dist', 'site'))
    if os.path.exists(out):
        shutil.rmtree(out)
    shutil.copytree(SITE, out, ignore=shutil.ignore_patterns('test', '__pycache__', '*.py', '*.mjs'))
    os.makedirs(os.path.join(out, 'downloads'), exist_ok=True)
    names = story_pack(os.path.join(out, 'downloads', 'gamebook-stories.zip'))
    open(os.path.join(out, '.nojekyll'), 'w').close()
    print(f'{out}: site and downloads/gamebook-stories.zip ({len(names)} stories)')


if __name__ == '__main__':
    main()
