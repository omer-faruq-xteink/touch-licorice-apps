"""Build the Literary Clock's quotes from public-domain books: a sentence that names a time of day,
for as many of the 1440 minutes as the books give.

  python -I apps/litclock/make_quotes.py BOOKS.tsv BOOKS_DIR

BOOKS.tsv: "<gutenberg number><TAB>title<TAB>author (Last, First)<TAB>death year" per line;
BOOKS_DIR/<number>.txt: the plain-text Project Gutenberg file. Use only books in the public domain
in the US and in life+70 countries (authors who died more than 70 years ago, no translators).

Writes apps/litclock/data/hHH.txt, one file per hour, one quote per line:

    HHMM<TAB>flag<TAB>before<TAB>time phrase<TAB>after<TAB>title<TAB>author

flag "e": the phrase names this minute; "n": no book names it, the nearest earlier quote stands in
(the app shows the exact time below it). Up to MAX_PER_MINUTE quotes per minute, from different
books, the shorter ones first.

A phrase without a.m. / p.m. or a part of the day ("in the morning", "at night" ...) counts for
both halves of the day.
"""
import collections, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'data')
MAX_PER_MINUTE = 3
MIN_LEN, MAX_LEN = 50, 300

NUM = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
       'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
       'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20}
for k in range(1, 10):
    w = [x for x, v in NUM.items() if v == k][0]
    NUM['twenty-' + w] = NUM['twenty ' + w] = 20 + k
HOUR = r'(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|1[012]|[1-9])'
MINW = r'(' + '|'.join(sorted((re.escape(k) for k in NUM if NUM[k] < 30), key=len, reverse=True)) + r'|[1-9]|[12][0-9])'
OCLOCK = r"o['’]clock"
PATTERNS = [
    # half past nine, half-past nine, a quarter past nine, quarter after nine
    (re.compile(r"\b(half|a quarter|quarter)[- ](?:past|after) " + HOUR + r"(?: " + OCLOCK + r")?\b", re.I),
     lambda m: (num(m.group(2)), 30 if m.group(1).lower() == 'half' else 15)),
    # a quarter to ten, quarter of ten
    (re.compile(r"\b(a quarter|quarter) (?:to|of|before) " + HOUR + r"(?: " + OCLOCK + r")?\b", re.I),
     lambda m: (num(m.group(2)) - 1, 45)),
    # twenty minutes past nine, five-and-twenty minutes to six, ten past nine
    (re.compile(r"\b" + MINW + r"(?: minutes?)? (past|after) " + HOUR + r"(?: " + OCLOCK + r")?\b", re.I),
     lambda m: (num(m.group(3)), num(m.group(1)))),
    (re.compile(r"\b" + MINW + r"(?: minutes? (?:to|before|of)| to| before) " + HOUR + r"(?: " + OCLOCK + r")?\b", re.I),
     lambda m: (num(m.group(2)) - 1, 60 - num(m.group(1)))),
    # nine o'clock
    (re.compile(r"\b" + HOUR + r" " + OCLOCK + r"\b", re.I), lambda m: (num(m.group(1)), 0)),
    # 9.30 a.m., 9:30 p.m., 10.15 o'clock
    (re.compile(r"\b(1[012]|[1-9])[.:]([0-5][0-9]) ?(a\.? ?m\.?|p\.? ?m\.?|" + OCLOCK + r")", re.I),
     lambda m: (int(m.group(1)), int(m.group(2)))),
    # noon, midnight
    (re.compile(r"\b(?:at |by |till |until |past |before |after )?(noon|midday|midnight)\b", re.I),
     lambda m: (12 if m.group(1).lower() in ('noon', 'midday') else 0, 0)),
]
AM = re.compile(r"\b(a\.? ?m\.?|in the morning|before dawn|at dawn|before breakfast|morning)\b", re.I)
PM = re.compile(r"\b(p\.? ?m\.?|in the afternoon|in the evening|at night|tonight|to-night|evening|afternoon|after dinner|after supper)\b", re.I)
# a cheap first test: a paragraph without any of these cannot hold a time phrase
QUICK = re.compile(r"clock|past|after|quarter|half|minute|noon|midday|midnight|\d[.:][0-5]\d|"
                   r"\b(?:to|before) (?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|\d)\b", re.I)
CUE = re.compile(r"\b(at|about|by|till|until|since|was|is|struck|nearly|almost|exactly|precisely|before|after|"
                 r"it's|'twas|past|towards|toward|around|already)\s+$", re.I)
# "ten to one that ...", "a hundred to one": odds, not a time
ODDS = re.compile(r"\b(odds|bets?|betting|wager|chances?|lay you|against|backs?|backed|backing|tips?|stakes?|"
                  r"pounds|guineas|fiver|tenner|favourite|favorite|outsiders?|field|price|race|horse|book-?maker)\b|"
                  r"\bto (one|two|three|ten) (that|on|against|chance)\b", re.I)
BAD = re.compile(r"(CHAPTER|Illustration|\[|\]|http|www\.|Gutenberg|_{2,}|\*)")


def num(s):
    s = s.lower()
    return int(s) if s.isdigit() else NUM[s]


def body(text):
    """The book without the Project Gutenberg header and licence."""
    a = re.search(r'\*\*\* ?START OF (THE|THIS) PROJECT GUTENBERG[^\n]*\n', text)
    b = re.search(r'\*\*\* ?END OF (THE|THIS) PROJECT GUTENBERG', text)
    return text[a.end() if a else 0: b.start() if b else len(text)]


SENT = re.compile(r'[^.!?]*?(?:[.!?]+["”’\')]*|$)', re.S)


def sentences(par):
    """Sentences of a paragraph, joining 'Mr.', 'Dr.' and the like back on."""
    out, cur = [], ''
    for s in SENT.findall(par):
        if not s.strip():
            continue
        cur += s
        if re.search(r'\b(Mr|Mrs|Dr|St|Mt|Messrs|a\.m|p\.m|[A-Z])\.\s*$', cur.strip()):
            continue
        out.append(cur.strip())
        cur = ''
    if cur.strip():
        out.append(cur.strip())
    return out


def tidy(s):
    s = s.replace('_', '').replace('’', "'").replace('‘', "'").replace('“', '"').replace('”', '"')
    s = s.replace('—', ' - ').replace('--', ' - ').replace('–', '-')
    return re.sub(r'\s+', ' ', s).strip()


def quotes_in(text):
    """(minutes of the day..., before, phrase, after) for each time phrase in the text."""
    pars = re.split(r'\n\s*\n', body(text))
    for par in pars:
        if not QUICK.search(par):                    # most paragraphs name no time: skip them fast
            continue
        par = tidy(par.replace('\r', ' ').replace('\n', ' '))
        if len(par) < MIN_LEN:
            continue
        for s in sentences(par):
            if not (MIN_LEN <= len(s) <= MAX_LEN) or BAD.search(s):
                continue
            if not re.match(r'["\'(]?[A-Z]', s):          # a piece cut off a "12.15": not a sentence
                continue
            for rx, conv in PATTERNS:
                m = rx.search(s)
                if not m:
                    continue
                try:
                    h, mi = conv(m)
                except (KeyError, ValueError):
                    continue
                if not (0 <= mi < 60) or not (0 <= h <= 12):
                    continue
                h %= 12
                if rx is PATTERNS[-1][0]:
                    halves = [h]                      # noon is 12:00, midnight 0:00
                else:
                    am, pm = AM.search(s), PM.search(s)
                    if h == 0:                        # the twelve o'clock hour: night is 0:xx, day 12:xx
                        night = re.search(r'\b(night|to-?night|midnight)\b', s, re.I)
                        halves = [0] if (am or night) else [12] if pm else [0, 12]
                    else:
                        halves = [h] if am and not pm else [h + 12] if pm and not am else [h, h + 12]
                before, phrase, after = s[:m.start()], m.group(0), s[m.end():]
                low = phrase.lower()
                if ' to ' in low and 'minute' not in low and ODDS.search(s):
                    break
                # a bare "three to four" / "ten past two" (no "minutes", no "o'clock") is often a
                # range ("from three to four days"): only after a word that leads to a time
                if re.search(r' (to|before|past|after) ', low) and 'minute' not in low and 'clock' not in low \
                        and not CUE.search(before[-24:]):
                    break
                # bare "X to Y": a clock says five, ten, twenty or twenty-five to; "six to one",
                # "it was ten to one they ..." are odds; "to one" only after a clock word
                bare = re.match(r'(.+?) (to|before) (.+)$', low)
                if bare and 'minute' not in low and 'clock' not in low:
                    if bare.group(1) not in ('five', 'ten', 'twenty', 'twenty-five', 'twenty five', 'a quarter', 'quarter'):
                        break
                    if bare.group(3) == 'one' and not re.search(r'\b(at|till|until|by|since|struck|past)\s+$', before[-12:], re.I):
                        break
                # "from nine to eleven o'clock", "between seven and eight": a span of hours
                if re.search(r' (to|before) ', low) and 'minute' not in low and re.search(r'\b(from|between)\s+$', before[-14:], re.I):
                    break
                if phrase.lower().startswith(('at ', 'by ', 'till ', 'until ', 'past ', 'before ', 'after ')):
                    sp = phrase.index(' ') + 1
                    before, phrase = before + phrase[:sp], phrase[sp:]
                yield [hh * 60 + mi for hh in halves], before, phrase, after
                break


TITLES = ('Mrs.', 'Mr.', 'Miss', 'Sir', 'Lady', 'Lord', 'Dr.', 'Rev.', 'Captain', 'Baroness', 'Baron')


def person(catalog_name):
    """'Wood, Henry, Mrs.' -> 'Mrs. Henry Wood'; 'Robertson, Alexander, M.D.' -> 'Alexander Robertson, M.D.'"""
    parts = [p.strip() for p in re.sub(r'\s*\(.*?\)', '', catalog_name).split(',') if p.strip()]
    if len(parts) < 2:
        return parts[0] if parts else ''
    last, first, rest = parts[0], parts[1], parts[2:]
    pre = ' '.join(r for r in rest if r in TITLES)
    post = ', '.join(r for r in rest if r not in TITLES)
    if first.endswith(' ' + last):                   # 'Orczy, Emmuska Orczy, Baroness': already there
        last = ''
    name = ' '.join(x for x in (pre, first, last) if x)
    return name + (', ' + post if post else '')


def main():
    lst, books = sys.argv[1], sys.argv[2]
    found = collections.defaultdict(list)            # minute -> [(len, book, before, phrase, after, title, author)]
    nbooks = 0
    for line in open(lst, encoding='utf-8'):
        n, title, author, _death = line.rstrip('\n').split('\t')
        path = os.path.join(books, n + '.txt')
        if not os.path.exists(path):
            continue
        nbooks += 1
        name = person(author)
        title = re.sub(r'\s+', ' ', title.split('\r')[0].split(':')[0]).strip()
        text = open(path, encoding='utf-8', errors='replace').read()
        for mins, before, phrase, after in quotes_in(text):
            for t in mins:
                found[t].append((len(before + phrase + after), n, before, phrase, after, title, name))
    os.makedirs(DATA, exist_ok=True)
    chosen = {}
    for t in range(1440):
        picks, books_used, authors_used = [], set(), set()
        for q in sorted(found.get(t, []), key=lambda q: (abs(q[0] - 140), q[1])):
            if q[1] in books_used or q[6] in authors_used:
                continue
            picks.append(q); books_used.add(q[1]); authors_used.add(q[6])
            if len(picks) == MAX_PER_MINUTE:
                break
        chosen[t] = picks
    exact = sum(1 for t in range(1440) if chosen[t])
    for f in os.listdir(DATA):
        if re.fullmatch(r'h\d\d\.txt', f):
            os.remove(os.path.join(DATA, f))
    files = collections.defaultdict(list)
    prev = None
    for t in list(range(1440)) * 2:                  # twice round, so the first minutes find an earlier quote
        if chosen.get(t):
            prev = chosen[t][0]
    for t in range(1440):
        hhmm = '%02d%02d' % (t // 60, t % 60)
        if chosen[t]:
            prev = chosen[t][0]
            for q in chosen[t]:
                files[t // 60].append('\t'.join([hhmm, 'e', q[2], q[3], q[4], q[5], q[6]]))
        elif prev:
            q = prev
            files[t // 60].append('\t'.join([hhmm, 'n', q[2], q[3], q[4], q[5], q[6]]))
    for h in range(24):
        open(os.path.join(DATA, 'h%02d.txt' % h), 'w', encoding='utf-8', newline='\n').write('\n'.join(files[h]) + '\n')
    print(f'{nbooks} books, {sum(len(v) for v in found.values())} time phrases; '
          f'{exact} of 1440 minutes have their own quote')


if __name__ == '__main__':
    main()
