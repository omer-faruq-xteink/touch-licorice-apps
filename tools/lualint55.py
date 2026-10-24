"""Static checks for Lua that must run on the device's Lua 5.5 but is tested under Lua 5.4.

  python lualint55.py FILE.lua [...]

Catches what 5.4 lets through and the device rejects at compile time:
  - assignment to a for-loop control variable (const in Lua 5.5). Observed: an API 2.9 app with
    `para = para:gsub(...)` inside `for para in ...` died with "App error, closed" at launch;
    the same pattern had compiled on the API 0.8 host, so treat it as forbidden everywhere.
Exit code 1 when something is found.
"""
import re, sys

FOR_RE = re.compile(r'^\s*for\s+([\w\s,]+?)\s+(?:=|in)\b')


def check(path):
    problems = []
    lines = open(path, encoding='utf-8').read().split('\n')
    # crude block tracking: a `for ... do` opens a scope that ends at the matching `end`
    stack = []  # (loop vars, depth at open)
    depth = 0
    for no, line in enumerate(lines, 1):
        code = re.sub(r'--.*$', '', line)
        m = FOR_RE.match(code)
        if m:
            names = [n.strip() for n in m.group(1).split(',') if n.strip()]
            stack.append((names, depth))
        for names, _ in stack:
            for n in names:
                if re.search(r'(^|[^\w.:])' + re.escape(n) + r'\s*=[^=]', code) and not re.match(r'\s*local\b', code) \
                        and not FOR_RE.match(code):
                    problems.append(f'{path}:{no}: assignment to for-loop variable "{n}" (const in Lua 5.5)')
        depth += len(re.findall(r'\b(function|do|then|repeat)\b', code)) - len(re.findall(r'\b(end|until)\b', code))
        depth -= len(re.findall(r'\belseif\b', code))  # `elseif ... then` adds a `then` without a new block
        while stack and depth <= stack[-1][1]:
            stack.pop()
    return problems


if __name__ == '__main__':
    all_problems = []
    for p in sys.argv[1:]:
        all_problems += check(p)
    for p in all_problems:
        print(p)
    print('lualint55:', 'no problems' if not all_problems else f'{len(all_problems)} problem(s)')
    sys.exit(1 if all_problems else 0)
