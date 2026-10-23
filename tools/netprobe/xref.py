"""Find code that loads given literal-pool entries (l32r) in the Licorice app image, and disassemble
around it with capstone (Xtensa). Usage: python netprobe/xref.py IMAGE POOL_FILE_OFF_START POOL_FILE_OFF_END"""
import struct, sys, re
import capstone as cs
img = open(sys.argv[1], 'rb').read()
lo, hi = int(sys.argv[2], 0), int(sys.argv[3], 0)
segs = []; o = 24
for _ in range(img[1]):
    la, ln = struct.unpack_from('<II', img, o); segs.append((la, ln, o + 8)); o += 8 + ln
def va_of(fo):
    for la, ln, f in segs:
        if f <= fo < f + ln: return la + fo - f
def fo_of(va):
    for la, ln, f in segs:
        if la <= va < la + ln: return f + va - la
def str_at(va):
    fo = fo_of(va)
    if fo is None: return None
    s = img[fo:fo + 48].split(b'\0')[0]
    return s.decode('ascii') if s and all(32 <= c < 127 for c in s) else None
# scan IROM (0x42......) for l32r whose target lies in [lo, hi)
irom = [(la, ln, f) for la, ln, f in segs if 0x42000000 <= la < 0x43000000]
hits = []
for la, ln, f in irom:
    seg = img[f:f + ln]
    for i in range(ln - 2):
        if seg[i] & 0x0F != 0x01: continue           # op0 == 1 -> l32r
        imm = seg[i + 1] | (seg[i + 2] << 8)
        pc = la + i
        tgt = ((pc + 3) & ~3) + ((imm | 0xFFFF0000) << 2 & 0xFFFFFFFF)
        tgt &= 0xFFFFFFFF
        tf = fo_of(tgt)
        if tf is not None and lo <= tf < hi:
            hits.append((pc, tgt))
print(f'{len(hits)} l32r hits into pool [{lo:#x},{hi:#x}); PC range {min(h[0] for h in hits):#x}..{max(h[0] for h in hits):#x}' if hits else 'no hits')
# group into functions by gaps > 0x400
hits.sort()
groups = []
for pc, tgt in hits:
    if groups and pc - groups[-1][-1][0] < 0x400: groups[-1].append((pc, tgt))
    else: groups.append([(pc, tgt)])
for g in groups:
    print(f'--- group {g[0][0]:#x}..{g[-1][0]:#x} ({len(g)} refs)')
    for pc, tgt in g:
        v = struct.unpack_from('<I', img, fo_of(tgt))[0]
        s = str_at(v)
        print(f'  {pc:#x}: l32r -> pool {tgt:#x} = {v:#x}' + (f' "{s}"' if s else ''))
if len(sys.argv) > 4:
    start, end = int(sys.argv[4], 0), int(sys.argv[5], 0)
    md = cs.Cs(cs.CS_ARCH_XTENSA, cs.CS_MODE_LITTLE_ENDIAN); md.skipdata = True
    f = fo_of(start)
    pool_vals = {}
    for ins in md.disasm(img[f:f + (end - start)], start):
        note = ''
        if ins.mnemonic == 'l32r':
            m = re.search(r'0x[0-9a-f]+', ins.op_str)
            if m:
                t = int(m.group(), 16); tf = fo_of(t)
                if tf is not None:
                    v = struct.unpack_from('<I', img, tf)[0]
                    s = str_at(v)
                    note = f'   ; = {v:#x}' + (f' "{s}"' if s else '')
        print(f'{ins.address:#x}: {ins.mnemonic:8s} {ins.op_str}{note}')
