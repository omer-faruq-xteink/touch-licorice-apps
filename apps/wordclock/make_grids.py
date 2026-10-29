"""Write src/grids.lua: the Word Clock's letter grid and word positions for each language.

  python -I apps/wordclock/make_grids.py

English and German use the classic 11x10 word-clock layouts. Turkish packs its words in reading
order (hour words before minute words: "SAAT ONU YİRMİ GEÇİYOR"), each hour in the three forms the
sentence needs (bare "ON", object "ONU" for past, dative "ONA" for to); a word that is the start
of a longer one shares its cells ("BİR" lights the first three letters of "BİRİ").
Rows are written as lists of characters so the Lua side needs no UTF-8 library.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))

EN_ROWS = ['ITLISASAMPM', 'ACQUARTERDC', 'TWENTYFIVEX', 'HALFSTENFTO', 'PASTERUNINE',
           'ONESIXTHREE', 'FOURFIVETWO', 'EIGHTELEVEN', 'SEVENTWELVE', 'TENSEOCLOCK']
DE_ROWS = ['ESKISTAFÜNF', 'ZEHNZWANZIG', 'DREIVIERTEL', 'VORFUNKNACH', 'HALBAELFÜNF',
           'EINSXAMZWEI', 'DREIPMJVIER', 'SECHSNLACHT', 'SIEBENZWÖLF', 'ZEHNEUNKUHR']

TR_TOKENS = ['SAAT', 'ONU', 'ONA', 'BİRİ', 'BİRE', 'İKİYİ', 'İKİYE', 'ÜÇÜ', 'ÜÇE', 'DÖRT', 'DÖRDÜ',
             'DÖRDE', 'BEŞİ', 'BEŞE', 'ALTIYI', 'ALTIYA', 'YEDİYİ', 'YEDİYE', 'SEKİZİ', 'SEKİZE',
             'DOKUZU', 'DOKUZA', 'YARIM', 'BUÇUK', 'YİRMİ', 'BEŞ', 'ON', 'ÇEYREK', 'GEÇİYOR', 'VAR']
TR_COLS = 12
FILL = 'KLMRSTNAEHUZ'


def find(rows, word, start=(0, 0)):
    """(row, col) of word at or after start, reading order."""
    r0, c0 = start
    for r in range(r0, len(rows)):
        i = rows[r].find(word, c0 if r == r0 else 0)
        if i >= 0:
            return r, i
    raise ValueError(word)


def pack(tokens, cols):
    """Rows of `cols` letters holding the tokens in order, a filler letter between neighbours
    when the row has room; the rest filler. Returns rows and {token: (row, col)}."""
    rows, pos, cur = [], {}, ''
    for t in tokens:
        sep = 1 if cur else 0
        if len(cur) + sep + len(t) > cols:
            if len(cur) + len(t) <= cols:
                sep = 0                              # fits without the gap
            else:
                rows.append(cur); cur, sep = '', 0
        if sep:
            cur += FILL[(len(rows) * 7 + len(cur)) % len(FILL)]
        pos[t] = (len(rows), len(cur))
        cur += t
    rows.append(cur)
    out = []
    for r, row in enumerate(rows):
        pad = cols - len(row)
        out.append(row + ''.join(FILL[(r * 5 + k) % len(FILL)] for k in range(pad)))
    return out, pos


def lua_str(s):
    return "'" + s.replace("'", "\\'") + "'"


def emit(name, rows, words):
    lines = [f'  {name} = {{', '    rows = {']
    for row in rows:
        lines.append('      { ' + ', '.join(lua_str(ch) for ch in row) + ' },')
    lines.append('    },')
    lines.append('    words = {')
    for k, (r, c, n) in words.items():
        lines.append(f'      [{lua_str(k)}] = {{ {r + 1}, {c + 1}, {n} }},')
    lines.append('    },')
    lines.append('  },')
    return lines


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    # English: (row, col, length) per word; FIVE_M / TEN_M are the minute words
    en = {}
    for key, word, start in [('IT', 'IT', (0, 0)), ('IS', 'IS', (0, 2)), ('A', 'A', (1, 0)), ('QUARTER', 'QUARTER', (1, 0)),
                             ('TWENTY', 'TWENTY', (2, 0)), ('FIVE_M', 'FIVE', (2, 0)), ('HALF', 'HALF', (3, 0)),
                             ('TEN_M', 'TEN', (3, 0)), ('TO', 'TO', (3, 8)), ('PAST', 'PAST', (4, 0)), ('9', 'NINE', (4, 0)),
                             ('1', 'ONE', (5, 0)), ('6', 'SIX', (5, 0)), ('3', 'THREE', (5, 0)), ('4', 'FOUR', (6, 0)),
                             ('5', 'FIVE', (6, 0)), ('2', 'TWO', (6, 0)), ('8', 'EIGHT', (7, 0)), ('11', 'ELEVEN', (7, 0)),
                             ('7', 'SEVEN', (8, 0)), ('12', 'TWELVE', (8, 0)), ('10', 'TEN', (9, 0)), ('OCLOCK', 'OCLOCK', (9, 0))]:
        r, c = find(EN_ROWS, word, start)
        en[key] = (r, c, len(word))
    de = {}
    for key, word, start in [('ES', 'ES', (0, 0)), ('IST', 'IST', (0, 0)), ('FÜNF_M', 'FÜNF', (0, 0)), ('ZEHN_M', 'ZEHN', (1, 0)),
                             ('ZWANZIG', 'ZWANZIG', (1, 0)), ('VIERTEL', 'VIERTEL', (2, 0)), ('VOR', 'VOR', (3, 0)),
                             ('NACH', 'NACH', (3, 0)), ('HALB', 'HALB', (4, 0)), ('11', 'ELF', (4, 0)), ('5', 'FÜNF', (4, 0)),
                             ('1', 'EINS', (5, 0)), ('EIN', 'EIN', (5, 0)), ('2', 'ZWEI', (5, 0)), ('3', 'DREI', (6, 0)),
                             ('4', 'VIER', (6, 0)), ('6', 'SECHS', (7, 0)), ('8', 'ACHT', (7, 0)), ('7', 'SIEBEN', (8, 0)),
                             ('12', 'ZWÖLF', (8, 0)), ('10', 'ZEHN', (9, 0)), ('9', 'NEUN', (9, 0)), ('UHR', 'UHR', (9, 0))]:
        r, c = find(DE_ROWS, word, start)
        de[key] = (r, c, len(word))
    tr_rows, tpos = pack(TR_TOKENS, TR_COLS)
    tr = {t: (r, c, len(t)) for t, (r, c) in tpos.items()}
    # the bare hour words inside the longer forms
    for bare, full in [('BİR', 'BİRİ'), ('İKİ', 'İKİYİ'), ('ÜÇ', 'ÜÇÜ'), ('BEŞ_H', 'BEŞİ'), ('ALTI', 'ALTIYI'),
                       ('YEDİ', 'YEDİYİ'), ('SEKİZ', 'SEKİZİ'), ('DOKUZ', 'DOKUZU'), ('ON_H', 'ONU')]:
        r, c, _n = tr[full]
        tr[bare] = (r, c, len(bare.split('_')[0]))
    out = ['-- built by make_grids.py: edit that, not this file', '', 'local GRIDS = {']
    out += emit('en', EN_ROWS, en) + emit('de', DE_ROWS, de) + emit('tr', tr_rows, tr)
    out.append('}')
    open(os.path.join(HERE, 'src', 'grids.lua'), 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
    for name, rows in (('en', EN_ROWS), ('de', DE_ROWS), ('tr', tr_rows)):
        print(name, len(rows), 'x', len(rows[0]))
        for row in rows:
            print('  ' + ' '.join(row))


if __name__ == '__main__':
    main()
