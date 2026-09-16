// t57 - הפינות יוצאות 90 מעלות מדויקות, ונשארות כאלה.
//
// שני באגים אמיתיים שהוא נתקל בהם, שניהם כאן:
//
// 1. הוא צייר קירות ישרים וקיבל פינות של 89.8 ו-90.2 מעלות. הסיבה: אחרי
//    שהזווית ננעלה במדויק, שתי הקואורדינטות עוגלו לחצי אינץ' - וחצי אינץ'
//    לרוחב קיר של 22 רגל הוא 0.11 מעלות בדיוק.
// 2. תיקון פינה אחת קלקל את השכנה, כי כל קיר נוגע בשתי פינות.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };

// ---------- 1. הציור עצמו יוצא ישר ----------
s('walls', []); s('pending', []); s('ghosts', []); s('sketches', []);
s('pendingSketches', []); s('guides', []); s('curLine', null); s('scale', 1);

// קיר של 22 רגל שמצויר בסטייה של 2 מעלות - בדיוק המקרה שלו.
// הפינה שממנה מתחילים כמעט אף פעם לא יושבת על רשת של חצי אינץ' - היא
// באה מהצמדה לפינה קיימת. שם בדיוק העיגול הרס את הזווית.
const from = { x: 0.3, y: 0.2 };
const a2 = 2 * Math.PI / 180, L = 264;
const q = c('snapPoint', { x: from.x + Math.cos(a2) * L, y: from.y + Math.sin(a2) * L }, from);
ok('קיר של 22 רגל יוצא אופקי מושלם, בלי 0.1 מעלות של עיגול',
   Math.abs(q.y - from.y) < 1e-9, [q.x, q.y, from]);
const degOff = Math.abs(Math.atan2(q.y - from.y, q.x - from.x) * 180 / Math.PI);
ok('הסטייה היא אפס, לא 0.11', degOff < 1e-9, degOff);

// ---------- 2. יישור כל הפינות יחד ----------
// חדר 22x19 רגל שכל פינה בו סוטה קצת - כמו בצילומים שלו.
const W = 264, H = 228;
const room = [
  { sx: 0,     sy: 0.4,  ex: W - 0.3, ey: 0,     th: 8, ha: 'left', cat: 'exterior', ops: [] },
  { sx: W - 0.3, sy: 0,  ex: W + 0.2, ey: H,     th: 8, ha: 'left', cat: 'exterior', ops: [] },
  { sx: W + 0.2, sy: H,  ex: 0.5,     ey: H - 0.4, th: 8, ha: 'left', cat: 'exterior', ops: [] },
  { sx: 0.5,   sy: H - 0.4, ex: 0,    ey: 0.4,   th: 8, ha: 'left', cat: 'exterior', ops: [] }
];
const degOf = (w) => Math.atan2(w.ey - w.sy, w.ex - w.sx) * 180 / Math.PI;
const offAxis = (w) => { const d = ((degOf(w) % 90) + 90) % 90; return Math.min(d, 90 - d); };
ok('בהתחלה כל הקירות עקומים', room.every(w => offAxis(w) > 0.02),
   room.map(offAxis));

const fixed = c('squareUpWalls', room, 12);
ok('אחרי היישור כל קיר יושב על ציר מדויק',
   fixed.every(w => offAxis(w) < 1e-9), fixed.map(offAxis));

// הפינות באמת סגורות - הקצה של כל קיר הוא בדיוק ההתחלה של הבא.
let joined = true;
for (let i = 0; i < 4; i++) {
  const a = fixed[i], b = fixed[(i + 1) % 4];
  if (Math.abs(a.ex - b.sx) > 1e-9 || Math.abs(a.ey - b.sy) > 1e-9) joined = false;
}
ok('והפינות סגורות בדיוק - לא נפתח פער', joined, fixed);

// זו התלונה עצמה: לא ייתכן שיישור אחד מקלקל אחר. להריץ שוב לא משנה כלום.
const again = c('squareUpWalls', fixed, 12);
ok('הרצה שנייה לא מזיזה כלום - אין וויכוח בין פינות',
   again.every((w, i) => Math.abs(w.sx - fixed[i].sx) < 1e-9 &&
                         Math.abs(w.sy - fixed[i].sy) < 1e-9 &&
                         Math.abs(w.ex - fixed[i].ex) < 1e-9 &&
                         Math.abs(w.ey - fixed[i].ey) < 1e-9), again);

// התזוזה קטנה - מיישרים, לא מעצבים מחדש.
ok('התיקון קטן מאינץ אחד',
   fixed.every((w, i) => Math.hypot(w.sx - room[i].sx, w.sy - room[i].sy) < 1 &&
                         Math.hypot(w.ex - room[i].ex, w.ey - room[i].ey) < 1),
   fixed.map((w, i) => Math.hypot(w.sx - room[i].sx, w.sy - room[i].sy)));

// קיר שסוטה יותר מהטולרנס לא נוגעים בו - "אם אני ארצה משהו אחר אני אשנה ידנית".
const diag = [{ sx: 0, sy: 0, ex: 100, ey: 100, th: 8, ha: 'left', cat: 'exterior', ops: [] }];
const dOut = c('squareUpWalls', diag, 12);
ok('אלכסון של 45 מעלות נשאר כמו שהוא',
   dOut[0].ex === 100 && dOut[0].ey === 100, dOut[0]);

// קיר מעוגל לא נוגעים בו בכלל.
const bow = [{ sx: 0, sy: 0.4, ex: 264, ey: 0, th: 8, ha: 'left', cat: 'exterior', ops: [], sag: 30 }];
const bOut = c('squareUpWalls', bow, 12);
ok('קיר מעוגל נשאר כמו שהוא', bOut[0].sy === 0.4 && bOut[0].ey === 0, bOut[0]);

process.exit(fails ? 1 : 0);
