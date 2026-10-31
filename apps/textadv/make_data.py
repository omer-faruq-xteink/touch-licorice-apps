"""The built-in game of Text adventures: games/Zork I.z3 -> data/zork1.txt, the story file as hex in
lines of 4096 characters (a package's data files are text). Zork I is under the MIT licence
(games/LICENSE-Zork.txt). The last line is padded with zeros: the packer keeps only lines of the
same length, and the bytes past the story's end are never read (its header gives the length).

  python -I apps/textadv/make_data.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, 'games', 'Zork I.z3'), 'rb').read().hex()
src += '0' * (-len(src) % 4096)
os.makedirs(os.path.join(HERE, 'data'), exist_ok=True)
with open(os.path.join(HERE, 'data', 'zork1.txt'), 'w', encoding='ascii', newline='\n') as f:
    for i in range(0, len(src), 4096):
        f.write(src[i:i + 4096] + '\n')
print('data/zork1.txt', len(src) // 2, 'bytes')
