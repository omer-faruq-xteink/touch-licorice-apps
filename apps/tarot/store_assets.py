"""Tarot's store build: the card pictures as packaged images, not base64 lines to decode.

Studio's preview has no image_decode, so there the sideloaded way (data/art_*.txt and
ctx.image:decode) would show only framed names. tools/store_export.py calls assets() for the
images (keys l_m00 ... s_p14, the app looks them up by card key) and leaves out DROP_DATA.
"""
import base64, io, os
from PIL import Image

DROP_DATA = ('art_l1.txt', 'art_l2.txt', 'art_s1.txt', 'art_s2.txt')


def assets(app_dir):
    data = os.path.join(app_dir, 'data')
    keys = [l.split('|', 1)[0] for l in open(os.path.join(data, 'cards.txt'), encoding='ascii').read().split('\n') if l]
    out = {}
    for size in ('l', 's'):
        lines = []
        for k in (1, 2):
            lines += [l.rstrip(' ') for l in open(os.path.join(data, f'art_{size}{k}.txt'), encoding='ascii').read().split('\n') if l]
        assert len(lines) == len(keys) == 78
        for key, b64 in zip(keys, lines):
            out[f'{size}_{key}'] = Image.open(io.BytesIO(base64.b64decode(b64))).convert('1')
    return out
