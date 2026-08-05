const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
function labelFor(room){
  s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('pendingRooms',[]); s('mode','sel');
  c('loadRooms',[room]);
  global.__draw.length=0; global.__rot=0;
  c('drawRooms');
  return global.__draw.map(d=>d.t);
}
const box=[0,0, 120,0, 120,120, 0,120];

let L = labelFor({id:'r1', name:'Room 1', number:1, area:100, pts:box});
ok('the default name is not doubled', L.includes('Room 1') && !L.some(t=>t.indexOf('Room 1  1')>=0), L);
L = labelFor({id:'r2', name:'Room 12', number:12, area:100, pts:box});
ok('two digit default is not doubled either', L.includes('Room 12'), L);
L = labelFor({id:'r3', name:'Kitchen', number:104, area:180, pts:box});
ok('a real name still shows the number', L.some(t=>t.indexOf('Kitchen')>=0 && t.indexOf('104')>=0), L);
L = labelFor({id:'r4', name:'Bedroom', number:0, area:120, pts:box});
ok('no number means no number', L.some(t=>t==='Bedroom'), L);
ok('the area is still there', L.some(t=>t.indexOf('SF')>=0), L);
L = labelFor({id:'r5', name:'Room 2', number:3, area:100, pts:box});
ok('a mismatched number is still shown', L.some(t=>t.indexOf('Room 2')>=0 && t.indexOf('3')>=0), L);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
