"""Checks of the For you pieces in src/hn.lua (Lua 5.4 through lupa): foryou.txt read and written,
the one Algolia search, mutes, the topics found in a title, a title's words for More like this.

  python -I apps/hackernews/test_foryou.py
"""
import os, sys, urllib.parse
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
sys.stdout.reconfigure(encoding='utf-8')
fails = []


def check(ok, what):
    print(('ok    ' if ok else 'FAIL  ') + what)
    if not ok:
        fails.append(what)


L = lua54.LuaRuntime(unpack_returned_tuples=True)
N = L.execute(open(os.path.join(HERE, 'src', 'hn.lua'), encoding='utf-8').read())
lst = lambda t: [] if t is None else [t[k] for k in range(1, len(t) + 1)]
tbl = lambda xs: L.table_from(xs)

fy = N.foryou_parse('Rust\n-crypto\n-site:Medium.com\nmachine learning\nrust\n-\n\n  \n')
check(lst(fy.topics) == ['rust', 'machine learning'] and lst(fy.words) == ['crypto'] and lst(fy.sites) == ['medium.com'],
      f'foryou.txt read: {lst(fy.topics)} {lst(fy.words)} {lst(fy.sites)}')
txt = N.foryou_text(fy)
fy2 = N.foryou_parse(txt)
check(txt == 'rust\nmachine learning\n-crypto\n-site:medium.com' and lst(fy2.topics) == lst(fy.topics), f'and written back: {txt!r}')

u = urllib.parse.urlsplit(N.foryou_url(tbl(['rust', 'machine learning']), 1793070000, 0))
q = dict(urllib.parse.parse_qsl(u.query))
check(u.netloc == 'hn.algolia.com' and u.path == '/api/v1/search', f'Algolia search by relevance: {u.path}')
check(q.get('query') == 'rust "machine learning"' and q.get('optionalWords') == q.get('query'), f'all topics, each optional: {q.get("query")!r}')
check(q.get('advancedSyntax') == 'true' and q.get('tags') == 'story' and q.get('hitsPerPage') == '40' and q.get('page') == '0',
      'phrases, stories, 40 a page, page 0')
check(q.get('numericFilters') == 'created_at_i>1792897200,points>=10', f'the last 2 days, 10 points: {q.get("numericFilters")}')
check(q.get('attributesToHighlight') == '[]' and 'title' in q.get('attributesToRetrieve', ''), 'the same fields as the other lists')
q2 = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(N.foryou_url(tbl(['rust']), 1793070000, 2)).query))
check(q2.get('page') == '2', 'later pages')

row = lambda title, url=None: L.table_from({'title': title, 'url': url})
fym = N.foryou_parse('-crypto\n-site:medium.com')
check(N.muted(row('Crypto winter is here'), fym), 'a muted word in the title')
check(not N.muted(row('Cryptography for beginners'), fym), 'a muted word is a whole word')
check(N.muted(row('A post', 'https://news.medium.com/x'), fym) and N.muted(row('A post', 'https://medium.com/x'), fym), 'a muted site and its subdomains')
check(not N.muted(row('A post', 'https://notmedium.com/'), fym) and not N.muted(row('Ask HN: anything'), fym), 'not a look-alike site, not a story without a link')

found = lst(N.topics_in('Machine learning in Rust', tbl(['rust', 'machine learning', 'lua'])))
check(found == ['rust', 'machine learning'], f'the topics in a title: {found}')
check(lst(N.topics_in('Rusty machines', tbl(['rust', 'machine learning']))) == [], 'whole words only')
w = lst(N.title_words('The Rust compiler and the borrow checker: the Rust way'))
check(w == ['rust', 'compiler', 'borrow', 'checker', 'way'], f"a title's words for More like this: {w}")
w = lst(N.title_words('Show HN: AgentRun – open-source agents … for you'))
check('–' not in w and '…' not in w and 'agentrun' in w, f'a dash or an ellipsis on its own is not a word: {w}')

odd = N.foryou_parse('İstanbul|x"\n')
check(lst(odd.topics) == ['İstanbul|x"'], f'odd characters kept as they are (only A-Z lowered): {lst(odd.topics)}')
url = N.foryou_url(odd.topics, 1793070000, 0)
check(' ' not in url and '|' not in url and '"' not in url, 'and sent percent-encoded')
check(lst(N.foryou_parse(N.foryou_text(odd)).topics) == lst(odd.topics), 'and kept through foryou.txt')

print('\n' + ('all passed' if not fails else f'{len(fails)} FAILED'))
sys.exit(1 if fails else 0)
