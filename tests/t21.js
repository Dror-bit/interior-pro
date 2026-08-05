const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('rooms',[]); s('pendingRooms',[]); s('selList',[]); s('sel',null); s('mode','sel'); }
const W=(a,b,cc,d)=>({sx:a,sy:b,ex:cc,ey:d,th:6,h:96,ha:'left',cat:'exterior',ops:[],corners:null,syms:[]});
function pend(p,cl){ g('pendingSketches').push({pts:p,closed:!!cl,style:'solid',weight:1,shape:'line'}); }
// left-to-right = window, right-to-left = crossing
const win  =(x0,y0,x1,y1)=>{ s('rubber',{x0:Math.min(x0,x1),y0:y0,x1:Math.max(x0,x1),y1:y1}); return c('rubberPick'); };
const cross=(x0,y0,x1,y1)=>{ s('rubber',{x0:Math.max(x0,x1),y0:y0,x1:Math.min(x0,x1),y1:y1}); return c('rubberPick'); };

// ---- the original complaint: three long lines, box over their right half --
reset();
pend([0,0, 200,0]); pend([0,20, 200,20]); pend([0,40, 200,40]);
ok('crossing catches lines the box only touches', cross(100,-10, 210,50).length===3,
   cross(100,-10, 210,50).length);
ok('window ignores lines that stick out', win(100,-10, 210,50).length===0,
   win(100,-10, 210,50).length);
ok('window catches them when they fit entirely', win(-10,-10, 210,50).length===3,
   win(-10,-10, 210,50).length);

// ---- a box fully inside a long line, touching nothing else --------------
reset(); pend([0,0, 400,0]);
ok('crossing catches a line running through the box', cross(100,-10, 200,10).length===1);
ok('window does not', win(100,-10, 200,10).length===0);

// ---- walls -------------------------------------------------------------
reset();
g('pending').push(W(0,0,200,0), W(200,0,200,200));
ok('crossing catches a wall it clips', cross(150,-20, 250,20).length===2, cross(150,-20,250,20).length);
ok('window takes only the wall that fits', win(-20,-20, 220,60).length===1, win(-20,-20,220,60).length);
ok('window takes both when the box covers everything', win(-20,-20, 260,260).length===2);

// ---- openings ----------------------------------------------------------
reset();
g('walls').push({id:'w1', sx:0,sy:0,ex:240,ey:0, th:6,h:96,ha:'left',cat:'exterior',ops:[],corners:null,
                 syms:[{id:'d1', body:'door', t:120, w:36}]});
const both = cross(-10,-10, 250,20);
ok('crossing takes the wall and the door', both.filter(o=>o.type==='sym').length===1 && both.filter(o=>o.type==='wall').length===1,
   both.map(o=>o.type));
const half = win(100,-10, 130,20);
ok('a window box cutting the door takes neither', half.length===0, half.map(o=>o.type));

// ---- a closed shape: box inside it --------------------------------------
reset(); pend([0,0, 200,0, 200,200, 0,200], true);
ok('a box floating inside a closed shape catches nothing', cross(80,80, 120,120).length===0,
   cross(80,80,120,120).length);
ok('a box on its edge catches it', cross(190,80, 210,120).length===1);
ok('window round the whole thing catches it', win(-10,-10, 210,210).length===1);

// ---- nothing selected when the box is empty ----------------------------
reset(); pend([0,0, 10,0]);
ok('an empty area selects nothing', cross(500,500, 600,600).length===0);

// ---- the drag direction is what decides --------------------------------
reset(); pend([0,0, 200,0]);
s('rubber',{x0:10,y0:-5,x1:100,y1:5});
ok('left to right is a window select', c('rubberCrossing')===false);
s('rubber',{x0:100,y0:-5,x1:10,y1:5});
ok('right to left is a crossing select', c('rubberCrossing')===true);
let d=true; try { c('draw'); } catch(e){ d=false; console.log('  '+e.message); }
ok('draw handles the box in either direction', d);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
