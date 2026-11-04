// The pronunciation of vowelled Arabic, by rules, for the Anki converter: min, allâhi, wash-shamsi
// (site/test/test_translit.mjs has the Arabic). Words of the Quran come with every vowel
// mark, so the reading follows from the letters: short vowels, sukun, shadda (doubled), tanween,
// long vowels, the article (al-, merged into the sun letters), the silent alif after the plural
// waw and after -an, and the superscript alif.
//
// Letters the reader's fonts surely have: long vowels â î û (as in Turkish and French), hamza ’,
// ʿayn ‘, and the emphatic consonants as plain letters (h s d t z), since dotted letters may be
// missing from the system fonts.
//
//   arabicReading(text) -> the reading of each Arabic word ('' when there is no Arabic)

const LETTER = {
  'ب': 'b', 'ت': 't', 'ث': 'th', 'ج': 'j', 'ح': 'h', 'خ': 'kh', 'د': 'd', 'ذ': 'dh', 'ر': 'r',
  'ز': 'z', 'س': 's', 'ش': 'sh', 'ص': 's', 'ض': 'd', 'ط': 't', 'ظ': 'z', 'ع': '‘', 'غ': 'gh',
  'ف': 'f', 'ق': 'q', 'ك': 'k', 'ل': 'l', 'م': 'm', 'ن': 'n', 'ه': 'h', 'و': 'w', 'ي': 'y',
  'ء': '’', 'أ': '’', 'إ': '’', 'ؤ': '’', 'ئ': '’', 'ة': 't',
  'ا': '', 'ٱ': '', 'آ': '', 'ى': '',
};
const SUN = new Set(['ت', 'ث', 'د', 'ذ', 'ر', 'ز', 'س', 'ش', 'ص', 'ض', 'ط', 'ظ', 'ل', 'ن']);
const ALIF = new Set(['ا', 'ٱ']);
const HAMZA = new Set(['ء', 'أ', 'إ', 'ؤ', 'ئ']);
const MARK = {
  '\u064E': 'a', '\u064F': 'u', '\u0650': 'i', '\u064B': 'an', '\u064C': 'un', '\u064D': 'in',
  '\u0652': 'sukun', '\u06E1': 'sukun', '\u0651': 'shadda', '\u0670': 'dagger', '\u0653': 'madda',
  '\u06E5': 'smallwaw', '\u06E6': 'smallya',
};
const LONG = { a: 'â', i: 'î', u: 'û' };
const ARABIC = /[\u0621-\u064A\u0671]/u;

// a word as units: { c: letter, v: vowel ('a' 'i' 'u' 'an' 'in' 'un' or ''), sukun, shadda, dagger, ... }
function units(word) {
  const out = [];
  for (const ch of word) {
    if (ch in LETTER) out.push({ c: ch, v: '' });
    else if (ch in MARK && out.length) {
      const u = out[out.length - 1], m = MARK[ch];
      if (m.length <= 2) u.v = m; else u[m] = true;
    }
  }
  return out;
}

function readWord(word) {
  const us = units(word);
  let out = '';
  const lengthen = (v) => {                 // the short vowel just written becomes long
    if (out.endsWith(v)) out = out.slice(0, -1) + LONG[v];
    else out += LONG[v];
  };
  for (let i = 0; i < us.length; i++) {
    const u = us[i], prev = us[i - 1], next = us[i + 1], after = us[i + 2];
    const first = i === 0, last = i === us.length - 1;
    // the article: an alif (no vowel) before a lam without one, then a letter
    if (ALIF.has(u.c) && !u.v && next && next.c === 'ل' && !next.v && after) {
      out += first ? 'a' : '';
      if (after.c === 'ل' && after.shadda && us[i + 3] && us[i + 3].c === 'ه') {   // allâhi, billâhi
        out += 'llâ';
        i += 2;
        continue;
      }
      if (SUN.has(after.c) && after.shadda) {
        out += LETTER[after.c] + '-';
        us[i + 2] = { ...after, shadda: false };
      } else out += 'l-';
      i += 1;
      continue;
    }
    // the name of God after li- / wa- ...: lillâhi, allâhumma
    if (u.c === 'ل' && u.shadda && next && next.c === 'ه' && prev && (prev.c === 'ل' || ALIF.has(prev.c))) {
      out += 'llâ';
      continue;
    }
    // lin-nâsi: a lam without a vowel after li-, before a doubled sun letter
    if (u.c === 'ل' && !u.v && !u.sukun && next && next.shadda && prev && prev.c === 'ل' && SUN.has(next.c)) {
      out += LETTER[next.c] + '-';
      us[i + 1] = { ...next, shadda: false };
      continue;
    }
    // lil-’abrâri: the article's lam after li-, before a letter that is not doubled
    if (u.c === 'ل' && u.sukun && i === 1 && prev.c === 'ل' && prev.v === 'i' && next && !next.shadda) {
      out += 'l-';
      continue;
    }
    if (u.c === 'آ') { out += (first ? '' : '’') + 'â'; continue; }
    if (ALIF.has(u.c)) {
      // a first alif: its own vowel, else "a" before a lam (alladhîna, allatî), else "i" (ism, ibn)
      if (first) { out += u.v || (next && next.c === 'ل' ? 'a' : 'i'); continue; }
      if (prev && (prev.v === 'an' || (prev.c === 'و' && last && !prev.v))) continue;   // -an, -û: silent
      if (u.c === 'ٱ') continue;                                                            // wasla
      // a joining alif (wasla) after a prefix: before a vowelless letter (fa-qdhifîhi, wa-sma‘),
      // or after bi- / li- (bi-lladhî); after -a before a doubled letter it is long (ad-dâllîna)
      if ((next && next.sukun) || (prev && (prev.v === 'i' || prev.v === 'u'))) continue;
      lengthen('a');
      continue;
    }
    if (u.c === 'ى') {
      if (prev && prev.v === 'an') continue;
      lengthen('a');
      continue;
    }
    // the waw of ulâ’ika, ulû, ulî is only spelled
    if (u.c === 'و' && !u.v && i === 1 && prev.c === 'أ' && prev.v === 'u' && next && next.c === 'ل') continue;
    if (u.c === 'و' && !u.v && !u.shadda && prev && prev.v === 'u') { lengthen('u'); continue; }
    if (u.c === 'ي' && !u.v && !u.shadda && prev && prev.v === 'i') { lengthen('i'); continue; }
    if (u.c === 'ة' && !u.v) { out += 'h'; continue; }
    if (HAMZA.has(u.c) && first) {
      out += u.v || (u.c === 'إ' ? 'i' : u.c === 'ؤ' ? 'u' : 'a');
    } else {
      const l = LETTER[u.c];
      out += u.shadda ? l + l : l;
      out += u.v;
    }
    if (u.dagger || u.madda) lengthen('a');
    if (u.smallwaw) lengthen('u');
    if (u.smallya) lengthen('i');
  }
  return out;
}

export function arabicReading(text) {
  return text.split(/\s+/).filter((w) => ARABIC.test(w)).map(readWord).filter(Boolean).join(' ');
}
