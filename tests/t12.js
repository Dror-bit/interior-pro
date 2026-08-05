const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.05);
const toPx=(x,y)=>({offsetX:x*1.6+60, offsetY:700-(y*1.6+60)});
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('selList',[]); s('sel',null); s('offOp',null); s('moveOp',null); s('rotOp',null); s('typed',''); s('mode','sel'); s('cursor',{x:0,y:0}); }
function pend(p,cl,sh){ g('pendingSketches').push({pts:p,closed:!!cl,style:'solid',weight:1,shape:sh||'line'}); }
function selIdx(i){ s('selList',[{type:'sketch',sk:g('pendingSketches')[i],kind:'pending',i:i}]); s('sel',g('selList')[0]); }
const area=(f)=>Math.abs(c('signedArea',f));

const fs=require('fs'), html=fs.readFileSync('out.html','utf8');
ok('offset button now starts the free tool', /id="ebOff"[^>]*onclick="startFreeOffset\(\)"/.test(html));
ok('offset needs an outline click first', /offStart/.test(fs.readFileSync('out.js','utf8')));
ok('the old Offset field is gone', !html.includes('id="selOff"'));

// ---- closed square: cursor OUTSIDE grows it ----------------------------
reset(); pend([0,0, 100,0, 100,100, 0,100], true, 'rect'); selIdx(0);
const a0 = area(g('pendingSketches')[0].pts);
c('startFreeOffset'); c('offStart',{x:0,y:0});
ok('offset started', !!g('offOp'));
c('handleMove', toPx(112,50).offsetX, toPx(112,50).offsetY);    // 12 in outside
ok('preview built', g('offOp').prev.length===1, g('offOp'));
ok('distance read from the cursor', near(g('offOp').d, 12), g('offOp').d);
ok('side is OUT', g('offOp').sgn===1, g('offOp').sgn);
ok('preview is bigger than the original', area(g('offOp').prev[0].pts) > a0, {prev:area(g('offOp').prev[0].pts), orig:a0});
fire('cv','mousedown',{button:0, ...toPx(112,50), shiftKey:false, preventDefault(){}});
ok('click creates the new shape', g('pendingSketches').length===2 && g('offOp')===null, g('pendingSketches').length);
ok('the original is untouched', near(area(g('pendingSketches')[0].pts), a0), area(g('pendingSketches')[0].pts));

// ---- cursor INSIDE shrinks it ------------------------------------------
reset(); pend([0,0, 100,0, 100,100, 0,100], true, 'rect'); selIdx(0);
const a1 = area(g('pendingSketches')[0].pts);
c('startFreeOffset'); c('offStart',{x:0,y:0});
c('handleMove', toPx(90,50).offsetX, toPx(90,50).offsetY);      // 10 in inside
ok('side is IN', g('offOp').sgn===-1, g('offOp').sgn);
ok('preview is smaller', area(g('offOp').prev[0].pts) < a1, {prev:area(g('offOp').prev[0].pts), orig:a1});
c('offCancel');
ok('Esc leaves nothing behind', g('pendingSketches').length===1 && g('offOp')===null);

// ---- a typed measure wins over the drag --------------------------------
reset(); pend([0,0, 100,0, 100,100, 0,100], true, 'rect'); selIdx(0);
c('startFreeOffset'); c('offStart',{x:0,y:0});
c('handleMove', toPx(105,50).offsetX, toPx(105,50).offsetY);    // 5 in out
s('typed','24');
fire('__win','keydown',{key:'Enter', target:{tagName:'BODY'}, preventDefault(){}});
ok('typed 24 in was used', g('pendingSketches').length===2, g('pendingSketches').length);
const w2 = Math.max.apply(null, g('pendingSketches')[1].pts.filter((_,i)=>i%2===0));
ok('new outline is 24 in out on every side', near(w2, 124), w2);

// ---- feet notation ------------------------------------------------------
reset(); pend([0,0, 100,0, 100,100, 0,100], true, 'rect'); selIdx(0);
c('startFreeOffset'); c('offStart',{x:0,y:0}); c('handleMove', toPx(105,50).offsetX, toPx(105,50).offsetY);
s('typed',"1'");
fire('__win','keydown',{key:'Enter', target:{tagName:'BODY'}, preventDefault(){}});
const w3 = Math.max.apply(null, g('pendingSketches')[1].pts.filter((_,i)=>i%2===0));
ok('1 ft = 12 in offset', near(w3, 112), w3);

// ---- open line: side follows the cursor --------------------------------
reset(); pend([0,0, 100,0]); selIdx(0);
c('startFreeOffset'); c('offStart',{x:0,y:0});
c('handleMove', toPx(50,20).offsetX, toPx(50,20).offsetY);      // above
const upSide = g('offOp').prev[0].pts[1];
c('handleMove', toPx(50,-20).offsetX, toPx(50,-20).offsetY);    // below
const dnSide = g('offOp').prev[0].pts[1];
ok('an open line offsets to whichever side you point at', near(upSide,20) && near(dnSide,-20), {upSide, dnSide});
c('offCancel');

// ---- style carried over -------------------------------------------------
reset(); g('pendingSketches').push({pts:[0,0,100,0,100,100,0,100], closed:true, style:'dashed', weight:2, shape:'rect'});
selIdx(0);
c('startFreeOffset'); c('offStart',{x:0,y:0}); c('handleMove', toPx(112,50).offsetX, toPx(112,50).offsetY); c('offCommit');
const nw=g('pendingSketches')[1];
ok('new shape keeps style and weight', nw.style==='dashed' && nw.weight===2 && nw.closed===true, nw);

// ---- a stray click with no drag creates nothing -------------------------
reset(); pend([0,0,100,0,100,100,0,100], true, 'rect'); selIdx(0);
c('startFreeOffset'); c('offStart',{x:0,y:0}); c('offCommit');
ok('no drag, no shape', g('pendingSketches').length===1, g('pendingSketches').length);

// draw survives
reset(); pend([0,0,100,0,100,100,0,100], true, 'rect'); selIdx(0);
c('startFreeOffset'); c('offStart',{x:0,y:0}); c('handleMove', toPx(112,50).offsetX, toPx(112,50).offsetY);
let d=true; try { c('draw'); } catch(e){ d=false; console.log('  '+e.message); }
ok('draw works during an offset', d);
c('offCancel');

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
