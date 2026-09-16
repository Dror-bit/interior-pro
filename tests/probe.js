const api = require('./run.js');
const g=(n)=>api.get(n), c=(n,...a)=>api.call(n,...a), s=(n,v)=>api.set(n,v);
s('walls',[]);s('pending',[]);s('ghosts',[]);s('guides',[]);s('sketches',[]);
s('pendingSketches',[]);s('curLine',null);s('scale',1);
// wall A: vertical, from (0,0) to (0,180), thickness 5, face-anchored left
const A={id:'A',sx:0,sy:0,ex:0,ey:180,th:5,ha:'left',cat:'exterior',ops:[],h:96};
s('pending',[A]);
const bq=c('bandQuad',A);
const C=c('endCorners',A,[A],bq);
console.log('band corners', JSON.stringify(C));
// he draws wall B from (120, 0) back to A's OUTER corner near y=0
const from={x:120,y:0};
[C.sp,C.sq,C.ep,C.eq].forEach(function(pt,i){
  const q=c('snapPoint',{x:pt.x,y:pt.y},from);
  const ang=Math.atan2(q.y-from.y,q.x-from.x)*180/Math.PI;
  console.log('corner'+i, JSON.stringify(pt), '-> q', JSON.stringify(q), 'ang', ang.toFixed(4));
});
