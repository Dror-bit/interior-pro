const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.02);
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('rooms',[]); s('pendingRooms',[]); s('mode','sel'); s('selList',[]); s('sel',null); c('setDimMode','both'); }
function grab(fn){ global.__draw.length=0; global.__rot=0; fn(); return global.__draw.slice(); }
// a 240 in wall with a 36 in door at t=60 and a 36 in window at t=180
const WD=(ops)=>({sx:0,sy:0,ex:240,ey:0,th:6,h:96,ha:'left',cat:'exterior',ops:ops||[],corners:null,syms:[]});

reset(); g('walls').push(WD([[60,36],[180,36]]));
let L = grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls')));
let texts = L.map(l=>l.t);
ok('the chain appears without selecting anything', L.length >= 6, texts);
ok('corner to the first opening = 3 ft 6 in', texts.includes(c('fmtLen',42)), texts);
ok('both opening widths show 3 ft', texts.filter(t=>t===c('fmtLen',36)).length===2, texts);
ok('the gap between them = 7 ft', texts.includes(c('fmtLen',84)), texts);
ok('the tail to the far corner = 3 ft 6 in', texts.filter(t=>t===c('fmtLen',42)).length===2, texts);
ok('the overall is still there', texts.includes(c('fmtLen',240)), texts);
ok('opening widths are bold green', L.filter(l=>l.t===c('fmtLen',36)).length===2);

// the overall steps further out so it does not collide with the chain
const chainY = L.filter(l=>l.t===c('fmtLen',84))[0].ty;
const overallY = L.filter(l=>l.t===c('fmtLen',240))[0].ty;
ok('the overall sits on its own row', Math.abs(chainY - overallY) > 6, {chainY, overallY});

// a wall with no openings keeps a single clean number
reset(); g('walls').push(WD([]));
L = grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls')));
ok('no openings, no chain', L.length===2, L.map(l=>l.t));

// one opening
reset(); g('walls').push(WD([[120,36]]));
texts = grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls'))).map(l=>l.t);
ok('one opening gives corner, width, corner', texts.filter(t=>t===c('fmtLen',102)).length===2 &&
                                              texts.includes(c('fmtLen',36)), texts);

// an opening running off the end is ignored
reset(); g('walls').push(WD([[2,36]]));
texts = grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls'))).map(l=>l.t);
ok('an opening off the end is skipped', !texts.includes(c('fmtLen',36)), texts);

// the switch still rules
reset(); g('walls').push(WD([[60,36],[180,36]]));
c('setDimMode','in');
ok('inside only hides the chain', grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls'))).length===1);
c('setDimMode','none');
ok('none hides everything', grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls'))).length===0);
c('setDimMode','out');
ok('outside only keeps the chain', grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls'))).length>=6);
c('setDimMode','both');

// chain numbers read along the wall
reset(); g('walls').push({sx:0,sy:0,ex:0,ey:240,th:6,h:96,ha:'left',cat:'exterior',ops:[[120,36]],corners:null,syms:[]});
L = grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls')));
ok('a vertical wall turns its chain too', L.every(l=>near(Math.abs(l.rot||0), Math.PI/2)), L.map(l=>l.rot));

let d=true; try { c('draw'); } catch(e){ d=false; console.log('  '+e.message); }
ok('draw survives the chain', d);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
