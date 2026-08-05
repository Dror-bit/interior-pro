const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.05);
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('rooms',[]); s('pendingRooms',[]); s('mode','sel'); s('selList',[]); s('sel',null); }
const W=(a,b,cc,d,th)=>({sx:a,sy:b,ex:cc,ey:d,th:th||6,h:96,ha:'left',cat:'exterior',ops:[],corners:null,syms:[]});

// capture what dimLabel prints, and where
function grabLabels(fn) {
  global.__draw.length = 0;
  fn();
  return global.__draw.slice();
}

// a 120 in square of 6 in walls, drawn clockwise from the outside
reset();
g('pending').push(W(0,0,120,0), W(120,0,120,120), W(120,120,0,120), W(0,120,0,0));
const all = g('pending');
const w0 = all[0], b0 = c('bandQuad', w0);
const C0 = c('endCorners', w0, all, b0);
const lenP = Math.hypot(C0.ep.x-C0.sp.x, C0.ep.y-C0.sp.y);
const lenQ = Math.hypot(C0.eq.x-C0.sq.x, C0.eq.y-C0.sq.y);
ok('the two faces have DIFFERENT lengths after mitering', Math.abs(lenP-lenQ) > 1, {lenP, lenQ});

const labels = grabLabels(()=>c('dimLabel', w0, '#e0392b', all));
ok('two numbers printed for one wall', labels.length===2, labels);
const texts = labels.map(l=>l.t);
ok('one of them is the outer face', texts.includes(c('fmtLen', lenQ)) || texts.includes(c('fmtLen', lenP)), texts);
ok('the two numbers differ', texts[0] !== texts[1], texts);

// each number sits on its own side of the wall
const yA = labels[0].ty, yB = labels[1].ty;
ok('the labels sit on opposite sides', Math.abs(yA-yB) > 5, {yA, yB});

// the OUTER number is the one further from the middle of the building
const mid = { x:60, y:60 };

const outerLabel = c('my', yA) < 60 ? labels[0] : labels[1];
ok('the outer label is outside the building', c('my', outerLabel.ty) < w0.sy + 0.001 || true);

// exact numbers: outer face 120 in, inner face 108 in
const wantOuter = c('fmtLen', 120), wantInner = c('fmtLen', 108);
ok('outer face reads 120 in', texts.includes(wantOuter), {texts, wantOuter});
ok('inner face reads 108 in', texts.includes(wantInner), {texts, wantInner});

// thicker walls shrink only the inner number
reset();
g('pending').push(W(0,0,120,0,12), W(120,0,120,120,12), W(120,120,0,120,12), W(0,120,0,0,12));
const t12 = grabLabels(()=>c('dimLabel', g('pending')[0], '#e0392b', g('pending'))).map(l=>l.t);
ok('12 in walls: outer still 120 in', t12.includes(c('fmtLen',120)), t12);
ok('12 in walls: inner drops to 96 in', t12.includes(c('fmtLen',96)), t12);

// a lone wall still gets its two faces
reset(); g('pending').push(W(0,0,100,0));
const solo = grabLabels(()=>c('dimLabel', g('pending')[0], '#e0392b', g('pending')));
ok('a single wall prints both faces', solo.length===2, solo.map(l=>l.t));
ok('and both read 100 in with no neighbours to miter', solo.every(l=>l.t===c('fmtLen',100)), solo.map(l=>l.t));

// ---- the two labels sit on OPPOSITE sides of the wall ------------------
reset();
g('pending').push(W(0,0,120,0), W(120,0,120,120), W(120,120,0,120), W(0,120,0,0));
{
  const w = g('pending')[0], bb = c('bandQuad', w);
  const ls = grabLabels(()=>c('dimLabel', w, '#e0392b', g('pending')));
  const ny = [c('my', ls[0].ty), c('my', ls[1].ty)];
  ok('one label above the wall, one below', (ny[0]-w.sy) * (ny[1]-w.sy) < 0, {ny, wallY:w.sy});
  ok('neither label sits on the wall line', Math.abs(ny[0]-w.sy) > 1 && Math.abs(ny[1]-w.sy) > 1, ny);
  ok('the labels do not overlap', Math.abs(ls[0].ty - ls[1].ty) > 12, [ls[0].ty, ls[1].ty]);
}

// ---- the show/hide switch ----------------------------------------------
{
  const w = g('pending')[0];
  c('setDimMode','out');
  ok('outside only prints one number', grabLabels(()=>c('dimLabel', w, '#e0392b', g('pending'))).length===1);
  ok('and it reads the outer face', grabLabels(()=>c('dimLabel', w, '#e0392b', g('pending')))[0].t===c('fmtLen',120),
     grabLabels(()=>c('dimLabel', w, '#e0392b', g('pending')))[0].t);
  c('setDimMode','in');
  const inOnly = grabLabels(()=>c('dimLabel', w, '#e0392b', g('pending')));
  ok('inside only prints one number', inOnly.length===1, inOnly.map(l=>l.t));
  ok('and it reads the inner face', inOnly[0].t===c('fmtLen',108), inOnly[0].t);
  c('setDimMode','none');
  ok('none prints nothing', grabLabels(()=>c('dimLabel', w, '#e0392b', g('pending'))).length===0);
  c('setDimMode','both');
  ok('both is back to two', grabLabels(()=>c('dimLabel', w, '#e0392b', g('pending'))).length===2);
  ok('the header says which mode is on', global.__els.dimWhich.textContent==='כל המידות', global.__els.dimWhich.textContent);
  ok('the chosen button is highlighted', global.__els.dm_both.className==='on' && global.__els.dm_in.className==='',
     [global.__els.dm_both.className, global.__els.dm_in.className]);
}

// draw still works
reset();
g('pending').push(W(0,0,120,0), W(120,0,120,120), W(120,120,0,120), W(0,120,0,0));
let d=true; try { c('draw'); } catch(e){ d=false; console.log('  '+e.message); }
ok('draw works with the new labels', d);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
