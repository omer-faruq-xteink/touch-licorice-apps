"""Text size in a reading app built like RSS (Instapaper, Readwise, wallabag): each app's test calls
run(globals(), '<menu label>', '<app>') near its end, with its own harness (L, g, tap, texts, key,
draw, row_y).

Checks: Settings → Text size opens a page with Small / Default / Large, Smaller / Larger and a
sample; Larger from Default saves 24 (px) and Settings shows "24 px"; with no .ttf font the page
says so; an article at 24 px is drawn with ctx.fonts:size (body 24, title 32); a size out of range
in config.txt gives Default. The app is started again with its config as it was at the end.
"""
import os
import re


def run(ns, menu_label, app):
    L = ns['L']
    tap, texts, key = ns['tap'], ns['texts'], ns['key']
    row_y = ns['row_y']
    here = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'apps', app)
    src = os.path.join(here, 'index.lua').replace(os.sep, '/')
    # ctx.fonts:size(px): a TTF of that size (named ttf<px>), or with no TTF the system font
    L.execute("""
      ttf_on, ttf_made = true, {}
      ctx.fonts.size = function(self, px)
        assert(self == ctx.fonts, 'method call expected for size')
        if not ttf_on then return ctx.fonts.medium end
        if not ttf_made[px] then
          local f = setmetatable({ name = 'ttf' .. px, px = px, line_height = px + 6 }, { __index = { measure = function(_, s) return #s * 10 end } })
          ttf_made[px] = f
        end
        return ttf_made[px]
      end
      -- a canvas that keeps each text's font name
      local fmt = { __index = function(_, k) return function(_, ...)
        if k == 'text' then local x, y, s, o = ...; fdrawn[#fdrawn + 1] = { s = s, x = x, y = y, f = (type(o) == 'table' and type(o.font) == 'table') and o.font.name or '?' } end
      end end }
      fcanvas = setmetatable({}, fmt)
      function fdraw() fdrawn = {}; on_draw(ctx, fcanvas); return fdrawn end
    """)
    base = str(ns['g'].store['config.txt'])

    def with_size(cfg, v):
        return re.sub(r'size=[^\r\n]*', 'size=' + v, cfg) if 'size=' in cfg else cfg + '\nsize=' + v

    def restart(cfg):
        L.globals().store['config.txt'] = cfg
        L.execute(f"dofile([[{src}]])")
        g = L.globals()
        g.pending = L.table()
        g.on_load(g.ctx)
        g.flush()
        ns['g'] = g
        return g

    def recs():
        return {str(v.s): (int(v.x), int(v.y)) for v in L.globals().fdraw().values()}

    def fonts():
        return {str(v.f) for v in L.globals().fdraw().values()}

    def tap_label(label):
        r = recs()
        assert label in r, (label, list(r))
        x, y = r[label]
        tap(x + 5, y + 5)

    def open_settings():
        for _ in range(4):
            key('back')
        tap_label('Settings')

    def open_size_page():
        open_settings()
        r = recs()
        label = next(k for k in r if k.startswith('Text size'))
        x, y = r[label]
        tap(x + 5, y + 30)                                   # the field under the label

    def open_article():
        tap_label(menu_label)
        ns['g'].flush()
        tap(100, row_y(0))
        ns['g'].flush()

    g = restart(with_size(base, 'default'))
    open_article()
    assert not any(f.startswith('ttf') for f in fonts()), fonts()   # Default: the system fonts

    open_size_page()
    t = texts()
    for label in ('Text size', 'Small', 'Default', 'Large', 'Smaller', 'Larger'):
        assert label in t, (label, t)
    assert any('sample' in x.lower() for x in t), t
    tap_label('Larger')
    cfg = str(ns['g'].store['config.txt'])
    assert 'size=24' in cfg and 'size=default' not in cfg, cfg
    assert '24 px' in texts() and 'ttf32' in fonts(), (texts(), fonts())   # the sample's title
    tap_label('Smaller'); tap_label('Smaller')
    assert 'size=20' in str(ns['g'].store['config.txt'])
    tap_label('Large')
    assert 'size=large' in str(ns['g'].store['config.txt'])
    tap_label('Larger')                                      # from Large: 28 + 2
    assert 'size=30' in str(ns['g'].store['config.txt'])
    L.globals().ttf_on = False
    assert any('No .ttf font' in x for x in texts()), texts()
    L.globals().ttf_on = True
    key('back')                                              # Back: Settings, showing the size
    assert any(x.startswith('30 px') for x in texts()), texts()

    g = restart(with_size(base, '24'))
    open_article()
    f = fonts()
    assert {'ttf24', 'ttf32'} <= f, f                        # the body and the title

    for bad in ('99', '8', 'huge'):
        g = restart(with_size(base, bad))
        open_settings()
        assert any(x.startswith('default') for x in texts()), (bad, texts())

    restart(base)
