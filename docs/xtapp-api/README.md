# XTApp API docs (local only)

The official XTApp / Ink App documentation (https://xtapp-ai.xteink.cc/docs, contract
api-2.17.0) is kept here for working on the apps: `INDEX.md`, `en/` and `zh/` (the Chinese text
is authoritative). The site is invite-only, so those files are **not committed** (see
`.gitignore`); only this note and `extract_docs.py` are.

To refresh them: save the docs page's JS bundles from the browser (signed in), then

    python -I extract_docs.py <bundle.js>

in this folder writes the Markdown documents to `en/` and `zh/`. The script only reads the
bundle's string literals; it runs nothing from it.

What the docs say and what the store does can differ: `docs` claims a first submission issues a
new `app_id` ("u-xxxxxxxx"), but the live packages kept ours (see `store/STATUS.md`).
