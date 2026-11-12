"""Tests of the BLE MIDI simulator's packet encoder and piece events (no Bluetooth needed); the
packets are parsed back by the app's own Lua parser (apps/pianofollow/src/midi.lua, under lupa).

  python -I tools/piano/test_sim.py
"""
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import blemidi_sim as sim  # noqa: E402
from lupa import lua54  # noqa: E402

L = lua54.LuaRuntime(unpack_returned_tuples=True, encoding='latin-1')
M = L.execute(open(os.path.join(ROOT, 'apps', 'pianofollow', 'src', 'midi.lua'), encoding='utf-8').read())


def parse(packets):
    st, out = M.new(), []
    for p in packets:
        evs = M.feed(st, p.decode('latin-1'))
        for k in sorted(evs.keys()):
            e = evs[k]
            out.append((bool(e.on), int(e.note), int(e.vel)))
    return out


events = [(True, 60, 100), (True, 64, 90), (True, 67, 80), (False, 60, 0), (False, 64, 0), (False, 67, 0)] * 4
for packing in ('multi', 'single'):
    pk = sim.encode(events, 1234, packing)
    assert all(len(p) <= 20 for p in pk), packing
    assert parse(pk) == [(on, n, v if on else 0) for on, n, v in events], packing
assert len(sim.encode(events, 0, 'single')) == len(events)
assert len(sim.encode(events, 0, 'multi')) < len(events)

# piece events from a converted fixture
xt = os.path.join(ROOT, 'dist', 'piano', 'test', 'scale.xtscore')
if not os.path.exists(xt):
    subprocess.run(['node', os.path.join(HERE, 'test', 'make_fixture.mjs'), os.path.join(HERE, 'test', 'fixtures', 'scale.musicxml'), xt], check=True)
_h, _pages, pmap = sim.read_xtscore(xt)
ev = sim.piece_events(xt, bpm=120, wrong=0, skip=0, repeat_bar=0, seed=1)
ons = [n for t, on, n, v in ev if on]
assert ons == [p for o in pmap['onsets'] for p in o[5] + o[6]], ons[:10]
assert all(ev[i][0] <= ev[i + 1][0] for i in range(len(ev) - 1))
assert ev[0][0] == 0 and abs([t for t, on, n, v in ev if on and n == 62][0] - 500) < 1      # 120 bpm: a quarter is 500 ms
a = sim.piece_events(xt, bpm=90, wrong=0.1, skip=0.1, repeat_bar=2, seed=7)
b = sim.piece_events(xt, bpm=90, wrong=0.1, skip=0.1, repeat_bar=2, seed=7)
assert a == b and a != ev
rep = sim.piece_events(xt, bpm=120, wrong=0, skip=0, repeat_bar=2, seed=1)
assert len([1 for e in rep if e[1]]) == len(ons) + sum(len(o[5] + o[6]) for o in pmap['onsets'] if o[1] == 2)
# practising: a wrong note is followed by the right ones (the player corrects), so every pitch still comes
cor = sim.piece_events(xt, bpm=120, wrong=0.3, skip=0, repeat_bar=0, seed=4, correct=True)
right = [p for o in pmap['onsets'] for p in o[5] + o[6]]
got = [n for t, on, n, v in cor if on]
it = iter(got)
assert all(any(n == p for n in it) for p in right), 'every right note, in order'
assert len(got) > len(right)
print('sim ok')
