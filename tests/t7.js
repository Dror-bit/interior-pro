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
c('toggleUnderLock');
ok('lock change saved', lastSave() && lastSave().locked===g('underLocked'), [lastSave(), g('underLocked')]);

// --- clearing hides everything ---
c('loadUnderlay', null);
ok('cleared', g('underImg')===null && els.underDot.style.display==='none' && els.underRow.style.display==='none');
calls.length=0; c('saveUnderlay');
ok('no save without an image', calls.filter(x=>x[0]==='save_underlay').length===0);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
