// Difficulty estimate of a piece from its note map (see convert.mjs). The four levels steer the
// catalog; catalog.yaml can override any of them after the review.
export function features(map, bpm = 90) {
  const on = map.onsets;
  if (!on.length) return { notesPerSec: 0, span: 0, chordMean: 0, lhActive: 0, onsets: 0 };
  let notes = 0, lo = 127, hi = 0, lhOn = 0;
  for (const o of on) {
    const all = [...o[5], ...o[6]];
    notes += all.length;
    for (const p of all) { lo = Math.min(lo, p); hi = Math.max(hi, p); }
    if (o[6].length) lhOn++;
  }
  const quarters = on[on.length - 1][0] - on[0][0] + 1;
  return { notesPerSec: notes / (quarters * 60 / bpm), span: hi - lo, chordMean: notes / on.length, lhActive: lhOn / on.length, onsets: on.length };
}

export function level(map, bpm = 90) {
  const f = features(map, bpm);
  const score = f.notesPerSec + f.span / 12 * 0.5 + (f.chordMean - 1) * 1.5 + f.lhActive;
  return score < 4.5 ? 'beginner' : score < 6.5 ? 'easy' : score < 9 ? 'intermediate' : 'advanced';   // re-tuned on the catalog
}
