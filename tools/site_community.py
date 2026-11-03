"""Community apps for the site: GitHub repos with the topic licorice-ink-app and an inkapp.json at
their root (the format is on the site's developers page, site/developers/index.html). build_site.py
calls build(out), which writes community.json: the apps that passed the checks below, each with its
repo, owner, stars and last push. Nothing of theirs is copied: the site links to their packages and
shows their pictures from GitHub.

    python -I tools/site_community.py [--fixtures DIR]     (prints what it found)

With GITHUB_TOKEN set, the search uses it (the workflow passes its own); without, GitHub allows a few
anonymous searches, enough by hand. Any failure leaves the list empty or skips that repo: the site is
built anyway. --fixtures DIR reads DIR/<owner>__<repo>.json files instead (tests).

A repo or owner named in site/community-blocklist.txt is left out.
"""
import json, os, re, sys, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOPIC = 'licorice-ink-app'
FILE = 'inkapp.json'
OWN = 'omer-faruq-xteink/touch-licorice-apps'        # its apps are listed already
BLOCKLIST = os.path.join(ROOT, 'site', 'community-blocklist.txt')
DEVICES = ('X4 Pro', 'X4 Classic')
CATEGORIES = ('read', 'tools', 'learn', 'stories', 'daily', 'puzzles', 'games')
MAX_APPS = 20                                        # per repo
TIMEOUT = 20


def get(url, token=None):
    req = urllib.request.Request(url, headers={'User-Agent': 'touch-licorice-apps-site',
                                               'Accept': 'application/vnd.github+json'})
    if token and url.startswith('https://api.github.com/'):
        req.add_header('Authorization', 'Bearer ' + token)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read()


def search(token):
    """the repos with the topic: full_name, owner, default branch, stars, last push, description"""
    out, page = [], 1
    while page <= 5:
        q = urllib.parse.urlencode({'q': f'topic:{TOPIC} fork:true archived:false', 'per_page': 100, 'page': page})
        data = json.loads(get('https://api.github.com/search/repositories?' + q, token))
        out += data.get('items', [])
        if len(data.get('items', [])) < 100:
            break
        page += 1
    return out


def text(v, n):
    """a plain one-line string of at most n characters, or None"""
    if not isinstance(v, str):
        return None
    v = ' '.join(v.split())
    return v[:n] if v else None


def url_in(repo, branch, v, raw):
    """an https address, or a path in the repo made into one (raw: the file itself, for pictures and
    packages; else its page on GitHub)"""
    v = text(v, 300)
    if not v:
        return None
    if v.startswith('https://'):
        return v
    if ':' in v or v.startswith('/') or '..' in v.split('/'):
        return None
    path = urllib.parse.quote(v.lstrip('./'))
    return (f'https://raw.githubusercontent.com/{repo}/{branch}/{path}' if raw else
            f'https://github.com/{repo}/blob/{branch}/{path}')


def check_app(a, repo, branch):
    """one app of an inkapp.json, cleaned, or (None, reason)"""
    if not isinstance(a, dict):
        return None, 'not an object'
    app_id = text(a.get('app_id'), 40)
    name = text(a.get('name'), 40)
    version = text(a.get('version'), 20)
    if not app_id or not re.fullmatch(r'[a-z]+', app_id):
        return None, 'app_id must be lower-case letters'
    if not name or not version or not re.fullmatch(r'\d+(\.\d+){0,3}', version):
        return None, 'name and a dotted version (1.2.0) are needed'
    package = url_in(repo, branch, a.get('package'), raw=True)
    if not package or not urllib.parse.urlparse(package).path.endswith('.xtapp'):
        return None, 'package must be an https address or repo path of a .xtapp'
    devices = [d for d in a.get('devices') or [] if d in DEVICES]
    if not devices:
        return None, f'devices must name one of {", ".join(DEVICES)}'
    shots = [u for u in (url_in(repo, branch, s, raw=True) for s in (a.get('screenshots') or [])[:6]) if u]
    cat = a.get('category') if a.get('category') in CATEGORIES else 'tools'
    firmware = text(a.get('firmware'), 12)
    return {
        'app_id': app_id, 'name': name, 'version': version,
        'summary': text(a.get('description'), 200) or '',
        'devices': devices, 'category': cat,
        'firmware': firmware if firmware and re.fullmatch(r'\d{8}', firmware) else None,
        'package': package,
        'icon': url_in(repo, branch, a.get('icon'), raw=True),
        'screenshots': shots,
        'homepage': url_in(repo, branch, a.get('homepage'), raw=False) or f'https://github.com/{repo}',
        'license': text(a.get('license'), 30),
    }, None


def check_file(data, item):
    """the apps of one repo's inkapp.json, and the problems found"""
    repo, branch = item['full_name'], item.get('default_branch') or 'main'
    if not isinstance(data, dict) or data.get('format') != 1 or not isinstance(data.get('apps'), list):
        return [], ['not format 1 with an "apps" list']
    apps, problems = [], []
    for i, a in enumerate(data['apps'][:MAX_APPS]):
        app, why = check_app(a, repo, branch)
        if app:
            app.update(repo=repo, owner=item['owner']['login'], stars=item.get('stargazers_count', 0),
                       pushed=(item.get('pushed_at') or '')[:10])
            apps.append(app)
        else:
            problems.append(f'app {i + 1}: {why}')
    return apps, problems


def blocked():
    if not os.path.exists(BLOCKLIST):
        return set()
    return {l.split('#')[0].strip().lower() for l in open(BLOCKLIST, encoding='utf-8') if l.split('#')[0].strip()}


def collect(fixtures=None, log=print):
    token = os.environ.get('GITHUB_TOKEN') or os.environ.get('GH_TOKEN')
    block = blocked()
    if fixtures:
        found = []
        for f in sorted(os.listdir(fixtures)):
            if f.endswith('.json'):
                owner, name = f[:-5].split('__', 1)
                found.append(({'full_name': f'{owner}/{name}', 'owner': {'login': owner}, 'default_branch': 'main',
                               'stargazers_count': 0, 'pushed_at': ''}, os.path.join(fixtures, f)))
    else:
        try:
            found = [(item, None) for item in search(token)]
        except Exception as e:  # noqa: BLE001 — no community list is better than no site
            log(f'community: search failed: {e}')
            return []
    apps, seen = [], set()
    for item, path in found:
        repo = item['full_name']
        if repo.lower() == OWN or repo.lower() in block or item['owner']['login'].lower() in block:
            continue
        try:
            if path:
                data = json.load(open(path, encoding='utf-8'))
            else:
                branch = item.get('default_branch') or 'main'
                data = json.loads(get(f'https://raw.githubusercontent.com/{repo}/{branch}/{FILE}'))
        except Exception as e:  # noqa: BLE001
            log(f'community: {repo}: no readable {FILE} ({e})')
            continue
        got, problems = check_file(data, item)
        for p in problems:
            log(f'community: {repo}: {p}')
        for a in got:
            key = (a['repo'].lower(), a['app_id'])
            if key not in seen:
                seen.add(key)
                apps.append(a)
    apps.sort(key=lambda a: (-a['stars'], a['name'].lower()))
    return apps


def build(out, fixtures=None, log=print):
    apps = collect(fixtures, log)
    with open(os.path.join(out, 'community.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'topic': TOPIC, 'apps': apps}, f, ensure_ascii=False, indent=1)
    return len(apps)


if __name__ == '__main__':
    fx = sys.argv[sys.argv.index('--fixtures') + 1] if '--fixtures' in sys.argv else None
    for a in collect(fx):
        print(f"{a['repo']}: {a['name']} {a['version']} ({', '.join(a['devices'])})")
