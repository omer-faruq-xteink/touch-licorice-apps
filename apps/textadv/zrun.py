"""Run a story file with the app's Z-machine (src/zmachine.lua) under Lua 5.4 (lupa): commands from
the command line or a file, output to stdout. For testing the interpreter against test programs
and real games.

  python -I apps/textadv/zrun.py STORY [COMMANDS_FILE | -c "cmd1;cmd2"] [--stats]
"""
import os, sys, time
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))


def load_machine(story_path):
    L = lua54.LuaRuntime(unpack_returned_tuples=True, encoding=None)
    Z = L.execute(open(os.path.join(HERE, 'src', 'zmachine.lua'), 'rb').read())
    story = open(story_path, 'rb').read()
    return L, Z, Z.new(story)


def play(story_path, commands, stats=False, out=sys.stdout.buffer, limit=2_000_000):
    L, Z, m = load_machine(story_path)
    saved = {}
    m.on_save = lambda s: saved.__setitem__('s', s) or True
    m.on_restore = lambda: saved.get('s')
    cmds = list(commands)
    total = 0
    t0 = time.time()
    while True:
        res = m.run(m, 20000)
        r, msg = (res if isinstance(res, tuple) else (res, None))
        r = r.decode() if isinstance(r, bytes) else r
        total += 20000 if r == 'more' else 0
        out.write(m.take_output(m))
        if r == 'more':
            if total > limit:
                out.write(b'\n[stopped: too many instructions]\n'); break
            continue
        if r == 'error':
            out.write(b'\n[ERROR] ' + (msg if isinstance(msg, bytes) else str(msg).encode()) + b'\n'); break
        if r == 'quit':
            out.write(b'\n[quit]\n'); break
        if r in ('input', 'char'):
            if m.v == 3 and r == 'input':
                left, right = m.status(m)
                out.write(b'[status: ' + left + b' | ' + right + b']\n')
            if not cmds:
                out.write(b'\n[end of commands]\n'); break
            c = cmds.pop(0)
            if r == 'char':
                m.send_char(m, ord(c[0]) if c else 13)
            else:
                out.write(b'> ' + c.encode() + b'\n')
                m.send_line(m, c.encode())
    if stats:
        out.write(f'\n[{time.time() - t0:.2f}s]\n'.encode())
    return m


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if a != '--stats']
    story = args[0]
    cmds = []
    if len(args) > 1:
        if args[1] == '-c':
            cmds = args[2].split(';')
        else:
            cmds = [l.rstrip('\n') for l in open(args[1], encoding='utf-8')]
    play(story, cmds, stats='--stats' in sys.argv)
