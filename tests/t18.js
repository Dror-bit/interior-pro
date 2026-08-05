const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.05);
const els=global.__els, calls=global.__calls;
const toPx=(x,y)=>({offsetX:x*1.6+60, offsetY:700-(y*1.6+60)});
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('rooms',[]); s('selList',[]); s('sel',null); s('mode','sel'); s('dimTags',[]); calls.length=0; }

// ---- rooms draw with name, number and area -----------------------------
reset();
c('loadRooms', [{ id:'r1', name:'Kitchen', number:104, area:180.44,
                  pts:[0,0, 120,0, 120,120, 0,120] }]);
ok('room loaded', g('rooms').length===1);
c('draw');
const roomTag = g('dimTags').filter(t=>t.kind==='room');
ok('the room label is clickable', roomTag.length===1, g('dimTags').map(t=>t.kind));
ok('area rounds to one decimal', c('fmtSqft', 180.44)==='180.4 SF', c('fmtSqft',180.44));
const cen = c('polyCentroid', [0,0, 120,0, 120,120, 0,120]);
ok('label sits at the centroid', near(cen.x,60) && near(cen.y,60), cen);

// clicking the label renames the room
global.prompt = () => 'Master Bedroom';
c('editDimTag', roomTag[0]);
const rn = calls.filter(x=>x[0]==='rename_room').pop();
ok('rename went to Ruby with the id', !!rn && JSON.parse(rn[1]).id==='r1' && JSON.parse(rn[1]).name==='Master Bedroom', rn);
ok('the canvas shows it straight away', g('rooms')[0].name==='Master Bedroom');
global.prompt = () => null;
calls.length=0;
c('editDimTag', roomTag[0]);
ok('cancel changes nothing', calls.filter(x=>x[0]==='rename_room').length===0);

// ---- area tag on a closed shape: off by default ------------------------
reset();
g('pendingSketches').push({pts:[0,0, 120,0, 120,60, 0,60], closed:true, style:'solid', weight:1, shape:'rect'});
c('draw');
ok('a plain shape shows no area', g('dimTags').filter(t=>t.kind==='skarea').length===0);

s('selList',[{type:'sketch', sk:g('pendingSketches')[0], kind:'pending', i:0}]); s('sel',g('selList')[0]);
c('updateSelPanel');
ok('the area button shows for a closed shape', els.ebArea.style.display==='', els.ebArea.style.display);
c('toggleSelArea');
ok('pressing it turns the tag on', g('pendingSketches')[0].area_on===true);
c('draw');
const skTag = g('dimTags').filter(t=>t.kind==='skarea');
ok('the tag is drawn and clickable', skTag.length===1, g('dimTags').map(t=>t.kind));
ok('120x60 in = 50 SF', c('fmtSqft', c('sqftOf', g('pendingSketches')[0].pts))==='50 SF',
   c('sqftOf', g('pendingSketches')[0].pts));
c('toggleSelArea');
ok('pressing again turns it off', !g('pendingSketches')[0].area_on);
c('draw');
ok('and the tag is gone', g('dimTags').filter(t=>t.kind==='skarea').length===0);

// ---- an OPEN shape gets no area ----------------------------------------
reset();
g('pendingSketches').push({pts:[0,0, 120,0, 120,60], closed:false, style:'solid', weight:1, shape:'line'});
s('selList',[{type:'sketch', sk:g('pendingSketches')[0], kind:'pending', i:0}]); s('sel',g('selList')[0]);
c('updateSelPanel');
ok('the area button hides for an open shape', els.ebArea.style.display==='none', els.ebArea.style.display);
c('toggleSelArea');
ok('and pressing it does nothing', !g('pendingSketches')[0].area_on);
ok('with a reason in the status bar', (els.hint.textContent||'').indexOf('סגורה')>=0, els.hint.textContent);

// ---- naming an area tag ------------------------------------------------
reset();
g('sketches').push({id:'sk-7', pts:[0,0, 120,0, 120,60, 0,60], closed:true, style:'solid', weight:1, shape:'rect', area_on:true});
c('draw');
const t7 = g('dimTags').filter(x=>x.kind==='skarea')[0];
global.prompt = () => 'Patio';
calls.length=0;
c('editDimTag', t7);
const an = calls.filter(x=>x[0]==='rename_sketch_area').pop();
ok('the area name goes to Ruby', !!an && JSON.parse(an[1]).id==='sk-7' && JSON.parse(an[1]).name==='Patio', an);
ok('and shows on the canvas', g('sketches')[0].area_name==='Patio');

// ---- a model shape toggles through Ruby --------------------------------
reset();
g('sketches').push({id:'sk-8', pts:[0,0, 120,0, 120,60, 0,60], closed:true, style:'solid', weight:1, shape:'rect'});
s('selList',[{type:'sketch', sk:g('sketches')[0], kind:'model', i:0}]); s('sel',g('selList')[0]);
calls.length=0;
c('toggleSelArea');
const sa = calls.filter(x=>x[0]==='set_sketch_area').pop();
ok('the toggle is saved on the model', !!sa && JSON.parse(sa[1]).ids[0]==='sk-8' && JSON.parse(sa[1]).on===true, sa);

// ---- rooms survive a wall reload ---------------------------------------
reset();
c('loadRooms',[{id:'r1',name:'Kitchen',number:1,area:100,pts:[0,0,100,0,100,144,0,144]}]);
c('loadWalls',[]);
ok('rooms are not wiped by loadWalls', g('rooms').length===1, g('rooms').length);

// draw never throws with everything on at once
reset();
c('loadRooms',[{id:'r1',name:'Kitchen',number:1,area:100,pts:[0,0,100,0,100,144,0,144]}]);
g('pendingSketches').push({pts:[200,0, 320,0, 320,60, 200,60], closed:true, style:'solid', weight:1, shape:'rect', area_on:true, area_name:'Deck'});
let d=true; try { c('draw'); } catch(e){ d=false; console.log('  '+e.message); }
ok('draw handles rooms and area tags together', d);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
