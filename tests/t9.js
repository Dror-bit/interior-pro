const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const els=global.__els, fs=require('fs'), html=fs.readFileSync('out.html','utf8');

ok('HTML: guides box is a fold box', /id="guideBox" class="foldBox"/.test(html));
ok('HTML: guides start folded', /id="guideBody" class="foldBody" style="display:none"/.test(html));
ok('HTML: guides sit at the bottom, above the image box', html.indexOf('id="guideBox"') > html.indexOf('id="status"') && html.indexOf('id="guideBox"') < html.indexOf('id="underBox"'));
ok('HTML: the old genBox is gone', !html.includes('id="genBox"'));
ok('HTML: all boxes live in the pinned wrapper', /id="botWrap"/.test(html));
ok('HTML: the wall-dimension box is there too', /id="dimBox" class="foldBox"/.test(html));
ok('HTML: it starts folded', /id="dimBody" class="foldBody" style="display:none"/.test(html));

// seed the stub the way the HTML declares it
['guide','under','dim'].forEach(w => {
  document.getElementById(w+'Body').style.display='none';
  document.getElementById(w+'Caret').innerHTML='▾';
});
c('toggleFold','guide');
ok('guides open on click', els.guideBody.style.display==='' && els.guideCaret.innerHTML==='▴');
ok('the image box did NOT open with it', els.underBody.style.display==='none');
c('toggleFold','under');
ok('image box opens on its own', els.underBody.style.display==='');
// 2026-08-07: ONE helper panel at a time - opening one folds the other away
ok('opening the image box folds the guides away', els.guideBody.style.display==='none');
c('toggleFold','guide');
ok('guides open again', els.guideBody.style.display==='' && els.guideCaret.innerHTML==='▴');
ok('and the image box folded away in turn', els.underBody.style.display==='none');
c('toggleFold','guide');
ok('guides fold back', els.guideBody.style.display==='none' && els.guideCaret.innerHTML==='▾');

// the green dot marks a live guide
s('guides', []); s('guideMode', false); c('markGuideBox');
ok('no dot when nothing is set', els.guideDot.style.display==='none', els.guideDot.style.display);
c('toggleGuideMode');
ok('dot shows while guide mode is on', els.guideDot.style.display==='');
c('toggleGuideMode');
ok('dot hides when guide mode goes off', els.guideDot.style.display==='none');
c('setGuideAim','2pt');
c('guideClick',{x:0,y:0}); c('guideClick',{x:100,y:0});
ok('a drawn guide keeps the dot on', g('guides').length===1 && els.guideDot.style.display==='', {n:g('guides').length, d:els.guideDot.style.display});
if (g('guideMode')) c('toggleGuideMode');   // a direction button also arms guide mode
c('clearGuides');
ok('clearing turns the dot off', g('guides').length===0 && els.guideDot.style.display==='none');

// guides still work as snap targets
s('guides', [{x1:0,y1:0,x2:100,y2:0}]); s('walls',[]); s('pending',[]); s('sketches',[]); s('pendingSketches',[]);
const q=c('snapPoint',{x:0.4,y:0.4},null);
ok('a guide end is still a snap point', q.snapped===true && Math.abs(q.x)<0.05 && Math.abs(q.y)<0.05, q);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
