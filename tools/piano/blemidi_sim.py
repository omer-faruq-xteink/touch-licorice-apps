"""A Bluetooth MIDI keyboard on the PC, for testing Piano Follow without one.

The PC's Bluetooth advertises the BLE MIDI service (Windows GATT server through the winrt bindings);
the reader finds it by that service, under the PC's Bluetooth name, and connects to it like a keyboard. Notes come from a USB MIDI keyboard plugged into the PC, or from a piece's note map
(a .xtscore file) played at a tempo, optionally with mistakes.

  python -m venv tools/piano/.venv && tools/piano/.venv/Scripts/pip install -r tools/piano/requirements.txt
  (then run it with tools/piano/.venv/Scripts/python)
  python tools/piano/blemidi_sim.py --probe                    advertise only; shows connections
  python tools/piano/blemidi_sim.py --keyboard [PORT]          forward a USB MIDI keyboard (first port by default)
  python tools/piano/blemidi_sim.py --piece FILE.xtscore --bpm 80 [--wrong 0.05] [--skip 0.05]
         [--repeat-bar N] [--seed 1] [--packing multi|single] [--wait 10 | --trigger FILE]

encode() and piece_events() need no Bluetooth (tools/piano/test_sim.py tests them).
"""
import argparse, asyncio, json, os, random, struct, sys, time, zlib

SVC = '03b80e5a-ede8-4b33-a751-6ce34ec4c700'
CHR = '7772e5db-3868-4112-a1a9-f2669d106bf3'
MAX_PACKET = 20                     # ATT MTU 23 - 3: what every central accepts


# ------------------------------------------------------------------ packets
def encode(events, ts_ms, packing='multi'):
    """events: [(on, note, vel)] sent at one time -> BLE MIDI packets (bytes). 'multi' packs as many
    messages as fit, with running status (timestamp byte + data); 'single' one message a packet.
    Note-offs go as note-on with velocity 0, so running status carries through."""
    hdr = 0x80 | ((ts_ms >> 7) & 0x3F)
    tsb = 0x80 | (ts_ms & 0x7F)
    packets, cur, running = [], None, None
    for on, note, vel in events:
        status, data = 0x90, bytes([note & 0x7F, (vel if on else 0) & 0x7F])
        if packing == 'single':
            packets.append(bytes([hdr, tsb, status]) + data)
            continue
        msg = (bytes([tsb]) + data) if (cur and running == status) else (bytes([tsb, status]) + data)
        if cur is None or len(cur) + len(msg) > MAX_PACKET:
            if cur:
                packets.append(bytes(cur))
            cur = bytearray([hdr])
            msg = bytes([tsb, status]) + data
        cur += msg
        running = status
    if cur:
        packets.append(bytes(cur))
    return packets


# ------------------------------------------------------------------ pieces
def read_xtscore(path):
    b = open(path, 'rb').read()
    if b[:8] != b'XTSCORE1':
        raise ValueError('not a .xtscore file')
    n = struct.unpack('<I', b[8:12])[0]
    h = json.loads(b[12:12 + n])
    pages = [zlib.decompress(b[o:o + l]) for o, l in h['pages']]
    mo, ml = h['map']
    return h, pages, json.loads(zlib.decompress(b[mo:mo + ml]))


def piece_events(path, bpm=80, wrong=0.0, skip=0.0, repeat_bar=0, seed=1, correct=False):
    """the note map played at bpm -> [(t_ms, on, note, vel)] sorted by time; with probability `skip`
    an onset is left out, with `wrong` it is replaced by one wrong note; bar `repeat_bar` (1-based)
    is played twice in a row (as a player starting a bar again); with `correct` a wrong note is
    followed by the right ones (as when practising)."""
    _h, _p, m = read_xtscore(path)
    on = m['onsets']
    q = 60000.0 / bpm
    order = list(range(len(on)))
    if repeat_bar:
        idx = [i for i in order if on[i][1] == repeat_bar]
        if idx:
            k = order.index(idx[-1]) + 1
            order = order[:k] + idx + order[k:]
    rnd = random.Random(seed)
    events, t, prev_q = [], 0.0, None
    for n, i in enumerate(order):
        o = on[i]
        if prev_q is not None:
            step = o[0] - prev_q
            t += (step if step > 0 else 1) * q
        prev_q = o[0]
        nxt = on[order[n + 1]][0] if n + 1 < len(order) else o[0] + 1
        dur = max(0.25, (nxt - o[0]) if nxt > o[0] else 1) * q * 0.8
        r = rnd.random()
        if r < skip:
            continue
        pitches = o[5] + o[6]
        start = t
        if r < skip + wrong:
            bad = rnd.randrange(30, 100)
            if correct:                             # the slip, then the right notes a moment later
                events.append((round(t), True, bad, 80))
                events.append((round(t + q * 0.2), False, bad, 0))
                start = t + q * 0.3
            else:
                pitches = [bad]
        for p in pitches:
            events.append((round(start), True, p, 80))
            events.append((round(start + dur), False, p, 0))
    events.sort(key=lambda e: (e[0], e[1]))           # offs before ons at the same time
    return events


# ------------------------------------------------------------------ Bluetooth (Windows GATT server)
async def serve(source, packing):
    import uuid
    from winrt.windows.devices.bluetooth import BluetoothAdapter
    from winrt.windows.devices.bluetooth.genericattributeprofile import (
        GattServiceProvider, GattLocalCharacteristicParameters, GattCharacteristicProperties as Prop,
        GattProtectionLevel, GattServiceProviderAdvertisingParameters)
    from winrt.windows.storage.streams import DataWriter

    adapter = await BluetoothAdapter.get_default_async()
    if not adapter or not adapter.is_peripheral_role_supported:
        raise SystemExit("this PC's Bluetooth cannot act as a peripheral (see the fallback in the design)")
    res = await GattServiceProvider.create_async(uuid.UUID(SVC))
    provider = res.service_provider
    params = GattLocalCharacteristicParameters()
    params.characteristic_properties = Prop.READ | Prop.NOTIFY | Prop.WRITE_WITHOUT_RESPONSE
    params.read_protection_level = GattProtectionLevel.PLAIN
    params.write_protection_level = GattProtectionLevel.PLAIN
    cres = await provider.service.create_characteristic_async(uuid.UUID(CHR), params)
    char = cres.characteristic

    def on_read(_c, args):                                 # BLE MIDI: a read returns an empty value
        deferral = args.get_deferral()

        async def reply():
            req = await args.get_request_async()
            req.respond_with_value(DataWriter().detach_buffer())
            deferral.complete()
        asyncio.run_coroutine_threadsafe(reply(), loop)

    def on_clients(c, _a):
        print(f'subscribed clients: {len(c.subscribed_clients)}', flush=True)

    loop = asyncio.get_running_loop()
    char.add_read_requested(on_read)
    char.add_subscribed_clients_changed(lambda c, a: loop.call_soon_threadsafe(on_clients, c, a))
    adv = GattServiceProviderAdvertisingParameters()
    adv.is_connectable = True
    adv.is_discoverable = True
    provider.start_advertising(adv)
    print("advertising the BLE MIDI service (the reader lists it under this PC's Bluetooth name). "
          'On the reader: Keyboard > Search.')
    t0 = time.monotonic()
    pending = []

    async def notify(buf):
        await char.notify_value_async(buf)

    def send(events):
        ts = int((time.monotonic() - t0) * 1000) & 0x1FFF
        for pkt in encode(events, ts, packing):
            w = DataWriter()
            w.write_bytes(pkt)
            pending.append(asyncio.ensure_future(notify(w.detach_buffer())))

    try:
        await source(send)
    finally:
        provider.stop_advertising()


async def probe(send):
    while True:
        await asyncio.sleep(5)
        print('still advertising ...')


def keyboard_source(port):
    async def run(send):
        import mido
        names = mido.get_input_names()
        if not names:
            raise SystemExit('no MIDI input: plug in the keyboard')
        name = port or names[0]
        print('forwarding', name)
        with mido.open_input(name) as inp:
            while True:
                batch = []
                for msg in inp.iter_pending():
                    if msg.type == 'note_on':
                        batch.append((msg.velocity > 0, msg.note, msg.velocity))
                    elif msg.type == 'note_off':
                        batch.append((False, msg.note, 0))
                if batch:
                    send(batch)
                    for on, n, v in batch:
                        print(('on ' if on else 'off'), n)
                await asyncio.sleep(0.005)
    return run


_SOUND = None


def sound_out(enabled):
    """the PC's own MIDI synthesizer (Windows: Microsoft GS Wavetable Synth), so the notes can be heard"""
    global _SOUND
    if enabled and _SOUND is None:
        import mido
        names = mido.get_output_names()
        if names:
            _SOUND = mido.open_output(names[0])
            print('sound:', names[0], flush=True)
    return _SOUND


async def play(send, ev):
    start = time.monotonic()
    k = 0
    while k < len(ev):
        t = ev[k][0]
        batch = []
        while k < len(ev) and ev[k][0] == t:
            batch.append(ev[k][1:])
            k += 1
        await asyncio.sleep(max(0, start + t / 1000 - time.monotonic()))
        send(batch)
        if _SOUND is not None:
            import mido
            for on, n, v in batch:
                _SOUND.send(mido.Message('note_on', note=n, velocity=v if on else 0))


def piece_source(args):
    async def run(send):
        ev = piece_events(args.piece, args.bpm, args.wrong, args.skip, args.repeat_bar, args.seed)
        if args.trigger:
            # stay up (the reader keeps its connection) and play each time the trigger file appears;
            # the file may hold options for that run (--piece, --bpm, --wrong, --skip, --repeat-bar, --seed)
            print(f'{len(ev) // 2} notes; waiting for {args.trigger}')
            while True:
                if os.path.exists(args.trigger):
                    opts = open(args.trigger, encoding='utf-8').read().split()
                    os.remove(args.trigger)
                    try:
                        run_args = argparse.Namespace(**vars(args))
                        sound_out(True) if '--sound' in opts and opts[opts.index('--sound') + 1] == '1' else None
                        for k in range(0, len(opts) - 1, 2):
                            key = opts[k].lstrip('-').replace('-', '_')
                            cur = getattr(run_args, key, None)
                            setattr(run_args, key, type(cur)(opts[k + 1]) if cur is not None else opts[k + 1])
                        e = piece_events(run_args.piece, run_args.bpm, run_args.wrong, run_args.skip, run_args.repeat_bar, run_args.seed,
                                         str(run_args.correct) in ('1', 'True', 'yes'))
                    except Exception as err:                 # a bad trigger: say so, stay up
                        print(f'error in the trigger options {opts}: {err}', flush=True)
                        continue
                    print(f'playing {os.path.basename(run_args.piece)} at {run_args.bpm} bpm, wrong {run_args.wrong}, '
                          f'skip {run_args.skip}, repeat bar {run_args.repeat_bar} ({len(e) // 2} notes)', flush=True)
                    await play(send, e)
                    print('done', flush=True)
                await asyncio.sleep(0.5)
        print(f'{len(ev) // 2} notes; starting in {args.wait} s (open the piece on the reader)')
        await asyncio.sleep(args.wait)
        await play(send, ev)
        print('done')
        await asyncio.sleep(3)
    return run


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--probe', action='store_true')
    g.add_argument('--keyboard', nargs='?', const='', metavar='PORT')
    g.add_argument('--piece', metavar='FILE')
    ap.add_argument('--bpm', type=float, default=80.0)
    ap.add_argument('--wrong', type=float, default=0.0)
    ap.add_argument('--skip', type=float, default=0.0)
    ap.add_argument('--repeat-bar', type=int, default=0)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--packing', choices=('multi', 'single'), default='multi')
    ap.add_argument('--wait', type=float, default=10)
    ap.add_argument('--trigger', metavar='FILE', help='with --piece: stay up and play whenever FILE appears')
    ap.add_argument('--correct', type=int, default=0, help='1: a wrong note is followed by the right ones (practice)')
    ap.add_argument('--sound', type=int, default=0, help='1: also play the notes on the PC (its MIDI synthesizer)')
    args = ap.parse_args()
    if args.sound:
        sound_out(True)
    if args.probe:
        src = probe
    elif args.keyboard is not None:
        src = keyboard_source(args.keyboard or None)
    else:
        src = piece_source(args)
    try:
        asyncio.run(serve(src, args.packing))
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
