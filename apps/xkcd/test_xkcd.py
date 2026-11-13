"""Offline test of xkcd (gamekit harness, a stand-in network answering like xkcd.com, imgs.xkcd.com and
images.weserv.nl, and a stand-in image decoder): the latest comic, Prev / Next, the screen turned for
wide comics, the alt text, big pictures through the resizer, interactive comics, the last 20 kept,
offline reading, and the draw-command count.

  python -I apps/xkcd/test_xkcd.py
"""
import json, os, struct, sys, urllib.parse, zlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

LATEST = 30
requests, pending, ranges = [], [], []
mode = {'online': True}


def png(w, h, size=2000):
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 0, 0, 0, 0)
    chunk = struct.pack('>I', len(ihdr)) + b'IHDR' + ihdr + struct.pack('>I', zlib.crc32(b'IHDR' + ihdr) & 0xffffffff)
    b = b'\x89PNG\r\n\x1a\n' + chunk
    return (b + b'\x00' * max(0, size - len(b))).decode('latin-1')


def comic(n):
    d = {'num': n, 'title': f'Comic {n}', 'safe_title': f'Comic {n}', 'img': f'https://imgs.xkcd.com/comics/c{n}.png',
         'alt': f'The alt text of comic {n}.' + (' It goes on and on.' * 30 if n == 24 else ''),
         'year': '2026', 'month': '11', 'day': str(n % 28 + 1)}
    if n == 27:
        d['extra_parts'] = {'headerextra': '<script>'}
    return d


def image(n):
    if n == 25:
        return png(1500, 500)                    # too wide for the reader
    if n == 26:
        return png(740, 300, 300000)            # too many bytes for a saved file
    return png(740, 300) if n % 2 == 0 else png(400, 900)


def answer(opts):
    url = str(opts['url'])
    u = urllib.parse.urlsplit(url)
    if not mode['online']:
        return {'ok': False, 'err': 'network_unavailable'}
    if u.netloc == 'xkcd.com':
        n = LATEST if u.path == '/info.0.json' else int(u.path.split('/')[1])
        if n < 1 or n > LATEST or n == 404:
            return {'ok': True, 'status': 404, 'body': 'not found'}
        return {'ok': True, 'status': 200, 'body': json.dumps(comic(n))}
    if u.netloc == 'imgs.xkcd.com':
        body = image(int(u.path.split('/c')[-1].split('.')[0]))
        hd = opts['headers']
        if hd is not None and hd['Range'] is not None:              # the first bytes only (the size)
            assert str(hd['Range']) == 'bytes=0-63', hd['Range']
            ranges.append(url)
            return {'ok': True, 'status': 206, 'body': body[:64]}
    elif u.netloc == 'images.weserv.nl':
        q = dict(urllib.parse.parse_qsl(u.query))
        assert q['fit'] == 'inside' and q['output'] == 'png' and q['filt'] == 'greyscale' and q['con'] == '100', q
        src = image(int(q['url'].split('/c')[-1].split('.')[0]))
        sw, sh = struct.unpack('>II', src[16:24].encode('latin-1'))
        s = min(int(q['w']) / sw, int(q['h']) / sh)                    # fit inside the box (it may enlarge)
        body = png(int(sw * s), int(sh * s))
    else:
        raise AssertionError(url)
    save = opts['save']
    if save is not None:
        assert str(save['to']) == 'storage', save
        if len(body) > 262144:
            return {'ok': True, 'status': 200, 'saved': False, 'err': 'limit_exceeded', 'body': ''}
        g.store[str(save['name'])] = body
        return {'ok': True, 'status': 200, 'saved': True, 'body': ''}
    return {'ok': True, 'status': 200, 'body': body[:131072]}


STUBS = r"""
images, released = {}, 0
rawset(gg, 'image', function(self, img, x, y, o) commands = commands + 1; images[#images + 1] = { img = img, x = x, y = y, o = o } end)
ctx.capabilities = { image_decode = true }
ctx.storage.remove = function(self, n) store[n] = nil; return true end
ctx.screen = { width = 480, height = 800 }
function ctx.screen.set_orientation(self, o)
  if o == 'landscape' then self.width, self.height = 800, 480 else self.width, self.height = 480, 800 end
  return true
end
ctx.clock.now = function(self) return { epoch_sec = 1793070000, valid = true, year = 2026, month = 11, day = 13, hour = 3, minute = 0, second = 0 } end
ctx.json = { decode = function(self, s) return JSON_DECODE(s) end }
ctx.image = { decode = function(self, b, o)
  local w, h
  if b:sub(1, 4) == '\137PNG' then w, h = string.unpack('>I4I4', b, 17)
  else w, h = b:match('W=(%d+);H=(%d+);'); w, h = tonumber(w), tonumber(h) end
  if not w then return nil, 'invalid_argument' end
  if w > 1024 or h > 1024 then return nil, 'limit_exceeded' end
  local s = 1
  if o and o.max_w then s = math.min(1, o.max_w / w, o.max_h / h) end
  return { width = math.floor(w * s), height = math.floor(h * s), release = function() released = released + 1 end }
end }
"""


def setup(game):
    L = game.L

    def to_lua(v):
        if isinstance(v, dict):
            return L.table_from({k: to_lua(x) for k, x in v.items()})
        if isinstance(v, list):
            return L.table_from([to_lua(x) for x in v])
        return v

    def request(self, opts, fn):
        requests.append((str(opts['url']), str(opts['save']['name']) if opts['save'] is not None else None))
        pending.append((fn, opts))
        return L.table_from({'cancel': lambda self: None})

    L.globals().JSON_DECODE = lambda s: to_lua(json.loads(s))
    L.globals().ctx.net = L.table_from({'request': request, 'keep_wifi': lambda self, ms: None})
    game.to_lua = to_lua


def answer_all(limit=20):
    n = 0
    while pending and n < limit:
        fn, opts = pending.pop(0)
        fn(g.L.globals().ctx, g.to_lua(answer(opts)))
        n += 1
    return n


g = Game(HERE, stubs=STUBS, encoding='latin-1', before_load=setup)
L = g.L
api = lambda: g.api
width = lambda: int(L.globals().ctx.screen.width)
texts = lambda: [str(t) for t in g.texts()]
back = L.eval("function() return on_input(ctx, { type = 'key', key = 'back', phase = 'up' }) end")

# the latest comic: its JSON, then its picture saved to a file; a wide one turns the screen
assert requests[-1] == ('https://xkcd.com/info.0.json', None), requests
answer_all()
# then the picture's first 64 bytes (its size and shape: a wide one turns the screen), then the
# picture made by the resizer for exactly the space it gets (800 x 316 here), greyscale at full contrast
assert ranges == ['https://imgs.xkcd.com/comics/c30.png'] and requests[1] == ('https://imgs.xkcd.com/comics/c30.png', None), requests
q = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(requests[2][0]).query))
assert requests[2][1] == 'c_30.png' and q['url'] == 'https://imgs.xkcd.com/comics/c30.png' and (q['w'], q['h']) == ('800', '316'), requests[2]
assert width() == 800, 'a wide comic: landscape'
t = texts()
assert '30: Comic 30' in t and 'Alt' in t and 'Prev' in t and 'Next' in t, t
assert len(L.globals().images) >= 1, 'the comic is drawn'
im = L.globals().images[1]
assert im.o is None and abs(int(im.img.width) - 779) <= 1 and abs(int(im.img.height) - 316) <= 1, 'drawn as made, no scaling on the reader'
assert int(im.y) + int(im.img.height) <= 480 - 68 - 26, int(im.y)
assert g.commands() < 1024
assert 'last=30' in g.store['settings.txt']
# the latest comic is also kept for the sleep screen, made for its size (the store's build cannot fetch there)
lockq = [dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(u).query)) for u, f in requests if f == 'lock.png']
assert lockq and (lockq[0]['w'], lockq[0]['h']) == ('464', '600'), lockq             # at most twice its own 300 px height
assert g.store['lock.txt'].startswith('png\t30\tComic 30\t') and g.store['lock.png'] is not None, g.store['lock.txt']
# Prev: a tall one turns the screen back; its alt text under it
g.tap_label('Prev'); answer_all()
assert width() == 480 and '29: Comic 29' in texts() and any('The alt text of comic 29.' in s for s in texts()), texts()
assert g.commands() < 1024
g.tap_label('Next'); answer_all()
n = len(requests)
g.tap_label('Next')
assert len(requests) == n and 'This is the latest.' in texts(), texts()
# down to 24 (a long alt text: the whole of it on the Alt page, below)
for _k in range(6):
    g.tap_label('Prev'); answer_all()
assert '24: Comic 24' in texts() and width() == 800
# 27 interactive: no picture asked, its address as a QR code
for _k in range(3):
    g.tap_label('Next'); answer_all()
assert '27: Comic 27' in texts() and not requests[-1][0].endswith('c27.png'), requests[-1]
assert any('interactive' in s.lower() for s in texts()), texts()
# 26 (its original 300 KB) and 25 (1500 px, more than the reader decodes): made small by the resizer
# like every other; 25 lost detail (over 1024 px): "(reduced)", the full size by QR code on its Alt page
g.tap_label('Prev'); answer_all()
assert '26: Comic 26' in texts() and not any('(reduced)' in s for s in texts()), texts()
g.tap_label('Prev'); answer_all()
assert '25: Comic 25' in texts() and any('(reduced)' in s for s in texts()) and g.store['c_25.png'] is not None, texts()
# the last 20 kept: down to 5, then 30's picture is gone
for _k in range(20):
    g.tap_label('Prev'); answer_all()
assert '5: Comic 5' in texts()
cache = g.store['cache.txt'].split('\n')
assert len(cache) == 20 and cache[0].startswith('png:400x900	5	'), cache[:2]     # with the original's size
assert g.store['c_5.png'] is not None and g.store['c_30.png'] is None, 'older pictures removed'
assert back() is False, 'Back on a comic: the host asks to leave'

# offline: the last comic seen opens; a saved one opens, one not saved says so
mode['online'] = False
g.restart(); answer_all()
assert '5: Comic 5' in texts(), texts()
g.tap_label('Next'); answer_all()
assert '6: Comic 6' in texts(), texts()
g.tap_label('Prev'); g.tap_label('Prev'); answer_all()
assert 'Not saved on the reader: needs Wi-Fi.' in texts() and '5: Comic 5' in texts(), texts()

# nothing saved, offline: a screen saying so, Reload once Wi-Fi is back
for k in [k for k in g.store.keys()]:
    g.store[k] = None
g.restart(); answer_all()
assert any('needs Wi-Fi' in s for s in texts()) and 'Reload' in texts(), texts()
mode['online'] = True
g.tap_label('Reload'); answer_all()
assert '30: Comic 30' in texts(), texts()
typed = lambda s: L.eval('inputs[#inputs]')(L.globals().ctx, s)
drag = L.eval("function(x0, y0, x1, y1) on_input(ctx, {type='pointer', phase='down', x=x0, y=y0}); "
              "on_input(ctx, {type='pointer', phase='up', x=x1, y=y1}) end")
last_image = lambda: L.globals().images[len(L.globals().images)]
L.execute("lock_calls, lock_on = {}, false; ctx.lockscreen = { is_default = function(self) return lock_on end, "
          "set_default = function(self) lock_calls[#lock_calls + 1] = 'set'; lock_on = true end, "
          "clear_default = function(self) lock_calls[#lock_calls + 1] = 'clear'; lock_on = false end }")
t = texts()
assert all(b in t for b in ('Prev', 'Random', 'Alt', 'More', 'Next')), t

# zoom: twice what is shown (or the original, when larger), at most 1024 px a side, made by the
# resizer; even a comic that fits (30: 740 x 300 shown at 779 x 316) gets twice as large
g.tap(400, 250)
zq = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(requests[-1][0]).query))
near = lambda a, b: abs(int(a) - b) <= 1
assert requests[-1][1] == 'zoom.png' and near(zq['w'], 1024) and near(zq['h'], 415), requests[-1]
answer_all()
assert api().zoom() is not None and int(api().zoom().img.width) > 1000, 'larger than the 779 px shown'
g.tap(400, 250)
assert api().zoom() is None
# 29 (400 x 900, shown at 268 x 604): twice that is 536 x 1208, more than the original, so that,
# within 1024: 454 x 1024; a part of it shown, a drag moves it, another tap fits it again
g.tap_label('Prev'); answer_all()
assert width() == 480 and int(api().cur().img.height) < 900
g.tap(240, 300)
zq = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(requests[-1][0]).query))
assert requests[-1][1] == 'zoom.png' and near(zq['w'], 454) and near(zq['h'], 1024), (requests[-1], int(api().cur().img.width), int(api().cur().img.height))
answer_all()
z = api().zoom()
assert z is not None and int(z.img.height) > 1000, 'larger than the original 900 px'
g.draw()
o = last_image().o
assert o is not None and o.src is not None and int(o.src.w) <= 480, 'a part of the full picture'
sy = int(z.sy)
drag(240, 400, 240, 300)                                   # up by 100: further down the comic
assert int(api().zoom().sy) == min(sy + 100, int(api().zoom().fh) - int(api().zoom().vh)), (sy, int(api().zoom().sy))
drag(240, 300, 240, 2000)                                  # far down: clamped at the top
assert int(api().zoom().sy) == 0
g.tap(240, 300)
assert api().zoom() is None
assert g.commands() < 1024

# Random: a number in 1..30, never 404 (math.random fixed here)
L.execute('math.random = function() return 0.5 end')
g.tap_label('Random')
assert requests[-1] == ('https://xkcd.com/16/info.0.json', None), requests[-1]
answer_all()
assert '16: Comic 16' in texts()

# Go to #: a number; not a comic: a message and no request
def goto(s):
    g.tap_label('More'); g.tap_label('Go to #'); typed(s)
goto('7'); answer_all()
assert '7: Comic 7' in texts(), texts()
# a message (here: not a number) has its own row above the buttons: it never covers the alt text
goto('x')
d = {str(r.s): int(r.y) for r in g.draw()}
alt_bottom = max(int(r.y) + 22 for r in g.draw() if 'alt text of comic 7' in str(r.s) or str(r.s).startswith('It goes'))
assert d['Type a comic number.'] >= alt_bottom, (d['Type a comic number.'], alt_bottom)
for s, msg in (('0', 'No comic 0.'), ('31', 'No comic 31.'), ('404', 'No comic 404.'), ('x', 'Type a comic number.')):
    n = len(requests)
    goto(s)
    assert len(requests) == n and msg in texts(), (s, texts())
g.tap_label('More'); g.tap_label('Latest'); answer_all()
assert '30: Comic 30' in texts()

# favourites: the star at the top right adds and removes; the list opens one
goto('7'); answer_all()
def tap_star():                                            # where the star is now (it moves when the screen turns)
    r = L.eval('function() return __TEST.api.star_rect() end')()
    g.tap(int(r.x) + 5, int(r.y) + 5)
tap_star()
assert g.store['favourites.txt'] == '7\tComic 7' and api().is_fav(7)
tap_star()
assert (g.store['favourites.txt'] or '') == '' and not api().is_fav(7)
tap_star()
goto('16'); answer_all()
tap_star()
g.tap_label('More'); g.tap_label('Favourites')
t = texts()
assert '7: Comic 7' in t and '16: Comic 16' in t and 'Back' in t, t
g.tap_label('7: Comic 7'); answer_all()
assert api().screen() == 'comic' and '7: Comic 7' in texts()

# the alt text in full (24's is long)
goto('24'); answer_all()
g.tap_label('Alt')
t = texts()
assert api().screen() == 'alt' and 'Close' in t and any('It goes on and on.' in s for s in t), t
assert back() is True and api().screen() == 'comic'

# Settings: the credit, the sleep screen (Off / every 3 / 6 / 12 hours)
goto('7'); answer_all()                                         # a tall comic: portrait, 480 px, as in Studio
assert width() == 480
g.tap_label('More'); g.tap_label('Settings')
t = texts()
assert 'xkcd by Randall Munroe · xkcd.com · CC BY-NC 2.5'.encode().decode('latin-1') in ' '.join(t) and 'Sleep screen: off' in t, t
wide = [str(r.s) for r in g.draw() if int(r.x) + 10 * len(str(r.s).encode('latin-1').decode('utf-8')) > width() - 12]
assert not wide, f'past the screen edge (Studio cut the credit off): {wide}'
g.tap_label('Sleep screen: off'); g.tap_label('Every 6 hours')
assert list(L.eval('lock_calls').values()) == ['set'] and 'lockevery=6' in g.store['settings.txt'] and 'Sleep screen: every 6 hours' in texts()
g.tap_label('Sleep screen: every 6 hours'); g.tap_label('Every 12 hours')
assert 'lockevery=12' in g.store['settings.txt'] and 'Sleep screen: every 12 hours' in texts()
g.tap_label('Sleep screen: every 12 hours'); g.tap_label('Off')
assert list(L.eval('lock_calls').values())[-1] == 'clear' and 'Sleep screen: off' in texts()
assert back() is True and api().screen() == 'comic'
assert back() is False
# a comic saved by 1.0.0 before the resizer (its own picture, no size in cache.txt) is fetched again
old = 'png' + chr(9) + '7' + chr(9) + 'Comic 7' + chr(9) + 'Old alt.' + chr(9) + 'https://imgs.xkcd.com/comics/c7.png' + chr(9) + '2026-11-08' + chr(9) + '0'
g.store['cache.txt'] = old
g.store['c_7.png'] = png(400, 900)
n = len(requests)
goto('7')
assert len(requests) > n and requests[n] == ('https://xkcd.com/7/info.0.json', None), requests[n:]
answer_all()
assert g.store['cache.txt'].startswith('png:400x900' + chr(9) + '7' + chr(9)), g.store['cache.txt'][:40]
# a host without picture decoding (Studio's preview): the app says so in plain words instead of an
# error. Not in the manifest's requires: there the preview would not open the app at all
man = json.load(open(os.path.join(HERE, 'manifest.json'), encoding='utf-8'))
assert 'image_decode' not in man['requires'], man['requires']
L.execute('saved_image = ctx.image; ctx.image = nil')
goto('9'); answer_all()
t = ' '.join(texts())
assert '9: Comic 9' in t and 'cannot show pictures' in t and 'attempt to' not in t, t
goto('7'); answer_all()                                         # saved before (above): shown from the saved copy
t = ' '.join(texts())
assert '7: Comic 7' in t and 'cannot show pictures' in t and 'attempt to' not in t, t
L.execute('ctx.image = saved_image')
g.no_err()
print('xkcd tests passed')
