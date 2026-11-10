"""Link preview images for the site (what Facebook, X, LinkedIn, WhatsApp, Slack or Discord show when a
page is shared; tools/build_site.py points og:image and twitter:image at them):

    site/social/home.png      the home page and the pages that are not an app's: the site's name, a
                              line about it, the number of apps and three screens
    site/social/<app>.png     an app's page: its icon, name, category and summary (README.md's app
                              table) beside its first screenshot (site/shots/<app>-1.png)
    .github/social-preview.png  the same as home.png at 1280x640, for the repository's own
                              preview (GitHub: Settings > General > Social preview)

All 1200x630 (the size the services ask for), PNG. Run it again after adding an app, a screenshot or
a new summary; the site's build does not need Pillow or these fonts:

  python -I tools/make_social.py
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import make_icons  # noqa: E402
import site_catalog  # noqa: E402

OUT = os.path.join(ROOT, 'site', 'social')
W, H = 1200, 630
# the store pages' hero (site/assets/store.css --s-hero) and device frame (--s-device)
TOP, MID, END = (0x1f, 0x3f, 0x5e), (0x2b, 0x5d, 0x8a), (0x4f, 0x86, 0xb4)
DEVICE = (0x2a, 0x2a, 0x28)
WHITE = (255, 255, 255)
SOFT = (0xdc, 0xe7, 0xf2)
HOST = 'omer-faruq-xteink.github.io/touch-licorice-apps'
FONTS = {  # Segoe UI on Windows, DejaVu elsewhere
    'bold': ['C:/Windows/Fonts/segoeuib.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'],
    'semi': ['C:/Windows/Fonts/seguisb.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'],
    'regular': ['C:/Windows/Fonts/segoeui.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'],
}


def font(kind, px):
    for path in FONTS[kind]:
        if os.path.exists(path):
            return ImageFont.truetype(path, px)
    raise SystemExit(f'no {kind} font: install DejaVu or run on Windows')


def background():
    """the hero's diagonal gradient, drawn small and scaled up (smooth, and fast)"""
    sw, sh = 120, 63
    g = Image.new('RGB', (sw, sh))
    px = g.load()
    for y in range(sh):
        for x in range(sw):
            t = (x / sw + y / sh) / 2
            a, b, u = (TOP, MID, t / 0.55) if t < 0.55 else (MID, END, (t - 0.55) / 0.45)
            px[x, y] = tuple(round(a[i] + (b[i] - a[i]) * u) for i in range(3))
    return g.resize((W, H), Image.BICUBIC)


def device(shot, screen_h):
    """a screenshot (480x800) in the reader's dark frame, with a soft shadow; RGBA"""
    sw = round(screen_h * 480 / 800)
    pad = round(screen_h * 0.035)
    dw, dh = sw + 2 * pad, screen_h + 2 * pad
    s = 24
    img = Image.new('RGBA', (dw + 2 * s, dh + 2 * s), (0, 0, 0, 0))
    shadow = Image.new('L', img.size, 0)
    ImageDraw.Draw(shadow).rounded_rectangle((s, s + 8, s + dw, s + dh + 8), radius=pad * 2, fill=90)
    from PIL import ImageFilter
    shadow = shadow.filter(ImageFilter.GaussianBlur(12))
    img.paste((0, 0, 0, 255), (0, 0), shadow)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((s, s, s + dw, s + dh), radius=pad * 2, fill=DEVICE + (255,))
    screen = Image.open(shot).convert('RGB').resize((sw, screen_h), Image.LANCZOS)
    img.paste(screen, (s + pad, s + pad))
    return img


def wrap(d, text, f, width, lines):
    """text in at most `lines` lines of `width` px, the last one shortened with an ellipsis"""
    words, out, cur = text.split(), [], ''
    for w in words:
        t = (cur + ' ' + w).strip()
        if d.textlength(t, font=f) <= width:
            cur = t
            continue
        out.append(cur)
        cur = w
        if len(out) == lines:
            break
    else:
        out.append(cur)
        return [x for x in out if x]
    last = out[-1]
    while last and d.textlength(last + '…', font=f) > width:
        last = last[:last.rstrip().rfind(' ')] if ' ' in last else last[:-1]
    out[-1] = last.rstrip(',;:.') + '…'
    return out


def icon(app, px):
    """the app's icon on a white rounded tile, px square; RGBA"""
    if app in make_icons.ICONS:          # drawn again large: sharper than the 96 px file
        p = make_icons.Pen()
        make_icons.ICONS[app](p)
        master = p.im.convert('L')
    else:
        master = Image.open(os.path.join(ROOT, 'apps', app, 'icon.png')).convert('L')
    inner = round(px * 0.78)
    tile = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle((0, 0, px - 1, px - 1), radius=round(px * 0.22), fill=WHITE + (255,))
    art = master.resize((inner, inner), Image.LANCZOS).convert('RGB')
    tile.paste(art, ((px - inner) // 2,) * 2)
    return tile


def footer(d, x, y):
    d.text((x, y), HOST, font=font('regular', 24), fill=SOFT)


def app_card(e):
    img = background()
    d = ImageDraw.Draw(img)
    left, text_w = 72, 640
    img.paste(t := icon(e['id'], 132), (left, 72), t)
    d.text((left + 160, 84), e['category_name'].upper(), font=font('semi', 22), fill=SOFT)
    name_f = font('bold', 64 if d.textlength(e['name'], font=font('bold', 64)) <= text_w - 160 else 48)
    d.text((left + 156, 112), e['name'], font=name_f, fill=WHITE)
    body = font('regular', 32)
    y = 250
    for line in wrap(d, e['plain'], body, text_w, 5):
        d.text((left, y), line, font=body, fill=WHITE)
        y += 44
    d.text((left, 500), 'Free InkApp for the Xteink X4 Pro', font=font('semi', 28), fill=WHITE)
    footer(d, left, 540)
    if e['shots']:
        dev = device(os.path.join(ROOT, 'site', 'shots', e['shots'][0]), 540)
        img.paste(dev, (W - dev.width - 40, (H - dev.height) // 2), dev)
    return img


HOME_SHOTS = ('calendar-1.png', 'rss-1.png', 'chessplay-1.png')


def home_card(count):
    img = background()
    d = ImageDraw.Draw(img)
    left = 72
    d.text((left, 70), 'TOUCH LICORICE APPS', font=font('semi', 24), fill=SOFT)
    title = font('bold', 66)
    d.text((left, 108), 'Apps for your', font=title, fill=WHITE)
    d.text((left, 190), 'Xteink X4 Pro', font=title, fill=WHITE)
    body = font('regular', 32)
    y = 300
    for line in wrap(d, 'Games, puzzles, readers and tools made for the e-ink screen. '
                        'Free, on the stock firmware.', body, 540, 4):
        d.text((left, y), line, font=body, fill=WHITE)
        y += 44
    d.text((left, 500), f'{count} free InkApps', font=font('semi', 30), fill=WHITE)
    footer(d, left, 542)
    shots = [os.path.join(ROOT, 'site', 'shots', f) for f in HOME_SHOTS]
    back = [device(shots[0], 430), device(shots[2], 430)]
    front = device(shots[1], 500)
    img.paste(back[0], (622, 122), back[0])
    img.paste(back[1], (878, 122), back[1])
    img.paste(front, (727, (H - front.height) // 2 + 10), front)
    return img


def entries():
    """the listed apps, as tools/site_catalog.py describes them (without packages)"""
    import json
    summaries = site_catalog.readme_table()
    out = []
    for key, cat, apps in site_catalog.CATEGORIES:
        for app in apps:
            man = json.load(open(os.path.join(ROOT, 'apps', app, 'manifest.json'), encoding='utf-8'))
            name = man.get('display_name', app)
            summary = summaries.get(name, man.get('description', ''))
            out.append({'id': app, 'name': name, 'category_name': cat,
                        'plain': site_catalog.plain(summary[:1].upper() + summary[1:]),
                        'shots': site_catalog.shot_files(app)})
    return out


def save(img, path):
    img.convert('P', palette=Image.ADAPTIVE, colors=256).save(path, optimize=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    es = entries()
    home = home_card(len(es))
    save(home, os.path.join(OUT, 'home.png'))
    gh = home.resize((1280, 672), Image.LANCZOS).crop((0, 16, 1280, 656))   # 2:1, nothing cut that shows
    os.makedirs(os.path.join(ROOT, '.github'), exist_ok=True)
    save(gh, os.path.join(ROOT, '.github', 'social-preview.png'))
    for e in es:
        save(app_card(e), os.path.join(OUT, e['id'] + '.png'))
    size = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
    print(f'site/social: home.png and {len(es)} app cards, {size // 1024} KB; .github/social-preview.png')


if __name__ == '__main__':
    main()
