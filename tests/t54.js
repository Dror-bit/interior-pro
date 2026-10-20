// t54 - autoOrientExterior turns a wall round WITHOUT moving it.
//
// The user traced his walls exactly onto the PDF's lines, pressed the Window
// button (which auto-applies), and every exterior wall jumped inward by its
// own thickness. Cause: the flip only swapped start/end, and 'left' measures
// the whole width off ONE side of the line - reverse the direction and the
// width lands on the other side. The band must stay on the same strip of
// floor; only the direction of travel may change.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const close = (a, b, tol) => Math.abs(a - b) < (tol || 0.001);

s('sketches', []); s('pendingSketches', []); s('pendingRooms', []); s('mode', 'sel');
s('walls', []);

// The strip of floor a wall's band really covers: the two face lines.
function faces(w) {
  const b = c('bandQuad', w);
  return [
    { x: w.sx + b.nx * b.p, y: w.sy + b.ny * b.p, X: w.ex + b.nx * b.p, Y: w.ey + b.ny * b.p },
    { x: w.sx + b.nx * b.q, y: w.sy + b.ny * b.q, X: w.ex + b.nx * b.q, Y: w.ey + b.ny * b.q }
  ];
}
// Same strip, whichever end each face is described from.
function sameStrip(a, b) {
  const key = (f) => [f.x, f.y, f.X, f.Y].map(v => Math.round(v * 1000) / 1000);
  const norm = (f) => { const k = key(f); return (k[0] < k[2] || (k[0] === k[2] && k[1] < k[3]))
                          ? k.join(',') : [k[2], k[3], k[0], k[1]].join(','); };
  return a.map(norm).sort().join(' | ') === b.map(norm).sort().join(' | ');
}

// A 200x200 room drawn CLOCKWISE, so every band points OUT of the building -
// exactly the case the flip exists for. th 8.
const mk = (sx, sy, ex, ey) =>
  ({ sx: sx, sy: sy, ex: ex, ey: ey, th: 8, ha: 'left', cat: 'exterior', ops: [] });
const room = [mk(0, 0, 0, 200), mk(0, 200, 200, 200), mk(200, 200, 200, 0), mk(200, 0, 0, 0)];
const before = room.map(faces);

s('pending', room.map(w => Object.assign({}, w)));
c('autoOrientExterior');
const after = g('pending');

const dir = (w) => { const L = Math.hypot(w.ex - w.sx, w.ey - w.sy);
                     return { x: (w.ex - w.sx) / L, y: (w.ey - w.sy) / L }; };
ok('every wall really was turned round (that is what the flip is for)',
   after.every((w, i) => { const a = dir(room[i]), b = dir(w);
                           return close(a.x, -b.x) && close(a.y, -b.y); }),
   after.map((w, i) => [dir(room[i]), dir(w)]));

// 2026-10-16: after the turn the ends go to the outer corners (a thickness longer each way), so the
// strip is the SAME LINES and the old strip lies inside the new one - it never moves sideways.
function onLine(f, g) { // segment g on the line of f
  const dx = f.X - f.x, dy = f.Y - f.y, L = Math.hypot(dx, dy);
  const off = (px, py) => Math.abs((px - f.x) * dy - (py - f.y) * dx) / L;
  return off(g.x, g.y) < 0.001 && off(g.X, g.Y) < 0.001;
}
function contains(f, g) { // old segment f inside new segment g
  const dx = g.X - g.x, dy = g.Y - g.y, L2 = dx * dx + dy * dy;
  const t = (px, py) => ((px - g.x) * dx + (py - g.y) * dy) / L2;
  return [t(f.x, f.y), t(f.X, f.Y)].every(v => v > -1e-6 && v < 1 + 1e-6);
}
after.forEach((w, i) => {
  const nf = faces(w), of = before[i];
  const okStrip = of.every(f => nf.some(g => onLine(f, g) && contains(f, g)));
  ok('wall ' + i + ' covers the SAME strip of floor after the flip (same lines, not shorter)', okStrip, { before: of, after: nf });
});

// The centreline itself is allowed to move (it is one face of the band), but
// the band's midline - the wall's real middle - must not budge by even 1/16".
after.forEach((w, i) => {
  const mid = (ww) => { const b = c('bandQuad', ww), m = (b.p + b.q) / 2;
    return { x: (ww.sx + ww.ex) / 2 + b.nx * m, y: (ww.sy + ww.ey) / 2 + b.ny * m }; };
  const a = mid(room[i]), b = mid(w);
  ok('wall ' + i + ' keeps its middle', close(a.x, b.x, 0.0625) && close(a.y, b.y, 0.0625), [a, b]);
});

// A room drawn the other way round is already correct and must be left alone.
const ccw = [mk(0, 0, 200, 0), mk(200, 0, 200, 200), mk(200, 200, 0, 200), mk(0, 200, 0, 0)];
s('pending', ccw.map(w => Object.assign({}, w)));
c('autoOrientExterior');
const kept = g('pending');
ok('a room already drawn the right way round is untouched',
   kept.every((w, i) => close(w.sx, ccw[i].sx) && close(w.sy, ccw[i].sy) &&
                        close(w.ex, ccw[i].ex) && close(w.ey, ccw[i].ey)),
   kept.map(w => [w.sx, w.sy, w.ex, w.ey]));

process.exit(fails ? 1 : 0);
