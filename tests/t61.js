// t61 - EXTERIOR LOOP FLIPS AS ONE (2026-09-30). ASTRA's report: an 8-wall
// envelope with a notch, drawn on side L, came out 92.1 / 87.9 in the notch.
// The center test flipped only the notch's two sides, opening 5" gaps.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };

function loop(pts, ha) {
  return pts.map((a, i) => { const b = pts[(i + 1) % pts.length];
    return { sx: a[0] * 12, sy: a[1] * 12, ex: b[0] * 12, ey: b[1] * 12, th: 5, ha: ha, cat: 'exterior' }; });
}
function maxGap(ws) {
  let worst = 0;
  for (let i = 0; i < ws.length; i++) {
    const A = ws[i], B = ws[(i + 1) % ws.length];
    let d = 1e9;
    [[A.sx, A.sy], [A.ex, A.ey]].forEach(p => [[B.sx, B.sy], [B.ex, B.ey]].forEach(q => { d = Math.min(d, Math.hypot(p[0] - q[0], p[1] - q[1])); }));
    worst = Math.max(worst, d);
  }
  return worst;
}
function axisOnly(ws) {
  return ws.every(w => Math.abs(w.sx - w.ex) < 1e-6 || Math.abs(w.sy - w.ey) < 1e-6);
}
const notch = [[0, 40], [0, 0], [20, 0], [20, 10], [30, 10], [30, 0], [50, 0], [50, 40]];
const rect = [[0, 40], [0, 0], [50, 0], [50, 40]];

const before = JSON.stringify(loop(notch, 'left'));
s('pending', loop(notch, 'left')); c('autoOrientExterior');
ok('notch drawn the right way round: nothing moves', JSON.stringify(g('pending')) === before, g('pending'));
ok('notch: no gap at any corner', maxGap(g('pending')) < 0.01, maxGap(g('pending')));

s('pending', loop(rect, 'left')); c('autoOrientExterior');
ok('rectangle drawn the right way round: no gap', maxGap(g('pending')) < 0.01, g('pending'));

// backwards: every wall flips (all or nothing), and stays on the axis
s('pending', loop(notch.slice().reverse(), 'left')); c('autoOrientExterior');
const flipped = g('pending');
ok('notch drawn backwards: walls stay straight', axisOnly(flipped), flipped);
// 2026-10-16: the ends move to the outer corners after the turn (the corners used to open 7.07" - his
// "כשאני שולח אותם ל3D אז הפינות נישברות"), so this compares DIRECTION, not length.
const unit = (w) => { const L = Math.hypot(w.ex - w.sx, w.ey - w.sy); return [(w.ex - w.sx) / L, (w.ey - w.sy) / L]; };
ok('notch drawn backwards: every wall turned (none left alone)',
   flipped.every((w, i) => { const o = loop(notch.slice().reverse(), 'left')[i];
     const a = unit(w), b = unit(o); return Math.abs(a[0] + b[0]) < 1e-6 && Math.abs(a[1] + b[1]) < 1e-6; }), flipped);
ok('notch drawn backwards: NO GAP at any corner after the turn (2026-10-16)', maxGap(flipped) < 0.01, maxGap(flipped));
s('pending', loop(rect.slice().reverse(), 'left')); c('autoOrientExterior');
ok('rectangle drawn backwards: no gap after the turn (2026-10-16)', maxGap(g('pending')) < 0.01, g('pending'));

// mixed drawing directions inside one loop: still decided per wall by the loop
const mix = loop(notch, 'left');
const t = mix[3]; [t.sx, t.sy, t.ex, t.ey] = [t.ex, t.ey, t.sx, t.sy];
s('pending', mix); c('autoOrientExterior');
const m = g('pending');
const others = m.filter((w, i) => i !== 3);
ok('one wall drawn backwards in a good loop: the others do not move',
   JSON.stringify(others) === JSON.stringify(loop(notch, 'left').filter((w, i) => i !== 3)), m);

process.exit(fails ? 1 : 0);
