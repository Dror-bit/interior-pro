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
const deg=(r)=>r*180/Math.PI;

// centre away from any geometry, so the aim is free to infer
function setup(){ reset(); pend([300,300, 400,300], false); selAll(); c('startFreeRotate'); click(0,0); }

setup(); hover(2, 100);                 // nearly straight up
let aim=c('rotBaseAim');
ok('the zero arm locks UP', aim && aim.axis==='y' && near(deg(aim.a), 90, 0.01), aim && {axis:aim.axis, a:deg(aim.a)});
hover(-2, -100);                        // nearly straight down
aim=c('rotBaseAim');
ok('the zero arm locks DOWN', aim && aim.axis==='y' && near(deg(aim.a), -90, 0.01), aim && {axis:aim.axis, a:deg(aim.a)});
hover(100, 3);                          // nearly right
aim=c('rotBaseAim');
ok('the zero arm locks RIGHT', aim && aim.axis==='x' && near(deg(aim.a), 0, 0.01), aim && {axis:aim.axis, a:deg(aim.a)});
hover(-100, 3);                         // nearly left
aim=c('rotBaseAim');
ok('the zero arm locks LEFT', aim && aim.axis==='x' && near(Math.abs(deg(aim.a)), 180, 0.01), aim && {axis:aim.axis, a:deg(aim.a)});
hover(100, 100);                        // clean diagonal
aim=c('rotBaseAim');
ok('a diagonal aim stays free', aim && aim.axis===null, aim && aim.axis);

// the locked aim is what actually gets stored as the base
setup(); hover(3, 100); click(3, 100);
ok('the stored base is exactly vertical', near(deg(g('rotOp').base), 90, 0.01), deg(g('rotOp').base));
ok('and the arm point sits on the axis', near(g('rotOp').baseP.x, 0, 0.01), g('rotOp').baseP);
c('rotCancel');

// pointing at a real corner still wins over the axis
reset(); pend([0,0, 100,0], false); pend([40,97, 60,97], false); selAll();
c('startFreeRotate'); click(0,0);
hover(40.3, 97.3);                      // a real endpoint, about 2 deg off vertical
aim=c('rotBaseAim');
ok('a real corner beats the axis lock', aim && aim.axis===null && near(deg(aim.a), deg(Math.atan2(97,40)), 0.01),
   aim && {axis:aim.axis, a:deg(aim.a)});
c('rotCancel');

// the whole flow: vertical base, then a quarter turn
reset(); pend([0,0, 100,0], false); selAll();
c('startFreeRotate'); click(0,0);
hover(2, 100); click(2, 100);           // base locked straight up
hover(100, 2);                          // turn to the right -> -90
ok('a square turn off a locked base is exact', near(deg(g('rotOp').ang), -90, 0.01), deg(g('rotOp').ang));
click(100, 2);
ok('the line ended up pointing down', near(g('pendingSketches')[0].pts[3], -100, 0.01), g('pendingSketches')[0].pts);

// draw in the aiming phase
setup(); hover(2, 100);
let d=true; try { c('draw'); } catch(e){ d=false; console.log('  '+e.message); }
ok('draw works while aiming the zero arm', d);
c('rotCancel');

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
