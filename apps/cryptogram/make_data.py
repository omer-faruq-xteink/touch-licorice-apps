"""Cryptogram's quotes: quotes.txt (author|quote, grouped by author) -> data/quotes.txt, checked
(plain ASCII, short enough for one screen, no repeats) and shuffled with a fixed seed so that
authors take turns. The app plays line N on day N (counted from 1 November 2026) and starts over
after the last one.

  python -I apps/cryptogram/make_data.py
"""
import os, random

HERE = os.path.dirname(os.path.abspath(__file__))
MAX_QUOTE, MAX_AUTHOR = 104, 26

rows, seen = [], set()
for n, line in enumerate(open(os.path.join(HERE, 'quotes.txt'), encoding='utf-8'), 1):
    line = line.rstrip('\n')
    if not line or line.startswith('#'):
        continue
    author, quote = line.split('|')
    assert line.isascii(), (n, line)
    assert 0 < len(quote) <= MAX_QUOTE and 0 < len(author) <= MAX_AUTHOR, (n, len(quote), line)
    if sum(c.isalpha() for c in set(quote.upper())) < 10:     # too few letters to work out
        print('  left out, too short:', quote)
        continue
    key = ''.join(c for c in quote.lower() if c.isalpha())
    assert key not in seen, (n, 'repeated', line)
    seen.add(key)
    rows.append(f'{author}|{quote}')
random.Random(20261101).shuffle(rows)
os.makedirs(os.path.join(HERE, 'data'), exist_ok=True)
with open(os.path.join(HERE, 'data', 'quotes.txt'), 'w', encoding='ascii', newline='\n') as f:
    f.write('\n'.join(rows) + '\n')
print(f'data/quotes.txt: {len(rows)} quotes, {len({r.split("|")[0] for r in rows})} authors')
