const api = require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('erasePick',null); }
function pend(p,cl,sh){ g('pendingSketches').push({pts:p,closed:!!cl,style:'solid',weight:1,shape:sh||'line'}); }
const flat = (a) => { const o=[]; a.forEach(p=>o.push(p.x,p.y)); return o; };

// Two real arcs, messy crossing point - exactly the screenshot case.
reset(); s('mode','line'); c('setLineTool','erase');
const A = c('arcPoints', {x:11.3,y:7.7}, {x:63.1,y:41.9}, {x:117.7,y:9.3}, 48);   // hump
const B = c('arcPoints', {x:83.4,y:-27.6}, {x:104.7,y:13.1}, {x:79.9,y:52.4}, 48); // crosses its right flank
pend(flat(A), false, 'arc');
pend(flat(B), false, 'arc');

let pkB = c('eraseFind', {x: B[40].x, y: B[40].y});   // upper part of B
ok('setup: B is cut by A', pkB && !pkB.whole, pkB && {whole:pkB.whole});
s('erasePick', pkB); c('eraseApply');
ok('setup: 2 shapes remain', g('pendingSketches').length===2, g('pendingSketches').length);

// B now ENDS on A. A must still be cut there.
const Anow = g('pendingSketches').find(x => Math.abs(x.pts[0]-11.3) < 0.01);
const pl = c('skChain', Anow), acc = c('chainAcc', pl);
const marks = c('cutMarks', Anow, pl, acc);
ok('A still has a cut mark where B ends', marks.length >= 1, {marks, L: acc[acc.length-1]});

let pkA = c('eraseFind', {x: A[44].x, y: A[44].y});   // the leftover tail of A past the crossing
ok('A tail is erasable on its own', pkA && !pkA.whole, pkA && {whole:pkA.whole});
if (pkA && !pkA.whole) {
  const cutLen = pkA.cut.length/2, wholeLen = Anow.pts.length/2;
  ok('A tail is only a small piece', cutLen < wholeLen * 0.5, {cutLen, wholeLen});
}
console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
