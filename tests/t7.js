const api = require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||1e-6);
const els=global.__els, calls=global.__calls;
const lastSave=()=>{ const k=calls.filter(x=>x[0]==='save_underlay').pop(); return k?JSON.parse(k[1]):null; };

// --- folding panel --- (seed the stub from what the HTML declares)
const fs=require('fs'); const html=fs.readFileSync('out.html','utf8');
ok('HTML: body starts hidden', /id="underBody" class="foldBody" style="display:none"/.test(html));
ok('HTML: caret starts down', /id="underCaret" class="caret">\u25be</.test(html));
ok('HTML: underBox sits after status', html.indexOf('id="underBox"') > html.indexOf('id="status"'));
ok('HTML: undo comes last', html.indexOf('id="undoWrap"') > html.indexOf('id="underBox"'));
document.getElementById('underBody').style.display='none';
document.getElementById('underCaret').innerHTML='\u25be';
document.getElementById('guideBody').style.display='none';
document.getElementById('guideCaret').innerHTML='\u25be';
c('toggleUnderBox');
ok('opens', els.underBody.style.display==='' && els.underCaret.innerHTML==='▴');
c('toggleUnderBox');
ok('folds', els.underBody.style.display==='none');

// --- fresh image: fits and saves the fit ---
calls.length=0;
c('loadUnderlay','data:image/png;base64,xx');
ok('image loaded', !!g('underImg'));
ok('marker dot shown', els.underDot.style.display==='', els.underDot.style.display);
ok('controls revealed', els.underRow.style.display==='');
let sv=lastSave();
ok('initial fit is saved', !!sv && sv.scale>0, sv);

// --- calibration doubles the size, locks, and saves ---
const before=g('underScale');
global.prompt=()=>'20';           // real distance = 20 in for a 10 in gap
c('startCalib');
c('calibClick',{x:0,y:0});
c('calibClick',{x:10,y:0});
ok('scale doubled', near(g('underScale'), before*2, 1e-9), {before, after:g('underScale')});
ok('auto locked', g('underLocked')===true);
sv=lastSave();
ok('calibration saved', sv && near(sv.scale, before*2, 1e-9) && sv.locked===true, sv);
const saved={x:sv.x, y:sv.y, scale:sv.scale, opacity:sv.opacity, locked:sv.locked};

// --- reopen: the SAME placement comes back, no re-fit ---
s('underImg', null); s('underScale', 1); s('underX', 0); s('underY', 0); s('underLocked', false);
c('loadUnderlay','data:image/png;base64,xx', saved);
ok('scale restored', near(g('underScale'), saved.scale), {got:g('underScale'), want:saved.scale});
ok('position restored', near(g('underX'), saved.x) && near(g('underY'), saved.y), [g('underX'), g('underY')]);
ok('lock restored', g('underLocked')===true);

// --- reopen with NO placement (new image) -> re-fits ---
s('underImg', null);
c('loadUnderlay','data:image/png;base64,yy', null);
ok('no placement -> re-fits', !near(g('underScale'), saved.scale), g('underScale'));

// --- opacity + lock changes are saved ---
calls.length=0;
c('setUnderOpacity', 30);
ok('opacity saved', lastSave() && near(lastSave().opacity, 0.30), lastSave());
// The image is an ORDINARY object while its panel is open (2026-08-07):
// no lock button, no flip buttons, no rotation box - Select's own tools.
c('setUnderRotation', 30);
ok('a typed angle is saved', lastSave() && near(lastSave().rot, 30), lastSave());
c('setUnderRotation', 0);
s('scale', 1);
c('loadUnderlay','data:image/png;base64,zz',{x:0,y:0,scale:0.2,opacity:0.5,rot:0});
c('toggleFold','under',false);
ok('panel closed = the image is locked', g('underLocked')===true);
ok('a locked image is not pickable', c('hitUnderlay',{x:100,y:-80})===null);
c('toggleFold','under',true);
ok('panel open = the image is live', g('underLocked')===false);
ok('an open image IS pickable', c('hitUnderlay',{x:100,y:-80})!==null);
ok('outside the image is still empty canvas', c('hitUnderlay',{x:900,y:-80})===null);
c('setMode','sel'); s('selList',[{type:'under'}]); s('sel',{type:'under'});
c('startFreeMove'); c('moveApply',50,20);
ok('the image moves with the normal Move tool',
   near(g('underX'),50) && near(g('underY'),20), [g('underX'),g('underY')]);
c('moveCommit');
c('startFreeRotate');
ok('the image accepts the normal Rotate tool', g('rotOp')!==null && g('rotOp').ub!==null);
c('rotCentre',{x:150,y:-60}); c('rotApply', Math.PI/2);
ok('rotating turns the image 90 degrees', near(g('underRot'),90), g('underRot'));
c('rotCancel');
ok('cancel puts the angle back', near(g('underRot'),0), g('underRot'));
s('selList',[{type:'under'}]); s('sel',{type:'under'});
c('toggleFold','under',false);
ok('closing the panel deselects AND locks',
   g('underLocked')===true && g('sel')===null, [g('underLocked'), g('sel')]);
c('toggleFold','under',true);

// sending the traced image into the 3D model (2026-08-07) - optional
s('scale', 1);
c('loadUnderlay','data:image/png;base64,zz',{x:10, y:400, scale:0.2, opacity:0.5, rot:30});
calls.length = 0;
c('sendUnderlayTo3D');
const sendCall = calls.filter(function(x){ return x[0]==='place_underlay_3d'; })[0];
ok('the send button reaches Ruby', !!sendCall);
const sendArg = sendCall ? JSON.parse(sendCall[1]) : {};
ok('it passes the size in real inches',
   near(sendArg.w, 200) && near(sendArg.h, 160), sendArg);
ok('it passes the corner and the angle',
   sendArg.x===10 && sendArg.y===400 && sendArg.rot===30, sendArg);
// an image parked outside the view walks itself back in, scale untouched
c('loadUnderlay','data:image/png;base64,zz',
  {x:900000, y:900000, scale:0.2, opacity:0.5, locked:true, rot:0});
ok('an off-screen image is pulled back into view', Math.abs(g('underX')) < 100000, g('underX'));
ok('and its scale is untouched', near(g('underScale'), 0.2), g('underScale'));

// --- clearing hides everything ---
c('loadUnderlay', null);
ok('cleared', g('underImg')===null && els.underDot.style.display==='none' && els.underRow.style.display==='none');
calls.length=0; c('saveUnderlay');
ok('no save without an image', calls.filter(x=>x[0]==='save_underlay').length===0);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
