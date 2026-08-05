const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('rooms',[]); s('pendingRooms',[]); s('mode','sel'); c('setDimMode','none'); }
function grab(fn){ global.__lines=0; global.__draw.length=0; fn(); return global.__lines; }
const wallWith=(kind)=>({id:'w1', sx:0,sy:0,ex:240,ey:0, th:6,h:96,ha:'left',cat:'exterior',ops:[[120,48]],
  corners:null, syms:[{id:'d1', body:'door', t:120, w:48, h:84, kind:kind, dtype:'', dcat:'interior', swing:'left', clicked:1, wtype:'', header:0}]});

reset(); g('walls').push(wallWith('opening'));
const nOpen = grab(()=>c('drawSyms', g('walls')[0]));
ok('a cased opening draws a symbol', nOpen > 0, nOpen);

reset(); g('walls').push(wallWith('door'));
const nDoor = grab(()=>c('drawSyms', g('walls')[0]));
ok('and it is simpler than a swing door', nOpen < nDoor, {opening:nOpen, door:nDoor});

reset(); g('walls').push(wallWith('window'));
ok('windows still draw', grab(()=>c('drawSyms', g('walls')[0])) > 0);
reset(); g('walls').push(wallWith('garage'));
ok('garage doors still draw', grab(()=>c('drawSyms', g('walls')[0])) > 0);
reset(); g('walls').push(wallWith('pocket'));
ok('pocket doors still draw', grab(()=>c('drawSyms', g('walls')[0])) > 0);

reset(); g('walls').push(wallWith('opening'));
let d=true; try { c('draw'); } catch(e){ d=false; console.log('  '+e.message); }
ok('draw survives a cased opening', d);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
