"""Export apps as XTApp Studio project backups, for the Xteink store at https://xtapp-ai.xteink.cc:
Studio → More (...) → Import backup restores one as a new project, which is then saved to the
cloud and submitted from the Developer Center. The archive is Studio's own backup format
("xtapp-studio-project-archive" v1, read from Studio's code on 2026-10-29):

    xtapp-studio/project.json  name, device, manifest, asset list, source list
    project-files/<path>       manifest.json, index.lua and every other .lua of the app
                               (not src/: bundle.py builds index.lua)
    project-files/data/<name>  the app's data files, listed in the manifest's data_files
                               (read with ctx.package)
    assets/xic/icon.xic        the icon drawn again at 88x88 (the store's icon tile), 1 bpp
    assets/raw/icon.png        the same as PNG
    presentation/store_icon.png  the icon at 512x512 for the store listing and the project card
    assets/xic/<key>.xic, assets/raw/<key>.png   more packaged images (ctx.package:image), from
                               an app's store_assets.py: assets(app_dir) -> {key: 1-bit image};
                               its DROP_DATA names data files the store build leaves out

  python -I tools/store_export.py APP [APP ...]      ->  dist/store/<app>/<app>.zip

Each app has its own folder, which also gets <app>-store-icon-512.png for the publish form (the
cover and screenshots for the listing go there too).

store/apps.json records what is in the store (tools/store_status.py turns it into
store/STATUS.md). Its app_id is the one the package carries; the docs say a first submission
issues "u-xxxxxxxx", but the live packages kept ours (Mahjong: "mahjong"), so an update exports
with the same app_id and installs as an upgrade.
"""
import datetime, importlib.util, io, json, os, re, sys, zipfile
from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, 'tools'))
sys.path.insert(0, HERE)
import make_icons  # noqa: E402
import xtpack  # noqa: E402

ICON_PX = 88
STORE_ICON_PX = 512
# the API version a store build declares: Studio checks every call against it (the sideloaded
# packages keep "2.0", which the X4 Pro's host runs as 2.9); 2.1 zlib, image decode; 2.4
# net:keep_wifi; 2.8 lockscreen:clear_default; 2.2 ctx.state; 2.9 ctx.files; 2.18 device:keep_awake;
# 2.21 layer:set_bits and ctx.ble (2.19)
STORE_API = {'calendar': '2.9', 'notes': '2.2', 'tasks': '2.18', 'timekeeper': '2.18', 'weather': '2.8', 'tbr': '2.8', 'hackernews': '2.18', 'wikipedia': '2.9', 'rss': '2.18', 'instapaper': '2.18', 'wallabag': '2.18', 'readwise': '2.18', 'dict': '2.9', 'anki': '2.9',
             'game2048': '2.2', 'sokoban': '2.2', 'sudoku': '2.2', 'suguru': '2.2',
             'litclock': '2.9', 'wordclock': '2.9', 'skytonight': '2.9', 'gamebook': '2.9', 'tsumego': '2.9', 'textadv': '2.9',
             'wordhive': '2.9', 'cryptogram': '2.9', 'tarot': '2.9', 'wordladder': '2.9',
             'hashi': '2.9', 'kakuro': '2.9', 'notebook': '2.9', 'pianofollow': '2.21'}
# code only the sideloaded build keeps (a lock screen fetching, which the store's API forbids):
# from a line "-- store: cut" through the next "-- store: end"
STORE_CUT = re.compile(r'^[ \t]*-- store: cut.*?^[ \t]*-- store: end[^\n]*\n', re.M | re.S)
APPS = os.path.join(HERE, 'store', 'apps.json')
# official 2.x manifest fields (Manifest JSON Schema); anything else is dropped
FIELDS = ('api', 'app_id', 'display_name', 'display_names', 'version', 'author', 'description',
          'entry', 'display', 'requires', 'permissions', 'preload_assets', 'data_files', 'lockscreen')


def icon_master(app, app_dir):
    """The app's icon in greyscale at 4x: drawn again from tools/make_icons.py when it knows the
    app (sharper than scaling the 96 px file), else icon.png."""
    if app in make_icons.ICONS:
        p = make_icons.Pen()
        make_icons.ICONS[app](p)
        return p.im
    return Image.open(os.path.join(app_dir, 'icon.png')).convert('L')


def icon_image(master):
    """The device icon: 88x88, 1 bpp."""
    small = master.resize((ICON_PX, ICON_PX), Image.LANCZOS)
    return small.point(lambda v: 0 if v < 128 else 255).convert('1')


def store_icon(master):
    """The store icon: 512x512, the drawing on white with a margin, edges kept smooth."""
    inner = int(STORE_ICON_PX * 0.82)
    img = Image.new('L', (STORE_ICON_PX, STORE_ICON_PX), 255)
    img.paste(master.resize((inner, inner), Image.LANCZOS), ((STORE_ICON_PX - inner) // 2,) * 2)
    return img


def png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, 'PNG')
    return buf.getvalue()


DATA_FORMATS = ('txt', 'tsv', 'json')
DATA_NAME = re.compile(r'^[A-Za-z0-9._-]{1,64}$')


def store_hook(app_dir):
    """The app's store_assets.py as a module, or None."""
    path = os.path.join(app_dir, 'store_assets.py')
    if not os.path.isfile(path):
        return None
    spec = importlib.util.spec_from_file_location('store_assets_' + os.path.basename(app_dir), path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def data_files(app, app_dir):
    """{name: bytes}: apps/<app>/data/ as the sideloaded packages carry it (xtpack: normalised
    files and the generated banks.tsv the games read), checked against the official packager's
    rules for names and formats."""
    out = {}
    for fn, blob in xtpack.collect_data_files(app_dir):
        ext = fn.rsplit('.', 1)[-1]
        if not DATA_NAME.match(fn) or ext not in DATA_FORMATS:
            raise SystemExit(f'{app}: data/{fn}: a data file name is [A-Za-z0-9._-], at most 64 bytes, .txt .tsv or .json')
        out[fn] = blob
    hook = store_hook(app_dir)
    for fn in getattr(hook, 'DROP_DATA', ()):
        out.pop(fn, None)
    return out


def manifest_for(app, app_dir, ids):
    src = json.load(open(os.path.join(app_dir, 'manifest.json'), encoding='utf-8'))
    m = {k: src[k] for k in FIELDS if k in src}
    m['app_id'] = ids.get(app, {}).get('app_id', src['app_id'])
    m['api'] = STORE_API.get(app, m.get('api', '2.0'))
    m['app_icon_s'] = 'icon'
    # every app here is drawn for the X4 Pro's touch screen; the X4 Classic has only keys
    m['requires'] = sorted(set(m.get('requires', [])) | {'pointer'})
    # only the official names (an unknown one refuses the install); the older host's sys.* go
    m['permissions'] = [x for x in m.get('permissions', []) if x in ('net', 'reader', 'ble')]
    if not m['permissions']:
        m.pop('permissions', None)
    lock = m.get('lockscreen')
    if lock:
        m['lockscreen'] = {k: lock[k] for k in ('entry', 'interval_sec') if k in lock}
    data = data_files(app, app_dir)
    if data:
        # each file's own size, rounded up to 4 KB, as its limit
        m['data_files'] = [{'name': n, 'format': n.rsplit('.', 1)[-1], 'max_bytes': -(-len(b) // 4096) * 4096}
                           for n, b in data.items()]
    return m


def export(app, ids, out_dir):
    app_dir = os.path.join(HERE, 'apps', app)
    if not os.path.isfile(os.path.join(app_dir, 'manifest.json')):
        raise SystemExit(f'{app}: no apps/{app}/manifest.json')
    manifest = manifest_for(app, app_dir, ids)
    data = data_files(app, app_dir)
    sources = {'manifest.json': json.dumps(manifest, indent=2, ensure_ascii=False) + '\n'}
    for root, dirs, fns in os.walk(app_dir):
        dirs[:] = [d for d in dirs if d not in ('src', 'data', '__pycache__') and not d.startswith('.')]
        for fn in fns:
            if fn.endswith('.lua'):
                path = os.path.join(root, fn)
                sources[os.path.relpath(path, app_dir).replace(os.sep, '/')] = STORE_CUT.sub('', open(path, encoding='utf-8').read())
    master = icon_master(app, app_dir)
    icon = icon_image(master)
    store_png = png_bytes(store_icon(master))
    images = {'icon': icon}
    hook = store_hook(app_dir)
    if hook and hasattr(hook, 'assets'):
        images.update(hook.assets(app_dir))
    for key in images:
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,23}', key):
            raise SystemExit(f'{app}: asset key {key!r}: [A-Za-z0-9_-], at most 23 bytes')
    asset_list = [{'key': k, 'width': im.size[0], 'height': im.size[1], 'bpp': 1, 'contentHash': '', 'process': {},
                   'xicPath': f'assets/xic/{k}.xic', 'rawPath': f'assets/raw/{k}.png',
                   'rawType': 'image/png', 'xicType': 'application/x-xic'} for k, im in images.items()]
    meta = {'format': 'xtapp-studio-project-archive', 'version': 1,
            'project': {'sourceProjectId': '', 'name': manifest['display_name'], 'device': 'x4_pro',
                        'manifest': manifest, 'assetRefs': {k: {} for k in images}, 'folders': [],
                        'presentation': {'storeCover': None,
                                         'storeIcon': {'key': 'store_icon', 'mime': 'image/png',
                                                       'width': STORE_ICON_PX, 'height': STORE_ICON_PX,
                                                       'path': 'presentation/store_icon.png'}}},
            'sourceFiles': sorted(list(sources) + ['data/' + n for n in data]), 'assets': asset_list,
            'exportedAt': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    files = {'xtapp-studio/project.json': (json.dumps(meta, indent=2, ensure_ascii=False) + '\n').encode('utf-8'),
             'presentation/store_icon.png': store_png}
    for k, im in images.items():
        files[f'assets/xic/{k}.xic'] = xtpack.build_xic_1bpp(im)
        files[f'assets/raw/{k}.png'] = png_bytes(im)
    files.update({'project-files/' + p: s.encode('utf-8') for p, s in sources.items()})
    files.update({'project-files/data/' + n: b for n, b in data.items()})
    out_dir = os.path.join(out_dir, app)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, app + '-store-icon-512.png'), 'wb') as f:
        f.write(store_png)
    zpath = os.path.join(out_dir, app + '.zip')
    with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
        for name in sorted(files):
            z.writestr(name, files[name])
    print(f'{os.path.relpath(zpath, HERE)}: ' + ', '.join(f'{n} {len(b)} B' for n, b in sorted(files.items())))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    ids = json.load(open(APPS, encoding='utf-8')) if os.path.isfile(APPS) else {}
    for a in sys.argv[1:]:
        export(a, ids, os.path.join(HERE, 'dist', 'store'))
