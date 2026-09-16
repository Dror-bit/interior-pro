// t55 - a wall drawn roughly square LOCKS onto the right angle.
//
// His law (2026-09-23): "it has to lock onto 90 even if it is 10 degrees off
// either way - if I want something else I will change it myself." Until now
// the only angle snap was to 45-degree steps with a ~7-degree window, so a
// line 20 degrees off an axis locked onto the DIAGONAL and every corner came
// out crooked.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };

// Nothing to snap to but the angle itself.
s('walls', []); s('pending', []); s('ghosts', []); s('sketches', []);
s('pendingSketches', []); s('guides', []); s('curLine', null); s('scale', 1);

const from = { x: 0, y: 0 };
const shoot = (deg, len) => {
  const a = deg * Math.PI / 180;
  return c('snapPoint', { x: Math.cos(a) * (len || 200), y: Math.sin(a) * (len || 200) }, from);
};
const angOf = (q) => { let d = Math.atan2(q.y, q.x) * 180 / Math.PI; return d < 0 ? d + 360 : d; };
const isSquare = (q) => { const a = angOf(q) % 90; return a < 0.6 || a > 89.4; };

// Off by 10 degrees, both ways, on all four axes - the exact case he named.
[0, 90, 180, 270].forEach((base) => {
  [-10, -6, 6, 10].forEach((off) => {
    const q = shoot(base + off);
    ok('drawn ' + off + ' degrees off ' + base + ' -> locks square', isSquare(q), angOf(q));
  });
});

// It must not eat a real diagonal: 45 still reachable.
const d45 = shoot(45);
ok('a deliberate 45 stays 45', Math.abs(angOf(d45) - 45) < 0.6, angOf(d45));

// Past the window it is left alone - he said he would set anything else by hand.
const free = shoot(25);
ok('25 degrees is outside every window and is left free',
   Math.abs(angOf(free) - 25) < 3, angOf(free));

// The length is kept: snapping turns the wall, it does not stretch it.
const q10 = shoot(80, 200);
ok('the length is unchanged by the snap',
   Math.abs(Math.hypot(q10.x, q10.y) - 200) < 1, Math.hypot(q10.x, q10.y));

process.exit(fails ? 1 : 0);
