const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.05);
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('mode','wall'); s('typed',''); s('shiftDown',false); s('lockDir',null); s('drawing',false); s('startPt',null); s('scale',1.6); }
// a 240 x 240 box of 6 in exterior walls, drawn bottom-left so the body is INSIDE 0..240
function boxWalls(){
  const W=(a,b,cc,d)=>({sx:a,sy:b,ex:cc,ey:d,th:6,h:96,ha:'left',cat:'exterior',ops:[],corners:null,syms:[]});
  g('pending').push(W(0,0,240,0), W(240,0,240,240), W(240,240,0,240), W(0,240,0,0));
}

// ---- an interior wall stops at the exterior face -----------------------
reset(); boxWalls(); s('cat','interior');
let e = c('clampToBoundary', {x:120, y:120}, {x:400, y:120});   // aimed way past the right wall
ok('it stops at the wall instead of running past', near(e.x, 234) && near(e.y, 120), e);
e = c('clampToBoundary', {x:120, y:120}, {x:120, y:400});
ok('same going up', near(e.y, 234) && near(e.x, 120), e);
e = c('clampToBoundary', {x:120, y:120}, {x:-400, y:120});
ok('same going left', near(e.x, 6) && near(e.y, 120), e);
e = c('clampToBoundary', {x:120, y:120}, {x:120, y:-400});
ok('same going down', near(e.y, 6), e);

// short of the wall: nothing is touched
e = c('clampToBoundary', {x:120, y:120}, {x:180, y:120});
ok('an end short of the wall is left alone', near(e.x, 180) && near(e.y, 120), e);

// diagonal
e = c('clampToBoundary', {x:120, y:120}, {x:400, y:400});
ok('a diagonal stops on the first face it meets', near(Math.max(e.x, e.y), 234), e);

// ---- exterior walls are NOT clipped ------------------------------------
reset(); boxWalls(); s('cat','exterior');
e = c('clampToBoundary', {x:120, y:120}, {x:400, y:120});
ok('an exterior wall can still run out', near(e.x, 400), e);

// ---- starting ON the wall face does not clamp at zero ------------------
reset(); boxWalls(); s('cat','interior');
e = c('clampToBoundary', {x:6, y:120}, {x:400, y:120});
ok('starting on a face still crosses the room', near(e.x, 234), e);

// ---- nothing to stop against -------------------------------------------
reset(); s('cat','interior');
e = c('clampToBoundary', {x:0, y:0}, {x:200, y:0});
ok('with no exterior walls nothing is clipped', near(e.x, 200), e);

// interior walls do not stop each other
reset(); s('cat','interior');
g('pending').push({sx:0,sy:100,ex:240,ey:100,th:4,h:96,ha:'left',cat:'interior',ops:[],corners:null,syms:[]});
e = c('clampToBoundary', {x:120, y:0}, {x:120, y:200});
ok('an interior wall does not block another', near(e.y, 200), e);

// ---- a typed length always wins ----------------------------------------
reset(); boxWalls(); s('cat','interior'); s('drawing', true); s('startPt', {x:120, y:120});
s('cursor', {x:400, y:120}); s('typed','');
let ce = c('currentEnd');
ok('free movement is clipped', near(ce.x, 234), ce);
s('typed', "30'");
ce = c('currentEnd');
ok('a typed 30 ft is honoured, not clipped', near(ce.x, 120 + 360), ce);
s('typed','');

// ---- the whole draw path uses it ---------------------------------------
reset(); boxWalls(); s('cat','interior');
const n0 = g('pending').length;
s('drawing', true); s('startPt', {x:120, y:120}); s('cursor', {x:400, y:120});
c('commitSegment');
ok('the committed wall really stops at the face', g('pending').length===n0+1 &&
   near(g('pending')[n0].ex, 234) || near(g('pending')[n0].sx, 234),
   g('pending')[n0] && [g('pending')[n0].sx, g('pending')[n0].ex]);

let d=true; try { c('draw'); } catch(er){ d=false; console.log('  '+er.message); }
ok('draw still works', d);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
