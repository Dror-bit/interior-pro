const api = require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('erasePick',null); }
function pend(p,cl,sh){ g('pendingSketches').push({pts:p,closed:!!cl,style:'solid',weight:1,shape:sh||'line'}); }
const flat=(a)=>{const o=[];a.forEach(p=>o.push(p.x,p.y));return o;};

// the user flow end to end: two arcs, trim BOTH leftovers
reset(); s('mode','line'); c('setLineTool','erase');
const A=c('arcPoints',{x:11.3,y:7.7},{x:63.1,y:41.9},{x:117.7,y:9.3},48);
const B=c('arcPoints',{x:83.4,y:-27.6},{x:104.7,y:13.1},{x:79.9,y:52.4},48);
pend(flat(A),false,'arc'); pend(flat(B),false,'arc');
let p1=c('eraseFind',{x:B[40].x,y:B[40].y}); s('erasePick',p1); c('eraseApply');
let p2=c('eraseFind',{x:A[44].x,y:A[44].y}); s('erasePick',p2); c('eraseApply');
ok('both leftovers trimmed, 2 shapes left', g('pendingSketches').length===2, g('pendingSketches').length);
const lens=g('pendingSketches').map(x=>x.pts.length/2);
ok('both survivors are real curves', lens.every(l=>l>5), lens);

// a shape ending NEAR but not ON another one must NOT cut it
reset(); s('mode','line'); c('setLineTool','erase');
pend([0,0, 200,0],false,'line');
pend([100,20, 100,3],false,'line');          // stops 3 in short
let pk=c('eraseFind',{x:50,y:0});
ok('a near miss does not cut', pk && pk.whole===true, pk && {whole:pk.whole});

// touching exactly DOES cut
reset(); s('mode','line'); c('setLineTool','erase');
pend([0,0, 200,0],false,'line');
pend([100,20, 100,0],false,'line');
pk=c('eraseFind',{x:50,y:0});
ok('an exact touch cuts', pk && !pk.whole && Math.abs(pk.cut[2]-100)<0.05, pk && pk.cut);

// a T of three lines: erase the stem, then each half of the bar separately
reset(); s('mode','line'); c('setLineTool','erase');
pend([0,0, 200,0],false,'line'); pend([100,0, 100,60],false,'line');
pk=c('eraseFind',{x:100,y:30}); s('erasePick',pk); c('eraseApply');
ok('T: stem gone', g('pendingSketches').length===1, g('pendingSketches').length);
pk=c('eraseFind',{x:50,y:0});
ok('T: bar is whole again once the stem is gone', pk && pk.whole===true, pk && {whole:pk.whole});

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
