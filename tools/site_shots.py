"""Screenshots for the app pages of the site: the store screenshots (dist/store/<app>/, made for the
Xteink store at 1440x2400 by tools/store_export.py's workflow) scaled to the reader's own 480x800
and saved in site/shots/, which is committed: screen captures (PNG) as small 16-grey PNGs,
<app>-<n>.png; photos of the reader (JPEG) as <app>-<n>-photo.jpg, which the app page shows
without the drawn reader around them.

  python -I tools/site_shots.py [APP ...]      (all apps with store screenshots when none given)

Run it again after new store screenshots; an app's old site shots are replaced.
"""
import glob, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORE = os.path.join(ROOT, 'dist', 'store')
OUT = os.path.join(ROOT, 'site', 'shots')
SIZE = (480, 800)


def shots(app):
    found = sorted(glob.glob(os.path.join(STORE, app, '*screenshot*')))
    if not found:
        return 0
    for old in glob.glob(os.path.join(OUT, f'{app}-*')):
        os.remove(old)
    for n, path in enumerate(found, 1):
        img = Image.open(path).convert('L')
        img = img.resize(SIZE if img.height >= img.width else SIZE[::-1], Image.LANCZOS)   # a landscape app: 800x480
        if path.lower().endswith('.jpg'):
            img.save(os.path.join(OUT, f'{app}-{n}-photo.jpg'), quality=82, optimize=True)
            continue
        img = img.quantize(16, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        img.save(os.path.join(OUT, f'{app}-{n}.png'), optimize=True)
    return len(found)


def main():
    os.makedirs(OUT, exist_ok=True)
    apps = sys.argv[1:] or sorted(os.listdir(STORE))
    total = 0
    for app in apps:
        n = shots(app)
        total += n
        if n:
            print(f'{app}: {n}')
    print(f'{total} screenshots in {OUT}')


if __name__ == '__main__':
    main()
