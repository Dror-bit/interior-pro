// t59 - THE NEIGHBOUR STAYS STRAIGHT, editor side (2026-09-24).
//
// He lengthened one blue wall by a hair to reach the outer corner and the
// square wall next to it read 89.9. setPendingLength set the partner's end
// straight onto the new corner while its far end stayed put - a tilt. His
// choice: "the neighbour must stay stable". The partner's end now slides
// along its OWN line; a square neighbour does not move at all.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };

const mk = (sx, sy, ex, ey) => ({ sx, sy, ex, ey, th: 5, ha: 'left', cat: 'exterior', ops: [], h: 96, lib: null, anchor: 'bottom-left' });
const ang = (w) => Math.atan2(w.ey - w.sy, w.ex - w.sx) * 180 / Math.PI;

function setup(partner) {
  s('walls', []); s('ghosts', []); s('sketches', []); s('pendingSketches', []);
  s('pending', [mk(0, 0, 120, 0), partner]);
  s('keepCorners', true); s('movingEnd', 'end'); s('sel', null);
}

// --- square neighbour: does not tilt, does not move
setup(mk(120, 0, 120, 96));
c('setPendingLength', 0, 121);
let P = g('pending');
ok('the wall itself got an inch longer', Math.abs(P[0].ex - 121) < 1e-9, P[0]);
ok('>>> the square neighbour did not tilt', Math.abs(ang(P[1]) - 90) < 1e-9, ang(P[1]));
ok('    and did not move', P[1].sx === 120 && P[1].sy === 0, P[1]);

// --- a neighbour at 45 degrees follows along its own line
setup(mk(120, 0, 210, 90));
c('setPendingLength', 0, 200);
P = g('pending');
ok('a 45-degree neighbour slides along its own line',
   Math.abs(P[1].sx - 160) < 1e-6 && Math.abs(P[1].sy - 40) < 1e-6, P[1]);
ok('and keeps its angle', Math.abs(ang(P[1]) - 45) < 1e-9, ang(P[1]));

// --- a collinear neighbour that would collapse is left alone
setup(mk(120, 0, 130, 0));
c('setPendingLength', 0, 128);
P = g('pending');
ok('a partner that would collapse is left alone', P[1].sx === 120 && P[1].ex === 130, P[1]);

// --- keepCorners off: nothing follows
setup(mk(120, 0, 210, 90));
s('keepCorners', false);
c('setPendingLength', 0, 200);
P = g('pending');
ok('with corners released the neighbour stays', P[1].sx === 120 && P[1].sy === 0, P[1]);

console.log(fails ? ('*** ' + fails + ' FAILED ***') : 'all good');
process.exit(fails ? 1 : 0);
