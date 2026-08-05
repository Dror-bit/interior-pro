const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
function ok(name, cond, extra) {
  console.log((cond ? 'PASS  ' : 'FAIL  ') + name + (cond ? '' : '   << ' + JSON.stringify(extra)));
  if (!cond) fails++;
}
const near = (a, b, t) => Math.abs(a - b) <= (t || 0.05);
function reset() { s('sketches', []); s('pendingSketches', []); s('walls', []); s('pending', []); s('erasePick', null); }
function pend(pts, closed, shape) { g('pendingSketches').push({ pts: pts, closed: !!closed, style:'solid', weight:1, shape: shape || 'line' }); }

// ---- A. a wall band cuts a line ---------------------------------------
reset();
s('mode','line'); c('setLineTool','erase');
g('walls').push({ id:'w1', sx:0, sy:0, ex:100, ey:0, th:6, h:96, ha:'left', cat:'exterior', ops:[], corners:null, syms:[] });
pend([50,-50, 50,50]);                       // vertical line straight through the wall
let pick = c('eraseFind', { x: 50, y: -20 });     // below the wall
ok('wall: piece stops at the wall face', pick && !pick.whole && near(Math.min(pick.cut[1],pick.cut[3]), -50) && near(Math.max(pick.cut[1],pick.cut[3]), 0), pick && pick.cut);
pick = c('eraseFind', { x: 50, y: 3 });           // inside the wall band
ok('wall: piece inside the band is 0..6', pick && near(Math.min(pick.cut[1],pick.cut[3]),0) && near(Math.max(pick.cut[1],pick.cut[3]),6), pick && pick.cut);
ok('wall: two pieces survive', pick && pick.rest.length === 2, pick && pick.rest.length);

// ---- B. real mouse path: hover then click ------------------------------
reset();
s('mode','line'); c('setLineTool','erase');
pend([0,0, 100,100]); pend([0,100, 100,0]);
const L = global.__listeners;
const toPx = (x, y) => ({ offsetX: x * 1.6 + 60, offsetY: 700 - (y * 1.6 + 60) });
let mv = toPx(20, 20);
fire('cv','mousemove',{ offsetX: mv.offsetX, offsetY: mv.offsetY });
ok('hover: erasePick set', !!g('erasePick'), g('erasePick'));
ok('hover: nothing deleted yet', g('pendingSketches').length === 2, g('pendingSketches').length);
fire('cv','mousedown',{ button: 0, offsetX: mv.offsetX, offsetY: mv.offsetY, shiftKey: false, preventDefault(){} });
ok('click: shape was split', g('pendingSketches').length === 2 && g('pendingSketches').some(x => near(x.pts[0], 50)), g('pendingSketches').map(x=>x.pts));
ok('click: preview cleared', g('erasePick') === null);

// ---- C. draw() survives erase mode -------------------------------------
reset(); s('mode','line'); c('setLineTool','erase');
pend([0,0, 100,100]); pend([0,100, 100,0]);
s('cursor', {x:20, y:20});
fire('cv','mousemove',toPx(20,20));
let drew = true; try { c('draw'); } catch (e) { drew = false; console.log('   draw error: ' + e.message); }
ok('draw() with a red preview', drew);

// ---- D. tool buttons ---------------------------------------------------
c('setLineTool','erase');
ok('button: erase is on', global.__els.ltErase.className === 'on', global.__els.ltErase.className);
ok('button: line is off', global.__els.ltLine.className === '', global.__els.ltLine.className);
c('setLineTool','line');
ok('button: erase turns off again', global.__els.ltErase.className === '', global.__els.ltErase.className);
ok('switch clears the preview', g('erasePick') === null);

// ---- E. regression: drawing still works, snap rounds to 1/2 in ---------
reset(); s('mode','line'); c('setLineTool','line');
s('scale', 1.6);
let sp = c('snapPoint', { x: 10.31, y: 20.77 }, null);
ok('snap: rounds to 1/2 in', near(sp.x, 10.5) && near(sp.y, 21.0), sp);
reset(); s('mode','line'); c('setLineTool','line');
fire('cv','mousedown',{ button:0, ...toPx(0,0), shiftKey:false, preventDefault(){} });
fire('cv','mousedown',{ button:0, ...toPx(100,0), shiftKey:false, preventDefault(){} });
ok('draw: two clicks make a line', g('curLine') && g('curLine').pts.length === 2, g('curLine'));
c('endLine');
ok('draw: finished shape is pending', g('pendingSketches').length === 1, g('pendingSketches').length);

// ---- F. wall drawing regression (mode wall) ----------------------------
reset(); s('mode','wall'); s('drawing', false); s('startPt', null);
fire('cv','mousedown',{ button:0, ...toPx(0,0), shiftKey:false, preventDefault(){} });
fire('cv','mousedown',{ button:0, ...toPx(120,0), shiftKey:false, preventDefault(){} });
ok('wall: one pending wall created', g('pending').length === 1, g('pending').length);

console.log(fails ? '\n*** ' + fails + ' FAILED ***' : '\nALL PASS');
process.exit(fails ? 1 : 0);
