"""Pack netprobe as an XTOS Licorice .xtapp.

  python netprobe/pack.py FIRMWARE [-o netprobe.xtapp]

FIRMWARE is either the Licorice app image (what x4pro-emu calls images/device/stock-app1-v261013.bin)
or a raw 16 MB flash dump of the device (tools/device.py backup, or `esptool read-flash 0 0x1000000`).
From a dump the script finds the app slot that holds XTOS Licorice (the esp_app_desc project name
`dragon_example`), writes it next to the output as licorice-app.bin and packs against it.

The device public key is derived from the firmware image by x4pro-emu's tools/xtapp.py; it is
version-specific (DROM 0x3c32c674 in build 261013). A different Licorice build may move the scalar,
and then the device answers "Install failed" -- the script warns when the version is not 261013.
"""
import argparse, os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
EMU_TOOLS = os.path.join(os.path.dirname(HERE), 'vendor')
sys.path.insert(0, EMU_TOOLS)
import xtapp  # noqa: E402  (x4pro-emu/tools/xtapp.py)

SLOTS = (0x10000, 0x7F0000)      # app0 / app1 under the stock partition table
SLOT_LEN = 0x7E0000
KNOWN_BUILD = '261013'


def app_desc(img):
    """(project_name, version) from the esp_app_desc_t at image offset 0x20."""
    if len(img) < 0x120 or img[0] != 0xE9:
        return None, None
    magic = struct.unpack_from('<I', img, 0x20)[0]
    if magic != 0xABCD5432:
        return None, None
    ver = img[0x30:0x50].split(b'\0', 1)[0].decode('ascii', 'replace')
    name = img[0x50:0x70].split(b'\0', 1)[0].decode('ascii', 'replace')
    return name, ver


def pick_image(path, out_dir):
    data = open(path, 'rb').read()
    if data[0] == 0xE9 and len(data) <= SLOT_LEN:
        name, ver = app_desc(data)
        print(f'app image: project={name!r} version={ver!r}')
        return path, ver
    found = []
    for off in SLOTS:
        if off + 0x120 <= len(data) and data[off] == 0xE9:
            name, ver = app_desc(data[off:off + 0x120])
            found.append((off, name, ver))
            print(f'slot @{off:#x}: project={name!r} version={ver!r}')
    lic = [f for f in found if f[1] == 'dragon_example' or 'Licorice' in (f[2] or '')]
    if not lic:
        sys.exit('no XTOS Licorice app (project dragon_example) found in the dump')
    off, _, ver = lic[-1]
    sl = data[off:off + SLOT_LEN]
    # trim to the image: header + segments + checksum/hash, keep it simple and keep the whole slot
    out = os.path.join(out_dir, 'licorice-app.bin')
    with open(out, 'wb') as f:
        f.write(sl)
    print(f'wrote {out} (slot @{off:#x})')
    return out, ver


def locate_scalar(image_path):
    """Find the device ECDH scalar in a Licorice app image without trusting the 261013 address.

    In build 261013 the AES-KW default IV (a6 x 8, DROM 0x3c32c66c) sits 8 bytes before the 32-byte
    scalar (0x3c32c674). The marker is unique in DROM, so: find a6*8 in the 0x3c...... segment and
    take the 32 bytes after it. Returns the scalar's virtual address, or None."""
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
    if len(hits) != 1:
        print(f'WARNING: {len(hits)} a6*8 markers in DROM ({", ".join(hex(h) for h in hits)}); cannot locate the scalar')
        return None
    return hits[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('firmware', help='Licorice app image or raw 16 MB flash dump')
    ap.add_argument('-o', '--out', default=os.path.join(HERE, 'netprobe.xtapp'))
    a = ap.parse_args()
    image, ver = pick_image(a.firmware, os.path.dirname(os.path.abspath(a.out)))
    va = locate_scalar(image)
    if va is None:
        print(f'falling back to the build-{KNOWN_BUILD} address {xtapp.LICORICE_SCALAR_VA:#x}; expect "Install failed" '
              f'if this build moved it')
    else:
        if va != xtapp.LICORICE_SCALAR_VA:
            print(f'device scalar located at {va:#x} via the AES-KW IV marker (build {KNOWN_BUILD} had '
                  f'{xtapp.LICORICE_SCALAR_VA:#x}); using it')
        xtapp.LICORICE_SCALAR_VA = va
    pub = xtapp.licorice_device_pubkey(image)
    print(f'device public key Q: {pub.hex()}')
    rep = xtapp.pack_licorice(HERE, a.out, image, True)
    print(f'{rep["out"]}: {rep["bytes"]} bytes, code files: {", ".join(rep["code_files"])}')
    for w in rep['warnings']:
        print('  note:', w)
    print('copy netprobe.xtapp to the SD card root (USB mode), then on the device: All Files -> tap it -> Install.')
    print('Unlock the menu: Settings -> About -> tap "Model" 10 times fast. Then drawer -> Ink App -> Net Probe.')


if __name__ == '__main__':
    main()
