const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.05);
const toPx=(x,y)=>({offsetX:x*1.6+60, offsetY:700-(y*1.6+60)});
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('selList',[]); s('sel',null); s('rotOp',null); s('moveOp',null); s('offOp',null); s('typed',''); s('shiftDown',false); s('mode','sel'); s('cursor',{x:0,y:0}); }
function pend(p,cl){ g('pendingSketches').push({pts:p,closed:!!cl,style:'solid',weight:1,shape:'line'}); }
function selAll(){ s('selList', g('pendingSketches').map((sk,i)=>({type:'sketch',sk:sk,kind:'pending',i:i}))); s('sel',g('selList')[0]); }
const click=(x,y)=>fire('cv','mousedown',{button:0, ...toPx(x,y), shiftKey:false, preventDefault(){}});
const hover=(x,y)=>c('handleMove', toPx(x,y).offsetX, toPx(x,y).offsetY);
const armAngle=()=>Math.atan2(g('pendingSketches')[0].pts[3]-g('pendingSketches')[0].pts[1],
                              g('pendingSketches')[0].pts[2]-g('pendingSketches')[0].pts[0])*180/Math.PI;

// a horizontal line, rotating about its left end, base along itself
function setup(){ reset(); pend([0,0, 100,0], false); selAll(); c('startFreeRotate'); click(0,0); click(100,0); }

setup(); hover(100, 6);            // ~3.4 deg above horizontal -> locks to RIGHT
ok('near right locks to horizontal', g('rotOp').axis==='x' && near(armAngle(), 0, 0.01), {axis:g('rotOp').axis, ang:armAngle()});
hover(6, 100);                     // ~3.4 deg off vertical -> locks UP
ok('near up locks to vertical', g('rotOp').axis==='y' && near(armAngle(), 90, 0.01), {axis:g('rotOp').axis, ang:armAngle()});
hover(-100, 6);                    // near LEFT
ok('near left locks to horizontal', g('rotOp').axis==='x' && near(Math.abs(armAngle()), 180, 0.01), {axis:g('rotOp').axis, ang:armAngle()});
hover(-6, -100);                   // near DOWN
ok('near down locks to vertical', g('rotOp').axis==='y' && near(armAngle(), -90, 0.01), {axis:g('rotOp').axis, ang:armAngle()});
hover(100, 100);                   // a clean 45 -> no lock
ok('45 degrees stays free', g('rotOp').axis===null && near(armAngle(), 45, 0.6), {axis:g('rotOp').axis, ang:armAngle()});
c('rotCancel');

// the lock survives a base that is NOT on an axis
reset(); pend([0,0, 100,100], false); selAll();
c('startFreeRotate'); click(0,0); click(100,100);      // base at 45 deg
hover(100, 5);
ok('an off-axis base still locks the arm to horizontal', g('rotOp').axis==='x' && near(armAngle(), 0, 0.01),
   {axis:g('rotOp').axis, ang:armAngle()});
c('rotCancel');

// Shift still gives 15-degree steps and overrides the axis lock
setup(); s('shiftDown', true);
hover(100, 6);
ok('Shift takes over with 15 deg steps', g('rotOp').axis===null && near(Math.round(armAngle()/15)*15, armAngle(), 0.01),
   {axis:g('rotOp').axis, ang:armAngle()});
s('shiftDown', false); c('rotCancel');

// a near-quarter turn snaps clean even without an axis lock
reset(); pend([0,0, 100,100], false); selAll();
c('startFreeRotate'); click(0,0); click(100,100);      // base 45
hover(-99, 100);                                       // about 134.7 deg -> 90 deg turn
ok('a near-quarter turn snaps to exactly 90', near(g('rotOp').ang*180/Math.PI, 90, 0.01), g('rotOp').ang*180/Math.PI);
c('rotCancel');

// typed degrees still win
setup(); s('typed','30');
fire('__win','keydown',{key:'Enter', target:{tagName:'BODY'}, preventDefault(){}});
ok('typed 30 deg still exact', g('rotOp')===null && near(armAngle(), 30, 0.01), armAngle());

// draw with a locked axis
setup(); hover(100,6);
let d=true; try { c('draw'); } catch(e){ d=false; console.log('  '+e.message); }
ok('draw works with the axis guide', d);
c('rotCancel');

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
