const api = require('./run.js');
const els = global.__els;
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('erasePick',null); s('selList',[]); s('sel',null); }
function pend(p,cl,sh){ g('pendingSketches').push({pts:p,closed:!!cl,style:'solid',weight:1,shape:sh||'line'}); }

// erase mode must not disturb the OTHER modes / tools
reset(); s('mode','sel'); pend([0,0,100,100]);
let hit = c('hitSketch', {x:50,y:50});
ok('select mode still picks whole shapes', hit && hit.type==='sketch', hit);

// arc / rect / circle tools still build shapes after the toolbar change
reset(); s('mode','line');
c('setLineTool','rect'); c('lineToolClick',{x:0,y:0}); c('lineToolClick',{x:40,y:30});
ok('rect tool still works', g('pendingSketches').length===1 && g('pendingSketches')[0].closed===true, g('pendingSketches'));
reset(); c('setLineTool','circle'); c('lineToolClick',{x:0,y:0}); c('lineToolClick',{x:20,y:0});
ok('circle tool still works', g('pendingSketches').length===1 && g('pendingSketches')[0].shape==='circle', g('pendingSketches').map(x=>x.shape));
reset(); c('setLineTool','arc'); c('lineToolClick',{x:0,y:0}); c('lineToolClick',{x:40,y:0}); c('lineToolClick',{x:20,y:10});
ok('arc tool still works', g('pendingSketches').length===1 && g('pendingSketches')[0].shape==='arc', g('pendingSketches').map(x=>x.shape));
reset(); c('setLineTool','hex'); c('lineToolClick',{x:0,y:0}); c('lineToolClick',{x:20,y:0});
ok('polygon tool still works', g('pendingSketches').length===1 && g('pendingSketches')[0].shape==='poly', g('pendingSketches').map(x=>x.shape));

// guides survive; guide points are still snap targets
reset(); s('mode','line'); c('setLineTool','line');
c('toggleGuideMode'); ok('guide mode on', g('guideMode')===true);
// two-point guide (the classic mode)
c('setGuideAim','2pt');
c('guideClick',{x:0,y:0}); c('guideClick',{x:100,y:0});
ok('guide created', g('guides').length===1, g('guides'));
// BricsCAD style (2026-08-07): pick the direction, ONE click drops it
s('guides',[]);
c('setGuideAim','h'); c('guideClick',{x:10,y:20});
ok('horizontal guide from one click',
   g('guides').length===1 && Math.abs(g('guides')[0].y2-g('guides')[0].y1)<1e-9, g('guides'));
s('guides',[]);
c('setGuideAim','v'); c('guideClick',{x:10,y:20});
ok('vertical guide from one click',
   g('guides').length===1 && Math.abs(g('guides')[0].x2-g('guides')[0].x1)<1e-9, g('guides'));
s('guides',[]);
document.getElementById('guideAng').value='45'; c('setGuideAim','ang'); c('guideClick',{x:0,y:0});
const ga=g('guides')[0];
ok('angled guide follows the typed angle',
   g('guides').length===1 && Math.abs((ga.y2-ga.y1)-(ga.x2-ga.x1))<1e-6, g('guides'));
// a guide can be picked, moved and deleted
s('guides',[{x1:0,y1:50,x2:1,y2:50}]);
const gh=c('hitGuide',{x:80,y:50});
ok('a guide is pickable', gh && gh.type==='guide', gh);
s('selList',[gh]); s('sel',gh);
c('startFreeMove'); c('moveApply',0,25);
ok('a guide moves', Math.abs(g('guides')[0].y1-75)<1e-9, g('guides'));
c('moveCommit');
c('dupGuides');
ok('a guide duplicates', g('guides').length===2, g('guides').length);
c('moveCancel');
s('selList',[{type:'guide',g:g('guides')[0],i:0}]); s('sel',g('selList')[0]);
c('deleteSelected');
ok('a guide deletes', g('guides').length===1, g('guides').length);
s('guides',[]); reset();
c('toggleGuideMode');

// erasing a piece that touches a guide line does NOT cut on it (guides are editor-only)
reset(); s('mode','line'); c('setLineTool','erase');
pend([0,0,100,0]);
let pk = c('eraseFind',{x:50,y:0});
ok('guides do not cut shapes', pk && pk.whole===true, pk && {whole:pk.whole});

// three lines crossing one line -> 4 pieces, erase the middle one
reset(); s('mode','line'); c('setLineTool','erase');
pend([0,0, 300,0]);
pend([100,-20, 100,20]); pend([200,-20, 200,20]);
pk = c('eraseFind',{x:150,y:0});
ok('middle piece is 100..200', pk && pk.cut[0]===100 && pk.cut[2]===200, pk && pk.cut);
ok('two pieces survive', pk && pk.rest.length===2, pk && pk.rest.length);
s('erasePick', pk); c('eraseApply');
ok('after erase: 4 shapes total', g('pendingSketches').length===4, g('pendingSketches').length);

// erase repeatedly until nothing is left - must not loop or crash
reset(); s('mode','line'); c('setLineTool','erase');
pend([0,0,100,100]); pend([0,100,100,0]);
let guard=0;
while (g('pendingSketches').length && guard++ < 20) {
  const p = c('eraseFind', {x: g('pendingSketches')[0].pts[0], y: g('pendingSketches')[0].pts[1]});
  if (!p) break;
  s('erasePick', p); c('eraseApply');
}
ok('erase down to empty terminates', g('pendingSketches').length===0 && guard<20, {left:g('pendingSketches').length, guard});

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
