"""Port Wren's text (game/text.lua): every sentence is made from the truth of the case, so the times and
places it names are the ones in the facts; statements read back to the suspects' accounts; no gore;
every template varies.

  python -I apps/portwren/test_text.py
"""
import os, re
from collections import defaultdict
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("T = require('game.text'); R = require('game.rng'); W = require('game.town')(T, R); G = require('game.gen')(T, R, W)")
T, G, Wn, Rn = L.eval('T'), L.eval('G'), L.eval('W'), L.eval('R')


def py(v):
    return {k: py(x) for k, x in v.items()} if lua54.lua_type(v) == 'table' else v


def lst(d):
    return [d[k] for k in sorted(d)] if isinstance(d, dict) else []


def strs(t):
    return [str(x) for x in lst(py(t))]


# every clock phrase from six in the evening to midnight, and back to minutes
PHRASES = {}
for m in range(18 * 60, 24 * 60 + 1, 30):
    PHRASES[str(T.clock(m))] = m
TIME_RX = re.compile('|'.join(sorted((re.escape(p) for p in PHRASES), key=len, reverse=True)))
PLACE_NAMES = {str(T.PLACES[k].name): str(k) for k in T.PLACES.keys()}
PLACE_RX = re.compile('|'.join(sorted((re.escape(p) for p in PLACE_NAMES), key=len, reverse=True)))
BANNED = ['blood', 'gore', 'stab wound', "corpse's", 'gash', 'entrails']
by_tpl = defaultdict(set)
fails = []


def check(ok, what):
    if not ok:
        fails.append(what)


def parse_statement(lines):
    """slot -> place key, back from 'From X until Y I was at P.' and 'At X I was at P.' lines"""
    out = {}
    for line in lines:
        m = re.match(rf'From ({TIME_RX.pattern}) until ({TIME_RX.pattern}),? I was at ({PLACE_RX.pattern})\.', line)
        if m:
            a, b, pl = PHRASES[m.group(1)], PHRASES[m.group(2)], PLACE_NAMES[m.group(3)]
            for mm in range(a, b, 30):
                out[mm] = pl
            continue
        m = re.match(rf'At ({TIME_RX.pattern}),? I was at ({PLACE_RX.pattern})\.', line)
        if m:
            out[PHRASES[m.group(1)]] = PLACE_NAMES[m.group(2)]
    return out


n = 0
for seed in range(1, 301):
    tw = Wn.make(2000 + seed % 11, 'career')
    size = 'long' if seed % 2 else 'short'
    pattern = ['classic', 'alibi', 'timeline', 'liar' if size == 'long' else 'classic'][seed % 4]
    cl = G.new_case(tw, L.table_from({'seed': seed, 'size': size, 'pattern': pattern, 'no': seed}))
    if seed % 5 == 0:
        sus = py(cl.suspects)
        G.strike(tw, cl, seed, next(p for p in lst(sus) if p != cl.killer))
    c = py(cl)
    r = Rn.new(seed)
    texts = []
    for clue in lst(c['clues']):
        s = str(T.clue(cl, tw, cl.clues[clue['id']], r))
        texts.append(s)
        by_tpl[clue['tpl']].add(re.sub(r'[A-Z][a-z]+ [A-Z][a-z]+', 'NAME', s))
        facts = lst(clue['facts'])
        slots = {f.get('slot') for f in facts} | {f.get('lo') for f in facts} | {f.get('hi') for f in facts}
        allowed_times = {str(T.time(x)) for x in slots if x}
        sp = clue['vars'].get('span')
        if sp:
            allowed_times |= {str(T.time(sp['lo'])), str(T.clock(int(T.minutes(sp['hi'])) + 30))}
        for ph in TIME_RX.findall(s):
            check(ph in allowed_times, f'seed {seed} clue {clue["id"]} ({clue["tpl"]}): time "{ph}" not in {allowed_times}: {s}')
        allowed_places = {f.get('place') for f in facts} | {clue['gate'].get('place')}
        for pn in PLACE_RX.findall(s):
            check(PLACE_NAMES[pn] in allowed_places, f'seed {seed} clue {clue["id"]} ({clue["tpl"]}): place "{pn}": {s}')
    for pid in lst(c['suspects']):
        lines = strs(T.statement(cl, tw, pid, False))
        texts += lines
        got = parse_statement(lines)
        want = {int(T.minutes(t)): c['says'][pid][t] for t in range(1, 13)}
        check(got == want, f'seed {seed}: statement of {pid} reads back wrong: {lines} vs {want}')
        if c.get('night2'):
            lines = strs(T.statement(cl, tw, pid, True))
            got = parse_statement(lines)
            want = {int(T.minutes(t)): c['says'][pid][t] for t in range(13, 19)}
            check(got == want, f'seed {seed}: night statement of {pid}: {lines}')
    people = lst(c['suspects']) + lst(c['witnesses'])
    for pid in people:
        texts.append(str(T.greet(cl, tw, pid, r)))
        for topic in strs(T.topics(cl, tw, pid)):
            texts.append(str(T.answer(cl, tw, pid, topic, r)))
        for clue in lst(c['clues'])[:4]:
            texts.append(str(T.react(cl, tw, pid, cl.clues[clue['id']], r)))
    texts += strs(T.account(cl, tw)) + strs(T.intro(cl, tw)) + [str(T.gossip(tw, r))]
    for s in texts:
        n += 1
        check('{' not in s and '}' not in s and 'nil' not in s.split(), f'seed {seed}: a placeholder left: {s}')
        check(not any(b in s.lower() for b in BANNED), f'seed {seed}: a banned word: {s}')
        check(s.strip() != '', f'seed {seed}: an empty line')

for tpl, seen in sorted(by_tpl.items()):
    check(len(seen) >= 3, f'template {tpl} has {len(seen)} distinct forms')

# a question of time: the clue that puts the killer at the scene names only the doctor's window,
# so the exact time still has to come from the time clues
for seed in range(1, 201):
    tw = Wn.make(4000 + seed % 9, 'career')
    size = 'long' if seed % 2 else 'short'
    cl = G.new_case(tw, L.table_from({'seed': seed, 'size': size, 'pattern': 'timeline', 'no': 1}))
    c = py(cl)
    if c['pattern'] != 'timeline':
        continue
    k, s_, lo, hi = c['killer'], c['slot'], c['window']['lo'], c['window']['hi']
    window_words = {str(T.time(lo)), str(T.clock(int(T.minutes(hi)) + 30))}
    for clue in lst(c['clues']):
        if any(f['t'] == 'at' and f['who'] == k and f['slot'] == s_ and f['place'] == c['scene'] for f in lst(clue['facts'])):
            txt = str(T.clue(cl, tw, cl.clues[clue['id']], None))
            found_times = set(TIME_RX.findall(txt))
            check(found_times <= window_words and found_times, f'seed {seed}: the decisive clue tells the exact time: {txt}')
    for t in range(lo, hi + 1):
        check(c['says'][k][t] != c['scene'], f'seed {seed}: the killer admits the scene inside the window')

# short names are told apart: the topics of one talk, and everyone of the case
labels_bad = 0
for seed in range(1, 301):
    tw = Wn.make(3000 + seed % 13, 'career')
    cl = G.new_case(tw, L.table_from({'seed': seed, 'size': 'long', 'pattern': 'classic', 'no': 1}))
    c = py(cl)
    everyone = lst(c['suspects']) + lst(c['witnesses']) + [c['victim']]
    shorts = [str(T.short_name(cl, tw, p)) for p in everyone]
    if len(set(shorts)) != len(set(everyone)):
        labels_bad += 1
    for pid in lst(c['suspects']):
        labels = [str(T.topic_label(cl, tw, t)) for t in strs(T.topics(cl, tw, pid))]
        check(len(labels) == len(set(labels)), f'seed {seed}: topics share a label: {labels}')
check(labels_bad == 0, f'{labels_bad} cases where two people get the same short name')

# times as words
assert str(T.clock(18 * 60)) == "six o'clock" and str(T.clock(24 * 60)) == 'midnight' and str(T.clock(20 * 60 + 30)) == 'half past eight'
for f in fails[:15]:
    print('FAIL', f)
assert not fails, f'{len(fails)} failures'
print(f'text: all tests passed ({n} sentences, {len(by_tpl)} templates)')
