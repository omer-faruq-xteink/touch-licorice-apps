// The Arabic reading rules of the Anki converter (site/tools/anki/translit.js) on common words of
// the Quran.   node site/test/test_translit.mjs
import { arabicReading } from '../tools/anki/translit.js';

const CASES = [
  ['مِنْ', 'min'], ['اللَّهِ', 'allâhi'], ['فِي', 'fî'], ['الَّذِينَ', 'alladhîna'], ['لَا', 'lâ'],
  ['مَا', 'mâ'], ['إِنَّ', 'inna'], ['إِلَّا', 'illâ'], ['وَلَا', 'walâ'], ['أَنْ', 'an'],
  ['قَالَ', 'qâla'], ['قَالُوا', 'qâlû'], ['تَحْكُمُوا', 'tahkumû'], ['السَّمَاوَاتِ', 'as-samâwâti'],
  ['الْكِتَابَ', 'al-kitâba'], ['وَالشَّمْسِ', 'wash-shamsi'], ['بِاللَّهِ', 'billâhi'], ['لِلَّهِ', 'lillâhi'],
  ['لِلنَّاسِ', 'lin-nâsi'], ['شَيْئًا', 'shay’an'], ['هُدًى', 'hudan'], ['عَلَى', '‘alâ'], ['هَٰذَا', 'hâdhâ'],
  ['آمَنُوا', 'âmanû'], ['مُؤْمِنٌ', 'mu’minun'], ['يَوْمَ', 'yawma'], ['رَحْمَةً', 'rahmatan'],
  ['اللَّهُمَّ', 'allâhumma'], ['بِبَغْيِهِمْ', 'bibaghyihim'], ['مَوَاخِرَ', 'mawâkhira'], ['وَالْأَرْضِ', 'wal-’ardi'],
  ['ذَٰلِكَ', 'dhâlika'], ['أُولَٰئِكَ', 'ulâ’ika'], ['رَبِّ', 'rabbi'], ['الرَّحْمَٰنِ', 'ar-rahmâni'],
  ['فَاقْذِفِيهِ', 'faqdhifîhi'], ['وَاسْمَعْ', 'wasma‘'], ['بِالَّذِي', 'billadhî'], ['الضَّالِّينَ', 'ad-dâllîna'],
  ['لِلْأَبْرَارِ', 'lil-’abrâri'],
  ['hello', ''], ['بِسْمِ اللَّهِ', 'bismi allâhi'],
];
let bad = 0;
for (const [ar, want] of CASES) {
  const got = arabicReading(ar);
  if (got !== want) { bad++; console.log(`${ar}: got ${got}, want ${want}`); }
}
if (bad) { console.log(`translit: ${bad} of ${CASES.length} wrong`); process.exit(1); }
console.log(`translit: ${CASES.length} words read right`);
