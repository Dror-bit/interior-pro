const fs=require('fs'),vm=require('vm'),assert=require('assert');
vm.runInThisContext(fs.readFileSync(process.argv[2]||require('path').join(__dirname,'kitchen_house_placement.js'),'utf8'));
const P=KitchenHousePlacement;
function make(id,kind,width,depth,h,z=0,flips={}){const c={kind,width,depth,...flips};return P.rowAt({id,cabinet:c,base_z:z,height:kind.includes('upper')?30:34.5},h);}
let count=0;
for(const kind of ['corner_base','corner_lazy','corner_upper'])for(const angle of [0,90,180,270,37])for(const mirror of [1,-1])for(const side of ['straight','return'])for(const withWall of [false,true])for(const flip of [false,true]){
 const a=angle*Math.PI/180,co=Math.cos(a),si=Math.sin(a),tx=117.25,ty=-86.75;
 const v=([x,y])=>[co*x-si*y*mirror,si*x+co*y*mirror];
 const p=q=>{const r=v(q);return [r[0]+tx,r[1]+ty]};
 const W=kind==='corner_upper'?24:38,D=kind==='corner_upper'?12:24,w=kind==='corner_upper'?18:9,z=kind==='corner_upper'?54:0;
 const corner=make('corner',kind,W,D,P.placement({width:W,depth:D},p([0,0]),v([1,0]),v([0,1])),z);
 const raw=side==='return'?[0,-W-w-.0752277180792]:[W+.0752277180792,0];
 const expected=p(side==='return'?[0,-W-w]:[W,0]);
 const x=side==='return'?[0,1]:[1,0],y=side==='return'?[-1,0]:[0,1];
 const c={width:w,depth:D,flip_x:flip,flip_y:false};
 const moving=make('moving',z?'wall':'doors',w,D,P.placement(c,p(raw),v(x),v(y)),z,{flip_x:flip});
 const wall=(id,s,e,corners)=>({id,sx:p(s)[0],sy:p(s)[1],ex:p(e)[0],ey:p(e)[1],corners:corners.flatMap(p),ops:[]});
 const walls=withWall?[wall('north',[-20,0],[140,0],[[-20,0],[-20,5],[140,5],[140,0]]),wall('west',[0,-160],[0,5],[[-5,-160],[0,-160],[0,5],[-5,5]])]:[];
 const r=P.propose(moving,[0,0],walls,1,[corner,moving]);
 assert(!r.error,JSON.stringify({kind,angle,mirror,side,withWall,flip,error:r.error}));
 const o=r.row.basis[0];
 const expectedPoly=[[0,0],[w,0],[w,-D],[0,-D]].map(([lx,ly])=>{const vx=v(x),vy=v(y);return [expected[0]+vx[0]*lx+vy[0]*ly,expected[1]+vx[1]*lx+vy[1]*ly]});
 assert(r.row.polygon.every(q=>expectedPoly.some(e=>Math.hypot(q[0]-e[0],q[1]-e[1])<1e-7)),JSON.stringify({kind,angle,mirror,side,withWall,flip,actual:o,expected,neighbor:r.neighbor}));
 assert.equal(r.neighbor,'corner');count++;
}
console.log('PASS '+count+' corner snap combinations: base/lazy/upper, both ends, rotations, mirrors, flipped doors, with/without walls');

