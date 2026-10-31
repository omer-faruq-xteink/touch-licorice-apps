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
  { id: 'worker', title: 'Worker setup', app: 'RSS, Hacker News, Readwise',
    blurb: 'Step by step: your own free Cloudflare Worker for the apps that use one, and what to type on the reader.' },
];

export function chrome(id) {
  const tool = TOOLS.find((t) => t.id === id);
  const root = id ? '../../' : './';
  const header = document.createElement('header');
  header.className = 'site';
  header.innerHTML = `<div class="wrap"><a class="home" href="${root}">Touch Licorice tools</a>` +
    (tool ? `<span class="crumb">/ ${tool.title}</span>` : '') + '</div>';
  document.body.prepend(header);
  const footer = document.createElement('footer');
  footer.className = 'site';
  footer.innerHTML = '<div class="wrap">Tools for the <a href="' + REPO + '">touch-licorice-apps</a> mini apps for the ' +
    'Xteink X4 Pro. Everything runs in your browser: your files are not uploaded anywhere.</div>';
  document.body.append(footer);
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
