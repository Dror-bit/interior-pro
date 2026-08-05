const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('rooms',[]); s('pendingRooms',[]); s('mode','sel'); s('selList',[]); s('sel',null); c('setDimMode','both'); }
const WD=(ops)=>({sx:0,sy:0,ex:240,ey:0,th:6,h:96,ha:'left',cat:'exterior',ops:ops||[],corners:null,syms:[]});
// count line strokes as well as texts
function grab(fn){
  global.__draw.length=0; global.__rot=0; global.__lines = 0;
  const realStroke = global.__strokeCount;
  fn();
  return { texts: global.__draw.slice(), lines: global.__lines };
}

reset(); g('walls').push(WD([[60,36],[180,36]]));
let R = grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls')));
ok('dimension lines are drawn, not just numbers', R.lines > 10, R.lines);
ok('the numbers are still all there', R.texts.length >= 6, R.texts.map(t=>t.t));

// a plain wall gets one run: 1 line + 2 witness + 2 ticks = 5 strokes
reset(); g('walls').push(WD([]));
R = grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls')));
ok('a plain wall gets two runs, one per face', R.lines === 10, R.lines);
ok('with one number each', R.texts.length === 2, R.texts.map(t=>t.t));

// none draws nothing at all
c('setDimMode','none');
R = grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls')));
ok('none draws no lines either', R.lines === 0 && R.texts.length === 0, R);
c('setDimMode','out');
R = grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls')));
ok('outside only draws one run', R.lines === 5, R.lines);
c('setDimMode','in');
R = grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls')));
ok('inside only draws one run', R.lines === 5, R.lines);
c('setDimMode','both');

// the four labels on the switch
const fs=require('fs'), html=fs.readFileSync('out.html','utf8');
ok('the switch offers four choices', /dm_out/.test(html) && /dm_in/.test(html) && /dm_both/.test(html) && /dm_none/.test(html));
ok('the header wording is the new one', html.indexOf('כל המידות') > 0);

// numbers still add up to the face length
reset(); g('walls').push(WD([[60,36],[180,36]]));
R = grab(()=>c('dimLabel', g('walls')[0], '#1a6ee0', g('walls')));
const chainTexts = R.texts.map(t=>t.t);
ok('42 + 36 + 84 + 36 + 42 = 240', chainTexts.includes(c('fmtLen',42)) && chainTexts.includes(c('fmtLen',36)) &&
   chainTexts.includes(c('fmtLen',84)) && chainTexts.includes(c('fmtLen',240)), chainTexts);

let d=true; try { c('draw'); } catch(e){ d=false; console.log('  '+e.message); }
ok('draw survives real dimension lines', d);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
