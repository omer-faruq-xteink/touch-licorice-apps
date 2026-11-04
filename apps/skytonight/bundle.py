"""Bundle Sky Tonight: index.lua = src/astro.lua + src/places.lua + src/sky.lua + src/app.lua,
lockscreen.lua = the same with src/lock.lua (each entry loads on its own).

  python -I apps/skytonight/bundle.py
  python -I apps/skytonight/bundle.py --debug OUT.xtapp

--debug packs a build that writes each step of the start and the frame, with the time and the
heap, to debug.txt (the lock screen: debug_lock.txt) in the app's folder on the card
(AppFiles/skytonight/), so a crash on someone's reader can be followed step by step.
"""
import os, shutil, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HEAD = '-- built by bundle.py from src/astro.lua, src/places.lua, src/sky.lua and src/{}: edit those, not this file\n\n'
DEBUG_OFF = 'local DEBUG = false\n'


def debug_source(text):
    assert text.count(DEBUG_OFF) == 1, 'DEBUG switch not found'
    return text.replace(DEBUG_OFF, 'local DEBUG = true\n')


def bundle():
    common = ''.join(open(os.path.join(HERE, 'src', n), encoding='utf-8').read() + '\n' for n in ('astro.lua', 'places.lua', 'sky.lua'))
    for out, part in (('index.lua', 'app.lua'), ('lockscreen.lua', 'lock.lua')):
        text = HEAD.format(part) + common + '\n' + open(os.path.join(HERE, 'src', part), encoding='utf-8').read()
        path = os.path.join(HERE, out)
        old = open(path, encoding='utf-8').read() if os.path.exists(path) else None
        if old != text:
            open(path, 'w', encoding='utf-8', newline='\n').write(text)
        print(f'skytonight: {out} {len(text.encode())} B' + (' (updated)' if old != text else ' (unchanged)'))


def debug_package(out):
    sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))
    import xtpack
    tmp = tempfile.mkdtemp()
    try:
        app = os.path.join(tmp, 'skytonight')
        shutil.copytree(HERE, app, ignore=shutil.ignore_patterns('src', '__pycache__', '*.py', '*.xtapp'))
        for fn in ('index.lua', 'lockscreen.lua'):
            p = os.path.join(app, fn)
            text = debug_source(open(p, encoding='utf-8').read())
            open(p, 'w', encoding='utf-8', newline='\n').write(text)
        xtpack.pack(app, os.path.abspath(out))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    bundle()
    if len(sys.argv) == 3 and sys.argv[1] == '--debug':
        debug_package(sys.argv[2])
