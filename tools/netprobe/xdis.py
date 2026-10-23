"""Disassemble a VA window of the Licorice app image with Espressif's xtensa-esp-elf-objdump and
annotate every l32r with the literal it loads (and the string it points at, when it is one).

  python netprobe/xdis.py IMAGE START_VA END_VA [--objdump PATH]

The objdump default is the one extracted into this session's scratchpad (see README).
"""
import argparse, glob, os, re, struct, subprocess, tempfile

DEFAULT_OBJDUMP = glob.glob(os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Temp', 'claude', '*', '*',
                                         'scratchpad', 'toolchain', 'xtensa-esp-elf', 'bin',
                                         'xtensa-esp-elf-objdump.exe'))


def segments(img):
    segs, o = [], 24
    for _ in range(img[1]):
        la, ln = struct.unpack_from('<II', img, o)
        segs.append((la, ln, o + 8))
        o += 8 + ln
    return segs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('image'); ap.add_argument('start'); ap.add_argument('end')
    ap.add_argument('--objdump', default=DEFAULT_OBJDUMP[0] if DEFAULT_OBJDUMP else None)
    a = ap.parse_args()
    if not a.objdump or not os.path.exists(a.objdump):
        raise SystemExit('xtensa-esp-elf-objdump not found; pass --objdump')
    img = open(a.image, 'rb').read()
    segs = segments(img)
    start, end = int(a.start, 0), int(a.end, 0)

    def fo_of(va):
        for la, ln, f in segs:
            if la <= va < la + ln:
                return f + va - la

    def str_at(va):
        fo = fo_of(va)
        if fo is None:
            return None
        s = img[fo:fo + 60].split(b'\0')[0]
        return s.decode('ascii') if s and all(32 <= c < 127 for c in s) else None

    for la, ln, f in segs:
        if la <= start < la + ln:
            t = tempfile.NamedTemporaryFile(suffix='.bin', delete=False)
            t.write(img[f:f + ln]); t.close()
            out = subprocess.run([a.objdump, '-D', '-b', 'binary', '-m', 'xtensa', f'--adjust-vma={la:#x}',
                                  f'--start-address={start:#x}', f'--stop-address={end:#x}', t.name],
                                 capture_output=True, text=True)
            os.unlink(t.name)
            for line in out.stdout.splitlines()[7:]:
                m = re.search(r'l32r\s+a\d+,\s*(0x[0-9a-f]+|[0-9a-f]+)', line)
                if m:
                    tgt = int(m.group(1), 16)
                    tf = fo_of(tgt)
                    if tf is not None:
                        v = struct.unpack_from('<I', img, tf)[0]
                        s = str_at(v)
                        line += f'    ; = {v:#x}' + (f' "{s}"' if s else '')
                print(line)
            if out.stderr.strip():
                print(out.stderr)
            return
    raise SystemExit('start VA not in any segment')


if __name__ == '__main__':
    main()
