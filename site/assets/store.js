// The reader's SD card in the browser: with the reader in USB mode, the page asks once for the card
// (or a folder on it) through the File System Access API (Chrome and Edge on a computer), copies
// packages there and reads which apps are installed. Installing stays on the reader: All Files, the
// package, Install. Browsers cannot reach the reader by USB themselves (WebUSB leaves storage alone),
// so without the API a page only offers the download.

import { esc, count } from './site.js';

const USB = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" ' +
  'stroke-linejoin="round"><rect x="6" y="2" width="12" height="20" rx="2.5"/><path d="M9 6h6M9 9.5h6M9 13h4"/>' +
  '<circle cx="12" cy="18" r="1"/></svg>';

export const canCopy = typeof window !== 'undefined' && 'showDirectoryPicker' in window;

// the chosen folder is kept in IndexedDB, so the next visit only has to confirm the permission
const DB = 'touch-licorice', KV = 'kv', KEY = 'card';
function idb(mode, fn) {
  return new Promise((ok, fail) => {
    const open = indexedDB.open(DB, 1);
    open.onupgradeneeded = () => open.result.createObjectStore(KV);
    open.onerror = () => fail(open.error);
    open.onsuccess = () => {
      const tx = open.result.transaction(KV, mode);
      const req = fn(tx.objectStore(KV));
      tx.oncomplete = () => ok(req && req.result);
      tx.onerror = () => fail(tx.error);
    };
  });
}
const saved = () => idb('readonly', (s) => s.get(KEY)).catch(() => null);
const save = (h) => idb('readwrite', (s) => s.put(h, KEY)).catch(() => null);
const forget = () => idb('readwrite', (s) => s.delete(KEY)).catch(() => null);

async function child(dir, name) {
  try { return await dir.getDirectoryHandle(name); } catch { return null; }
}

// the manifest of a package: offset and length at 0x10 of its header, then plain JSON
export function packageManifest(bytes) {
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const off = v.getUint32(0x10, true), n = v.getUint32(0x14, true);
  return JSON.parse(new TextDecoder().decode(bytes.subarray(off, off + n)));
}

// installed apps: XTApps/<app_id>/ on the card, with the version from its manifest.json or its package
async function installed(root) {
  const out = new Map();
  const apps = await child(root, 'XTApps');
  if (!apps) return null;
  for await (const [name, h] of apps.entries()) {
    if (h.kind !== 'directory') continue;
    let version = '';
    try {
      for await (const [fname, fh] of h.entries()) {
        if (fh.kind !== 'file') continue;
        if (fname === 'manifest.json') {
          version = JSON.parse(await (await fh.getFile()).text()).version || version;
          break;
        }
        if (fname.endsWith('.xtapp')) {
          const f = await fh.getFile();
          version = packageManifest(new Uint8Array(await f.slice(0, 4096).arrayBuffer())).version || version;
        }
      }
    } catch { /* an unreadable folder: listed without a version */ }
    out.set(name, version);
  }
  return out;
}

// dotted versions: 1.10.0 is newer than 1.9.2
export function newer(a, b) {
  const x = String(a).split('.').map(Number), y = String(b).split('.').map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] || 0) - (y[i] || 0);
    if (d) return d > 0;
  }
  return false;
}

export const card = {
  handle: null,
  apps: null,          // Map app_id -> version, or null when the folder is not the card's root
  listeners: new Set(),
  changed() { for (const f of this.listeners) f(); },

  async restore() {
    if (!canCopy) return;
    const h = await saved();
    if (h && (await h.queryPermission({ mode: 'readwrite' })) === 'granted') await this.use(h);
    else if (h) { this.pending = h; this.changed(); }
  },
  async connect() {
    let h = this.pending;
    if (h && (await h.requestPermission({ mode: 'readwrite' })) === 'granted') return this.use(h);
    h = await window.showDirectoryPicker({ id: 'xteink-card', mode: 'readwrite' });
    if (h.name === 'XTApps' || h.name === 'AppFiles')
      throw new Error(`That is the card's ${h.name} folder. Choose the card itself, or another folder on it.`);
    await save(h);
    return this.use(h);
  },
  async use(h) {
    this.handle = h;
    this.pending = null;
    this.apps = await installed(h);
    this.changed();
  },
  async disconnect() {
    this.handle = this.apps = this.pending = null;
    await forget();
    this.changed();
  },
  async copy(root, app) {
    const res = await fetch(root + 'packages/' + app.file, { cache: 'no-cache' });
    if (!res.ok) throw new Error(`could not download ${app.file} (${res.status})`);
    const bytes = new Uint8Array(await res.arrayBuffer());
    const fh = await this.handle.getFileHandle(app.file, { create: true });
    const w = await fh.createWritable();
    await w.write(bytes);
    await w.close();
  },
  state(app) {
    if (!this.apps) return null;
    const v = this.apps.get(app.app_id);
    if (v === undefined) return null;
    if (v && newer(app.version, v)) return { label: `Update: ${v} → ${app.version}`, update: true };
    return { label: v ? `Installed ${v}` : 'Installed', current: true };
  },
};

// the panel that connects the card; apps: the ids this page offers (one on an app page, all on the
// home page), whose .copy buttons and .status lines it keeps up to date
export async function readerPanel(el, root, ids, catalog) {
  catalog = catalog || await fetch(root + 'catalog.json', { cache: 'no-cache' }).then((r) => r.json());
  const byId = new Map(catalog.apps.map((a) => [a.id, a]));
  const msg = document.createElement('p');
  msg.className = 'msg';
  const single = ids.length === 1;      // an app's own page: its buttons stay prominent
  const copied = new Set();

  function render() {
    let cls = '', title, text, acts = '';
    if (!canCopy) {
      title = 'Download, then copy to the reader';
      text = 'Chrome or Edge on a computer can copy apps straight to the reader. Here, download the <code>.xtapp</code> and ' +
        'copy it to the SD card with the reader in USB mode.';
    } else if (card.handle) {
      cls = ' on';
      const updates = ids.map((id) => byId.get(id)).filter((a) => a && card.state(a)?.update);
      // the card's root (it holds XTApps/) is named just "\" by the browser
      const name = card.apps ? 'SD card' : card.handle.name;
      title = `Reader connected <span class="note">· ${esc(name)}</span>`;
      text = card.apps ? `${card.apps.size} apps installed` +
        (updates.length ? `, <b>${updates.length} with an update</b>.` : ', all up to date.') :
        'A folder on the card: choose the card itself to see which apps are installed.';
      if (updates.length > 1) acts += `<button type="button" class="get primary all">Update all (${updates.length})</button>`;
      acts += '<button type="button" class="get disconnect">Disconnect</button>';
    } else {
      title = 'Install straight from this page';
      text = 'Put the reader in USB mode and connect it to this computer, then choose its SD card. Apps are copied there, ' +
        'and the page shows what is installed and what has an update.';
      acts = `<button type="button" class="get primary connect">${card.pending ? 'Reconnect the reader' : 'Connect the reader'}</button>`;
    }
    el.innerHTML = `<div class="reader-panel${cls}"><div class="ico">${USB}</div><div class="txt"><strong>${title}</strong>` +
      `<p>${text}</p></div><div class="acts">${acts}</div></div>`;
    el.querySelector('.txt').append(msg);
    // (button classes of their own: the connected panel itself has the class "on")
    el.querySelector('button.connect')?.addEventListener('click', () => card.connect().catch(fail));
    el.querySelector('button.disconnect')?.addEventListener('click', () => card.disconnect());
    el.querySelector('button.all')?.addEventListener('click', () =>
      copyMany(ids.map((id) => byId.get(id)).filter((a) => a && card.state(a)?.update)));
  }

  function fail(e) {
    if (e && e.name === 'AbortError') {
      msg.className = 'msg warn';
      msg.textContent = 'Nothing chosen. If the browser refused the card itself, choose a folder on it instead: ' +
        'the reader installs from any folder.';
      return;
    }
    msg.className = 'msg err';
    msg.textContent = String(e && e.message || e);
  }

  async function copyMany(list) {
    try {
      for (const a of list) {
        msg.className = 'msg';
        msg.textContent = `Copying ${a.file}…`;
        await card.copy(root, a);
        count(root, `apps/${a.id}/got/`);
        copied.add(a.id);
        sync();
      }
      msg.className = 'msg ok';
      msg.textContent = `Copied ${list.map((a) => a.file).join(', ')}. Eject the card or leave USB mode, then on the ` +
        'reader: All Files, tap the package, Install. Updates install over the app and keep its files.';
    } catch (e) { fail(e); }
  }

  function sync() {
    render();
    for (const id of ids) {
      const a = byId.get(id);
      if (!a) continue;
      const s = card.state(a), on = canCopy && !!card.handle;
      for (const b of document.querySelectorAll(`button.copy[data-app="${id}"]`)) {
        b.hidden = !on || (!single && s?.current && !copied.has(id));
        b.disabled = copied.has(id);
        b.textContent = copied.has(id) ? 'Copied ✓' : s?.update ? 'Update' : s?.current ? 'Copy again' : single ? 'Copy to reader' : 'Copy';
        b.classList.toggle('primary', single || !!s?.update);
        b.onclick = () => copyMany([a]);
      }
      // on the list the download gives way to the copy while the reader is connected
      if (!single) for (const d of document.querySelectorAll(`a.dl[data-app="${id}"]`)) d.hidden = on;
      for (const t of document.querySelectorAll(`.status[data-app="${id}"]`)) {
        t.textContent = s ? s.label : '';
        t.className = 'status' + (s?.update ? ' update' : s?.current ? ' current' : '');
      }
    }
  }
  card.listeners.add(sync);
  sync();
  await card.restore();
  return catalog;
}
