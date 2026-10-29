"""Write store/STATUS.md from store/apps.json: what is in the Xteink store, at which version.

  python -I tools/store_status.py

store/apps.json holds one entry per app (keyed by its folder under apps/): the store's name, the
app_id the package carries, the listing and Studio project ids, the release version last
submitted, its status, the live version and the date. Update it after every submission or
review result, then run this script.
"""
import json, os

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPS = os.path.join(HERE, 'store', 'apps.json')
OUT = os.path.join(HERE, 'store', 'STATUS.md')

HEAD = """# Store status

What is in the [Xteink store](https://xtapp-ai.xteink.cc/store?view=creator), written by
`tools/store_status.py` from `store/apps.json` (edit that file, not this one).

## Releasing an update

1. Change the app, raise `version` in its `manifest.json`, run its tests, commit.
2. `python -I tools/store_export.py <app>` writes `dist/store/<app>/<app>.zip`. Keep the app's
   `app_id`: the store kept ours (checked on Mahjong's live package), and a new one would install
   as a different app without the saved data.
3. Studio: open the app's project (Studio project id below), More (...) > Import backup with the
   zip; the project keeps its id. Save.
4. Developer Center > the app > Release new version: a higher release version, release notes,
   new screenshots if the screens changed. Submit for review.
5. In `store/apps.json`: the new `release_version`, `status: "in review"`, `submitted`; after
   the review `status: "published"` and `live_version`. Run `tools/store_status.py`, commit.

## Apps

| app | store name | app_id | release | status | live | submitted | Studio project |
|---|---|---|---|---|---|---|---|
"""


def main():
    apps = json.load(open(APPS, encoding='utf-8'))
    order = sorted(apps.items(), key=lambda kv: (kv[1]['status'] != 'published', kv[1]['name'].lower()))
    rows = [f"| `{k}` | {a['name']} | `{a['app_id']}` | {a['release_version']} | {a['status']} | "
            f"{a.get('live_version') or '-'} | {a.get('submitted') or '-'} | `{a['project_id']}` |"
            for k, a in order]
    pub = sum(1 for a in apps.values() if a['status'] == 'published')
    tail = f"\n{pub} published, {len(apps) - pub} in review or draft, {len(apps)} in all.\n"
    open(OUT, 'w', encoding='utf-8', newline='\n').write(HEAD + '\n'.join(rows) + '\n' + tail)
    print(OUT)


if __name__ == '__main__':
    main()
