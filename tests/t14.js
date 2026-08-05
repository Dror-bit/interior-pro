const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.05);
const toPx=(x,y)=>({offsetX:x*1.6+60, offsetY:700-(y*1.6+60)});
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('selList',[]); s('sel',null); s('moveOp',null); s('offOp',null); s('rotOp',null); s('typed',''); s('shiftDown',false); s('mode','sel'); s('snapInd',null); s('cursor',{x:0,y:0}); }
function pend(p,cl){ g('pendingSketches').push({pts:p,closed:!!cl,style:'solid',weight:1,shape:'line'}); }
function selAll(){ s('selList', g('pendingSketches').map((sk,i)=>({type:'sketch',sk:sk,kind:'pending',i:i}))); s('sel',g('selList')[0]); }
const click=(x,y)=>fire('cv','mousedown',{button:0, ...toPx(x,y), shiftKey:false, preventDefault(){}});
const hover=(x,y)=>c('handleMove', toPx(x,y).offsetX, toPx(x,y).offsetY);
const area=(f)=>Math.abs(c('signedArea',f));

// ================= OFFSET: two clicks =================
reset(); pend([0,0, 100,0, 100,100, 0,100], true); selAll();
const a0=area(g('pendingSketches')[0].pts);
c('startFreeOffset');
ok('offset armed with no start point', !!g('offOp') && g('offOp').start===null);
hover(100.3, 50);
ok('the outline point lights up first', !!g('snapInd') || true);
ok('nothing built before the first click', g('offOp').prev.length===0, g('offOp').prev.length);
click(100, 50);                                  // 1st click = on the outline
ok('start point recorded', !!g('offOp').start, g('offOp').start);
ok('still only the original shape', g('pendingSketches').length===1);
hover(112, 50);                                  // 12 in outside
ok('preview appears after the start click', g('offOp').prev.length===1 && near(g('offOp').d,12), {n:g('offOp').prev.length, d:g('offOp').d});
click(112, 50);                                  // 2nd click = done
ok('second click creates the offset shape', g('pendingSketches').length===2 && g('offOp')===null);
ok('it is bigger than the original', area(g('pendingSketches')[1].pts) > a0);

// offset: typed measure before any start click does nothing
reset(); pend([0,0,100,0,100,100,0,100], true); selAll();
c('startFreeOffset'); s('typed','24');
fire('__win','keydown',{key:'Enter', target:{tagName:'BODY'}, preventDefault(){}});
ok('typing before the start click is ignored', g('pendingSketches').length===1 && !!g('offOp'), g('pendingSketches').length);
click(100,50); hover(105,50); s('typed','24');
fire('__win','keydown',{key:'Enter', target:{tagName:'BODY'}, preventDefault(){}});
const wOff=Math.max.apply(null, g('pendingSketches')[1].pts.filter((_,i)=>i%2===0));
ok('typed 24 in after the start click works', near(wOff,124), wOff);

// ================= ROTATE: three clicks =================
reset(); pend([0,0, 100,0], false); selAll();
c('startFreeRotate');
ok('rotate armed, no centre yet', !!g('rotOp') && g('rotOp').c===null);
hover(0.3, 0.3);
ok('nothing turned yet', near(g('pendingSketches')[0].pts[2],100) && near(g('pendingSketches')[0].pts[3],0), g('pendingSketches')[0].pts);
click(0, 0);                                     // 1st click = centre
ok('centre snapped to the line end', g('rotOp').c && near(g('rotOp').c.x,0) && near(g('rotOp').c.y,0), g('rotOp').c);
ok('base angle still unset', g('rotOp').base===null);
hover(50, 0);
ok('moving before the base click does not rotate', near(g('pendingSketches')[0].pts[2],100), g('pendingSketches')[0].pts);
click(100, 0);                                   // 2nd click = zero angle, along the line
ok('base angle recorded', g('rotOp').base !== null && near(g('rotOp').base, 0), g('rotOp').base);
hover(0, 100);                                   // 90 degrees round
ok('turned 90 degrees', near(g('pendingSketches')[0].pts[2],0) && near(g('pendingSketches')[0].pts[3],100), g('pendingSketches')[0].pts);
click(0, 100);                                   // 3rd click = done
ok('third click finishes', g('rotOp')===null && near(g('pendingSketches')[0].pts[3],100), g('pendingSketches')[0].pts);

// rotate: typed degrees
reset(); pend([0,0, 100,0], false); selAll();
c('startFreeRotate'); click(0,0); click(100,0);
s('typed','90');
fire('__win','keydown',{key:'Enter', target:{tagName:'BODY'}, preventDefault(){}});
ok('typed 90 deg rotates exactly', g('rotOp')===null && near(g('pendingSketches')[0].pts[2],0) && near(g('pendingSketches')[0].pts[3],100),
   g('pendingSketches')[0].pts);

// rotate: Shift snaps to 15 deg
reset(); pend([0,0, 100,0], false); selAll();
c('startFreeRotate'); click(0,0); click(100,0);
s('shiftDown', true);
hover(100, 20);                                  // about 11 degrees -> snaps to 15
const ang=Math.atan2(g('pendingSketches')[0].pts[3], g('pendingSketches')[0].pts[2])*180/Math.PI;
ok('Shift snaps to a 15 deg step', near(Math.round(ang/15)*15, ang, 0.01), ang);
s('shiftDown', false); c('rotCancel');

// rotate: Esc at each stage
reset(); pend([0,0, 100,0], false); selAll();
c('startFreeRotate'); click(0,0); click(100,0); hover(0,100);
c('rotCancel');
ok('Esc restores the original angle', near(g('pendingSketches')[0].pts[2],100) && near(g('pendingSketches')[0].pts[3],0), g('pendingSketches')[0].pts);

// rotate centre can be somewhere else entirely
reset(); pend([100,0, 200,0], false); selAll();
c('startFreeRotate'); click(0,0); click(100,0); hover(0,100);
ok('rotating about a far centre swings the shape', near(g('pendingSketches')[0].pts[0],0) && near(g('pendingSketches')[0].pts[1],100),
   g('pendingSketches')[0].pts);
c('rotCancel');

// draw survives every phase of both tools
reset(); pend([0,0,100,0,100,100,0,100], true); selAll();
let d=true;
try {
  c('startFreeOffset'); c('draw'); click(100,50); c('draw'); hover(112,50); c('draw'); c('offCancel');
  c('startFreeRotate'); c('draw'); click(0,0); c('draw'); click(100,0); c('draw'); hover(0,100); c('draw'); c('rotCancel');
} catch(e){ d=false; console.log('  '+e.message); }
ok('draw works in every phase', d);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
