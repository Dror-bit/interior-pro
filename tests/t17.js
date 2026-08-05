const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.05);
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('selList',[]); s('sel',null); s('mode','sel'); }
const W=(a,b,cc,d)=>({sx:a,sy:b,ex:cc,ey:d,th:6,h:96,ha:'left',cat:'exterior',ops:[],corners:null,syms:[]});
function selPending(){ s('selList', g('pending').map((_,i)=>({type:'pending',i:i}))); s('sel',g('selList')[0]); }
const xs=()=>g('pending').flatMap(w=>[w.sx,w.ex]);
const ys=()=>g('pending').flatMap(w=>[w.sy,w.ey]);

// ---- an L of three walls, flipped left-right ---------------------------
reset();
g('pending').push(W(0,0, 100,0));
g('pending').push(W(100,0, 100,60));
g('pending').push(W(100,60, 40,60));
selPending();
const n0=g('pending').length;
const spanX0=[Math.min.apply(null,xs()), Math.max.apply(null,xs())];
c('flipSel','h');
ok('no copy was added', g('pending').length===n0, g('pending').length);
const spanX1=[Math.min.apply(null,xs()), Math.max.apply(null,xs())];
ok('it stayed in the same footprint', near(spanX0[0],spanX1[0]) && near(spanX0[1],spanX1[1]), {before:spanX0, after:spanX1});
// the short leg was on the LEFT of centre before, it must be on the RIGHT now
const shortMidBefore = 70;     // wall 3 ran 100->40, mid 70 (right of centre 50)
const w3 = g('pending')[2];
ok('the shape really mirrored', near((w3.sx + w3.ex) / 2, 30), (w3.sx + w3.ex) / 2);

// flipping twice returns the original
reset();
g('pending').push(W(0,0, 100,0));
g('pending').push(W(100,0, 100,60));
g('pending').push(W(100,60, 40,60));
selPending();
const before = JSON.stringify(g('pending').map(w=>[w.sx,w.sy,w.ex,w.ey].map(v=>Math.round(v*100)/100)));
c('flipSel','h'); c('flipSel','h');
const after = JSON.stringify(g('pending').map(w=>[w.sx,w.sy,w.ex,w.ey].map(v=>Math.round(v*100)/100)));
ok('flip twice is a no-op on the footprint', g('pending').length===3, g('pending').length);
ok('every wall is back where it was', before===after, {before, after});

// ---- vertical flip ------------------------------------------------------
reset();
g('pending').push(W(0,0, 100,0));
g('pending').push(W(0,0, 0,80));
selPending();
const spanY0=[Math.min.apply(null,ys()), Math.max.apply(null,ys())];
c('flipSel','v');
ok('vertical flip adds nothing either', g('pending').length===2, g('pending').length);
const spanY1=[Math.min.apply(null,ys()), Math.max.apply(null,ys())];
ok('vertical footprint kept', near(spanY0[0],spanY1[0]) && near(spanY0[1],spanY1[1]), {before:spanY0, after:spanY1});

// ---- applied walls are reported, not silently copied --------------------
reset();
g('walls').push({id:'w1', sx:0,sy:0,ex:100,ey:0, th:6,h:96,ha:'left',cat:'exterior',ops:[],corners:null,syms:[]});
s('selList',[{type:'wall', w:g('walls')[0]}]); s('sel',g('selList')[0]);
c('flipSel','h');
ok('no pending copy created from an applied wall', g('pending').length===0, g('pending').length);
ok('the applied wall is untouched', near(g('walls')[0].sx,0) && near(g('walls')[0].ex,100), g('walls')[0]);
ok('the user is told why', (global.__els.hint.textContent||'').indexOf('הוחלו') >= 0, global.__els.hint.textContent);

// ---- shapes still flip in place (unchanged behaviour) -------------------
reset();
g('pendingSketches').push({pts:[0,0, 100,0, 100,50], closed:false, style:'solid', weight:1, shape:'line'});
s('selList',[{type:'sketch', sk:g('pendingSketches')[0], kind:'pending', i:0}]); s('sel',g('selList')[0]);
c('flipSel','h');
ok('a shape flips without duplicating', g('pendingSketches').length===1, g('pendingSketches').length);
ok('and its points really mirrored', near(g('pendingSketches')[0].pts[0],100) && near(g('pendingSketches')[0].pts[2],0),
   g('pendingSketches')[0].pts);

// ---- Duplicate is still the way to get a copy --------------------------
reset(); g('pending').push(W(0,0,100,0)); selPending();
c('duplicateSel');
ok('Duplicate still arms a ghost copy', !!g('ghostCopy'));
s('ghostCopy', null);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
