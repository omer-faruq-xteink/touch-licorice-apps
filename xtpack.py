"""Pack a mini-app folder as an XTOS Licorice .xtapp.

  python xtpack.py APP_DIR [-o OUT] [--image LICORICE_APP_IMAGE]

APP_DIR holds manifest.json and index.lua; every *.lua under it (except under data/ and src/, the
sources an app's bundle.py turns into index.lua) goes into the
code section. If APP_DIR/data/ exists, its *.txt / *.tsv / *.csv files go into the package's DATA
section, readable on the device through ctx.data (open_text / read_text / size / exists); a
generated banks.tsv lists them ("name<TAB>line count<TAB>stride<TAB>label"). A RECORD file (nearly
every line the same length, e.g. a puzzle bank) is reduced to those lines so an app can seek to
record N at N * stride; any other file is kept line for line with stride 0. An APP_DIR/icon.png
becomes the app's icon in the Ink App grid (1 bpp, dark pixels black, scaled to the slot).

The package is encrypted for the device key that XTOS Licorice carries. That key is a constant in
the firmware, identical on every unit, so its PUBLIC half is embedded here (DEVICE_PUBKEY_HEX) and
no firmware dump is needed to build. Pass --image with a Licorice app image (see
tools/netprobe/pack.py) to derive the key from it instead -- the way to re-check a new firmware
build, which may rotate the key.

Format details: docs/firmware-notes.md. The container and crypto code is kycube/x4pro-emu's
tools/xtapp.py (MIT), vendored under tools/vendor/.
"""
import argparse, collections, json, os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'tools', 'vendor'))
import xtapp  # noqa: E402

# The device ECDH public key Q = d*G (uncompressed SEC1), derived from XTOS Licorice 26102301.
DEVICE_PUBKEY_HEX = ('04085a8cf979b14b0792abdb3fd97c6a347ff6cd968e33475b73d6daa4fceee7ef'
                     '245b28a54ba0e310f04f227d380be89a38f54bf5516bcb518614291a569799ff')

XTDT_MAGIC = b'XTDT'
XTDT_HEAD, XTDT_ENTRY, XTDT_MAX_FILES, XTDT_NAME = 16, 80, 128, 64
FEATURE_DATA = 0x08
NAME_RE = re.compile(r'^[A-Za-z0-9._-]{5,64}$')


def locate_scalar(image_path):
    """VA of the device ECDH scalar in a Licorice app image: the 32 bytes after the AES-KW default IV
    (a6 x 8), which is unique in DROM (0x3c32c674 in build 261013, 0x3c3610f0 in 26102301)."""
    img = open(image_path, 'rb').read()
    off, hits = 24, []
    for _ in range(img[1]):
        la, ln = struct.unpack_from('<II', img, off)
        if 0x3C000000 <= la < 0x3D000000:
            seg = img[off + 8:off + 8 + ln]
            i = seg.find(b'\xa6' * 8)
            while i != -1:
                hits.append(la + i + 8)
                i = seg.find(b'\xa6' * 8, i + 1)
        off += 8 + ln
    return hits[0] if len(hits) == 1 else None


def device_pubkey(image=None):
    if not image:
        return bytes.fromhex(DEVICE_PUBKEY_HEX)
    va = locate_scalar(image)
    if va:
        xtapp.LICORICE_SCALAR_VA = va
    pub = xtapp.licorice_device_pubkey(image)
    if pub.hex() != DEVICE_PUBKEY_HEX:
        print(f'NOTE: the key derived from {image} differs from the embedded one; using the derived key')
    return pub


def build_xtdt(files):
    files = [(str(n), bytes(b)) for n, b in files]
    if not 1 <= len(files) <= XTDT_MAX_FILES:
        raise SystemExit(f'the data section holds 1..{XTDT_MAX_FILES} files, got {len(files)}')
    table_end = XTDT_HEAD + XTDT_ENTRY * len(files)
    head = XTDT_MAGIC + struct.pack('<HHII', 1, 0, len(files), table_end)
    entries, blobs, off = b'', b'', 0
    for name, blob in files:
        if not NAME_RE.match(name) or '..' in name or not name.endswith(('.txt', '.tsv')):
            raise SystemExit(f'data file name {name!r}: 5..64 chars of letters/digits/-/./_ ending in .txt or .tsv')
        nb = name.encode('ascii')
        # name[64], u32 offset (from the table end), u32 length, 8 reserved: 80 bytes per entry
        entries += nb.ljust(XTDT_NAME, b'\0') + struct.pack('<II', off, len(blob)) + bytes(XTDT_ENTRY - XTDT_NAME - 8)
        blobs += blob
        off += len(blob)
    return head + entries + blobs


def read_xtdt(blob):
    """Inverse of build_xtdt with the firmware's checks; returns [(name, bytes)]."""
    if blob[:4] != XTDT_MAGIC:
        raise ValueError('not an XTDT table')
    count, table_end = struct.unpack_from('<II', blob, 8)
    if count > XTDT_MAX_FILES or table_end != XTDT_HEAD + XTDT_ENTRY * count or len(blob) < table_end:
        raise ValueError('XTDT header rejected')
    out = []
    for i in range(count):
        e = XTDT_HEAD + XTDT_ENTRY * i
        name = blob[e:e + XTDT_NAME].split(b'\0')[0].decode('ascii')
        off, ln = struct.unpack_from('<II', blob, e + XTDT_NAME)
        if not name or table_end + off + ln > len(blob):
            raise ValueError(f'entry {i} rejected')
        out.append((name, blob[table_end + off:table_end + off + ln]))
    return out


XTAB_MAGIC = b'XTAB'
XTAB_HEAD, XTAB_ENTRY, XTAB_NAME, XTAB_MAX_ICONS = 64, 40, 24, 8
XIC_MAGIC = b'XIC\0'
# A set bit is drawn black (device, 26102401); the grid scales the icon to its slot.
ICON_INK_BIT = 1


def build_xic_1bpp(img, ink_bit=ICON_INK_BIT):
    """A Pillow image as the firmware's 1-bpp image: a 24-byte XIC header (u16 width at 4, height
    at 6, version 1 at 8, format 1 = 1 bpp at 9, planes 1 at 10, no alpha at 14/15, u32 size at 16)
    and rows of ceil(w/8) bytes, most significant bit first; dark pixels get ink_bit."""
    img = img.convert('L')
    w, h = img.size
    stride = (w + 7) // 8
    px = img.load()
    rows = bytearray(stride * h)
    for y in range(h):
        for x in range(w):
            if (px[x, y] < 128) == bool(ink_bit):
                rows[y * stride + x // 8] |= 0x80 >> (x % 8)
    head = bytearray(24)
    head[0:4] = XIC_MAGIC
    struct.pack_into('<HHBBB', head, 4, w, h, 1, 1, 1)
    struct.pack_into('<I', head, 16, len(rows))
    return bytes(head) + bytes(rows)


def build_xtab(entries):
    """The icons section: a 64-byte XTAB header (version 1 at 4, count at 8, 64 at 12, data start at
    16, section length at 20), 40-byte entries (name[24], offset from the data start, length, u16 w,
    u16 h, u8 format) and the blobs. The Ink App grid looks up "app_icon_s", then "app_icon_l"."""
    if not 1 <= len(entries) <= XTAB_MAX_ICONS:
        raise SystemExit(f'the icons section holds 1..{XTAB_MAX_ICONS} entries, got {len(entries)}')
    start = XTAB_HEAD + XTAB_ENTRY * len(entries)
    table, blobs = b'', b''
    for name, blob in entries:
        w, h, fmt = struct.unpack_from('<HH', blob, 4) + (blob[9],)
        table += name.encode('ascii').ljust(XTAB_NAME, b'\0') + struct.pack('<IIHHB', len(blobs), len(blob), w, h, fmt) + bytes(3)
        blobs += blob
    head = bytearray(XTAB_HEAD)
    head[0:4] = XTAB_MAGIC
    struct.pack_into('<HHIIII', head, 4, 1, 0, len(entries), XTAB_HEAD, start, start + len(blobs))
    return bytes(head) + table + blobs


def collect_icons(app_dir):
    """APP_DIR/icon.png as the grid icon (app_icon_s); None when there is none."""
    path = os.path.join(app_dir, 'icon.png')
    if not os.path.isfile(path):
        return None
    from PIL import Image
    img = Image.open(path)
    print(f'  icon.png: {img.size[0]}x{img.size[1]}, 1 bpp')
    return build_xtab([('app_icon_s', build_xic_1bpp(img))])


def collect_data_files(app_dir):
    """Normalised data files from APP_DIR/data plus the generated banks.tsv; [] when there is none."""
    ddir = os.path.join(app_dir, 'data')
    if not os.path.isdir(ddir):
        return []
    files, index = [], []
    for fn in sorted(os.listdir(ddir)):
        if not fn.lower().endswith(('.txt', '.tsv', '.csv')):
            continue
        name = fn if fn.endswith(('.txt', '.tsv')) else os.path.splitext(fn)[0] + '.txt'
        raw = open(os.path.join(ddir, fn), 'rb').read().decode('utf-8', 'surrogateescape')
        lines = [l.rstrip('\r') for l in raw.split('\n')]
        if lines and lines[-1] == '':
            lines.pop()
        if not lines:
            print(f'  data/{fn}: empty, skipped'); continue
        body = [l for l in lines if l and not l.startswith('#') and not l.lower().startswith(('quizzes', 'puzzle'))]
        mode_len, mode_n = collections.Counter(len(l) for l in body).most_common(1)[0] if body else (0, 0)
        if body and mode_len > 0 and mode_n >= 0.9 * len(body):
            keep = [l for l in body if len(l) == mode_len]
            if len(keep) != len(body):
                print(f'  data/{fn}: dropped {len(body) - len(keep)} lines whose length differs from {mode_len}')
            stride = mode_len + 1
        else:
            keep, stride = lines, 0
        blob = ('\n'.join(keep) + '\n').encode('utf-8', 'surrogateescape')
        files.append((name, blob))
        index.append(f'{name}\t{len(keep)}\t{stride}\t{os.path.splitext(fn)[0]}')
        print(f'  data/{name}: {len(keep)} ' + (f'records, stride {stride}' if stride else 'lines, kept as-is') + f', {len(blob)} bytes')
    if files:
        files.insert(0, ('banks.tsv', ('\n'.join(index) + '\n').encode('utf-8')))
    return files


def build_container(manifest_obj, pubkey, code_files, data_files, icons=None):
    obj = collections.OrderedDict(manifest_obj)
    dek, E, wrapped = xtapp.licorice_wrap_dek(pubkey)
    obj['dek_wrap_alg'] = xtapp.LICORICE_ALG
    obj['dek_wrap_key_id'] = xtapp.LICORICE_KEY_ID
    obj['dek_wrap_ephemeral_pub'] = E.hex()
    obj['wrapped_dek_pack'] = wrapped.hex()
    iv = os.urandom(16)
    plain = xtapp.build_xtco(code_files)
    if len(plain) > xtapp.LICORICE_INMEM_MAX:
        raise SystemExit(f'code section {len(plain)} bytes exceeds the in-RAM limit {xtapp.LICORICE_INMEM_MAX}')
    code = xtapp.licorice_ctr(dek, iv, plain)
    obj['iv_code'] = iv.hex()
    obj['hmac_code'] = xtapp.licorice_section_hmac(dek, code).hex()
    mask = xtapp.LICORICE_FEATURE_CODE
    data = b''
    if data_files:
        iv_d = os.urandom(16)
        data = xtapp.licorice_ctr(dek, iv_d, build_xtdt(data_files))
        obj['iv_data'] = iv_d.hex()
        obj['hmac_data'] = xtapp.licorice_section_hmac(dek, data).hex()
        mask |= FEATURE_DATA
    blob = json.dumps(obj, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
    if not 1 <= len(blob) <= xtapp.MANIFEST_MAX:
        raise SystemExit(f'manifest {len(blob)} bytes, limit {xtapp.MANIFEST_MAX}')
    H = xtapp.HEADER_SIZE
    code_off = H + len(blob) + (-(H + len(blob)) % 16)
    data_off = code_off + len(code) + (-(code_off + len(code)) % 16) if data else 0
    total = (data_off + len(data)) if data else (code_off + len(code))
    # the icons section is read in the clear (no DEK, no HMAC), so it can follow everything else
    icons_off = total + (-total % 16) if icons else 0
    if icons:
        total = icons_off + len(icons)
    head = bytearray(H)
    head[0:4] = xtapp.MAGIC
    struct.pack_into('<HH', head, 4, xtapp.VERSION, H)
    struct.pack_into('<I', head, 0x08, total)
    struct.pack_into('<I', head, 0x0c, mask)
    struct.pack_into('<II', head, 0x10, xtapp.MANIFEST_OFF, len(blob))
    struct.pack_into('<II', head, 0x18, code_off, len(code))
    if data:
        struct.pack_into('<II', head, 0x38, data_off, len(data))
    if icons:
        struct.pack_into('<II', head, 0x30, icons_off, len(icons))
    out = bytes(head) + blob + bytes(code_off - H - len(blob)) + code
    if data:
        out += bytes(data_off - len(out)) + data
    if icons:
        out += bytes(icons_off - len(out)) + icons
    return out, dek


API2_PERMISSIONS = ('net', 'reader')


def validate_manifest(obj, where):
    """API 0.8 manifests go through the vendored validator. A manifest with "api": "2.0" selects the
    host's API 2.9 (docs/firmware-notes.md): its permission vocabulary is just `net` and `reader`
    (the 0.8 names make the installer reject the package), and it may carry a `lockscreen` block
    ({enabled, entry, interval_sec}) whose entry is drawn when the device locks."""
    if str(obj.get('api', '')) != '2.0':
        return xtapp.validate_manifest_licorice(obj, where)
    for key in ('app_id', 'display_name'):
        if not isinstance(obj.get(key), str) or not obj[key].strip():
            raise SystemExit(f'{where}: "{key}" must be a non-empty string')
    if not re.fullmatch(r'[A-Za-z]+', obj['app_id']):
        raise SystemExit(f'{where}: app_id must be ASCII letters only, got {obj["app_id"]!r}')
    perms = obj.get('permissions', [])
    if not isinstance(perms, list) or any(p not in API2_PERMISSIONS for p in perms):
        raise SystemExit(f'{where}: with "api": "2.0" permissions must be a list drawn from {API2_PERMISSIONS}, got {perms!r}')
    entry = obj.get('entry', 'index.lua')
    if not isinstance(entry, str) or not 1 <= len(entry.encode()) <= 31:
        raise SystemExit(f'{where}: "entry" must be 1..31 bytes, got {entry!r}')
    lock = obj.get('lockscreen')
    if lock is not None:
        if not isinstance(lock, dict) or not isinstance(lock.get('entry', 'lockscreen.lua'), str):
            raise SystemExit(f'{where}: "lockscreen" must be an object like {{"enabled": true, "entry": "lockscreen.lua", "interval_sec": 60}}')
    return obj


def pack(app_dir, out=None, image=None):
    mpath = os.path.join(app_dir, 'manifest.json')
    man = validate_manifest(xtapp.load_manifest(mpath), mpath)
    entry = man.get('entry', 'index.lua')
    code_files = []
    for root, dirs, fns in os.walk(app_dir):
        dirs[:] = [d for d in dirs if d not in ('data', 'src', '__pycache__') and not d.startswith('.')]
        for fn in sorted(fns):
            if fn.endswith('.lua'):
                rel = os.path.relpath(os.path.join(root, fn), app_dir).replace(os.sep, '/')
                code_files.append((rel, open(os.path.join(root, fn), 'rb').read()))
    code_files.sort(key=lambda t: (t[0] != entry, t[0]))
    if not code_files or code_files[0][0] != entry:
        raise SystemExit(f'{entry} not found in {app_dir}')
    lock = man.get('lockscreen')
    if isinstance(lock, dict) and lock.get('entry', 'lockscreen.lua') not in [c[0] for c in code_files]:
        raise SystemExit(f'lockscreen entry {lock.get("entry")!r} not found in {app_dir}')
    data_files = collect_data_files(app_dir)
    out = out or os.path.join(app_dir, man['app_id'] + '.xtapp')
    icons = collect_icons(app_dir)
    pkg, _ = build_container(man, device_pubkey(image), code_files, data_files, icons)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'wb') as f:
        f.write(pkg)
    sec = xtapp.licorice_sections(pkg)
    print(f'{out}: {len(pkg)} bytes, app_id={man["app_id"]} "{man["display_name"]}", '
          f'code {sec["code"][1]} B ({len(code_files)} files), data {sec["data"][1]} B ({len(data_files)} files)')
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('app_dir')
    ap.add_argument('-o', '--out')
    ap.add_argument('--image', help='derive the device key from this Licorice app image instead of the embedded one')
    a = ap.parse_args()
    pack(a.app_dir, a.out, a.image)
    print("copy to the SD card root, install from All Files, open from the drawer's Ink App")


if __name__ == '__main__':
    main()
