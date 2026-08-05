const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.02);
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('rooms',[]); s('pendingRooms',[]); s('mode','sel'); s('selList',[]); s('sel',null); c('setDimMode','both'); }
const W=(a,b,cc,d,th)=>({sx:a,sy:b,ex:cc,ey:d,th:th||6,h:96,ha:'left',cat:'exterior',ops:[],corners:null,syms:[]});
function pend(p,cl,sh){ g('pendingSketches').push({pts:p,closed:!!cl,style:'solid',weight:1,shape:sh||'line'}); }
function grab(fn){ global.__draw.length=0; global.__rot=0; fn(); return global.__draw.slice(); }

// ---- wall numbers run ALONG the wall -----------------------------------
reset();
g('pending').push(W(0,0,200,0));                       // horizontal
let L = grab(()=>c('dimLabel', g('pending')[0], '#e0392b', g('pending')));
ok('a horizontal wall gets horizontal numbers', L.length===2 && L.every(l=>near(l.rot||0, 0)), L.map(l=>l.rot));

reset();
g('pending').push(W(0,0,0,200));                       // vertical
L = grab(()=>c('dimLabel', g('pending')[0], '#e0392b', g('pending')));
ok('a vertical wall gets vertical numbers', L.length===2 && L.every(l=>near(Math.abs(l.rot||0), Math.PI/2)),
   L.map(l=>l.rot));

reset();
g('pending').push(W(0,0,100,100));                     // 45 degrees
L = grab(()=>c('dimLabel', g('pending')[0], '#e0392b', g('pending')));
ok('a diagonal wall follows its own angle', L.length===2 && L.every(l=>near(Math.abs(l.rot||0), Math.PI/4)),
   L.map(l=>l.rot));

// text never ends up upside down
reset();
g('pending').push(W(200,0,0,0));                       // drawn right to left
L = grab(()=>c('dimLabel', g('pending')[0], '#e0392b', g('pending')));
ok('a wall drawn backwards still reads upright', L.every(l=>Math.abs(l.rot||0) <= Math.PI/2 + 0.01), L.map(l=>l.rot));

// ---- shapes get numbers too --------------------------------------------
reset(); pend([0,0, 120,0, 120,60, 0,60], true, 'rect');
L = grab(()=>c('drawShapeDims'));
ok('a rectangle gets four numbers', L.length===4, L.map(l=>l.t));
ok('and they read 10 ft and 5 ft', L.filter(l=>l.t===c('fmtLen',120)).length===2 &&
                                   L.filter(l=>l.t===c('fmtLen',60)).length===2, L.map(l=>l.t));
ok('the horizontal sides read horizontally', L.filter(l=>near(l.rot||0,0)).length===2, L.map(l=>l.rot));
ok('the vertical sides read vertically', L.filter(l=>near(Math.abs(l.rot||0), Math.PI/2)).length===2, L.map(l=>l.rot));

reset(); pend([0,0, 200,0]);
L = grab(()=>c('drawShapeDims'));
ok('a single line gets its length', L.length===1 && L[0].t===c('fmtLen',200), L.map(l=>l.t));

reset(); pend([0,0, 100,0, 100,80]);
L = grab(()=>c('drawShapeDims'));
ok('an L polyline gets one number per leg', L.length===2, L.map(l=>l.t));

// a circle gets a diameter, not 64 tiny numbers
reset();
let cir=[]; for (let i=0;i<64;i++) cir.push(50+40*Math.cos(i/64*2*Math.PI), 50+40*Math.sin(i/64*2*Math.PI));
pend(cir, true, 'circle');
L = grab(()=>c('drawShapeDims'));
ok('a circle gets ONE number', L.length===1, L.length);
ok('and it is the diameter', L[0].t.indexOf('⌀')===0, L[0].t);

// an arc stays clean
reset(); pend([0,0, 10,5, 20,8, 30,9], false, 'arc');
ok('an arc gets no clutter', grab(()=>c('drawShapeDims')).length===0);

// tiny segments are skipped
reset(); pend([0,0, 3,0, 3,100]);
L = grab(()=>c('drawShapeDims'));
ok('a 3 in stub is skipped', L.length===1, L.map(l=>l.t));

// ---- the switch still rules everything ---------------------------------
reset(); pend([0,0, 120,0, 120,60, 0,60], true, 'rect');
g('pending').push(W(0,-100,200,-100));
c('setDimMode','none');
ok('none hides shape numbers too', grab(()=>c('drawShapeDims')).length===0);
ok('and wall numbers', grab(()=>c('dimLabel', g('pending')[0], '#e0392b', g('pending'))).length===0);
c('setDimMode','out');
ok('outside-only still shows shape numbers', grab(()=>c('drawShapeDims')).length===4);
c('setDimMode','both');

let d=true; try { c('draw'); } catch(e){ d=false; console.log('  '+e.message); }
ok('draw works with everything on', d);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
