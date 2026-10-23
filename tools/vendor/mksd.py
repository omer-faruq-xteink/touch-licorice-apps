#!/usr/bin/env python3
"""Create a FAT32 SD-card image of a power-of-two size and populate it with mtools.

No root, no loop mounts. QEMU's SD model refuses images whose size is not a
power of two, so the size is validated here. By default the image carries an
MBR with one FAT32 (0x0C) partition starting at 1 MiB, like the X4 Pro's own
card: SdFat mounts partition 1 and does not fall back to a superfloppy.

  mksd.py out.img [--size 256M] [--src DIR ...] [--label X4PRO] [--superfloppy]
"""
import argparse, os, shutil, struct, subprocess, sys

PART_START = 2048   # sectors (1 MiB)

def write_mbr(path, size):
    sectors = size // 512
    part_sectors = sectors - PART_START
    mbr = bytearray(512)
    # partition 1: bootable flag 0, type 0x0C (FAT32 LBA), CHS fields set to the LBA sentinel
    entry = struct.pack('<B3sB3sII', 0x00, b'\xfe\xff\xff', 0x0C, b'\xfe\xff\xff', PART_START, part_sectors)
    mbr[446:462] = entry
    mbr[510] = 0x55; mbr[511] = 0xAA
    with open(path, 'r+b') as f:
        f.write(mbr)

def parse_size(s):
    s = s.strip().upper()
    mult = {'K': 1 << 10, 'M': 1 << 20, 'G': 1 << 30}
    if s[-1] in mult:
        return int(s[:-1]) * mult[s[-1]]
    return int(s)

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('out')
    ap.add_argument('--size', default='256M', help='image size, power of two (default 256M)')
    ap.add_argument('--src', action='append', default=[], help='directory whose contents go to the root of the image')
    ap.add_argument('--label', default='X4PRO')
    ap.add_argument('--force', action='store_true')
    ap.add_argument('--superfloppy', action='store_true', help='no MBR: FAT boot sector at sector 0')
    a = ap.parse_args()

    size = parse_size(a.size)
    if size & (size - 1):
        sys.exit(f'size {size} is not a power of two (QEMU hw/sd/sd.c requires it)')
    if os.path.exists(a.out) and not a.force:
        sys.exit(f'{a.out} exists; pass --force to overwrite')
    for tool in ('mkfs.vfat', 'mcopy'):
        if not shutil.which(tool):
            sys.exit(f'{tool} not found (brew install dosfstools mtools / apt install dosfstools mtools)')

    with open(a.out, 'wb') as f:
        f.truncate(size)
    if a.superfloppy:
        subprocess.run(['mkfs.vfat', '-F', '32', '-n', a.label, a.out], check=True, stdout=subprocess.DEVNULL)
        img_ref = a.out
    else:
        write_mbr(a.out, size)
        part_sectors = size // 512 - PART_START
        subprocess.run(['mkfs.vfat', '-F', '32', '-n', a.label, '--offset', str(PART_START), a.out, str(part_sectors // 2)],
                       check=True, stdout=subprocess.DEVNULL)
        img_ref = f'{a.out}@@{PART_START * 512}'
    for src in a.src:
        entries = sorted(os.listdir(src))
        if not entries:
            continue
        # -s recursive, -m preserve mtime, -Q quit on error; :: is the image root
        cmd = ['mcopy', '-i', img_ref, '-s', '-m', '-Q'] + [os.path.join(src, e) for e in entries] + ['::/']
        subprocess.run(cmd, check=True)
    print(f'{a.out}: {size >> 20} MiB FAT32 ({"superfloppy" if a.superfloppy else "MBR, partition 1 at 1 MiB"}), label {a.label}, populated from {a.src or "nothing"}')

if __name__ == '__main__':
    main()
