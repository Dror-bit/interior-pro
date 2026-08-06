// t29 - levels in the 2D editor: the ghost underlay of the level below
// snaps (corners + midpoints) but is never selectable, and the level
// picker round-trips through the sketchup bridge.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
function ok(name, cond, extra) {
  console.log((cond ? 'PASS  ' : 'FAIL  ') + name + (cond ? '' : '   << ' + JSON.stringify(extra)));
  if (!cond) fails++;
}
const near = (a, b, t) => Math.abs(a - b) <= (t || 0.05);

function reset() {
  s('sketches', []); s('pendingSketches', []); s('walls', []); s('pending', []);
  s('ghosts', []); s('guides', []); s('curLine', null); s('scale', 1);
}

// one ghost wall of the level below: 0,0 -> 100,0, 4.5 thick, left anchor
const GW = { id: 'g1', sx: 0, sy: 0, ex: 100, ey: 0, th: 4.5, ha: 'left', cat: 'exterior', ops: [], syms: [] };

// ---- 1. loadGhosts stores the list -------------------------------------
reset();
c('loadGhosts', [GW]);
ok('ghost list stored', g('ghosts').length === 1 && g('ghosts')[0].id === 'g1', g('ghosts'));
c('loadGhosts', null);
ok('null clears the ghosts', g('ghosts').length === 0, g('ghosts'));

// ---- 2. drawing snaps to a ghost corner --------------------------------
reset();
s('ghosts', [GW]);
let p = c('snapPoint', { x: 2, y: 2 }, null);
ok('corner of the level below snaps', p.snapped === true && near(p.x, 0) && near(p.y, 0), p);
ok('marker is the green end ring', g('snapInd') && g('snapInd').kind === 'end', g('snapInd'));

// far away - no snap, free point survives
p = c('snapPoint', { x: 40, y: 30 }, null);
ok('far from the ghost stays free', p.snapped === false && near(p.x, 40) && near(p.y, 30), p);

// ---- 3. drawing snaps to a ghost midpoint ------------------------------
reset();
s('ghosts', [GW]);
p = c('snapPoint', { x: 50, y: -3 }, null);
ok('midpoint of the level below snaps', p.snapped === true && near(p.x, 50) && near(p.y, 0), p);
ok('marker is the cyan mid ring', g('snapInd') && g('snapInd').kind === 'mid', g('snapInd'));

// ---- 4. a real wall on THIS level still wins over the ghost ------------
reset();
s('ghosts', [GW]);
s('walls', [{ id: 'w1', sx: 1, sy: 1, ex: 60, ey: 80, th: 4.5, ha: 'left', cat: 'exterior', ops: [], syms: [] }]);
p = c('snapPoint', { x: 1.4, y: 1.4 }, null);
ok('nearest point wins (the real wall)', p.snapped === true && near(p.x, 1) && near(p.y, 1), p);

// ---- 5. ghosts are never selectable ------------------------------------
reset();
s('ghosts', [GW]);
const hit = c('hitWall', { x: 50, y: 2 });   // inside the ghost band
ok('hitWall ignores the level below', hit === null, hit);

// ---- 6. the level picker round-trips -----------------------------------
reset();
c('loadLevel', 2);
ok('loadLevel(2) sets the active level', g('activeLevel') === 2);
global.__calls.length = 0;
c('setLevel', 2);
ok('same level = no bridge call', global.__calls.length === 0, global.__calls);
c('setLevel', 1);
const call = global.__calls.find((x) => x[0] === 'set_level');
ok('picking the other level calls set_level', !!call && call[1] === '1', global.__calls);
c('loadLevel', 1);
ok('loadLevel(1) comes back', g('activeLevel') === 1);

console.log(fails ? '*** ' + fails + ' FAILED ***' : 'ALL PASS');
process.exit(fails ? 1 : 0);
