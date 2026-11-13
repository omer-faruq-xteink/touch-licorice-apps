"""Checks of src/xk.lua (Lua 5.4 through lupa): xkcd's addresses, its JSON as a comic, a PNG's size
from its header, fitting, the resizer's address, the saved-comic lines and Random.

  python -I apps/xkcd/test_xk.py
"""
import os, struct, sys, urllib.parse, zlib
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
sys.stdout.reconfigure(encoding='utf-8')
fails = []


def check(ok, what):
    print(('ok    ' if ok else 'FAIL  ') + what)
    if not ok:
        fails.append(what)


def png(w, h):
    """a real PNG header (signature + IHDR) and a little more"""
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 0, 0, 0, 0)
    chunk = struct.pack('>I', len(ihdr)) + b'IHDR' + ihdr + struct.pack('>I', zlib.crc32(b'IHDR' + ihdr) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk + b'\x00' * 20


L = lua54.LuaRuntime(unpack_returned_tuples=True, encoding='latin-1')
X = L.execute(open(os.path.join(HERE, 'src', 'xk.lua'), encoding='utf-8').read())

check(X.json_url(None) == 'https://xkcd.com/info.0.json' and X.json_url(614) == 'https://xkcd.com/614/info.0.json', 'the addresses')
d = L.table_from({'num': 3323, 'title': 'Meteor Fear', 'safe_title': 'Meteor Fear', 'alt': "Don't worry.",
                  'img': 'https://imgs.xkcd.com/comics/meteor_fear.png', 'year': '2026', 'month': '11', 'day': '1'})
c = X.comic(d)
check(c.num == 3323 and c.title == 'Meteor Fear' and c.date == '2026-11-01' and c.interactive is False, f'a comic: {c.num} {c.date}')
for extra, what in (({'extra_parts': L.table_from({'links': 'x'})}, 'extra_parts'), ({'img': 'https://imgs.xkcd.com/comics/a.gif'}, 'a GIF'),
                    ({'img': ''}, 'no picture')):
    dd = dict(d)
    dd.update(extra)
    check(X.comic(L.table_from(dd)).interactive is True, f'interactive: {what}')
check(X.comic(L.table_from({'num': 5})) is not None and X.comic(L.table_from({'title': 'x'})) is None, 'a number is needed')

w, h = X.png_size(png(740, 300).decode('latin-1'))
check((w, h) == (740, 300), f'a PNG header: {w} x {h}')
check(X.png_size('GIF89a' + '\0' * 30) is None, 'not a PNG: nil')
check(X.ext(png(1, 1).decode('latin-1')) == 'png' and X.ext('\xff\xd8\xff\xe0abc') == 'jpg' and X.ext('GIF89a') is None, 'the kind from the first bytes')

# the resizer: the picture at exactly the size it is shown, greyscale at full contrast (the reader's
# dithering then keeps the lines whole); never more than twice its own size
q = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(X.weserv_url('https://imgs.xkcd.com/comics/a b.png', 800, 316, 740, 300)).query))
check(q.get('url') == 'https://imgs.xkcd.com/comics/a b.png' and q.get('w') == '800' and q.get('h') == '316' and q.get('fit') == 'inside'
      and q.get('output') == 'png' and q.get('filt') == 'greyscale' and q.get('con') == '100', f'the resizer: {q}')
q = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(X.weserv_url('https://x/a.png', 800, 600, 200, 100)).query))
check(q.get('w') == '400' and q.get('h') == '200', f'at most twice as large: {q.get("w")} x {q.get("h")}')
q = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(X.weserv_url('https://x/a.png', 480, 600)).query))
check(q.get('w') == '480' and q.get('h') == '600', 'its size unknown: the box')
check(' ' not in X.weserv_url('https://imgs.xkcd.com/comics/a b.png', 480, 600), 'its address encoded')

check(tuple(X.fit(740, 300, 480, 600)) == (480, 194) and tuple(X.fit(300, 200, 480, 600)) == (300, 200)
      and tuple(X.fit(400, 1000, 480, 600)) == (240, 600), 'fitting: down only, proportional')
check(X.landscape(740, 300) is True and X.landscape(300, 740) is False and X.landscape(500, 500) is False, 'wider than tall: landscape')

odd = X.comic(L.table_from({'num': 7, 'title': 'Tab\there', 'alt': 'line one\nline two\ttab', 'img': 'https://imgs.xkcd.com/comics/x.png',
                            'year': '2006', 'month': '1', 'day': '1'}))
back = X.parse_line(X.line(odd))
check(back is not None and back.num == 7 and back.alt == 'line one line two tab' and back.title == 'Tab here' and back.date == '2006-01-01',
      f'a saved line: {back and back.alt}')
check(X.parse_line('nonsense') is None, 'a broken line: nil')

seen = set()
for k in range(2000):
    n = X.random(30 if k % 2 else 1000, k / 2000)
    seen.add(n)
check(404 not in seen and min(seen) >= 1 and max(seen) <= 1000, 'Random: 1..latest, never 404')
check(X.random(1000, 403.5 / 1000) != 404, 'not even where it would land on 404')

print('\n' + ('all passed' if not fails else f'{len(fails)} FAILED'))
sys.exit(1 if fails else 0)
