"""Test of src/feeds.lua under Lua 5.4 (lupa): RSS 2.0, Atom and RSS 1.0 feeds, a feed cut short,
dates, OPML read and written, feed discovery, HTML to text.

  python -I apps/rss/test_feeds.py [FEED_FILE ...]     real feeds given are parsed too
"""
import os, sys
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
F = L.execute(open(os.path.join(HERE, 'src', 'feeds.lua'), encoding='utf-8').read())


def items(feed):
    return [feed['items'][i] for i in range(1, len(feed['items']) + 1)]


RSS = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
  <title>Example &amp; Co</title>
  <link>https://example.com/</link>
  <atom:link href="https://example.com/feed" rel="self"/>
  <item>
    <title><![CDATA[First <post>]]></title>
    <link>https://example.com/first</link>
    <guid isPermaLink="false">abc-1</guid>
    <pubDate>Wed, 30 Oct 2026 16:00:00 +0300</pubDate>
    <description>&lt;p&gt;Short &amp;amp; sweet&lt;/p&gt;</description>
    <content:encoded><![CDATA[<h2>Head</h2><p>Body text with <b>bold</b> and an image <img src="/pic.jpg" width="900" height="600"></p>]]></content:encoded>
  </item>
  <item>
    <title>Second</title>
    <link>/second</link>
    <pubDate>Tue, 29 Oct 2026 08:30:00 GMT</pubDate>
    <description>Plain summary</description>
  </item>
  <item>
    <title>Cut off</title>
    <link>https://example.com/cut</link>
    <description>this item never ends'''

ATOM = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title type="text">Atom Site</title>
  <link rel="self" href="https://atom.example/feed.xml"/>
  <link rel="alternate" href="https://atom.example/"/>
  <entry>
    <title>Entry one</title>
    <link rel="alternate" type="text/html" href="https://atom.example/one"/>
    <link rel="replies" href="https://atom.example/one#comments"/>
    <id>tag:atom.example,2026:1</id>
    <published>2026-10-30T13:00:00Z</published>
    <updated>2026-10-30T14:00:00Z</updated>
    <summary type="html">&lt;p&gt;Summary one&lt;/p&gt;</summary>
    <content type="html">&lt;p&gt;Full content one&lt;/p&gt;</content>
  </entry>
  <entry>
    <title>Entry two</title>
    <link href="https://atom.example/two"/>
    <id>tag:atom.example,2026:2</id>
    <updated>2026-10-29T10:00:00.000+02:00</updated>
  </entry>
</feed>'''

RDF = '''<?xml version="1.0"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel rdf:about="https://rdf.example/"><title>RDF Site</title><link>https://rdf.example/</link>
    <items><rdf:Seq><rdf:li resource="https://rdf.example/a"/></rdf:Seq></items></channel>
  <item rdf:about="https://rdf.example/a"><title>RDF item</title><link>https://rdf.example/a</link>
    <dc:date>2026-10-28T09:00:00+00:00</dc:date><description>About a</description></item>
</rdf:RDF>'''

f = F.parse_feed(RSS)
assert f['title'] == 'Example & Co' and f['link'] == 'https://example.com/', (f['title'], f['link'])
it = items(f)
assert len(it) == 2, 'the item cut off is left out'
assert it[0]['title'] == 'First <post>' and it[0]['id'] == 'abc-1' and it[0]['link'] == 'https://example.com/first'
assert it[0]['date'] == F.date('2026-10-30T13:00:00Z'), it[0]['date']
assert it[1]['link'] == 'https://example.com/second' and it[1]['id'] == 'https://example.com/second'
assert it[1]['date'] == F.date('2026-10-29T08:30:00Z')
assert F.excerpt(it[0]['summary'], 400) == 'Short & sweet', F.excerpt(it[0]['summary'], 400)
imgs = L.table()
text = F.html_to_text(it[0]['content'], 20000, imgs, it[0]['link'])
assert text.startswith('# Head\n\nBody text with bold and an image') and '[[img:1]]' in text, text
assert imgs[1]['n'] == 1 and imgs[1]['w'] == 456 and imgs[1]['h'] == 304, (imgs[1]['w'], imgs[1]['h'])
assert 'url=https%3A%2F%2Fexample.com%2Fpic.jpg' in imgs[1]['src'], imgs[1]['src']

a = F.parse_feed(ATOM)
ai = items(a)
assert a['title'] == 'Atom Site' and a['link'] == 'https://atom.example/'
assert ai[0]['link'] == 'https://atom.example/one' and ai[0]['id'] == 'tag:atom.example,2026:1'
assert ai[0]['date'] == F.date('2026-10-30T13:00:00Z') and F.excerpt(ai[0]['content'], 400) == 'Full content one'
assert ai[1]['link'] == 'https://atom.example/two' and ai[1]['date'] == F.date('2026-10-29T08:00:00Z')

r = F.parse_feed(RDF)
ri = items(r)
assert r['title'] == 'RDF Site' and len(ri) == 1 and ri[0]['title'] == 'RDF item' and ri[0]['date'] == F.date('2026-10-28T09:00:00Z')

assert F.parse_feed('<html><body>no</body></html>') is None or F.parse_feed('<html>')[0] is None
assert F.is_opml('<?xml version="1.0"?><opml version="2.0">') and not F.is_opml(RSS)

# dates: zones, two-digit years, no seconds
assert F.date('Thu, 01 Jan 1970 00:00:00 GMT') == 0
assert F.date('Sat, 31 Oct 2026 10:00 EST') == F.date('2026-10-31T15:00:00Z')
assert F.date('31 Oct 26 10:00:00 +0100') == F.date('2026-10-31T09:00:00Z')
assert F.date('2026-10-31') == F.date('2026-10-31T00:00:00Z') and F.date('nonsense') is None
assert F.format_date(F.date('2026-10-30T13:05:00Z'), 180) == '2026-10-30 16:05' and F.format_date(0, 0) == '1970-01-01 00:00'
assert F.format_date(F.date('2028-02-29T23:30:00Z'), 60) == '2028-03-01 00:30'

# OPML: folders (nested, as KOReader and others export them), attributes, written and read back
OPML = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="1.0"><head><title>My subscriptions</title></head><body>
  <outline text="News" title="News">
    <outline type="rss" text="BBC" xmlUrl="https://feeds.bbci.co.uk/news/rss.xml" htmlUrl="https://www.bbc.co.uk/news"/>
    <outline text="TR" title="TR">
      <outline type="rss" text="Q &amp; A" xmlUrl="https://qa.example/feed?a=1&amp;b=2"/>
    </outline>
  </outline>
  <outline type="rss" title="Loose" text="ignored" xmlUrl="https://loose.example/rss"/>
</body></opml>'''
o = F.parse_opml(OPML)
of = [o['feeds'][i] for i in range(1, len(o['feeds']) + 1)]
path = lambda f: list(f['path'].values())
assert o['title'] == 'My subscriptions' and len(of) == 3
assert of[0]['title'] == 'BBC' and path(of[0]) == ['News'] and of[0]['site'] == 'https://www.bbc.co.uk/news'
assert of[1]['title'] == 'Q & A' and of[1]['url'] == 'https://qa.example/feed?a=1&b=2' and path(of[1]) == ['News', 'TR']
assert of[2]['title'] == 'Loose' and path(of[2]) == []
w = F.write_opml('My feeds', o['feeds'])
o2 = F.parse_opml(w)
of2 = [o2['feeds'][i] for i in range(1, len(o2['feeds']) + 1)]
assert o2['title'] == 'My feeds' and [(x['title'], x['url'], path(x)) for x in of2] == [('Loose', 'https://loose.example/rss', []), ('BBC', 'https://feeds.bbci.co.uk/news/rss.xml', ['News']), ('Q & A', 'https://qa.example/feed?a=1&b=2', ['News', 'TR'])], w

# discovery: rss and atom links, relative addresses
HTML = '''<html><head><link rel="stylesheet" href="/s.css"><link rel="alternate" type="application/rss+xml" title="Posts" href="/feed/">
<link rel="alternate" type="application/atom+xml" href="https://site.example/atom.xml"></head><body></body></html>'''
d = F.discover(HTML, 'https://site.example/blog/post')
ds = [d[i] for i in range(1, len(d) + 1)]
assert [(x['url'], x['title']) for x in ds] == [('https://site.example/feed/', 'Posts'), ('https://site.example/atom.xml', None)], ds

assert F.hash('https://example.com/feed') == F.hash('https://example.com/feed') and len(F.hash('x')) == 8
assert F.hash('https://a') != F.hash('https://b')
print('feeds: made-up feeds, dates, OPML, discovery OK')

for path in sys.argv[1:]:
    body = open(path, 'rb').read()[:131072].decode('utf-8', 'replace')
    feed = F.parse_feed(body)
    its = items(feed) if feed else []
    dated = sum(1 for x in its if x['date'])
    full = sum(1 for x in its if x['content'])
    print(f'{os.path.basename(path)}: "{feed["title"] if feed else "?"}", {len(its)} items, {dated} dated, {full} with content')
    assert feed and its and all(x['title'] or x['link'] for x in its), path
print('feeds: all tests passed')
