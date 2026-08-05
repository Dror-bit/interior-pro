const api = require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.05);
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('erasePick',null); }
function pend(p,cl,sh){ g('pendingSketches').push({pts:p,closed:!!cl,style:'solid',weight:1,shape:sh||'line'}); }
function samp(f, n){ const o=[]; for(let i=0;i<=n;i++){ const p=f(i/n); o.push(p.x,p.y);} return o; }

// two ARCS crossing at (60,0)
reset(); s('mode','line'); c('setLineTool','erase');
pend(samp(t => ({x: t*100, y: 0}), 48), false, 'arc');            // A: along y=0
pend(samp(t => ({x: 60, y: -40 + t*80}), 48), false, 'arc');      // B: vertical through it

let pk = c('eraseFind', {x:60, y:20});
ok('step1: B stub above the crossing is found', pk && !pk.whole, pk && {whole:pk.whole});
ok('step1: stub runs 0 -> 40', pk && near(Math.min(pk.cut[1], pk.cut[pk.cut.length-1]),0) && near(Math.max(pk.cut[1], pk.cut[pk.cut.length-1]),40), pk && [pk.cut[1], pk.cut[pk.cut.length-1]]);
s('erasePick', pk); c('eraseApply');
ok('step1: two shapes remain', g('pendingSketches').length===2, g('pendingSketches').length);

// now B ENDS at the crossing. The leftover of A must STILL be erasable on its own.
pk = c('eraseFind', {x:80, y:0});
ok('step2: A right leftover is NOT the whole arc', pk && !pk.whole, pk && {whole:pk.whole});
ok('step2: it runs 60 -> 100', pk && near(pk.cut[0],60) && near(pk.cut[pk.cut.length-2],100), pk && [pk.cut[0], pk.cut[pk.cut.length-2]]);
pk = c('eraseFind', {x:30, y:0});
ok('step3: A left part runs 0 -> 60', pk && !pk.whole && near(pk.cut[0],0) && near(pk.cut[pk.cut.length-2],60), pk && pk.cut && [pk.cut[0], pk.cut[pk.cut.length-2]]);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
