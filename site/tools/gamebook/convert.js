// Twine (Harlowe, SugarCube; links only for Chapbook and Snowman) and Ink stories -> the .story
// format of the Gamebook app (apps/gamebook/FORMAT.md). Runs in the browser and in Node.
//
//   convert(fileName, text) -> { story, warnings, info }     story: the .story text
//   check(storyText)        -> { passages, errors, warnings } a .story file's links and names
//
// What does not map (Harlowe's (display:), interactive (click:) hooks, Ink tunnels, threads, lists
// and functions, ...) is left out with a warning naming the passage, so the rest still plays.

import { unescapeHtml } from '../../assets/unescape.js';

export function detect(name, text) {
  const n = (name || '').toLowerCase();
  if (/<tw-storydata/i.test(text)) return 'twine';
  if (n.endsWith('.story')) return 'story';
  if (n.endsWith('.ink')) return 'ink';
  if (n.endsWith('.json') && /"inkVersion"/.test(text)) return 'ink-json';
  if (n.endsWith('.tw') || n.endsWith('.twee') || /^::\s*\S/m.test(text)) return 'twee';
  if (/^\s*(===|VAR |CONST |->)/m.test(text) || /^\s*[*+]\s/m.test(text)) return 'ink';
  if (/^==\s*[A-Za-z_]/m.test(text)) return 'story';
  return null;
}

export function convert(name, text) {
  const kind = detect(name, text);
  if (kind === 'twine') return fromTwine(parseTwineHtml(text));
  if (kind === 'twee') return fromTwine(parseTwee(text));
  if (kind === 'ink') return fromInk(text, name);
  if (kind === 'story') {
    const r = check(text);
    return { story: text, warnings: [...r.errors, ...r.warnings], info: { format: '.story', passages: r.passages } };
  }
  if (kind === 'ink-json') {
    throw new Error('This is a compiled Ink story (.json). Convert the Ink source instead: the .ink file you write in Inky.');
  }
  throw new Error('Not a story this page knows: use a Twine 2 published .html, a Twee (.twee / .tw) file or an Ink (.ink) file.');
}

// ------------------------------------------------------------------ shared

const RESERVED = new Set(['END', 'DONE', 'true', 'false', 'and', 'or', 'not', 'random', 'min', 'max', 'abs', 'visited', 'visits']);

// text for a .story line: the format's own characters escaped
function escText(s) {
  s = s.replace(/\\/g, '\\\\').replace(/\{/g, '\\{').replace(/\}/g, '\\}').replace(/\|/g, '\\|');
  if (/^(\*|->|~|==|\/\/|-)/.test(s.trimStart())) s = '\\' + s.trimStart();
  return s;
}

function makeNamer() {
  const used = new Map(), taken = new Set();
  return {
    id(name) {
      if (used.has(name)) return used.get(name);
      let base = String(name).normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^A-Za-z0-9_]+/g, '_').replace(/^_+|_+$/g, '') || 'passage';
      if (!/^[A-Za-z_]/.test(base)) base = 'p_' + base;
      if (RESERVED.has(base)) base += '_';
      let id = base, k = 2;
      while (taken.has(id.toLowerCase())) id = base + '_' + k++;
      taken.add(id.toLowerCase());
      used.set(name, id);
      return id;
    },
    reserve(id) { taken.add(id.toLowerCase()); },
    has(name) { return used.has(name); },
  };
}

function varId(v) {
  let s = v.replace(/[^A-Za-z0-9_]/g, '_');
  if (!/^[A-Za-z_]/.test(s)) s = 'v_' + s;
  if (RESERVED.has(s)) s += '_';
  return s;
}

function literal(v) {
  if (typeof v === 'boolean' || typeof v === 'number') return String(v);
  return JSON.stringify(String(v));
}

function andCond(a, b) {
  if (!a) return b || null;
  if (!b) return a;
  return `(${a}) and (${b})`;
}

function header(meta, vars) {
  const out = [];
  for (const k of ['title', 'author', 'language', 'licence', 'about', 'start']) {
    if (meta[k]) out.push(`${k}: ${String(meta[k]).replace(/\s+/g, ' ').trim()}`);
  }
  for (const [n, v] of vars) out.push(`var: ${n} = ${literal(v)}`);
  return out.join('\n');
}

function serialize(meta, vars, passages) {
  const parts = [header(meta, vars)];
  for (const p of passages) {
    const lines = [`== ${p.id}`];
    for (const l of p.lines) lines.push(l);
    while (lines.length > 1 && lines[lines.length - 1] === '') lines.pop();
    parts.push(lines.join('\n'));
  }
  return parts.join('\n\n') + '\n';
}

// ------------------------------------------------------------------ Twine: reading the files

export function parseTwineHtml(html) {
  const sd = html.match(/<tw-storydata\b([^>]*)>/i);
  if (!sd) throw new Error('no <tw-storydata> in this file: publish the story to a file from Twine 2');
  const attr = (s, n) => { const m = s.match(new RegExp(`\\b${n}\\s*=\\s*("([^"]*)"|'([^']*)')`, 'i')); return m ? unescapeHtml(m[2] ?? m[3]) : null; };
  const passages = [];
  const re = /<tw-passagedata\b([^>]*)>([\s\S]*?)<\/tw-passagedata>/gi;
  let m;
  while ((m = re.exec(html))) {
    passages.push({ pid: attr(m[1], 'pid'), name: attr(m[1], 'name') || '', tags: (attr(m[1], 'tags') || '').split(/\s+/).filter(Boolean), text: unescapeHtml(m[2]) });
  }
  const startPid = attr(sd[1], 'startnode');
  const start = passages.find((p) => p.pid === startPid) || passages[0];
  return { title: attr(sd[1], 'name'), format: attr(sd[1], 'format') || 'Harlowe', start: start && start.name, passages };
}

export function parseTwee(text) {
  const passages = [];
  let cur = null;
  for (const raw of text.replace(/\r/g, '').split('\n')) {
    const h = raw.match(/^::\s*(.*?)\s*(\[([^\]]*)\])?\s*(\{.*\})?\s*$/);
    if (h && raw.startsWith('::')) {
      cur = { name: h[1].replace(/\\(.)/g, '$1'), tags: (h[3] || '').split(/\s+/).filter(Boolean), lines: [] };
      passages.push(cur);
    } else if (cur) cur.lines.push(raw);
  }
  const out = { title: null, format: 'Harlowe', start: null, passages: [] };
  for (const p of passages) {
    const body = p.lines.join('\n').replace(/\s+$/, '');
    if (p.name === 'StoryTitle') { out.title = body.trim(); continue; }
    if (p.name === 'StoryData') {
      try { const d = JSON.parse(body); out.format = d.format || out.format; out.start = d.start || null; } catch { /* keep going */ }
      continue;
    }
    out.passages.push({ name: p.name, tags: p.tags, text: body });
  }
  if (!out.start) out.start = (out.passages.find((p) => p.name === 'Start') || out.passages[0] || {}).name;
  return out;
}

// ------------------------------------------------------------------ Twine: expressions

// a Harlowe / SugarCube expression in our syntax; `it` is the variable being set
function twExpr(s, ctx, it) {
  const out = [];
  let i = 0;
  s = s.trim();
  while (i < s.length) {
    const rest = s.slice(i);
    let m;
    if ((m = rest.match(/^\s+/))) { out.push(' '); i += m[0].length; continue; }
    if ((m = rest.match(/^("([^"\\]|\\.)*"|'([^'\\]|\\.)*')/))) { out.push(m[0]); i += m[0].length; continue; }
    if ((m = rest.match(/^\$([A-Za-z_][\w]*)/))) { out.push(ctx.var(m[1])); i += m[0].length; continue; }
    if ((m = rest.match(/^_([A-Za-z][\w]*)/))) { out.push(ctx.var('t_' + m[1])); i += m[0].length; continue; }
    if ((m = rest.match(/^\(\s*(random|either)\s*:\s*([^)]*)\)/i))) {
      if (m[1].toLowerCase() === 'random') out.push(`random(${twExpr(m[2], ctx, it)})`);
      else { ctx.warn('(either:) is not supported; the first value is used'); out.push(twExpr(m[2].split(',')[0], ctx, it)); }
      i += m[0].length; continue;
    }
    if ((m = rest.match(/^(visited|visits)\s*\(\s*("([^"]*)"|'([^']*)')?\s*\)/))) {
      out.push(m[2] ? ctx.passageRef(m[3] ?? m[4]) : ctx.here); i += m[0].length; continue;
    }
    if ((m = rest.match(/^\(\s*history\s*:\s*\)\s+contains\s+("([^"]*)"|'([^']*)')/i))) {
      out.push(`(${ctx.passageRef(m[2] ?? m[3])} > 0)`); i += m[0].length; continue;
    }
    if ((m = rest.match(/^(Math\.)?random\s*\(/))) { out.push('random('); i += m[0].length; continue; }
    if ((m = rest.match(/^(is\s+not|isnot|neq|!==|!=)(?![\w])/))) { out.push('!='); i += m[0].length; continue; }
    if ((m = rest.match(/^(===|==|is|eq)(?![\w=])/))) { out.push('=='); i += m[0].length; continue; }
    if ((m = rest.match(/^(gte|>=)(?![\w])/))) { out.push('>='); i += m[0].length; continue; }
    if ((m = rest.match(/^(lte|<=)(?![\w])/))) { out.push('<='); i += m[0].length; continue; }
    if ((m = rest.match(/^(gt)(?![\w])/))) { out.push('>'); i += m[0].length; continue; }
    if ((m = rest.match(/^(lt)(?![\w])/))) { out.push('<'); i += m[0].length; continue; }
    if ((m = rest.match(/^(and|&&)(?![\w])/))) { out.push('and'); i += m[0].length; continue; }
    if ((m = rest.match(/^(or|\|\|)(?![\w])/))) { out.push('or'); i += m[0].length; continue; }
    if ((m = rest.match(/^(not|!)(?![\w=])/))) { out.push('not '); i += m[0].length; continue; }
    if ((m = rest.match(/^it(?![\w])/))) { out.push(it || '0'); i += m[0].length; continue; }
    if ((m = rest.match(/^(true|false)(?![\w])/))) { out.push(m[1]); i += m[0].length; continue; }
    if ((m = rest.match(/^\d+(\.\d+)?/))) { out.push(m[0]); i += m[0].length; continue; }
    if ((m = rest.match(/^[-+*/%<>(),]/))) { out.push(m[0]); i += 1; continue; }
    if ((m = rest.match(/^(contains|is in|matches|\w+)/))) {
      ctx.warn(`"${m[0]}" in an expression is not supported: ${s}`);
      out.push('0'); i += m[0].length; continue;
    }
    ctx.warn(`could not read "${rest.slice(0, 20)}" in: ${s}`);
    break;
  }
  return out.join('').replace(/\s+/g, ' ').trim();
}

// "$x to 5", "$x = 5, $y += 1" (SugarCube), "put: 5 into $x" -> "x = 5; y += 1"
function twSet(s, ctx, put) {
  const stmts = [];
  if (put) {
    const m = s.match(/^([\s\S]*)\binto\s+\$([A-Za-z_]\w*)\s*$/);
    if (!m) { ctx.warn(`(put:) not understood: ${s}`); return ''; }
    const v = ctx.var(m[2]);
    return `${v} = ${twExpr(m[1], ctx, v)}`;
  }
  for (const part of splitTop(s, [',', ';'])) {
    const m = part.match(/^\s*([$_])([A-Za-z_]\w*)\s*(to|=|\+=|-=|\*=|\/=)\s*([\s\S]+)$/);
    const inc = part.match(/^\s*([$_])([A-Za-z_]\w*)\s*(\+\+|--)\s*$/);
    if (inc) { const v = ctx.var((inc[1] === '_' ? 't_' : '') + inc[2]); stmts.push(`${v} ${inc[3] === '++' ? '+=' : '-='} 1`); continue; }
    if (!m) { if (part.trim()) ctx.warn(`(set:) not understood: ${part.trim()}`); continue; }
    const v = ctx.var((m[1] === '_' ? 't_' : '') + m[2]);
    const op = m[3] === 'to' || m[3] === '=' ? '=' : m[3];
    const e = twExpr(m[4], ctx, v);
    if (op === '*=' || op === '/=') stmts.push(`${v} = ${v} ${op[0]} (${e})`);
    else stmts.push(`${v} ${op} ${e}`);
    if (op === '=') ctx.noteSet(v, m[4].trim());
  }
  return stmts.join('; ');
}

// split on separators outside quotes and brackets
function splitTop(s, seps) {
  const out = [];
  let depth = 0, q = null, start = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (q) { if (c === '\\') i++; else if (c === q) q = null; continue; }
    if (c === '"' || c === "'") q = c;
    else if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) depth--;
    else if (depth === 0 && seps.includes(c)) { out.push(s.slice(start, i)); start = i + 1; }
  }
  out.push(s.slice(start));
  return out;
}

function unquote(s) {
  const m = s.trim().match(/^("((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')$/);
  return m ? (m[2] ?? m[3]).replace(/\\(.)/g, '$1') : null;
}

// [[...]] -> { label, target, setter }
function twLink(inner) {
  let setter = null;
  const sc = inner.match(/^(.*?)\]\[(.*)$/s);
  if (sc) { inner = sc[1]; setter = sc[2]; }
  let label, target;
  const r = inner.lastIndexOf('->'), l = inner.indexOf('<-'), bar = inner.lastIndexOf('|');
  if (r >= 0) { label = inner.slice(0, r); target = inner.slice(r + 2); }
  else if (l >= 0) { target = inner.slice(0, l); label = inner.slice(l + 2); }
  else if (bar >= 0) { label = inner.slice(0, bar); target = inner.slice(bar + 1); }
  else { label = target = inner; }
  return { label: label.trim(), target: target.trim(), setter };
}

// ------------------------------------------------------------------ Twine: passage text -> nodes

// nodes: { t: 'text', s } | { t: 'link', label, target, setter } | { t: 'macro', name, args, hook }
//        | { t: 'br' } | { t: 'block', name, branches: [{ name, args, nodes }] } (SugarCube <<if>>, <<link>>)
function harloweNodes(src, ctx) {
  let i = 0;
  function nodes(stop) {
    const out = [];
    let text = '';
    const flush = () => { if (text) { out.push({ t: 'text', s: text }); text = ''; } };
    while (i < src.length) {
      const c = src[i];
      if (stop && c === ']') { i++; break; }
      if (src.startsWith('[[', i)) {
        const j = src.indexOf(']]', i + 2);
        if (j < 0) { text += src.slice(i); i = src.length; break; }
        flush();
        out.push({ t: 'link', ...twLink(src.slice(i + 2, j)) });
        i = j + 2;
        continue;
      }
      let m = src.slice(i).match(/^\(([A-Za-z][\w-]*)\s*:/);
      if (m) {
        flush();
        const name = m[1].toLowerCase().replace(/-/g, '');
        let depth = 0, q = null, j = i;
        for (; j < src.length; j++) {
          const ch = src[j];
          if (q) { if (ch === '\\') j++; else if (ch === q) q = null; continue; }
          if (ch === '"' || ch === "'") q = ch;
          else if (ch === '(') depth++;
          else if (ch === ')') { depth--; if (depth === 0) break; }
        }
        const args = src.slice(i + m[0].length, j);
        i = j + 1;
        let hook = null;
        // a hook follows: "[" (but "[[" is a link, and "[[[" a hook holding a link)
        const hm = src.slice(i).match(/^\s*\[/);
        const at = hm ? i + hm[0].length - 1 : -1;
        if (hm && (!src.startsWith('[[', at) || src.startsWith('[[[', at))) { i += hm[0].length; hook = nodes(true); }
        out.push({ t: 'macro', name, args, hook });
        continue;
      }
      // named hooks: |name>[ ... ]  and [ ... ]<name|
      m = src.slice(i).match(/^\|[\w-]+>\[/);
      if (m) { flush(); i += m[0].length; out.push({ t: 'macro', name: 'hook', args: '', hook: nodes(true) }); continue; }
      if (c === '[' && !src.startsWith('[[', i)) {
        flush(); i++;
        out.push({ t: 'macro', name: 'hook', args: '', hook: nodes(true) });
        const nm = src.slice(i).match(/^<[\w-]+\|/);
        if (nm) i += nm[0].length;
        continue;
      }
      if (c === '\n') { flush(); out.push({ t: 'br' }); i++; continue; }
      m = src.slice(i).match(/^\$([A-Za-z_]\w*)/);
      if (m) { flush(); out.push({ t: 'print', expr: '$' + m[1] }); i += m[0].length; continue; }
      text += c; i++;
    }
    flush();
    return out;
  }
  return nodes(false);
}

function sugarNodes(src, ctx) {
  // tokens first: text, [[links]], <<macro args>>, <</macro>>, $var, newlines
  const toks = [];
  let i = 0, text = '';
  const flush = () => { if (text) { toks.push({ t: 'text', s: text }); text = ''; } };
  while (i < src.length) {
    if (src.startsWith('[[', i)) {
      const j = src.indexOf(']]', i + 2);
      if (j >= 0) { flush(); toks.push({ t: 'link', ...twLink(src.slice(i + 2, j)) }); i = j + 2; continue; }
    }
    if (src.startsWith('<<', i)) {
      let j = i + 2, q = null;
      for (; j < src.length; j++) {
        const ch = src[j];
        if (q) { if (ch === '\\') j++; else if (ch === q) q = null; continue; }
        if (ch === '"' || ch === "'") q = ch;
        else if (src.startsWith('>>', j)) break;
      }
      flush();
      const body = src.slice(i + 2, j).trim();
      const m = body.match(/^(\/?)([=\w-]+)\s*([\s\S]*)$/);
      if (m) toks.push(m[1] ? { t: 'close', name: m[2].toLowerCase() } : { t: 'm', name: m[2].toLowerCase(), args: m[3] });
      i = j + 2;
      continue;
    }
    if (src[i] === '\n') { flush(); toks.push({ t: 'br' }); i++; continue; }
    const m = src.slice(i).match(/^\$([A-Za-z_]\w*)/);
    if (m) { flush(); toks.push({ t: 'print', expr: '$' + m[1] }); i += m[0].length; continue; }
    text += src[i]; i++;
  }
  flush();
  // then the tree: <<if>> / <<elseif>> / <<else>> / <</if>>, <<link>> ... <</link>>
  let p = 0;
  function seq(stops) {
    const out = [];
    while (p < toks.length) {
      const tk = toks[p];
      if (tk.t === 'close' && stops.includes('/' + tk.name)) return out;
      if (tk.t === 'm' && stops.includes(tk.name)) return out;
      p++;
      if (tk.t === 'm' && tk.name === 'if') {
        const branches = [{ name: 'if', args: tk.args, nodes: seq(['elseif', 'else', '/if']) }];
        while (p < toks.length && toks[p].t === 'm' && (toks[p].name === 'elseif' || toks[p].name === 'else')) {
          const b = toks[p++];
          const args = b.name === 'else' && /^if\b/.test(b.args) ? b.args.slice(2) : b.args;
          branches.push({ name: b.name === 'else' && args === b.args ? 'else' : 'elseif', args, nodes: seq(['elseif', 'else', '/if']) });
        }
        p++;
        out.push({ t: 'block', name: 'if', branches });
      } else if (tk.t === 'm' && (tk.name === 'link' || tk.name === 'button')) {
        const nodes = /^\s*\[\[/.test(tk.args) ? [] : seq(['/' + tk.name]);
        if (!/^\s*\[\[/.test(tk.args)) p++;
        out.push({ t: 'block', name: 'link', branches: [{ name: 'link', args: tk.args, nodes }] });
      } else if (tk.t === 'm' && ['nobr', 'silently', 'span', 'div', 'type', 'linkappend', 'linkreplace', 'linkprepend', 'switch', 'for', 'repeat', 'timed', 'widget', 'script', 'done'].includes(tk.name)) {
        const inner = seq(['/' + tk.name]);
        p++;
        if (!['nobr', 'silently', 'span', 'div', 'type'].includes(tk.name)) ctx.warn(`<<${tk.name}>> is not supported; its contents are kept as text`);
        out.push(...inner);
      } else if (tk.t === 'close') {
        // a closing tag with no opener: ignore
      } else out.push(tk);
    }
    return out;
  }
  return seq([]);
}

// ------------------------------------------------------------------ Twine: nodes -> lines

function fromTwine(tw) {
  const warnings = [];
  const isSugar = /sugarcube/i.test(tw.format || '');
  const isHarlowe = !isSugar && /harlowe/i.test(tw.format || 'Harlowe');
  const namer = makeNamer();
  const vars = new Map();
  const special = new Set(['StoryInit', 'StoryCaption', 'StoryMenu', 'StoryBanner', 'StorySubtitle', 'StoryAuthor',
    'PassageReady', 'PassageDone', 'PassageHeader', 'PassageFooter', 'StoryShare', 'StoryInterface', 'StoryTitle', 'StoryData']);
  const skipTags = new Set(['header', 'footer', 'debug-header', 'debug-footer', 'debug-startup', 'widget', 'script', 'stylesheet', 'Twine.image']);
  const byName = new Map(tw.passages.map((p) => [p.name, p]));
  const play = tw.passages.filter((p) => !special.has(p.name) && !p.tags.some((t) => skipTags.has(t) || t === 'startup'));
  const init = tw.passages.filter((p) => p.name === 'StoryInit' || p.tags.includes('startup'));
  for (const p of play) namer.id(p.name);
  const varNames = new Map();
  let here = null;
  const ctx = {
    warn: (m) => warnings.push(`${here ? `"${here}"` : 'story'}: ${m}`),
    var: (n) => {
      if (!varNames.has(n)) {
        let id = varId(n), k = 2;
        while ([...varNames.values()].includes(id) || play.some((p) => namer.id(p.name) === id)) id = varId(n) + '_' + k++;
        varNames.set(n, id);
        if (!vars.has(id)) vars.set(id, 0);
      }
      return varNames.get(n);
    },
    passageRef: (name) => {
      if (!byName.has(name)) { ctx.warn(`refers to a passage "${name}" that does not exist`); return '0'; }
      return namer.id(name);
    },
    noteSet: () => {},
    get here() { return here ? namer.id(here) : '0'; },
  };
  const target = (name) => {
    if (byName.has(name) && !special.has(name)) return namer.id(name);
    ctx.warn(`links to "${name}", which is not a passage; the link ends the story`);
    return 'END';
  };

  // initial values: (set:) / <<set>> in startup passages, when they are plain values
  for (const p of init) {
    here = p.name;
    const re = isSugar ? /<<set\s+([\s\S]*?)>>/g : /\(set:\s*([\s\S]*?)\)(?=\s|$|\()/g;
    let m;
    while ((m = re.exec(p.text))) {
      for (const part of splitTop(m[1], [',', ';'])) {
        const a = part.match(/^\s*\$([A-Za-z_]\w*)\s*(?:to|=)\s*([\s\S]+?)\s*$/);
        if (!a) continue;
        const v = ctx.var(a[1]);
        const lit = a[2].match(/^(-?\d+)$/) ? parseInt(a[2], 10) : a[2] === 'true' ? true : a[2] === 'false' ? false : unquote(a[2]);
        if (lit === null) ctx.warn(`the starting value of $${a[1]} is not a plain value: ${a[2]}`);
        else vars.set(v, lit);
      }
    }
  }

  const passages = [];
  for (const p of play) {
    here = p.name;
    const nodes = isSugar ? sugarNodes(p.text, ctx) : harloweNodes(p.text, ctx);
    if (!isSugar && !isHarlowe && /<%|\{[a-z]/.test(p.text)) ctx.warn(`${tw.format}: only text and links are converted`);
    passages.push({ id: namer.id(p.name), lines: twineLines(nodes, ctx, target, isSugar) });
  }
  here = null;
  const meta = { title: tw.title || 'Untitled', start: tw.start && byName.has(tw.start) ? namer.id(tw.start) : passages[0]?.id };
  const startIdx = passages.findIndex((p) => p.id === meta.start);
  if (startIdx > 0) passages.unshift(...passages.splice(startIdx, 1));
  return { story: serialize(meta, vars, passages), warnings, info: { format: `Twine (${tw.format || 'Harlowe'})`, passages: passages.length } };
}

function stripMarkup(s) {
  return s.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '')
    .replace(/''|\*\*|~~|\^\^|(?<!:)\/\/(?!\/)/g, '').replace(/^\s*#{1,6}\s+/gm, '').replace(/^\s*\*\s+/gm, '• ');
}

function twineLines(nodes, ctx, target, isSugar) {
  const lines = [], choices = [], effects = [], diverts = [];
  let line = [];              // pieces of the current text line: strings already in .story syntax
  let lineHadLink = false, lineHasText = false;
  // a line made only of links is dropped: the links become the choices
  const endLine = () => {
    const s = line.join('').replace(/[ \t]+/g, ' ').trim();
    if (s && (lineHasText || !lineHadLink)) lines.push(s);
    else if (!s && !lineHadLink) lines.push('');
    line = []; lineHadLink = false; lineHasText = false;
  };
  const wrapCond = (cond, s) => (cond ? `{${cond}: ${s}}` : s);
  const addText = (s, cond) => {
    const parts = stripMarkup(s).split('\n');
    parts.forEach((part, k) => {
      if (k > 0) endLine();
      if (part) line.push(wrapCond(cond, escText(part).replace(/^\\(?=[*~=-])/, line.length ? '' : '\\')));
      if (/[\p{L}\p{N}]/u.test(part)) lineHasText = true;
    });
  };
  // conditions are worked out when the passage opens, before its (set:)s run, as in Twine where
  // an (if:) is read before the (set:) inside its hook: each becomes a flag _c1, _c2 ...
  const flags = new Map();
  const hoist = (c) => {
    if (!flags.has(c)) flags.set(c, `_c${flags.size + 1}`);
    return flags.get(c);
  };
  const choice = (label, tgt, cond, setter) => {
    lineHadLink = true;
    choices.push({ label, target: tgt, cond, eff: setter });
  };

  function walk(list, cond) {
    for (let k = 0; k < list.length; k++) {
      const n = list[k];
      if (n.t === 'text') addText(n.s, cond);
      else if (n.t === 'br') endLine();
      else if (n.t === 'print') { lineHasText = true; line.push(`{${cond ? `${cond}: {${twExpr(n.expr, ctx)}}` : twExpr(n.expr, ctx)}}`); }
      else if (n.t === 'link') {
        const tgt = target(n.target);
        line.push(wrapCond(cond, escText(stripMarkup(n.label))));
        choice(n.label, tgt, cond, n.setter ? twSet(n.setter, ctx) : null);
      } else if (n.t === 'macro') {
        const a = n.args;
        switch (n.name) {
          case 'set': { const s = twSet(a, ctx); if (s) effects.push({ cond, s }); break; }
          case 'put': { const s = twSet(a, ctx, true); if (s) effects.push({ cond, s }); break; }
          case 'if': case 'unless': case 'elseif': case 'else': {
            // a chain: (if:)[..](else-if:)[..](else:)[..]
            let prev = [];
            let j = k;
            for (; j < list.length; j++) {
              const b = list[j];
              if (b.t === 'text' && !b.s.trim() && j > k && list[j + 1]?.t === 'macro' && ['elseif', 'else'].includes(list[j + 1].name)) continue;
              if (b.t !== 'macro' || (j > k && !['elseif', 'else'].includes(b.name))) break;
              if (j > k && b.name !== 'elseif' && b.name !== 'else') break;
              let c = b.name === 'else' ? null : hoist(twExpr(b.args, ctx));
              if (b.name === 'unless') c = `not (${c})`;
              const mine = prev.reduce((acc, x) => andCond(acc, `not (${x})`), null);
              if (b.hook) walk(b.hook, andCond(cond, andCond(mine, c)));
              if (c) prev.push(c);
              if (b.name === 'else') { j++; break; }
            }
            k = j - 1;
            break;
          }
          case 'linkgoto': case 'linkreveal goto': {
            const args = splitTop(a, [',']).map(unquote);
            const label = args[0] ?? '', tgt = args[1] ?? args[0] ?? '';
            line.push(wrapCond(cond, escText(label)));
            choice(label, target(tgt), cond, null);
            break;
          }
          case 'goto': case 'redirect': {
            const t = unquote(a);
            if (t !== null) diverts.push({ cond, target: target(t) });
            break;
          }
          case 'link': case 'linkreveal': case 'linkrepeat': case 'linkreplace': case 'linkrerun': {
            // (link: "Label")[(set: ..)(goto: "x")] -> a choice with effects
            const label = unquote(splitTop(a, [','])[0]) ?? '';
            const inner = n.hook || [];
            const go = inner.find((x) => x.t === 'macro' && (x.name === 'goto' || x.name === 'redirect'));
            const sets = inner.filter((x) => x.t === 'macro' && (x.name === 'set' || x.name === 'put'))
              .map((x) => twSet(x.args, ctx, x.name === 'put')).filter(Boolean);
            if (go) choice(label, target(unquote(go.args) ?? ''), cond, sets.join('; ') || null);
            else ctx.warn(`(link: "${label}") without a (goto:) inside is not supported; left out`);
            break;
          }
          case 'print': line.push(`{${cond ? `${cond}: {${twExpr(a, ctx)}}` : twExpr(a, ctx)}}`); break;
          case 'display': case 'include': ctx.warn(`(${n.name}:) is not supported; left out`); break;
          case 'hook': if (n.hook) walk(n.hook, cond); break;
          case 'textstyle': case 'font': case 'textcolour': case 'textcolor': case 'colour': case 'color': case 'background':
          case 'align': case 'css': case 'transition': case 't8n': case 'transitiontime': case 'textsize': case 'b4r':
          case 'hoverstyle': case 'textrotate': case 'box': case 'float': case 'nobr': case 'collapse':
            if (n.hook) walk(n.hook, cond);
            break;
          case 'random': case 'either':
            line.push(`{${twExpr(`(${n.name}: ${a})`, ctx)}}`); break;
          default:
            ctx.warn(`(${n.name}:) is not supported; ${n.hook ? 'its hook is kept as text' : 'left out'}`);
            if (n.hook) walk(n.hook, cond);
        }
      } else if (n.t === 'm') {
        // SugarCube
        switch (n.name) {
          case 'set': case 'run': { const s = twSet(n.args, ctx); if (s) effects.push({ cond, s }); break; }
          case 'goto': {
            const t = unquote(n.args) ?? n.args.replace(/^\[\[|\]\]$/g, '');
            diverts.push({ cond, target: target(t.trim()) });
            break;
          }
          case 'print': case '=': case '-': line.push(`{${cond ? `${cond}: {${twExpr(n.args, ctx)}}` : twExpr(n.args, ctx)}}`); break;
          case 'actions': case 'choice': {
            const re = /\[\[(.*?)\]\]/g;
            let m;
            while ((m = re.exec(n.args))) { const l = twLink(m[1]); choice(l.label, target(l.target), cond, l.setter ? twSet(l.setter, ctx) : null); }
            break;
          }
          case 'back': case 'return': ctx.warn(`<<${n.name}>> is not supported (use Undo in the app); left out`); break;
          case 'include': case 'display': ctx.warn(`<<${n.name}>> is not supported; left out`); break;
          default: ctx.warn(`<<${n.name}>> is not supported; left out`);
        }
      } else if (n.t === 'block' && n.name === 'if') {
        const prev = [];
        for (const b of n.branches) {
          const c = b.name === 'else' ? null : hoist(twExpr(b.args, ctx));
          const mine = prev.reduce((acc, x) => andCond(acc, `not (${x})`), null);
          walk(b.nodes, andCond(cond, andCond(mine, c)));
          if (c) prev.push(c);
        }
      } else if (n.t === 'block' && n.name === 'link') {
        const b = n.branches[0];
        const lm = b.args.match(/^\s*\[\[(.*?)\]\]\s*$/);
        let label, tgt = null;
        if (lm) { const l = twLink(lm[1]); label = l.label; tgt = l.target; }
        else {
          const args = b.args.match(/("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g) || [];
          label = unquote(args[0] || '""') ?? ''; tgt = args[1] ? unquote(args[1]) : null;
        }
        const sets = [];
        for (const x of b.nodes) {
          if (x.t === 'm' && (x.name === 'set' || x.name === 'run')) { const s = twSet(x.args, ctx); if (s) sets.push(s); }
          if (x.t === 'm' && x.name === 'goto') tgt = unquote(x.args) ?? x.args.replace(/^\[\[|\]\]$/g, '').trim();
        }
        if (tgt) choice(label, target(tgt), cond, sets.join('; ') || null);
        else ctx.warn(`<<link "${label}">> without a passage is not supported; left out`);
      }
    }
  }
  walk(nodes, null);
  endLine();
  while (lines.length && lines[0] === '') lines.shift();
  while (lines.length && lines[lines.length - 1] === '') lines.pop();
  // (goto:) / <<goto>> leave the passage at once: while one applies, its text and links are not
  // shown, so the app goes on without a page (a passage with no text and a "->" that holds)
  let away = null;
  if (diverts.some((d) => !d.cond)) { lines.length = 0; choices.length = 0; }
  else if (diverts.length) away = diverts.map((d) => `(${d.cond})`).join(' or ');
  const out = [];
  if (effects.length) for (const [c, f] of flags) out.push(`~ ${f} = ${c}`);
  for (const e of effects) out.push(`~ ${e.cond ? `{${e.cond}} ` : ''}${e.s}`);
  for (const l of lines) {
    if (l === '' && out[out.length - 1] === '') continue;
    out.push(away && l ? `{not (${away}): ${l}}` : l);
  }
  for (const c of choices) {
    const label = escText(stripMarkup(c.label).replace(/\s+/g, ' ').trim()).replace(/~/g, '\\~').replace(/->/g, '-\\>') || '…';
    const cond = away ? andCond(c.cond, `not (${away})`) : c.cond;
    out.push(`* ${cond ? `{${cond}} ` : ''}${label}${c.eff ? ` ~ ${c.eff}` : ''} -> ${c.target}`);
  }
  for (const d of diverts) out.push(`-> ${d.cond ? `{${d.cond}} ` : ''}${d.target}`);
  // with no (set:) in the passage the flags are not needed: the conditions go back in place
  if (!effects.length) {
    const back = new Map([...flags].map(([c, f]) => [f, c]));
    return out.map((l) => l.replace(/\b_c\d+\b/g, (f) => back.get(f) ?? f));
  }
  return out;
}

// ------------------------------------------------------------------ Ink

// a subset of Ink: knots and stitches, choices (* once, + sticky) with [] text and conditions,
// gathers and nested weaves, diverts, VAR / CONST, ~ assignments, {inline} logic and multi-line
// conditionals, glue. Each choice and gather becomes a passage of its own.
export function fromInk(src, fileName) {
  const warnings = [];
  const meta = { title: null };
  const vars = new Map();
  let where = 'top';
  const warn = (m) => warnings.push(`${where}: ${m}`);

  // comments out, lines kept
  src = src.replace(/\r/g, '').replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ''));
  const raw = src.split('\n').map((l) => l.replace(/(^|[^:\\])\/\/.*$/, '$1').replace(/\s+$/, ''));

  // the title from "# title: ..." tags at the top
  for (const l of raw) {
    const t = l.match(/^\s*#\s*title\s*:\s*(.+)$/i); if (t && !meta.title) meta.title = t[1].trim();
    const a = l.match(/^\s*#\s*author\s*:\s*(.+)$/i); if (a && !meta.author) meta.author = a[1].trim();
  }

  // knots: [{ name, lines }] ("" = the top before the first knot); stitches become knots "k.s"
  const knots = [{ name: '', lines: [] }];
  let knot = '';
  for (const l of raw) {
    let m;
    if ((m = l.match(/^\s*={2,}\s*(function\s+)?([A-Za-z_]\w*)\s*(\(([^)]*)\))?\s*=*\s*$/))) {
      if (m[1]) { warn(`function ${m[2]} is not supported; left out`); knots.push({ name: null, lines: [] }); knot = null; continue; }
      if (m[3] && m[4].trim()) warn(`knot ${m[2]} takes parameters, which are not supported`);
      knot = m[2];
      knots.push({ name: knot, lines: [] });
      continue;
    }
    if ((m = l.match(/^\s*=\s*([A-Za-z_]\w*)\s*(\(.*\))?\s*$/)) && knot) {
      knots.push({ name: `${knot}.${m[1]}`, lines: [], stitch: true, knot });
      continue;
    }
    if ((m = l.match(/^\s*(VAR|CONST)\s+([A-Za-z_]\w*)\s*=\s*(.+)$/))) {
      const v = m[3].trim();
      vars.set(m[2], /^-?\d+$/.test(v) ? parseInt(v, 10) : /^-?\d*\.\d+$/.test(v) ? Math.round(parseFloat(v)) : v === 'true' ? true : v === 'false' ? false : (unquote(v) ?? 0));
      if (/^-?\d*\.\d+$/.test(v)) warn(`${m[2]}: decimal numbers are rounded`);
      continue;
    }
    if (/^\s*LIST\s/.test(l)) { warn('LIST is not supported; left out'); continue; }
    if (/^\s*(INCLUDE|EXTERNAL)\s/.test(l)) { warn(`${l.trim().split(/\s/)[0]} is not supported; left out`); continue; }
    knots[knots.length - 1].lines.push(l);
  }
  const live = knots.filter((k) => k.name !== null);
  // a knot whose content is only its first stitch flows into it
  const names = new Set(live.map((k) => k.name).filter(Boolean));
  const passages = [];
  const labelsOf = new Map();          // knot -> label -> full passage name

  // names for references: "x" inside knot k may mean k.x (a stitch or a label) or a knot x
  function resolve(ref, k) {
    if (ref === 'END' || ref === 'DONE') return 'END';
    const base = k && k.includes('.') ? k.split('.')[0] : k;
    const labels = labelsOf.get(k) || new Map();
    if (labels.has(ref)) return labels.get(ref);
    if (base && names.has(`${base}.${ref}`)) return `${base}.${ref}`;
    const bl = labelsOf.get(base);
    if (bl && bl.has(ref)) return bl.get(ref);
    if (names.has(ref)) return ref;
    if (ref.includes('.')) {
      const [a, b] = ref.split('.');
      if (labelsOf.get(a)?.has(b)) return labelsOf.get(a).get(b);
      if (names.has(ref)) return ref;
    }
    return null;
  }
  // expressions: RANDOM -> random, identifiers resolved to passage names where they name one
  function expr(s, k) {
    return s.replace(/("(?:[^"\\]|\\.)*")|\b(RANDOM|MIN|MAX|POW|FLOOR|CEILING|INT|TURNS_SINCE|TURNS|CHOICE_COUNT|SEED_RANDOM|LIST_\w+)\b|([A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)?)/g, (m, str, fn, id) => {
      if (str) return str;
      if (fn) {
        if (fn === 'RANDOM' || fn === 'MIN' || fn === 'MAX') return fn.toLowerCase();
        if (fn === 'INT' || fn === 'FLOOR') return '';
        warn(`${fn}() is not supported`); return '0*';
      }
      if (['and', 'or', 'not', 'true', 'false', 'mod'].includes(id)) return id === 'mod' ? '%' : id;
      if (vars.has(id) || temps.has(id)) return id;
      const r = resolve(id, k);
      return r && r !== 'END' ? r : id;
    }).replace(/\?/g, () => { warn('the ? (contains) operator is not supported'); return '=='; });
  }
  let temps = new Set();
  // inline {...} in text: ink and .story share the syntax; expressions inside need resolving
  function inline(s, k) {
    let out = '', i = 0;
    while (i < s.length) {
      const c = s[i];
      if (c === '\\') { out += s.slice(i, i + 2); i += 2; continue; }
      if (c === '{') {
        let d = 0, j = i;
        for (; j < s.length; j++) { if (s[j] === '\\') { j++; continue; } if (s[j] === '{') d++; else if (s[j] === '}' && --d === 0) break; }
        const body = s.slice(i + 1, j);
        out += '{' + inlineBody(body, k) + '}';
        i = j + 1; continue;
      }
      if (c === '|' ) { out += '\\|'; i++; continue; }
      out += c; i++;
    }
    return out;
  }
  function inlineBody(body, k) {
    if (/^[&~!$]/.test(body)) {
      const mode = body[0];
      const items = splitTop(body.slice(1), ['|']).map((x) => inline(x, k));
      if (mode === '!') return items.join('|') + '|';
      if (mode === '$') { warn('shuffle-once {$...} is shown as a shuffle'); return '~' + items.join('|'); }
      return mode + items.join('|');
    }
    const colon = topColon(body);
    if (colon >= 0) {
      const branches = splitTop(body.slice(colon + 1), ['|']);
      return expr(body.slice(0, colon), k) + ':' + branches.map((x) => inline(x, k)).join('|');
    }
    const items = splitTop(body, ['|']);
    if (items.length > 1) return items.map((x) => inline(x, k)).join('|');
    return expr(body, k);
  }
  function topColon(s) {
    let d = 0, q = false;
    for (let i = 0; i < s.length; i++) {
      const c = s[i];
      if (c === '\\') { i++; continue; }
      if (c === '"') q = !q;
      else if (!q && c === '{') d++;
      else if (!q && c === '}') d--;
      else if (!q && d === 0 && c === ':') return i;
    }
    return -1;
  }

  // ---- one knot: lines -> items
  // item: { t: 'text', s, cond } | { t: 'eff', s, cond } | { t: 'divert', target, cond }
  //       | { t: 'choice', depth, sticky, label, out, cond, name, body: [items], divert }
  //       | { t: 'gather', depth, name }
  function items(lines, k) {
    const out = [];
    const condStack = [];
    const cond = () => condStack.filter(Boolean).reduce((a, b) => andCond(a, b), null);
    for (let idx = 0; idx < lines.length; idx++) {
      let l = lines[idx].trim();
      if (!l || /^#/.test(l) || /^TODO\b/.test(l)) { if (!l) out.push({ t: 'text', s: '', cond: cond() }); continue; }
      l = l.replace(/\s+#[^#{}]*$/, '');
      // multi-line { cond: ... - else: ... }  and { - a: ... - b: ... }
      let m;
      if ((m = l.match(/^\{\s*([^{}:]*):\s*$/)) || l === '{') {
        condStack.push(null);
        const ml = { first: m ? expr(m[1], k) : null, prev: [] };
        if (ml.first) { condStack[condStack.length - 1] = ml.first; ml.prev.push(ml.first); }
        mlStack.push(ml);
        continue;
      }
      if (mlStack.length && (m = l.match(/^-\s*(else|[^:]+?)\s*:\s*(.*)$/)) && !/^-\s*>/.test(l)) {
        const top = mlStack[mlStack.length - 1];
        const mine = top.prev.reduce((acc, x) => andCond(acc, `not (${x})`), null);
        if (m[1] === 'else') condStack[condStack.length - 1] = mine || 'true';
        else {
          const c = expr(m[1], k);
          condStack[condStack.length - 1] = andCond(mine, c);
          top.prev.push(c);
        }
        if (m[2]) lines.splice(idx + 1, 0, m[2]);
        continue;
      }
      if (mlStack.length && l === '}') { mlStack.pop(); condStack.pop(); continue; }
      if (mlStack.length && /^else\s*:/.test(l)) {
        const top = mlStack[mlStack.length - 1];
        condStack[condStack.length - 1] = top.prev.reduce((acc, x) => andCond(acc, `not (${x})`), null) || 'true';
        const rest = l.replace(/^else\s*:\s*/, ''); if (rest) lines.splice(idx + 1, 0, rest);
        continue;
      }
      // choices: * / + (several for nesting), (label), {cond}, text [choice only] output, -> target
      if ((m = l.match(/^((?:[*+]\s*)+)(.*)$/))) {
        const depth = (m[1].match(/[*+]/g) || []).length;
        const sticky = m[1].includes('+');
        let rest = m[2].trim();
        let name = null, c = null;
        let lm = rest.match(/^\(\s*([A-Za-z_]\w*)\s*\)\s*/);
        if (lm) { name = lm[1]; rest = rest.slice(lm[0].length); }
        while ((lm = rest.match(/^\{([^{}]*)\}\s*/)) && topColon(lm[1]) < 0 && !/\|/.test(lm[1])) {
          c = andCond(c, expr(lm[1], k)); rest = rest.slice(lm[0].length);
        }
        let divert = null;
        const dm = rest.match(/->\s*([A-Za-z_][\w.]*)\s*$/);
        if (dm) { divert = dm[1]; rest = rest.slice(0, dm.index).trim(); }
        let label, outText;
        const br = rest.match(/^(.*?)\[(.*?)\](.*)$/);
        if (br) { label = br[1] + br[2]; outText = br[1] + br[3]; } else { label = outText = rest; }
        out.push({ t: 'choice', depth, sticky, name, cond: andCond(cond(), c), label: label.trim(), out: outText.trim(), divert, k });
        continue;
      }
      // gathers: - (several for nesting), optional (label)
      if ((m = l.match(/^((?:-\s*)+)(?!>)(.*)$/)) && !/^-\s*>/.test(l)) {
        const depth = (m[1].match(/-/g) || []).length;
        let rest = m[2].trim(), name = null;
        const lm = rest.match(/^\(\s*([A-Za-z_]\w*)\s*\)\s*/);
        if (lm) { name = lm[1]; rest = rest.slice(lm[0].length); }
        out.push({ t: 'gather', depth, name });
        if (rest) lines.splice(idx + 1, 0, rest);
        continue;
      }
      if ((m = l.match(/^~\s*(.*)$/))) {
        let s = m[1].trim();
        if (/^temp\s+/.test(s)) { s = s.replace(/^temp\s+/, ''); const n = s.match(/^([A-Za-z_]\w*)/); if (n) { temps.add(n[1]); if (!vars.has(n[1])) vars.set(n[1], 0); } }
        if ((m = s.match(/^([A-Za-z_]\w*)\s*(\+\+|--)$/))) s = `${m[1]} ${m[2] === '++' ? '+=' : '-='} 1`;
        const a = s.match(/^([A-Za-z_]\w*)\s*(=|\+=|-=)\s*(.+)$/);
        if (a) out.push({ t: 'eff', s: `${a[1]} ${a[2]} ${expr(a[3], k)}`, cond: cond() });
        else warn(`"~ ${s}" is not supported; left out`);
        continue;
      }
      if (/^->->|<-/.test(l) || /->\s*->/.test(l)) { warn(`tunnels and threads are not supported: ${l}`); continue; }
      // text, maybe ending with a divert; glue <> joins lines
      let divert = null;
      const dm = l.match(/(^|[^\\])->\s*([A-Za-z_][\w.]*)\s*$/);
      if (dm) { divert = dm[2]; l = l.slice(0, dm.index + dm[1].length).trim(); }
      if (l) {
        const glueBefore = l.startsWith('<>'), glueAfter = l.endsWith('<>');
        l = l.replace(/^<>|<>$/g, '').replace(/<>/g, '');
        const prev = out[out.length - 1];
        if (glueBefore && prev && prev.t === 'text' && prev.s) prev.s += l;
        else out.push({ t: 'text', s: l, cond: cond(), glue: glueAfter });
        if (prev && prev.t === 'text' && prev.glue && !glueBefore && out[out.length - 1] !== prev) {
          prev.s += out.pop().s;
          prev.glue = glueAfter;
        }
      }
      if (divert) out.push({ t: 'divert', target: divert, cond: cond() });
    }
    return out;
  }
  const mlStack = [];

  // ---- weave: items -> passages
  let counter = 0;

  function emit(knotName, list) {
    const k = knotName;
    where = k || 'top';
    const mk = (suffix) => `${k || 'top'}.${suffix}`;
    // passage being written
    function newPassage(id) { const p = { id, lines: [], choices: 0, diverted: false }; passages.push(p); return p; }
    function textLine(p, it) {
      const s = it.s ? inline(it.s.replace(/^(\*|->|~|==|-)/, '\\$1'), k) : '';
      if (!s && it.s) return;
      p.lines.push(it.cond && s ? `{${it.cond}: ${s}}` : s);
    }
    // write items at choice depth `depth`; `after` = where loose ends go
    function run(p, list, depth, after) {
      let i = 0;
      while (i < list.length) {
        const it = list[i];
        if (it.t === 'text') { textLine(p, it); i++; continue; }
        if (it.t === 'eff') { p.lines.push(`~ ${it.cond ? `{${it.cond}} ` : ''}${it.s}`); i++; continue; }
        if (it.t === 'divert') {
          const tgt = resolve(it.target, k);
          if (!tgt) warn(`-> ${it.target}: no such knot, stitch or label`);
          p.lines.push(`-> ${it.cond ? `{${it.cond}} ` : ''}${tgt || 'END'}`);
          if (!it.cond) p.diverted = true;
          i++; continue;
        }
        if (it.t === 'gather' && it.depth <= depth) return { p, rest: list.slice(i) };
        if (it.t === 'gather') { i++; continue; }
        if (it.t === 'choice' && it.depth < depth) return { p, rest: list.slice(i) };
        if (it.t === 'choice') {
          // the group: choices at this depth until a gather of depth <= this one
          const group = [];
          while (i < list.length) {
            const c = list[i];
            if (c.t === 'gather' && c.depth <= it.depth) break;
            if (c.t === 'choice' && c.depth < it.depth) break;
            if (c.t === 'choice' && c.depth === it.depth) { group.push({ c, body: [] }); i++; continue; }
            group[group.length - 1].body.push(c); i++;
          }
          for (const g of group) while (g.body.length && g.body[g.body.length - 1].t === 'text' && !g.body[g.body.length - 1].s) g.body.pop();
          let gatherId = null, gatherItem = null;
          if (i < list.length && list[i].t === 'gather' && list[i].depth === it.depth) {
            gatherItem = list[i];
            gatherId = gatherItem.name ? labelsOf.get(k).get(gatherItem.name) : mk('g' + (++counter));
            i++;
          } else if (i < list.length && list[i].t === 'gather') {
            gatherItem = list[i];
          }
          const loose = gatherId || after;
          for (const { c, body } of group) {
            const cid = c.name ? labelsOf.get(k).get(c.name) : mk('c' + (++counter));
            if (!c.label && !c.out) {
              // a fallback choice: taken when nothing else is left
              const tgt = c.divert ? resolve(c.divert, k) : cid;
              p.lines.push(`-> ${c.cond ? `{${c.cond}} ` : ''}${tgt || 'END'}`);
              if (!c.divert || body.length) writeChoice(cid, c, body, it.depth, loose);
              continue;
            }
            const label = inline(c.label, k).replace(/->/g, '-\\>').replace(/(^|\s)~/g, '$1\\~');
            const target = (!body.length && !c.out && c.divert) ? (resolve(c.divert, k) || 'END') : cid;
            p.lines.push(`* ${c.sticky ? '' : '[once] '}${c.cond ? `{${c.cond}} ` : ''}${label} -> ${target}`);
            p.choices++;
            if (target === cid) writeChoice(cid, c, body, it.depth, loose);
          }
          if (gatherId) {
            const g = newPassage(gatherId);
            const r = run(g, list.slice(i), depth, after);
            close(r.p, after);
            return { p: g, rest: r.rest, done: true };
          }
          if (gatherItem && gatherItem.depth < it.depth) return { p, rest: list.slice(i), done: true };
          // no gather: what follows (more text) cannot be reached in ink either
          return { p, rest: [], done: true };
        }
        i++;
      }
      return { p, rest: [] };
    }
    function writeChoice(cid, c, body, depth, loose) {
      const cp = newPassage(cid);
      if (c.out) textLine(cp, { s: c.out });
      if (c.divert) {
        const tgt = resolve(c.divert, k);
        const r = run(cp, body, depth + 1, loose);
        if (!r.p.diverted && !r.p.choices) { r.p.lines.push(`-> ${tgt || 'END'}`); r.p.diverted = true; }
        return;
      }
      const r = run(cp, body, depth + 1, loose);
      close(r.p, loose);
    }
    function close(p, after) {
      if (!p.diverted && !p.choices) { p.lines.push(`-> ${after || 'END'}`); p.diverted = true; }
    }
    // the knot itself; its loose end runs out (END), except a knot's text flowing into its
    // first stitch (ink does that when the knot has no divert of its own)
    const first = newPassage(k || 'top');
    let next = null;
    const kn = live.findIndex((x) => x.name === k);
    if (kn >= 0 && live[kn + 1] && live[kn + 1].stitch && live[kn + 1].knot === k) next = live[kn + 1].name;
    let r = run(first, list, 1, next);
    while (r.rest && r.rest.length) {
      // a gather at depth 1 with nothing before it, or leftovers: go on in a new passage
      const g = r.rest[0];
      const gid = g.t === 'gather' && g.name ? labelsOf.get(k).get(g.name) : mk('g' + (++counter));
      if (!r.p.diverted && !r.p.choices) r.p.lines.push(`-> ${gid}`);
      const np = newPassage(gid);
      r = run(np, g.t === 'gather' ? r.rest.slice(1) : r.rest, 1, next);
    }
    close(r.p, next);
  }

  const parsed = live.map((kn) => {
    temps = new Set();
    where = kn.name || 'top';
    const its = items(kn.lines.slice(), kn.name);
    // labels of choices and gathers -> passage names
    const lab = new Map();
    for (const it of its) if ((it.t === 'choice' || it.t === 'gather') && it.name) lab.set(it.name, `${kn.name || 'top'}.${it.name}`);
    labelsOf.set(kn.name, lab);
    return { kn, its };
  });
  for (const { kn, its } of parsed) {
    const hasContent = its.some((x) => x.t !== 'text' || x.s);
    if (!kn.name && !hasContent) continue;
    emit(kn.name, its);
  }
  // the top: ink starts there; with nothing there, at the first knot
  const ids = new Set(passages.map((p) => p.id));
  for (const p of passages) {
    while (p.lines.length && p.lines[0] === '') p.lines.shift();
  }
  if (!ids.has('top') && passages.length) meta.start = passages[0].id;
  // names: ink allows a knot called "top"; ours may not clash with variables
  for (const n of vars.keys()) if (ids.has(n)) warn(`the variable ${n} has the same name as a knot; the variable wins in conditions`);
  meta.title = meta.title || (fileName || 'Untitled').replace(/\.[^.]+$/, '');
  const story = serialize(meta, vars, passages);
  const c = check(story);
  return { story, warnings: [...warnings, ...c.errors], info: { format: 'Ink', passages: passages.length } };
}

// ------------------------------------------------------------------ checking a .story file

export function check(text) {
  const errors = [], warnings = [];
  const names = new Set(), targets = [];
  let cur = null, n = 0, lineNo = 0;
  const vars = new Set();
  // a "->" is used only when no choice is shown: with a choice that is always shown it never is
  const shape = new Map();
  const note = (k) => { const s = shape.get(cur) || {}; if (!s[k]) s[k] = lineNo; shape.set(cur, s); };
  for (const raw of text.replace(/\r/g, '').split('\n')) {
    lineNo++;
    const l = raw.trim();
    let m;
    if ((m = l.match(/^==+\s*([A-Za-z_][\w.]*)/))) {
      cur = m[1]; n++;
      if (names.has(cur)) errors.push(`line ${lineNo}: a second passage called ${cur} (the first one is used)`);
      names.add(cur);
      continue;
    }
    if (!cur) {
      if ((m = l.match(/^var\s*:\s*([A-Za-z_][\w.]*)\s*=/))) vars.add(m[1]);
      continue;
    }
    if (l.startsWith('*') && !/^\*\s*(\[once\]\s*)?\{/.test(l)) note('always');
    if (l.startsWith('->')) note('divert');
    if ((m = l.match(/^\*.*->\s*([A-Za-z_][\w.]*)\s*$/)) || (m = l.match(/^->\s*(?:\{.*\}\s*)?([A-Za-z_][\w.]*)/))) {
      targets.push([m[1], lineNo, cur]);
    } else if (l.startsWith('*')) warnings.push(`line ${lineNo} (${cur}): a choice without "-> passage" ends the story`);
  }
  for (const [t, ln, from] of targets) {
    if (t !== 'END' && t !== 'DONE' && !names.has(t)) errors.push(`line ${ln} (${from}): no passage called ${t}`);
  }
  for (const [p, s] of shape) {
    if (s.always && s.divert) warnings.push(`line ${s.divert} (${p}): this "->" is never used, because the passage always shows a choice (put the check in a passage of its own, with no text)`);
  }
  if (!n) errors.push('no passages: each starts with a line "== name"');
  return { passages: n, errors, warnings };
}
