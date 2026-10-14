// t97 - PLUMBING IN THE DRAWING (2026-10-14, his "מעולה" on plumb_signs.png): every sign draws without an error at
// its real size, is never picked in Select, and a click on it picks nothing (step 1: shown only).
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const click = (x, y) => global.fire('cv', 'mousedown', { button: 0, offsetX: c('sx', x), offsetY: c('sy', y), shiftKey: false, preventDefault() {} });

s('pages', []); s('activePage', 0); s('homeStash', null);
c('loadWalls', [{ id: 'w1', sx: 0, sy: 0, ex: 400, ey: 0, th: 5, ha: 'center', syms: [] }]);
const items = [
  { id: 'p1', kind: 'plumb', sign: 'head', x: 20, y: 2.5, nx: 0, ny: 1, w: 8, a0: 0, a1: 14 },
  { id: 'p2', kind: 'plumb', sign: 'toilet', x: 60, y: 2.5, nx: 0, ny: 1, w: 20, a0: 0, a1: 28 },
  { id: 'p3', kind: 'plumb', sign: 'vanity', x: 120, y: 2.5, nx: 0, ny: 1, w: 36, a0: 0, a1: 21 },
  { id: 'p4', kind: 'plumb', sign: 'tub', x: 200, y: 2.5, nx: 0, ny: 1, w: 60, a0: 0, a1: 30 },
  { id: 'p5', kind: 'plumb', sign: 'fs_tub', x: 300, y: 2.5, nx: 0, ny: 1, w: 66, a0: 4, a1: 36 },
  { id: 'e1', kind: 'outlet', x: 380, y: 2.5, nx: 0, ny: 1 }
];
c('loadElec', items);
c('setMode', 'sel');
let err = null;
try { c('draw'); } catch (e) { err = String(e); }
ok('all five signs and an outlet draw without an error', !err, err);
const sh = g('elecShown');
ok('no plumbing in elecShown (shown only, never picked)', !sh.some(o => o.kind === 'plumb'), sh);
ok('the outlet still shown', sh.some(o => o.id === 'e1'), sh);
s('scale', 4); c('draw');
click(60, 16);
ok('a click on the toilet picks nothing', !g('elecSel'), g('elecSel'));
ok('and takes nothing away', g('elecItems').length === 6, g('elecItems').length);
// a tiny box must not blow up the rounded corners
c('loadElec', [{ id: 'p6', kind: 'plumb', sign: 'tub', x: 20, y: 2.5, nx: 0, ny: 1, w: 3, a0: 0, a1: 2 }]);
err = null; try { c('draw'); } catch (e) { err = String(e); }
ok('a tiny tub draws without an error', !err, err);
console.log(fails ? `\n${fails} FAILED` : '\nALL PASS');
process.exit(fails ? 1 : 0);
