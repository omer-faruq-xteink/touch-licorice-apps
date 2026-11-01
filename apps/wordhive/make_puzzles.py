"""Word Hive puzzles: 12dicts' 2of12inf word list -> data/puzzles.txt, one puzzle a line:

  <centre letter><six outer letters> <answer> <answer> ...

Seven different letters (never S, so plurals do not double every list), at least one pangram (a
word using all seven), every answer at least four letters long and holding the centre letter.
Answer lists of 20 to 50 words. The order is shuffled with a fixed seed: the app plays line
N on day N (counted from 1 November 2026) and starts over after the last one.

2of12inf is Alan Beale's 12dicts list with inflections (public domain; its inflections come from
Kevin Atkinson's AGID, see LICENSE-12dicts.txt). Get it from http://wordlist.aspell.net/12dicts/
(12dicts-6.0.2.zip, American/2of12inf.txt), then

  python -I apps/wordhive/make_puzzles.py PATH/2of12inf.txt
"""
import os, random, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
N_PUZZLES = 730
MIN_WORDS, MAX_WORDS = 20, 50

# left out: words a family puzzle should not ask for (exact words, and roots that start a word)
BLOCK = set('''cock cocks tit tits titty titties homo coon coons anal anus orgy orgies spic gook gooks
kike kikes chink chinks honky honkies jap japs dago dagos wop wops paki gyp gypped gypping tranny
negro negroes nigra boob boobie booby boobies hooker hookers horny bimbo poof poofter frig frigged
frigging fart farted farting poop pooped pooping booty randy'''.split())
BLOCK_ROOTS = ('fuck', 'cunt', 'nigg', 'whor', 'slut', 'fag', 'dyke', 'dick', 'twat', 'wank', 'turd',
               'bitch', 'bastard', 'crap', 'damn', 'rape', 'rapi', 'pervert', 'penis', 'vagin', 'erotic',
               'orgasm', 'nipple', 'dildo', 'porn', 'retard', 'nazi', 'jizz', 'pimp', 'butthole', 'lesbo',
               'wetback', 'goddam', 'bugger', 'bollock', 'prick', 'pecker', 'boner', 'hell', 'piss', 'shit')


def load(path):
    words = set()
    for line in open(path, encoding='latin-1'):
        w = re.sub(r'[^a-z]', '', line.strip().split()[0] if line.strip() else '')
        if len(w) >= 4 and 's' not in w and len(set(w)) <= 7 and line.strip().rstrip('%!~=+^&').isalpha():
            if w not in BLOCK and not w.startswith(BLOCK_ROOTS):
                words.add(w)
    return words


def score(w, letters):
    return (1 if len(w) == 4 else len(w)) + (7 if set(w) == letters else 0)


def main(path):
    words = load(path)
    by_mask = {}
    for w in words:
        by_mask.setdefault(frozenset(w), []).append(w)
    sets = sorted({frozenset(w) for w in words if len(set(w)) == 7}, key=lambda s: ''.join(sorted(s)))
    rnd = random.Random(20261101)
    rnd.shuffle(sets)
    out, used_words = [], 0
    for s in sets:
        letters = sorted(s)
        subsets = []
        for bits in range(1, 128):
            sub = frozenset(letters[i] for i in range(7) if bits >> i & 1)
            subsets += by_mask.get(sub, [])
        centres = letters[:]
        rnd.shuffle(centres)
        for c in centres:
            ans = sorted(w for w in subsets if c in w)
            if MIN_WORDS <= len(ans) <= MAX_WORDS and any(set(w) == s for w in ans):
                outer = [l for l in letters if l != c]
                out.append(c + ''.join(outer) + ' ' + ' '.join(ans))
                used_words += len(ans)
                break
        if len(out) >= N_PUZZLES:
            break
    os.makedirs(os.path.join(HERE, 'data'), exist_ok=True)
    with open(os.path.join(HERE, 'data', 'puzzles.txt'), 'w', encoding='ascii', newline='\n') as f:
        f.write('\n'.join(out) + '\n')
    print(f'{len(words)} words, {len(sets)} pangram letter sets -> {len(out)} puzzles, '
          f'{used_words / len(out):.1f} answers each, longest line {max(map(len, out))}')


if __name__ == '__main__':
    main(sys.argv[1])
