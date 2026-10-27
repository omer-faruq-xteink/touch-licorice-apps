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
# an app built from several sources (apps/merchant) bundles them into its index.lua first
for app in apps:
    if os.path.isfile(os.path.join(app, 'bundle.py')):
        subprocess.run([sys.executable, '-I', os.path.join(app, 'bundle.py')], check=True)
apps += [os.path.join(HERE, 'tools', 'netprobe'), os.path.join(HERE, 'tools', 'probe')]
lua_files = []
for app in apps:
    for root, _, fns in os.walk(app):
        lua_files += [os.path.join(root, fn) for fn in fns if fn.endswith('.lua')]
subprocess.run([sys.executable, '-I', os.path.join(HERE, 'tools', 'lualint55.py'), *lua_files], check=True)
# and through a real Lua 5.5 compiler when lupa has one (lupa >= 2.5): the lint missed an
# assignment to a for-loop variable on the loop's own line, and TBR Planner closed on start
try:
    from lupa import lua55
except ImportError:
    print('lua55: not checked (pip install -U lupa)')
else:
    check = lua55.LuaRuntime().eval('function(s, n) local f, e = load(s, n); return e end')
    errors = [e for e in (check(open(f, encoding='utf-8').read(), '@' + os.path.relpath(f, HERE)) for f in lua_files) if e]
    for e in errors: print(e)
    if errors: sys.exit('Lua 5.5 rejects the files above')
    print(f'lua55: {len(lua_files)} files compile')
for app in apps:
    if os.path.isfile(os.path.join(app, 'manifest.json')):
        print(f'== {os.path.basename(app)}')
        xtpack.pack(app, os.path.join(dist, os.path.basename(app) + '.xtapp'), a.image)
print('\nrelease assets:', ', '.join(sorted(os.listdir(dist))))
