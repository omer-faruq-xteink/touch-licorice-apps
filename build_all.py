"""Build every app into dist/<app_id>.xtapp (the files to attach to a release).

  python build_all.py [--image LICORICE_APP_IMAGE]

Every Lua file is first passed through tools/lualint55.py: the device runs Lua 5.5, which rejects
at compile time what the Lua 5.4 tests let through (assignment to a for-loop variable), and such
a package only says "App error, closed" on the device.
"""
import argparse, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import xtpack  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('--image')
a = ap.parse_args()
dist = os.path.join(HERE, 'dist')
os.makedirs(dist, exist_ok=True)
apps = [os.path.join(HERE, 'apps', d) for d in sorted(os.listdir(os.path.join(HERE, 'apps')))]
apps += [os.path.join(HERE, 'tools', 'netprobe'), os.path.join(HERE, 'tools', 'probe')]
lua_files = []
for app in apps:
    for root, _, fns in os.walk(app):
        lua_files += [os.path.join(root, fn) for fn in fns if fn.endswith('.lua')]
subprocess.run([sys.executable, '-I', os.path.join(HERE, 'tools', 'lualint55.py'), *lua_files], check=True)
for app in apps:
    if os.path.isfile(os.path.join(app, 'manifest.json')):
        print(f'== {os.path.basename(app)}')
        xtpack.pack(app, os.path.join(dist, os.path.basename(app) + '.xtapp'), a.image)
print('\nrelease assets:', ', '.join(sorted(os.listdir(dist))))
