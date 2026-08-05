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

// ---- 1. X of two pending lines: erase one arm -------------------------
reset();
pend([0,0, 100,100]);            // A  (diagonal up-right)
pend([0,100, 100,0]);            // B  (diagonal down-right) - cross at 50,50
s('mode', 'line'); c('setLineTool', 'erase');
let pick = c('eraseFind', { x: 20, y: 20 });      // lower-left arm of A
ok('X: found a piece', !!pick && !pick.whole, pick && {whole:pick.whole});
ok('X: cut runs 0,0 -> 50,50', pick && near(pick.cut[0],0) && near(pick.cut[1],0) && near(pick.cut[2],50) && near(pick.cut[3],50), pick && pick.cut);
ok('X: exactly one piece survives', pick && pick.rest.length === 1, pick && pick.rest.length);
s('erasePick', pick); c('eraseApply');
ok('X: still 2 shapes after erase', g('pendingSketches').length === 2, g('pendingSketches').length);
let surv = g('pendingSketches').find(x => x.pts.length === 4 && near(x.pts[0],50));
ok('X: survivor is 50,50 -> 100,100', !!surv && near(surv.pts[2],100) && near(surv.pts[3],100), g('pendingSketches').map(x=>x.pts));

// ---- 2. L polyline: erase one leg only ---------------------------------
reset();
pend([0,0, 100,0, 100,80]);      // corner at 100,0
pick = c('eraseFind', { x: 50, y: 0 });
ok('L: cut is the first leg only', pick && !pick.whole && pick.cut.length === 4 && near(pick.cut[2],100) && near(pick.cut[3],0), pick && pick.cut);
ok('L: one leg survives', pick && pick.rest.length === 1 && pick.rest[0].length === 2, pick && pick.rest);

// ---- 3. closed rectangle: erase one side -> open 3-sided shape ---------
reset();
pend([0,0, 100,0, 100,60, 0,60], true, 'rect');
pick = c('eraseFind', { x: 50, y: 0 });
ok('rect: cut is the bottom side', pick && pick.cut.length === 4 && near(pick.cut[0],0) && near(pick.cut[2],100), pick && pick.cut);
ok('rect: one open piece survives with 4 pts', pick && pick.rest.length === 1 && pick.rest[0].length === 4, pick && pick.rest.map(r=>r.length));
s('erasePick', pick); c('eraseApply');
ok('rect: survivor is open', g('pendingSketches').length === 1 && g('pendingSketches')[0].closed === false, g('pendingSketches'));

// ---- 3b. rectangle: erase across the seam (the side that starts at pts[0]) 
reset();
pend([0,0, 100,0, 100,60, 0,60], true, 'rect');
pick = c('eraseFind', { x: 0, y: 30 });        // left side = seam side
ok('rect seam: cut has 2 points', pick && pick.cut.length === 4, pick && pick.cut);
ok('rect seam: survivor keeps 4 pts', pick && pick.rest.length === 1 && pick.rest[0].length === 4, pick && pick.rest.map(r=>r.length));

// ---- 4. circle crossed by a line: erase the small arc ------------------
reset();
let circ = []; for (let i=0;i<64;i++){ circ.push(50+40*Math.cos(i/64*2*Math.PI), 50+40*Math.sin(i/64*2*Math.PI)); }
pend(circ, true, 'circle');
pend([-60,80, 160,80]);                        // horizontal chord above centre
pick = c('eraseFind', { x: 50, y: 90 });       // top cap of the circle
ok('circle: piece found, not whole', pick && !pick.whole, pick && {whole:pick.whole});
ok('circle: one arc survives', pick && pick.rest.length === 1, pick && pick.rest.length);
let capLen = pick ? pick.cut.length/2 : 0, keepLen = pick ? pick.rest[0].length : 0;
ok('circle: cap is the SHORT arc', capLen < keepLen, {capLen, keepLen});

// ---- 5. grouped shape is protected ------------------------------------
reset();
pend([0,0, 100,100]); pend([0,100, 100,0]);
g('pendingSketches')[0].gid = 'grp1';
pick = c('eraseFind', { x: 20, y: 20 });
ok('group: erases whole', pick && pick.whole === true, pick && {whole:pick.whole});

// ---- 6. lone line with nothing crossing it: whole ---------------------
reset();
pend([0,0, 100,0]);
pick = c('eraseFind', { x: 50, y: 0 });
ok('lone line: whole', pick && pick.whole === true, pick && {whole:pick.whole});

// ---- 7. nothing under the cursor -------------------------------------
reset(); pend([0,0, 100,0]);
ok('far away: no pick', c('eraseFind', { x: 50, y: 400 }) === null);

// ---- 8. model shape goes to Ruby --------------------------------------
reset();
g('sketches').push({ id:'sk-1', pts:[0,0, 100,100], closed:false, style:'solid', weight:1, shape:'line' });
pend([0,100, 100,0]);
pick = c('eraseFind', { x: 20, y: 20 });
s('erasePick', pick); c('eraseApply');
let call = global.__calls.filter(x => x[0] === 'split_sketch').pop();
ok('model: split_sketch called', !!call, global.__calls.map(x=>x[0]));
if (call) {
  const pl = JSON.parse(call[1]);
  ok('model: right id + 1 piece', pl.id === 'sk-1' && pl.pieces.length === 1, pl);
  ok('model: piece is the far arm', near(pl.pieces[0].pts[0],50) && near(pl.pieces[0].pts[2],100), pl.pieces[0].pts);
}

console.log(fails ? '\n*** ' + fails + ' FAILED ***' : '\nALL PASS');
process.exit(fails ? 1 : 0);
