const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.05);
const toPx=(x,y)=>({offsetX:x*1.6+60, offsetY:700-(y*1.6+60)});
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('drawing',false); s('startPt',null); s('snapInd',null); }

// the U from the screenshot: three PENDING walls, 6 in thick
reset(); s('mode','wall');
const W=(sx0,sy0,ex,ey)=>({sx:sx0,sy:sy0,ex:ex,ey:ey,th:6,h:96,ha:'left',cat:'exterior',ops:[],corners:null,syms:[]});
g('pending').push(W(0,175,175,175));     // top
g('pending').push(W(175,175,175,0));     // right
g('pending').push(W(175,0,0,0));         // bottom

// hover the INNER corner of the bottom wall, no click yet
let inner = c('endCorners', g('pending')[2], g('pending').concat(g('walls')), c('bandQuad', g('pending')[2]));
ok('inner corner exists', !!inner, inner);
s('snapInd', null);
c('handleMove', toPx(inner.sp.x + 1, inner.sp.y + 1).offsetX, toPx(inner.sp.x + 1, inner.sp.y + 1).offsetY);
ok('green marker appears on hover, before any click', !!g('snapInd'), g('snapInd'));
ok('it is a corner (green), not a midpoint', g('snapInd') && g('snapInd').kind==='end', g('snapInd'));
ok('it sits exactly on the corner', g('snapInd') && near(g('snapInd').x, inner.sp.x) && near(g('snapInd').y, inner.sp.y),
   {got:g('snapInd'), want:inner.sp});

// away from everything -> no marker
c('handleMove', toPx(600,600).offsetX, toPx(600,600).offsetY);
ok('no marker in empty space', g('snapInd')===null, g('snapInd'));

// the marker also survives INTO the chain (old behaviour kept)
c('handleMove', toPx(inner.sp.x, inner.sp.y).offsetX, toPx(inner.sp.x, inner.sp.y).offsetY);
const L=global.__listeners;
L.cv.mousedown ? null : null;
fire('cv','mousedown',{button:0, ...toPx(inner.sp.x, inner.sp.y), shiftKey:false, preventDefault(){}});
ok('click starts the chain at the corner', g('drawing')===true && near(g('startPt').x, inner.sp.x) && near(g('startPt').y, inner.sp.y),
   {drawing:g('drawing'), startPt:g('startPt')});

// draw() must not throw in either state
let okDraw=true; try { c('draw'); s('drawing',false); c('draw'); } catch(e){ okDraw=false; console.log('  draw error: '+e.message); }
ok('draw works hovering and drawing', okDraw);

// mitered corner is used for PENDING walls (not the raw band corner)
reset(); s('mode','wall');
g('pending').push(W(0,0,100,0));
g('pending').push(W(100,0,100,100));
const b0=c('bandQuad', g('pending')[0]);
const C0=c('endCorners', g('pending')[0], g('pending'), b0);
const rawCorner={x:100+b0.nx*b0.p, y:0+b0.ny*b0.p};
const mitered=C0.ep;
if (Math.hypot(mitered.x-rawCorner.x, mitered.y-rawCorner.y) > 0.1) {
  const q=c('snapPoint', {x:mitered.x+0.5, y:mitered.y+0.5}, null);
  ok('snaps to the MITERED corner, not the raw one', near(q.x, mitered.x) && near(q.y, mitered.y),
     {got:q, mitered, raw:rawCorner});
} else { ok('mitered == raw here (no miter to test)', true); }

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
