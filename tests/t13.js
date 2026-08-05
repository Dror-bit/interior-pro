const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.05);
const toPx=(x,y)=>({offsetX:x*1.6+60, offsetY:700-(y*1.6+60)});
const els=global.__els, calls=global.__calls;
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('selList',[]); s('sel',null); s('moveOp',null); s('offOp',null); s('rotOp',null); s('typed',''); s('shiftDown',false); s('mode','sel'); s('snapInd',null); }
function pend(p,cl){ g('pendingSketches').push({pts:p,closed:!!cl,style:'solid',weight:1,shape:'line'}); }
function selAll(){ s('selList', g('pendingSketches').map((sk,i)=>({type:'sketch',sk:sk,kind:'pending',i:i}))); s('sel',g('selList')[0]); }
const click=(x,y)=>fire('cv','mousedown',{button:0, ...toPx(x,y), shiftKey:false, preventDefault(){}});
const hover=(x,y)=>c('handleMove', toPx(x,y).offsetX, toPx(x,y).offsetY);

const fs=require('fs'), html=fs.readFileSync('out.html','utf8');
ok('the left/right arrows are gone', !html.includes('id="ebMoveL"') && !html.includes('id="ebMoveR"'));
ok('the 4-way move button stayed', html.includes('id="ebMove"'));
ok('no duplicate Move field was left behind', (html.match(/id="selMove"/g)||[]).length===1);

// ---- SketchUp flow: grab a corner, then drop it somewhere ---------------
reset(); pend([0,0, 100,0, 100,60, 0,60], true); selAll();
c('startFreeMove');
ok('armed, but no grab point yet', !!g('moveOp') && g('moveOp').grab===null);
hover(100.4, 60.4);                                  // hover the top-right corner
ok('the corner lights up before you click', !!g('snapInd') && near(g('snapInd').x,100) && near(g('snapInd').y,60), g('snapInd'));
ok('nothing moved yet', near(g('pendingSketches')[0].pts[0], 0), g('pendingSketches')[0].pts);
click(100.4, 60.4);                                  // 1st click = grab
ok('grab point locked onto the corner', g('moveOp').grab && near(g('moveOp').grab.x,100) && near(g('moveOp').grab.y,60), g('moveOp').grab);
ok('still nothing moved', near(g('pendingSketches')[0].pts[0], 0), g('pendingSketches')[0].pts);
hover(140, 60);                                      // move 40 right
ok('shape follows grab-to-cursor, no jump', near(g('pendingSketches')[0].pts[0], 40) && near(g('pendingSketches')[0].pts[1], 0),
   g('pendingSketches')[0].pts);
click(140, 60);                                      // 2nd click = drop
ok('second click drops it', g('moveOp')===null && near(g('pendingSketches')[0].pts[0], 40), g('pendingSketches')[0].pts);

// ---- axis locks on by itself near horizontal ---------------------------
reset(); pend([0,0, 100,0, 100,60, 0,60], true); selAll();
c('startFreeMove'); click(0,0);
hover(50, 1.5);                                       // almost horizontal
ok('near-horizontal locks to the X axis', g('moveOp').lock==='x' && near(g('pendingSketches')[0].pts[1], 0),
   {lock:g('moveOp').lock, pts:g('pendingSketches')[0].pts});
hover(1.5, 50);                                       // almost vertical
ok('near-vertical locks to the Y axis', g('moveOp').lock==='y' && near(g('pendingSketches')[0].pts[0], 0),
   {lock:g('moveOp').lock, pts:g('pendingSketches')[0].pts});
hover(50, 50);                                        // clean diagonal
ok('a real diagonal stays free', g('moveOp').lock===null, g('moveOp').lock);
c('moveCancel');

// ---- Shift forces the axis ---------------------------------------------
reset(); pend([0,0, 100,0], false); selAll();
c('startFreeMove'); click(0,0);
s('shiftDown', true);
hover(60, 25);
ok('Shift keeps it on one axis', near(g('pendingSketches')[0].pts[0],60) && near(g('pendingSketches')[0].pts[1],0),
   g('pendingSketches')[0].pts);
s('shiftDown', false); c('moveCancel');

// ---- the destination snaps to another object ---------------------------
reset(); pend([0,0, 50,0], false); pend([200,80, 300,80], false); selAll();
s('selList',[{type:'sketch',sk:g('pendingSketches')[0],kind:'pending',i:0}]); s('sel',g('selList')[0]);
c('startFreeMove'); click(0,0);
hover(200.4, 80.4);                                   // near the other line end
ok('drop point snapped onto the other shape', near(g('pendingSketches')[0].pts[0],200) && near(g('pendingSketches')[0].pts[1],80),
   g('pendingSketches')[0].pts);
c('moveCancel');

// ---- typed distance ----------------------------------------------------
reset(); pend([0,0, 100,0], false); selAll();
c('startFreeMove'); click(0,0);
hover(30, 0);
s('typed','96');
fire('__win','keydown',{key:'Enter', target:{tagName:'BODY'}, preventDefault(){}});
ok('typed 96 in moved it exactly', g('moveOp')===null && near(g('pendingSketches')[0].pts[0],96), g('pendingSketches')[0].pts);

// ---- Esc after grabbing puts it back -----------------------------------
reset(); pend([0,0, 100,0], false); selAll();
c('startFreeMove'); click(0,0); hover(70,70);
c('moveCancel');
ok('Esc restores the original position', near(g('pendingSketches')[0].pts[0],0) && near(g('pendingSketches')[0].pts[1],0), g('pendingSketches')[0].pts);

// ---- the old wall Move sideways field still works ----------------------
reset(); s('mode','sel');
g('pending').push({sx:0,sy:0,ex:100,ey:0,th:6,h:96,ha:'left',cat:'exterior',ops:[],corners:null,syms:[]});
s('selList',[{type:'pending',i:0}]); s('sel',g('selList')[0]);
document.getElementById('selMove').value='10';
const beforeY=g('pending')[0].sy;
c('moveWall', 1);
ok('wall Move sideways still moves the wall', g('pending')[0].sy !== beforeY, {before:beforeY, after:g('pending')[0].sy});

// draw in both phases
reset(); pend([0,0,100,0],false); selAll();
c('startFreeMove');
let d=true; try { c('draw'); click(0,0); hover(40,0); c('draw'); } catch(e){ d=false; console.log('  '+e.message); }
ok('draw works before and after the grab', d);
c('moveCancel');

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
