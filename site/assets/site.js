// Shared pieces of the tools pages: the list of tools (the home page shows it), the page header
// and footer, a file drop zone, downloads and a small log. Everything runs in the browser: files
// are read and converted on this computer and never uploaded.

import { writeZip } from './zip.js';

export const REPO = 'https://github.com/omer-faruq-xteink/touch-licorice-apps';

// a new tool: a folder under tools/ with an index.html, and an entry here
export const TOOLS = [
  { id: 'gamebook', title: 'Gamebook stories', app: 'Gamebook',
    blurb: 'Turn a Twine or Ink story into a .story file for the reader, or download the story pack.' },
  { id: 'anki', title: 'Anki decks', app: 'Anki',
    blurb: 'Convert an Anki deck (.apkg) or a word list (.tsv, .csv) into cards for the reader.' },
  { id: 'dictionary', title: 'StarDict dictionaries', app: 'Dictionary',
    blurb: 'Cut a StarDict dictionary into the small files the Dictionary app looks words up in.' },
  { id: 'feeds', title: 'Feed lists', app: 'RSS',
    blurb: 'Ready feed lists by topic, and an OPML list of your own for the RSS app to read on the reader.' },
  { id: 'textadv', title: 'Text adventures', app: 'Text adventures',
    blurb: 'Zork I, II and III as a free pack, and where to find more games for the reader.' },
  { id: 'piano', title: 'Piano scores', app: 'Piano Follow',
    blurb: 'Engrave your own MusicXML or ABC sheet music for the reader’s screen and write it to the card.' },
  { id: 'worker', title: 'Worker setup', app: 'RSS, Hacker News',
    blurb: 'Step by step: your own free Cloudflare Worker for the apps that use one, and what to type on the reader.' },
];

// the header and footer of a page: chrome(null) the app list (the home page), chrome('tools') the
// tools list, chrome('developers') the page for app makers, chrome('<tool id>') a tool,
// chrome({ app: name }) an app's page
export function chrome(id) {
  const tool = TOOLS.find((t) => t.id === id);
  const root = id === null ? './' : id === 'tools' || id === 'developers' || id === 'whats-new' ? '../' : '../../';
  let crumb = id === 'developers' ? '<span class="crumb">/ Add your app</span>' : '';
  if (tool) crumb = `<span class="crumb">/ <a href="${root}tools/">Tools</a> / ${esc(tool.title)}</span>`;
  else if (id && id.app) crumb = `<span class="crumb">/ ${esc(id.app)}</span>`;
  const here = id === 'tools' || tool ? 'tools' : id === 'whats-new' ? 'whats-new' : 'apps';
  const cur = (k) => (here === k ? ' aria-current="page"' : '');
  const header = document.createElement('header');
  header.className = 'site';
  header.innerHTML = `<div class="wrap"><a class="home" href="${root}">Touch Licorice apps</a>${crumb}` +
    `<nav><a href="${root}"${cur('apps')}>Apps</a>` +
    `<a href="${root}whats-new/"${cur('whats-new')} id="nav-new">What’s new</a>` +
    `<a href="${root}tools/"${cur('tools')}>Tools</a></nav></div>`;
  document.body.prepend(header);
  // a dot on What's new while the latest release is at most a week old (the apps' New badges' rule)
  fetch(`${root}catalog.json`).then((r) => r.json()).then((c) => {
    const t = c.release && Date.parse(c.release.date);
    if (t && Date.now() - t <= 7 * 864e5) document.getElementById('nav-new').classList.add('fresh');
  }).catch(() => {});
  const footer = document.createElement('footer');
  footer.className = 'site';
  footer.innerHTML = '<div class="wrap">Unofficial <a href="' + REPO + '">touch-licorice-apps</a> mini apps for the ' +
    'Xteink X4 Pro. Everything runs in your browser: your files are not uploaded anywhere. ' +
    `Made an app? <a href="${root}developers/">Add it to the list</a>.</div>`;
  document.body.append(footer);
  // downloads: a package counts for its app, any other file (packs, feed lists, dictionaries) for got/
  document.addEventListener('click', (e) => {
    const a = e.target.closest && e.target.closest('a[href]');
    if (!a) return;
    const href = a.getAttribute('href');
    const pkg = href.match(/(?:^|\/)packages\/([\w-]+)\.xtapp$/);
    if (pkg) count(root, `apps/${a.dataset.app || pkg[1]}/got/`);
    else if (a.hasAttribute('download') || /\.(zip|opml)$/.test(href)) count(root, 'got/');
  });
}

// Count a download without telling anything about it: Cloudflare's beacon keeps only a page's
// path (it drops the query), so a hidden 1-pixel frame loads a page of its own, apps/<id>/got/,
// whose beacon reports one view of that path. Built by tools/build_site.py; never in the way.
export function count(root, path) {
  try {
    const f = document.createElement('iframe');
    f.setAttribute('aria-hidden', 'true');
    f.setAttribute('tabindex', '-1');
    f.setAttribute('title', '');
    f.setAttribute('referrerpolicy', 'no-referrer');
    f.style.cssText = 'position:fixed;right:0;bottom:0;width:1px;height:1px;border:0;opacity:0.01;pointer-events:none';
    f.src = root + path;         // set before it is added: no history entry
    document.body.appendChild(f);
    setTimeout(() => f.remove(), 15000);
  } catch (err) { /* counting never stops a download */ }
}

// a drop zone: el is a .drop element holding an <input type=file>
export function dropZone(el, onFiles) {
  const input = el.querySelector('input[type=file]');
  const take = async (list) => {
    const files = [];
    for (const f of list) files.push({ name: f.name, bytes: new Uint8Array(await f.arrayBuffer()) });
    if (files.length) onFiles(files);
  };
  el.addEventListener('click', () => input.click());
  el.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); input.click(); } });
  input.addEventListener('change', () => { take(input.files); input.value = ''; });
  el.addEventListener('dragover', (e) => { e.preventDefault(); el.classList.add('over'); });
  el.addEventListener('dragleave', () => el.classList.remove('over'));
  el.addEventListener('drop', (e) => { e.preventDefault(); el.classList.remove('over'); take(e.dataTransfer.files); });
}

export function download(name, data, type = 'application/octet-stream') {
  const blob = data instanceof Blob ? data : new Blob([data], { type });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = name;
  document.body.append(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
}

export async function downloadZip(name, files) {
  download(name, await writeZip(files), 'application/zip');
}

export function logger(el) {
  return {
    clear() { el.textContent = ''; },
    line(s) { el.textContent += (el.textContent ? '\n' : '') + s; },
  };
}

export function message(el, text, kind = '') {
  el.className = 'msg ' + kind;
  el.textContent = text;
}

export const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const loaded = new Map();
export function loadScript(src) {
  if (!loaded.has(src)) {
    loaded.set(src, new Promise((ok, fail) => {
      const s = document.createElement('script');
      s.src = src;
      s.onload = ok;
      s.onerror = () => fail(new Error('could not load ' + src));
      document.head.append(s);
    }));
  }
  return loaded.get(src);
}

export const bytesText = (n) => (n < 1024 ? `${n} B` : n < 1048576 ? `${Math.round(n / 1024)} KB` : `${(n / 1048576).toFixed(1)} MB`);
