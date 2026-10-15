// t100 - TILE IN THE DRAWING (2026-10-14): a tiled wall strip and a shower floor (outline, drain, kind) draw without an
// error, are never picked, and a click on them picks nothing. No floor grid.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const click = (x, y) => global.fire('cv', 'mousedown', { button: 0, offsetX: c('sx', x), offsetY: c('sy', y), shiftKey: false, preventDefault() {} });
s('pages', []); s('activePage', 0); s('homeStash', null);
c('loadWalls', [{ id: 'w1', sx: 0, sy: 0, ex: 400, ey: 0, th: 5, ha: 'center', syms: [] }]);
c('loadRooms', []);
c('elecEnable', true, true, true, true, true, true);
c('loadElec', [
  { id: 'TW1', kind: 'tile', pts: [[10, 2.5], [60, 2.5], [60, 3.125], [10, 3.125]] },
  { id: 'SH1', kind: 'shower', pts: [[100, 2.5], [140, 2.5], [140, 62.5], [100, 62.5]], drain: [[134.5, 20.5], [137.5, 20.5], [137.5, 44.5], [134.5, 44.5]], label: 'Curb 4"' },
  { id: 'SH2', kind: 'shower', pts: [[200, 2.5], [240, 2.5], [240, 62.5], [200, 62.5]], drain: null, label: 'Curbless' },
  { id: 'o1', kind: 'outlet', x: 300, y: 2.5, nx: 0, ny: 1, gangs: 1, h: 18 }]);
c('setMode', 'sel'); s('scale', 4);
let err = null; try { c('draw'); } catch (e) { err = String(e); }
ok('tile strip, shower with a drain, shower without, and an outlet draw without an error', !err, err);
ok('tile / shower never in elecShown', !g('elecShown').some(o => o.kind === 'tile' || o.kind === 'shower'), g('elecShown'));
ok('the outlet still shown', g('elecShown').some(o => o.id === 'o1'));
click(120, 30);
ok('a click on the shower floor picks nothing', !g('elecSel'), g('elecSel'));
console.log(fails ? `\n${fails} FAILED` : '\nALL PASS');
process.exit(fails ? 1 : 0);
