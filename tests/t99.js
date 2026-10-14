// t99 - PICK, DELETE AND MOVE A PLUMBING PRODUCT IN THE DRAWING (2026-10-14, his "תמשיך ל-2"): a press on its sign in
// Select picks it; Delete sends delete_elec with its id; a drag along the wall is green and lets go with move_plumb
// (not move_elec); Escape in the middle drops the drag; without Ruby's say-so (kill switch) it is only shown.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const K = global.__listeners.__win.keydown[0];
const key = (k) => K({ key: k, code: '', target: { tagName: 'CANVAS' }, preventDefault() {}, stopPropagation() {} });
const down = (x, y) => global.fire('cv', 'mousedown', { button: 0, offsetX: c('sx', x), offsetY: c('sy', y), shiftKey: false, preventDefault() {} });
const calls = (n) => global.__calls.filter(k => k[0] === n).map(k => k[1] ? JSON.parse(k[1]) : null);

s('pages', []); s('activePage', 0); s('homeStash', null);
c('loadWalls', [
  { id: 'w1', sx: 0, sy: 0, ex: 0, ey: 200, th: 5, ha: 'center', syms: [] },
  { id: 'w2', sx: 0, sy: 200, ex: 300, ey: 200, th: 5, ha: 'center', syms: [] }]);
c('loadRooms', []);
const toilet = { id: 'f1', kind: 'plumb', sign: 'toilet', product: 'TOTO', x: 2.5, y: 60, nx: 1, ny: 0, w: 20, a0: 0, a1: 28, h: 15, hh: 15 };
c('loadElec', [toilet, { id: 'o1', kind: 'outlet', x: 2.5, y: 120, nx: 1, ny: 0, gangs: 1, h: 18 }]);
c('setMode', 'sel'); s('scale', 4);
// kill switch off: shown, never picked
c('elecEnable', true, true, true, true, true, false);
c('draw');
ok('without Ruby\'s say-so the toilet is not in elecShown (shown only)', !g('elecShown').some(o => o.kind === 'plumb'), g('elecShown'));
c('elecEnable', true, true, true, true, true, true);
c('draw');
const tp = g('elecShown').find(o => o.kind === 'plumb');
ok('with it: in elecShown at the middle of its box, with a radius', tp && Math.abs(tp.x - 16.5) < 1e-6 && tp.y === 60 && tp.r === 14, tp);
down(16, 62);
ok('a press on the toilet picks it and starts its drag', g('elecSel') === 'f1' && g('dragElec') && g('dragElec').id === 'f1', [g('elecSel'), g('dragElec')]);
c('handleMove', c('sx', 16), c('sy', 100));   // held by its middle, 14" off the wall (12:28, "היא לא זזה")
ok('along the wall, held by its middle: the face under the mouse pulled back, green, at t 100', g('dragElec').h && g('dragElec').h.ok && Math.abs(g('dragElec').h.t - 100) < 1e-6, g('dragElec').h);
let err = null; try { c('draw'); } catch (e) { err = String(e); }
ok('the drag ghost draws without an error', !err, err);
global.__calls.length = 0;
c('finishDrag');
const mv = calls('move_plumb');
ok('let go: move_plumb with the wall and the point on its face', mv.length === 1 && mv[0].id === 'f1' && mv[0].wall_id === 'w1' && Math.abs(mv[0].py - 100) < 1e-6, mv);
ok('and NOT move_elec', calls('move_elec').length === 0, calls('move_elec'));
ok('one step of the model\'s undo', g('editHist').slice(-1)[0].what === 'move_plumb');
// a shower head held by its circle, 9" off the wall (12:32, "ראש המקלחת לא זז")
c('loadElec', [{ id: 'h1', kind: 'plumb', sign: 'head', product: 'DAWN', x: 2.5, y: 60, nx: 1, ny: 0, w: 10, a0: 0.6, a1: 14, h: 78, hh: 3 }]);
c('draw');
down(11.5, 60);
c('handleMove', c('sx', 11.5), c('sy', 90));
ok('a shower head held by its circle finds its wall, green at t 90', g('dragElec') && g('dragElec').h && g('dragElec').h.ok && Math.abs(g('dragElec').h.t - 90) < 1e-6, g('dragElec') && g('dragElec').h);
ok('and the face that looks at the mouse (not the far one - 12:36)', g('dragElec').h.b.nx * g('dragElec').h.ns > 0, g('dragElec').h);
key('Escape');
c('loadElec', [toilet, { id: 'o1', kind: 'outlet', x: 2.5, y: 120, nx: 1, ny: 0, gangs: 1, h: 18 }]); c('draw');
// Escape in the middle of a drag drops it (iron law 1)
down(16, 62);
c('handleMove', c('sx', 1.5), c('sy', 150));
key('Escape');
ok('Escape drops the drag', !g('dragElec'), g('dragElec'));
// Delete
s('elecSel', 'f1'); global.__calls.length = 0;
key('Delete');
const del = calls('delete_elec');
ok('Delete sends its id to the model', del.length === 1 && del[0].id === 'f1', del);
ok('and it goes at once from the drawing', !g('elecItems').some(o => o.id === 'f1'), g('elecItems'));
console.log(fails ? `\n${fails} FAILED` : '\nALL PASS');
process.exit(fails ? 1 : 0);
