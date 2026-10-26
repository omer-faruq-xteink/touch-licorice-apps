"""Build the Anki app's built-in English deck: data/en_info.txt and data/en_c000.txt ...

  python -I apps/anki/make_default_deck.py WORDNET_ZIP [--count 2000] [--from-rank 4000] [--to-rank 16000]

Words: English words by frequency from wordfreq (Robyn Speer, data CC BY-SA 4.0), skipping the
most common ones (--from-rank) so the deck starts past everyday basics, up to about the rank where
words get rare. A word is kept only if WordNet (Princeton, WordNet licence) gives it a sense with
an example sentence that uses the word; inflected forms (plurals, -ed, -ing) whose base word is in
WordNet, and proper names, are left out.

Card: the front is the word and its part of speech; the back holds up to two senses, each with
its definition and an example sentence, and a line of similar words.

WORDNET_ZIP is the Dictionary's dict-wordnet-en.zip (wn_d000.txt ... shards of
"word<TAB>definition", with "\\n" for line breaks). Card order is fixed: a rebuilt deck must keep
the cards of the old one at their places (progress on the device is kept by position), so add
new cards only at the end.
"""
import argparse, os, re, sys, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
POS = {'n': 'noun', 'v': 'verb', 'adj': 'adjective', 'adv': 'adverb'}
PER_SHARD = 200


def load_wordnet(path):
    wn = {}
    with zipfile.ZipFile(path) as z:
        for name in sorted(z.namelist()):
            if re.match(r'wn_d\d+\.txt$', name):
                for line in z.read(name).decode('utf-8').split('\n'):
                    w, _, d = line.partition('\t')
                    if w and d:
                        wn.setdefault(w, d)
    return wn


def senses(defn):
    """[(pos, gloss, [examples], [synonyms])] in WordNet order"""
    out, pos = [], None
    for part in defn.split('\\n'):
        part = part.strip()
        m = re.match(r'^(n|v|adj|adv)\s+(\d+):\s*(.*)$', part)
        if m:
            pos, body = m.group(1), m.group(3)
        else:
            m = re.match(r'^(\d+):\s*(.*)$', part)
            if not m or not pos:
                continue
            body = m.group(2)
        syn = re.findall(r'\{([^}]+)\}', ' '.join(re.findall(r'\[syn: ([^\]]*)\]', body)))
        syn = [re.sub(r'\(\w\)$', '', x) for x in syn]           # "howling(a)": WordNet's position marks
        body = re.sub(r'\[(syn|ant|also):[^\]]*\]', '', body).strip()
        examples = re.findall(r'"([^"]+)"', body)
        gloss = re.split(r';\s*"', body, maxsplit=1)[0].strip(' ;')
        out.append((pos, gloss, examples, syn))
    return out


def uses(example, word):
    return re.search(r'\b' + re.escape(word[:max(4, len(word) - 2)]), example, re.I) is not None


def card(word, defn):
    """the word's main sense (WordNet lists the most frequent first) must come with an example
    that uses the word; a second sense of the same part of speech among the next two is added
    when it has one too"""
    ss = senses(defn)
    if not ss or not any(uses(e, word) for e in ss[0][2]):
        return None
    pos = ss[0][0]
    good = [ss[0]] + [s for s in ss[1:3] if s[0] == pos and any(uses(e, word) for e in s[2])][:1]
    lines, similar = [], []
    for k, (_p, gloss, examples, syn) in enumerate(good, 1):
        ex = next(e for e in examples if uses(e, word))
        lines.append(f'{k}. {gloss}' if len(good) > 1 else gloss)
        lines.append(f'   "{ex}"')
        similar += [s for s in syn if s != word and s not in similar]
    if similar:
        lines.append('Similar: ' + ', '.join(similar[:4]))
    return f'{word}\\n({POS[pos]})', '\\n'.join(lines)


def inflected(word, wn):
    for suf, rep in (('ies', 'y'), ('es', ''), ('s', ''), ('ied', 'y'), ('ed', ''), ('ed', 'e'), ('ing', ''), ('ing', 'e')):
        if word.endswith(suf) and len(word) - len(suf) >= 3:
            base = word[:-len(suf)] + rep
            if base in wn and base != word:
                return True
    if word.endswith('ly') and (word[:-2] in wn or word[:-3] + 'y' in wn or word[:-2] + 'le' in wn
                                or (word.endswith('ally') and word[:-4] in wn)):
        return True                      # an adverb made from an adjective
    if re.search(r'(.)\1(ed|ing)$', word) and word[:-3 if word.endswith('ing') else -2][:-1] in wn:
        return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('wordnet_zip')
    ap.add_argument('--count', type=int, default=2000)
    ap.add_argument('--from-rank', type=int, default=4000)
    ap.add_argument('--to-rank', type=int, default=16000)
    ap.add_argument('--preview', type=int, default=0)
    a = ap.parse_args()
    from wordfreq import top_n_list
    wn = load_wordnet(a.wordnet_zip)
    cards = []
    ranked = top_n_list('en', 60000)
    for rank, w in enumerate(ranked):
        if rank >= a.to_rank:
            break
        if rank < a.from_rank or not re.fullmatch(r'[a-z]{4,}', w) or w not in wn or inflected(w, wn):
            continue
        c = card(w, wn[w])
        if c:
            cards.append((rank, w, c))
        if len(cards) >= a.count:
            break
    print(f'{len(cards)} cards, ranks {cards[0][0]}..{cards[-1][0]}')
    if a.preview:
        for rank, w, (f, b) in cards[::max(1, len(cards) // a.preview)]:
            print(f'--- #{rank} {f}\n{b}'.replace('\\n', '\n'))
        return
    ddir = os.path.join(HERE, 'data')
    os.makedirs(ddir, exist_ok=True)
    for fn in os.listdir(ddir):
        if fn.startswith('en_'):
            os.remove(os.path.join(ddir, fn))
    shards = (len(cards) + PER_SHARD - 1) // PER_SHARD
    for s in range(shards):
        part = cards[s * PER_SHARD:(s + 1) * PER_SHARD]
        with open(os.path.join(ddir, f'en_c{s:03d}.txt'), 'w', encoding='utf-8', newline='\n') as f:
            for rank, w, (front, back) in part:
                f.write(f'en{w}\t{front}\t{back}\n')
    with open(os.path.join(ddir, 'en_info.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(f'name=English words B2-C1\ncards={len(cards)}\nshards={shards}\nper={PER_SHARD}\n'
                'source=words by frequency from wordfreq (CC BY-SA 4.0), senses and examples from WordNet 3.0\n')
    print(f'wrote {shards} shards to {ddir}')


if __name__ == '__main__':
    main()
