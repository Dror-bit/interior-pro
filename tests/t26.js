const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.05);
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('snapInd',null); s('mode','wall'); s('scale',1.6); }
// a 240 in wall, 6 in thick, drawn along y=0 -> body y 0..6
const W=(cat)=>({sx:0,sy:0,ex:240,ey:0,th:6,h:96,ha:'left',cat:cat||'exterior',ops:[],corners:null,syms:[]});

reset(); g('pending').push(W());
// midpoint of the DRAWN face (y=0)
let q = c('snapPoint', {x:120.5, y:0.4}, null);
ok('drawn-face midpoint still snaps', q.snapped && near(q.x,120) && near(q.y,0), q);
ok('and it is marked as a midpoint', g('snapInd') && g('snapInd').kind==='mid', g('snapInd'));
// midpoint of the OTHER face (y=6) - this is what was missing
q = c('snapPoint', {x:120.5, y:6.4}, null);
ok('the far face midpoint snaps too', q.snapped && near(q.x,120) && near(q.y,6), q);
ok('also marked as a midpoint', g('snapInd') && g('snapInd').kind==='mid', g('snapInd'));

// an INTERIOR wall behaves the same
reset(); g('pending').push(W('interior'));
q = c('snapPoint', {x:120.5, y:6.4}, null);
ok('interior walls get both midpoints', q.snapped && near(q.y,6), q);

// an applied wall with real mitered corners
reset();
g('walls').push({id:'w1', sx:0,sy:0,ex:240,ey:0, th:6,h:96,ha:'left',cat:'exterior',ops:[],
                 corners:[0,6, 240,6, 240,0, 0,0], syms:[]});
q = c('snapPoint', {x:120.4, y:6.3}, null);
ok('applied wall: far face midpoint snaps', q.snapped && near(q.x,120) && near(q.y,6), q);
q = c('snapPoint', {x:120.4, y:0.3}, null);
ok('applied wall: near face midpoint snaps', q.snapped && near(q.x,120) && near(q.y,0), q);

// a corner still beats a midpoint when you are near both
reset(); g('pending').push(W());
q = c('snapPoint', {x:0.3, y:0.3}, null);
ok('a corner still wins over a midpoint', g('snapInd').kind==='end' && near(q.x,0) && near(q.y,0), {q, ind:g('snapInd')});

// nothing nearby stays free
q = c('snapPoint', {x:120, y:60}, null);
ok('far away is still free movement', !q.snapped, q);

// a vertical wall too
reset(); g('pending').push({sx:0,sy:0,ex:0,ey:240,th:6,h:96,ha:'left',cat:'exterior',ops:[],corners:null,syms:[]});
q = c('snapPoint', {x:-6.4, y:120.4}, null);
ok('vertical wall: both faces work', q.snapped && near(q.y,120) && near(Math.abs(q.x),6), q);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
