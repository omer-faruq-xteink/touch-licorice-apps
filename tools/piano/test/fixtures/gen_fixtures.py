"""Writes the MusicXML test fixtures of tools/piano/test (run: python -I gen_fixtures.py).

scale.musicxml   4 bars: RH C major scale in quarters (C4..C5 then back), LH whole-note C3+G3 chords
long.musicxml    64 bars of RH quarters and LH half notes (several pages)
repeat.musicxml  2 bars of RH quarters inside repeat signs
dense.musicxml   8 bars of RH 16ths over 3 octaves and LH 4-note chords in quarters
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
STEPS = ['C', 'C', 'D', 'D', 'E', 'F', 'F', 'G', 'G', 'A', 'A', 'B']
ALTER = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0]
TYPES = {1: '16th', 2: 'eighth', 4: 'quarter', 8: 'half', 16: 'whole'}


def pitch(m):
    return f'<pitch><step>{STEPS[m % 12]}</step>{"<alter>1</alter>" if ALTER[m % 12] else ""}<octave>{m // 12 - 1}</octave></pitch>'


def notes(events, staff, voice):
    """events: list of (midi list, duration in 16ths)"""
    out = []
    for chord, dur in events:
        for i, m in enumerate(chord):
            out.append(f'<note>{"<chord/>" if i else ""}{pitch(m)}<duration>{dur}</duration><voice>{voice}</voice>'
                       f'<type>{TYPES[dur]}</type><staff>{staff}</staff></note>')
    return ''.join(out)


def score(title, bars, repeat=False):
    """bars: list of (rh events, lh events); 4/4, divisions 4 (a 16th = 1)"""
    ms = []
    for i, (rh, lh) in enumerate(bars):
        attr = ('<attributes><divisions>4</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time>'
                '<staves>2</staves><clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef></attributes>') if i == 0 else ''
        left = '<barline location="left"><repeat direction="forward"/></barline>' if repeat and i == 0 else ''
        right = '<barline location="right"><bar-style>light-heavy</bar-style><repeat direction="backward"/></barline>' if repeat and i == len(bars) - 1 else ''
        body = notes(rh, 1, 1) + '<backup><duration>16</duration></backup>' + notes(lh, 2, 5)
        ms.append(f'<measure number="{i + 1}">{attr}{left}{body}{right}</measure>')
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">\n'
            f'<score-partwise version="4.0"><work><work-title>{title}</work-title></work><identification><creator type="composer">Test</creator></identification>'
            '<part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>'
            f'<part id="P1">{"".join(ms)}</part></score-partwise>\n')


def write(name, text):
    open(os.path.join(HERE, name), 'w', encoding='utf-8', newline='\n').write(text)


up = [60, 62, 64, 65, 67, 69, 71, 72]
scale = [up[0:4], up[4:8], up[::-1][0:4], up[::-1][4:8]]
write('scale.musicxml', score('Scale', [([([m], 4) for m in b], [([48, 55], 16)]) for b in scale]))
long_bars = []
for i in range(64):
    base = 60 + (i % 5)
    long_bars.append(([([base + k], 4) for k in (0, 2, 4, 2)], [([base - 12], 8), ([base - 5], 8)]))
write('long.musicxml', score('Long', long_bars))
write('repeat.musicxml', score('Repeat', [([([m], 4) for m in up[0:4]], [([48], 16)]), ([([m], 4) for m in up[4:8]], [([43], 16)])], repeat=True))
dense = []
for i in range(8):
    run = [48 + ((k * 5 + i) % 36) for k in range(16)]
    dense.append(([([m], 1) for m in run], [([36, 43, 48, 52], 4)] * 4))
write('dense.musicxml', score('Dense', dense))
