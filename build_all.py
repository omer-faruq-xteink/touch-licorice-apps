"""Build every app into dist/<app_id>.xtapp (the files to attach to a release).

  python build_all.py [--image LICORICE_APP_IMAGE]
"""
import argparse, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import xtpack  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('--image')
a = ap.parse_args()
dist = os.path.join(HERE, 'dist')
os.makedirs(dist, exist_ok=True)
apps = [os.path.join(HERE, 'apps', d) for d in sorted(os.listdir(os.path.join(HERE, 'apps')))]
apps.append(os.path.join(HERE, 'tools', 'netprobe'))
for app in apps:
    if os.path.isfile(os.path.join(app, 'manifest.json')):
        print(f'== {os.path.basename(app)}')
        xtpack.pack(app, os.path.join(dist, os.path.basename(app) + '.xtapp'), a.image)
print('\nrelease assets:', ', '.join(sorted(os.listdir(dist))))
