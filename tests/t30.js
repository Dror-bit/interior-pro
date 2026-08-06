// t30 - Shift + stab-a-point while dragging a wall sideways: the nearest
// face of the dragged wall lands exactly on the picked point (level-below
// ghost corners included), and the commit goes through even for a tiny
// shift. Without Shift the plain 1/4" drag behaviour is untouched.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
function ok(name, cond, extra) {
  console.log((cond ? 'PASS  ' : 'FAIL  ') + name + (cond ? '' : '   << ' + JSON.stringify(extra)));
  if (!cond) fails++;
}
const near = (a, b, t) => Math.abs(a - b) <= (t || 0.01);

// screen coords for a model point (must match sx/sy in the editor)
function px(x) { return x * g('scale') + g('panX'); }
function py(y) { return 700 - (y * g('scale') + g('panY')); }

function reset() {
  s('sketches', []); s('pendingSketches', []); s('walls', []); s('pending', []);
  s('ghosts', []); s('guides', []); s('curLine', null);
  s('scale', 1); s('panX', 0); s('panY', 0);
  s('mode', 'sel'); s('dragSym', null); s('panning', false);
  s('rubber', null); s('dragUnder', null); s('typed', '');
}

// pending wall: 0,0 -> 100,0, th 4.5, ha left (faces at y=0 and y=4.5)
function mkPending() {
  return { sx: 0, sy: 0, ex: 100, ey: 0, th: 4.5, ha: 'left', cat: 'exterior', ops: [], syms: [] };
}
// ghost wall of the level below, its q-face line at y=20
const GW = { id: 'g1', sx: 0, sy: 20, ex: 100, ey: 20, th: 4.5, ha: 'left', cat: 'exterior', ops: [], syms: [] };

// ---- 1. Shift + stab: the wall face lands ON the ghost corner ----------
reset();
const pw = mkPending();
s('pending', [pw]);
s('ghosts', [GW]);
s('shiftDown', true);
s('dragWall', { w: pw, b: c('bandQuad', pw), pi: 0, from: { x: 50, y: 2 }, off: 0, moved: false,
                sxy: { x: px(50), y: py(2) } });
// drag near the ghost's corner at (0,20): cursor at (1,21), so the
// candidate closest to the hand is the drawn line itself -> full stack
c('handleMove', px(1), py(21));
let dw = g('dragWall');
ok('stab: drag snapped to a point', !!dw.snapPt, dw);
ok('stab: the point is the ghost corner (0,20)', dw.snapPt && near(dw.snapPt.x, 0) && near(dw.snapPt.y, 20), dw.snapPt);
// the drawn line lands on the point -> off = 20 (wall stacks on the ghost)
ok('stab: the wall lands on the point (off=20)', near(dw.off, 20), dw.off);
c('finishDrag');
ok('stab: pending wall moved exactly onto the line', near(pw.sy, 20) && near(pw.ey, 20), pw);
ok('stab: drag ended clean', g('dragWall') === null);

// ---- 2. a TINY stabbed alignment still commits --------------------------
reset();
const pw2 = mkPending();
s('pending', [pw2]);
s('ghosts', [{ id: 'g2', sx: 0, sy: 0.1, ex: 100, ey: 0.1, th: 4.5, ha: 'left', cat: 'exterior', ops: [], syms: [] }]);
s('shiftDown', true);
s('dragWall', { w: pw2, b: c('bandQuad', pw2), pi: 0, from: { x: 50, y: 2 }, off: 0, moved: false,
                sxy: { x: px(50), y: py(2) } });
c('handleMove', px(1), py(0.4));       // near the ghost corner at (0,0.1)
dw = g('dragWall');
ok('tiny: snapped', !!dw.snapPt && near(dw.off, 0.1), dw.off);
c('finishDrag');
ok('tiny: 0.1" alignment committed (no 1/4" floor)', near(pw2.sy, 0.1), pw2.sy);

// ---- 3. without Shift nothing changed: 1/4" steps, no snap --------------
reset();
const pw3 = mkPending();
s('pending', [pw3]);
s('ghosts', [GW]);
s('shiftDown', false);
s('dragWall', { w: pw3, b: c('bandQuad', pw3), pi: 0, from: { x: 50, y: 2 }, off: 0, moved: false,
                sxy: { x: px(50), y: py(2) } });
c('handleMove', px(1), py(19));        // same cursor as test 1
dw = g('dragWall');
ok('plain: no snap point', !dw.snapPt, dw.snapPt);
ok('plain: off is the rounded cursor move (17)', near(dw.off, 17), dw.off);
s('dragWall', null);

console.log(fails ? '*** ' + fails + ' FAILED ***' : 'ALL PASS');
process.exit(fails ? 1 : 0);
