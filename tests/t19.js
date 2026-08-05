const api=require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
let fails=0; const ok=(n,cd,x)=>{console.log((cd?'PASS  ':'FAIL  ')+n+(cd?'':'   << '+JSON.stringify(x))); if(!cd)fails++;};
const near=(a,b,t)=>Math.abs(a-b)<=(t||0.05);
const calls=global.__calls;
function reset(){ s('sketches',[]); s('pendingSketches',[]); s('walls',[]); s('pending',[]); s('rooms',[]); s('pendingRooms',[]); s('lastPendSig',null); s('dimTags',[]); s('mode','sel'); calls.length=0; }
const W=(a,b,cc,d)=>({sx:a,sy:b,ex:cc,ey:d,th:6,h:96,ha:'left',cat:'exterior',ops:[],corners:null,syms:[]});
const wait=(ms)=>new Promise(r=>setTimeout(r,ms));

(async () => {
// a closed square of four blue walls asks Ruby for its area
reset();
g('pending').push(W(0,0,120,0), W(120,0,120,120), W(120,120,0,120), W(0,120,0,0));
c('updateStatus');
await wait(300);
const req = calls.filter(x=>x[0]==='preview_rooms').pop();
ok('the editor asked Ruby for a live area', !!req, calls.map(x=>x[0]));
if (req) {
  const rows = JSON.parse(req[1]).rows;
  ok('all four blue walls were sent', rows.length===4, rows.length);
  ok('each row carries what the maths needs', rows[0].sx!==undefined && rows[0].th===6 && rows[0].ha==='left', rows[0]);
}

// no repeat request while nothing changed
calls.length=0;
c('updateStatus'); c('updateStatus');
await wait(300);
ok('no repeat request when nothing moved', calls.filter(x=>x[0]==='preview_rooms').length===0, calls.map(x=>x[0]));

// moving a wall asks again
g('pending')[0].ex = 140;
c('updateStatus');
await wait(300);
ok('moving a wall asks again', calls.filter(x=>x[0]==='preview_rooms').length===1);

// the answer draws as a provisional area
c('loadPendingRooms', [{ pts:[3,3, 117,3, 117,117, 3,117], area:90.25 }]);
ok('preview stored', g('pendingRooms').length===1);
c('draw');
ok('draw survives a preview room', true);

// a preview sitting on a real room is not drawn twice
reset();
c('loadRooms', [{ id:'r1', name:'Kitchen', number:1, area:90, pts:[0,0, 120,0, 120,120, 0,120] }]);
c('loadPendingRooms', [{ pts:[0,0, 120,0, 120,120, 0,120], area:90 }]);
c('draw');
ok('only the real room label is clickable', g('dimTags').filter(t=>t.kind==='room').length===1,
   g('dimTags').map(t=>t.kind));

// clearing the blue walls clears the preview
reset();
g('pending').push(W(0,0,120,0));
c('updateStatus');
await wait(250);
s('pendingRooms', [{pts:[0,0,10,0,10,10,0,10], area:1}]);
s('pending', []);
c('updateStatus');
ok('no blue walls -> no preview', g('pendingRooms').length===0, g('pendingRooms').length);

console.log(fails?'\n*** '+fails+' FAILED ***':'\nALL PASS');
process.exit(fails?1:0);
})();
