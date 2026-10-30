// Project Aon's gamebooks (Lone Wolf, Grey Star, Freeway Warrior: https://www.projectaon.org) from
// their EPUB edition -> the .story format. Each numbered section becomes a passage and each
// "turn to N" a choice; "pick a number from the Random Number Table" shows a random number; the
// rules come first, from the start page. Combat and the Action Chart stay with the reader, as in
// the book. Project Aon's licence allows personal use: the file says so and is not to be shared.
//
//   isAonEpub(files)    files: [{ name, bytes }] from the EPUB (a zip)
//   fromAonEpub(files)  -> { story, warnings, info }

import { unescapeHtml } from '../../assets/unescape.js';

const dec = new TextDecoder('utf-8');
const base = (n) => n.replace(/^.*\//, '');

export function isAonEpub(files) {
  const opf = files.find((f) => f.name.endsWith('.opf'));
  return !!opf && files.some((f) => /(^|\/)sect1\.html?$/.test(f.name)) && /Project Aon/i.test(dec.decode(opf.bytes));
}

// plain text of an HTML fragment, on one line
function text(html) {
  return unescapeHtml(html.replace(/<br\s*\/?>/gi, ' ').replace(/<[^>]+>/g, '')).replace(/\s+/g, ' ').trim();
}

// a .story text line: the format's own characters escaped
function esc(s) {
  s = s.replace(/\\/g, '\\\\').replace(/\{/g, '\\{').replace(/\}/g, '\\}').replace(/\|/g, '\\|');
  return /^(\*|->|~|==|\/\/|-)/.test(s) ? '\\' + s : s;
}

// the blocks of a page in order: headings, paragraphs, list items, table cells
function blocks(html) {
  const body = html.replace(/^[\s\S]*?<body[^>]*>/i, '').replace(/<\/body>[\s\S]*$/i, '')
    .replace(/<(script|style)\b[\s\S]*?<\/\1>/gi, '').replace(/<div class="illustration">[\s\S]*?<\/div>/gi, '');
  const out = [];
  const re = /<(h[1-6]|p|li|dt|dd|td|th|blockquote)\b([^>]*)>([\s\S]*?)<\/\1>/gi;
  let m;
  while ((m = re.exec(body))) out.push({ tag: m[1].toLowerCase(), cls: (m[2].match(/class="([^"]*)"/) || [])[1] || '', html: m[3] });
  return out;
}

const SECT = /(?:^|\/)sect(\d+)\.html?(?:#.*)?$/;

export function fromAonEpub(files) {
  const warnings = [];
  const byName = new Map(files.map((f) => [base(f.name), f]));
  const opfFile = files.find((f) => f.name.endsWith('.opf'));
  const opf = dec.decode(opfFile.bytes);
  const title = text((opf.match(/<dc:title[^>]*>([\s\S]*?)<\/dc:title>/) || [])[1] || 'Gamebook');
  const author = text((opf.match(/<dc:creator[^>]*>([\s\S]*?)<\/dc:creator>/) || [])[1] || '');
  // the reading order, from the spine
  const hrefOf = new Map();
  for (const m of opf.matchAll(/<item\b[^>]*\bid="([^"]+)"[^>]*\bhref="([^"]+)"/g)) hrefOf.set(m[1], base(m[2]));
  for (const m of opf.matchAll(/<item\b[^>]*\bhref="([^"]+)"[^>]*\bid="([^"]+)"/g)) hrefOf.set(m[2], base(m[1]));
  const spine = [...opf.matchAll(/<itemref\b[^>]*\bidref="([^"]+)"/g)].map((m) => hrefOf.get(m[1])).filter(Boolean);
  const page = (n) => (byName.get(n) ? dec.decode(byName.get(n).bytes) : null);

  // ---- the numbered sections
  const sections = [];
  for (const n of spine) {
    const m = n.match(SECT);
    if (m) sections.push([+m[1], n]);
  }
  if (!sections.length) throw new Error('no numbered sections (sect1.html ...) in this EPUB');
  const ids = new Set(sections.map(([k]) => k));
  const passages = [];
  let randoms = 0;
  for (const [k, n] of sections) {
    const lines = [`— ${k} —`];
    const choices = [];
    for (const b of blocks(page(n))) {
      if (/^h\d$/.test(b.tag) && text(b.html) === String(k)) continue;
      const links = [...b.html.matchAll(/<a\b[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi)].map((x) => [x[1], text(x[2])]);
      const goes = links.filter(([h]) => SECT.test(h));
      if (goes.length && b.cls.includes('choice')) {
        const target = +goes[0][0].match(SECT)[1];
        let label = text(b.html).replace(/[,;]?\s*(?:then\s+)?turn\s+to\s+\d+\.?\s*$/i, '').replace(/[.,;:]\s*$/, '');
        if (!label) label = `Turn to ${target}`;
        if (!ids.has(target)) warnings.push(`section ${k}: turns to ${target}, which is not in this book`);
        choices.push(`* ${esc(label).replace(/~/g, '\\~').replace(/->/g, '-\\>')} -> ${ids.has(target) ? 's' + target : 'END'}`);
        continue;
      }
      const t = text(b.html);
      if (!t) continue;
      lines.push(esc(t));
      if (links.some(([h]) => /random\.html?/i.test(h)) || /Random Number Table/i.test(t)) {
        lines.push('Your number from the Random Number Table: {random(0, 9)}');
        randoms++;
      }
    }
    passages.push({ id: 's' + k, lines: [...lines, ...choices] });
  }

  // ---- the pages before section 1: the story so far and the rules
  const SKIP = /^(titlepage|toc|dedicate|acknwldg|errata|footnotz|illstrat|license|numbered|map|crtable|random|crsumary|action)\./;
  const front = [];
  for (const n of spine) {
    if (SECT.test(n)) break;
    if (SKIP.test(n) || n === 'title.html' || !page(n)) continue;
    const bl = blocks(page(n));
    const head = bl.find((b) => /^h\d$/.test(b.tag));
    const name = head ? text(head.html) : n.replace(/\.html?$/, '');
    const lines = [];
    for (const b of bl) {
      const t = b === head ? '' : text(b.html);
      if (!t) continue;
      lines.push(esc((b.tag === 'li' ? '• ' : '') + t));
      // the rules have the reader pick numbers too (COMBAT SKILL, ENDURANCE, Gold Crowns)
      if (/Random Number Table/i.test(t) && /\bpick\b/i.test(t)) lines.push('Your number from the Random Number Table: {random(0, 9)}');
    }
    if (n === 'cmbtrulz.html') {
      lines.push('', 'The Combat Results Table is a picture in the book: keep it at hand from the PDF or the web edition at projectaon.org.');
    }
    front.push({ id: 'p_' + n.replace(/\.html?$/, '').replace(/\W/g, '_'), name, lines });
  }
  const intro = blocks(page('title.html') || '').filter((b) => b.tag === 'p').map((b) => text(b.html)).filter(Boolean);
  const startLines = [...intro.slice(0, 2).map(esc), ''];
  for (const f of front) startLines.push(`* ${esc(f.name)} -> ${f.id}`);
  startLines.push(`* Begin the adventure -> s${sections[0][0]}`);
  const startPassage = { id: 'contents', lines: startLines };
  const frontPassages = front.map((f) => ({ id: f.id, lines: [f.name.toUpperCase(), '', ...f.lines, `* Back to the contents -> contents`, `* Begin the adventure -> s${sections[0][0]}`] }));

  const head = [
    `title: ${title}`, author && `author: ${author}`, 'language: en',
    'licence: Project Aon licence: for your own use only; do not share this file',
    intro[0] && `about: ${intro[0].slice(0, 200)}`, 'start: contents',
  ].filter(Boolean).join('\n');
  const all = [startPassage, ...frontPassages, ...passages];
  const story = head + '\n\n' + all.map((p) => [`== ${p.id}`, ...p.lines].join('\n')).join('\n\n') + '\n';
  return { story, warnings, info: { format: `Project Aon (${sections.length} sections, ${randoms} random numbers)`, passages: all.length } };
}
