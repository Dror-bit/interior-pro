// t31 - the Move tool works on walls too (2026-08-04): a selection of
// applied walls + pending walls + shapes travels together; commit sends
// the applied walls to Ruby as one delta; cancel puts everything back.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
function ok(name, cond, extra) {
  console.log((cond ? 'PASS  ' : 'FAIL  ') + name + (cond ? '' : '   << ' + JSON.stringify(extra)));
  if (!cond) fails++;
}
const near = (a, b, t) => Math.abs(a - b) <= (t || 0.01);

function reset() {
  s('sketches', []); s('pendingSketches', []); s('walls', []); s('pending', []);
  s('ghosts', []); s('guides', []); s('curLine', null); s('moveOp', null);
  s('scale', 1); s('panX', 0); s('panY', 0); s('mode', 'sel');
}

const W = { id: 'w1', sx: 0, sy: 0, ex: 100, ey: 0, th: 4.5, ha: 'left', cat: 'exterior',
            ops: [], syms: [], corners: [0, 0, 100, 0, 100, 4.5, 0, 4.5] };
const PW = { sx: 0, sy: 30, ex: 100, ey: 30, th: 4.5, ha: 'left', cat: 'interior', ops: [], syms: [] };
const SK = { id: 'sk1', pts: [10, 50, 60, 50], closed: false, style: 'solid', weight: 1, shape: 'line' };

// ---- 1. mixed selection moves together ----------------------------------
reset();
s('walls', [W]); s('pending', [PW]); s('pendingSketches', []); s('sketches', [SK]);
s('selList', [{ type: 'wall', w: W }, { type: 'pending', i: 0 }, { type: 'sketch', kind: 'model', sk: SK }]);
c('startFreeMove');
ok('moveOp starts with all 3 kinds', g('moveOp') && g('moveOp').orig.length === 3,
   g('moveOp') && g('moveOp').orig.length);
c('moveGrab', { x: 0, y: 0 });
c('moveApply', 24, 12);
ok('applied wall moved', near(W.sx, 24) && near(W.sy, 12) && near(W.ex, 124) && near(W.ey, 12), W);
ok('wall corners moved too', near(W.corners[0], 24) && near(W.corners[1], 12) && near(W.corners[5], 16.5), W.corners);
ok('pending wall moved', near(PW.sy, 42) && near(PW.ey, 42), PW);
ok('shape moved', near(SK.pts[0], 34) && near(SK.pts[1], 62), SK.pts);

// commit: the applied wall goes to Ruby as one delta
global.__calls.length = 0;
c('moveCommit');
const mv = global.__calls.find((x) => x[0] === 'move_selection');
ok('commit calls move_selection', !!mv, global.__calls.map((x) => x[0]));
const arg = mv ? JSON.parse(mv[1]) : null;
ok('with the wall id and the delta', arg && arg.ids.length === 1 && arg.ids[0] === 'w1' &&
   near(arg.dx, 24) && near(arg.dy, 12), arg);
const upd = global.__calls.find((x) => x[0] === 'update_sketches');
ok('the model shape goes through update_sketches', !!upd, global.__calls.map((x) => x[0]));
ok('moveOp ended', g('moveOp') === null);

// ---- 2. cancel restores everything --------------------------------------
reset();
const W2 = { id: 'w2', sx: 0, sy: 0, ex: 100, ey: 0, th: 4.5, ha: 'left', cat: 'exterior',
             ops: [], syms: [], corners: [0, 0, 100, 0, 100, 4.5, 0, 4.5] };
s('walls', [W2]);
s('selList', [{ type: 'wall', w: W2 }]);
c('startFreeMove');
c('moveGrab', { x: 0, y: 0 });
c('moveApply', 50, 50);
c('moveCancel');
ok('cancel puts the wall back', near(W2.sx, 0) && near(W2.sy, 0) && near(W2.ex, 100) && near(W2.ey, 0), W2);
ok('and its corners', near(W2.corners[0], 0) && near(W2.corners[5], 4.5), W2.corners);

// ---- 3. a tiny commit does not bother Ruby -------------------------------
reset();
const W3 = { id: 'w3', sx: 0, sy: 0, ex: 100, ey: 0, th: 4.5, ha: 'left', cat: 'exterior',
             ops: [], syms: [], corners: null };
s('walls', [W3]);
s('selList', [{ type: 'wall', w: W3 }]);
c('startFreeMove');
c('moveGrab', { x: 0, y: 0 });
c('moveApply', 0, 0);
global.__calls.length = 0;
c('moveCommit');
ok('zero move sends nothing', !global.__calls.find((x) => x[0] === 'move_selection'),
   global.__calls.map((x) => x[0]));

console.log(fails ? '*** ' + fails + ' FAILED ***' : 'ALL PASS');
process.exit(fails ? 1 : 0);
