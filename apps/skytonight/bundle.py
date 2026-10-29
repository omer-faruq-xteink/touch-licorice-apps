"""Bundle Sky Tonight: index.lua = src/astro.lua + src/places.lua + src/sky.lua + src/app.lua,
lockscreen.lua = the same with src/lock.lua (each entry loads on its own).

  python -I apps/skytonight/bundle.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
HEAD = '-- built by bundle.py from src/astro.lua, src/places.lua, src/sky.lua and src/{}: edit those, not this file\n\n'


def bundle():
    common = ''.join(open(os.path.join(HERE, 'src', n), encoding='utf-8').read() + '\n' for n in ('astro.lua', 'places.lua', 'sky.lua'))
    for out, part in (('index.lua', 'app.lua'), ('lockscreen.lua', 'lock.lua')):
        text = HEAD.format(part) + common + '\n' + open(os.path.join(HERE, 'src', part), encoding='utf-8').read()
        path = os.path.join(HERE, out)
        old = open(path, encoding='utf-8').read() if os.path.exists(path) else None
        if old != text:
            open(path, 'w', encoding='utf-8', newline='\n').write(text)
        print(f'skytonight: {out} {len(text.encode())} B' + (' (updated)' if old != text else ' (unchanged)'))


if __name__ == '__main__':
    bundle()
