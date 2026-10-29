"""Pull the Markdown documents embedded as JS string literals out of the docs bundle (text only, nothing executed)."""
import sys, re, os

s = open(sys.argv[1], encoding='utf-8').read()
os.makedirs('en', exist_ok=True)
os.makedirs('zh', exist_ok=True)
BS = chr(92)
esc = {'n': '\n', 't': '\t', 'r': '', BS: BS}
out = []
for m in re.finditer(r"[=:,(]\s*(['\"`])(# )", s):
    q = m.group(1)
    i = m.start(2)
    buf = []
    while i < len(s):
        c = s[i]
        if c == BS:
            n = s[i + 1]
            if n == 'u':
                buf.append(chr(int(s[i + 2:i + 6], 16)))
                i += 6
                continue
            buf.append(esc.get(n, n))
            i += 2
            continue
        if c == q:
            break
        buf.append(c)
        i += 1
    t = ''.join(buf)
    if len(t) < 200:
        continue
    title = t.split('\n', 1)[0][2:].strip()
    ratio = sum(ch < 'Ā' for ch in t) / len(t)
    lang = 'en' if ratio > 0.97 else 'zh'
    name = re.sub(r'[^A-Za-z0-9]+', '-', title).strip('-')[:60] or 'doc'
    p = f'{lang}/{name}.md'
    k = 2
    while os.path.exists(p):
        p = f'{lang}/{name}-{k}.md'
        k += 1
    open(p, 'w', encoding='utf-8').write(t)
    out.append((lang, p, len(t), title))
en = [o for o in out if o[0] == 'en']
print(len(out), 'docs,', len(en), 'English')
for o in en:
    print(o[2], o[1])
