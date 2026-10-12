import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const box={};vm.createContext(box);vm.runInContext(fs.readFileSync('kitchen_house_placement.js','utf8'),box);const H=box.KitchenHousePlacement;
const wall={id:'north',sx:0,sy:0,ex:200,ey:0,corners:[0,0,200,0,200,4,0,4],ops:[]};
const c={id:'c',kind:'doors',width:36,depth:24,height:34.5,flip_x:false,flip_y:false},row={id:'c',cabinet:c,base_z:0,height:34.5,basis:[[40,-3],[41,-3],[40,-4]],polygon:[[40,-3],[76,-3],[76,-27],[40,-27]]};
let p=H.propose(row,[0,0],[wall],5);assert(p.snapped&&!p.error);assert(Math.abs(p.row.basis[0][1])<1e-8);assert(p.row.polygon.every(q=>q[1]<=1e-8));
const east={id:'east',sx:100,sy:-120,ex:100,ey:0,corners:[100,-120,104,-120,104,0,100,0],ops:[]};p=H.propose(row,[30,-50],[east],30);assert(p.snapped&&!p.error);assert.equal(p.placement.wall_id,'east');assert(Math.abs(p.row.polygon[0][0]-100)<1e-8);assert(p.row.polygon.every(q=>q[0]<=100.001));
let free=H.propose(row,[12,-40],[wall],5);assert(!free.snapped&&!free.error);assert(Math.abs(free.row.basis[0][0]-52)<1e-8);
assert(H.propose(row,[0,0],[{...wall,ops:[[58,36]]}],5).error.includes('Door'));
const other={...row,id:'other'};assert(H.propose(row,[0,0],[wall],5,[row,other]).error.includes('overlap'));
assert(!H.propose(row,[0,0],[wall],5,[row,{...other,base_z:54}]).error);
assert(!H.propose(row,[0,0],[{...wall,sag:5}],5).snapped);
for(const flip_x of [false,true])for(const flip_y of [false,true]){const r={...row,cabinet:{...c,flip_x,flip_y}};p=H.propose(r,[0,0],[wall],5);assert(!p.error);assert(Math.abs(p.row.basis[0][1])<1e-8);assert(Math.abs(p.row.basis[1][0]-p.row.basis[0][0]-1)<1e-8);}
console.log('PASS: wall faces, perpendicular transfer, free move, doors, cabinet overlap, vertical clearance, curved-wall exclusion and flipped axes.');
// Regression cases: edge magnets and pushing the cabinet towards the wall.
const neighbor=H.rowAt({...row,id:'neighbor',cabinet:{...c,id:'neighbor'}},{x:40,y:0,angle:0,handedness:1});
for(const x of [74,79]){const moving=H.rowAt(row,{x,y:-2,angle:0,handedness:1});const r=H.propose(moving,[0,0],[wall],5,[moving,neighbor]);assert(!r.error&&r.neighbor==='neighbor');assert(Math.abs(r.row.basis[0][0]-76)<1e-8);assert(Math.abs(r.row.basis[0][1])<1e-8);}
const left=H.rowAt(row,{x:6,y:-2,angle:0,handedness:1});const leftSnap=H.propose(left,[0,0],[wall],5,[left,neighbor]);assert(!leftSnap.error);assert(Math.abs(leftSnap.row.basis[0][0]-4)<1e-8);
const island=H.rowAt(neighbor,{x:40,y:-70,angle:0,handedness:1}),movingIsland=H.rowAt(row,{x:79,y:-72,angle:0,handedness:1});const islandSnap=H.propose(movingIsland,[0,0],[wall],5,[island,movingIsland]);assert(!islandSnap.error&&islandSnap.neighbor);assert(Math.abs(islandSnap.row.basis[0][0]-76)<1e-8);assert(Math.abs(islandSnap.row.basis[0][1]+70)<1e-8);
const pushed=H.propose(row,[0,13],[wall],5);assert(!pushed.error&&pushed.snapped);assert(Math.abs(pushed.row.basis[0][1])<1e-8);
console.log('PASS: neighbor attachment from both sides, small overlap recovery, island alignment and wall push capture.');
const entry=H.propose(H.rowAt(row,{x:79,y:-70,angle:0,handedness:1}),[0,0],[],5,[island]);assert(entry.neighbor);
const edge=H.rowAt(row,{x:82,y:-70,angle:0,handedness:1});assert(!H.propose(edge,[0,0],[],5,[island]).neighbor);assert(H.propose(edge,[0,0],[],5,[island],entry).neighbor);
assert(!H.propose(H.rowAt(row,{x:87,y:-70,angle:0,handedness:1}),[0,0],[],5,[island],entry).neighbor);
console.log('PASS: snap retains through boundary jitter and releases after deliberate movement.');
const windowWall={...wall,ops:[[58,36]],kitchen_openings:[[58,36,36,84,'window']]};
assert(!H.propose(row,[0,0],[windowWall],5).error);
assert(!H.propose({...row,height:36},[0,0],[windowWall],5).error);
assert.equal(H.propose({...row,height:37},[0,0],[windowWall],5).error,'Window is too low for this cabinet.');
assert(!H.propose({...row,base_z:84},[0,0],[windowWall],5).error);
assert(H.propose(row,[0,0],[{...windowWall,kitchen_openings:[[58,36,0,84,'door']]}],5).error.includes('Door'));
console.log('PASS: below-window placement, exact sill fit, low-window message, above opening and door blocking.');
const cornerRow={...row,cabinet:{...c,kind:'corner_base'}};
const cornerSnap=H.propose(cornerRow,[0,0],[wall],5);
assert(!cornerSnap.error&&cornerSnap.snapped);
assert.equal(Math.max(...cornerSnap.row.polygon.map(p=>p[1])),0);
assert.equal(Math.min(...cornerSnap.row.polygon.map(p=>p[1])),-36);
console.log('PASS: house corner uses full square footprint when snapping.');
const west={id:'west',sx:0,sy:-200,ex:0,ey:0,corners:[-4,-200,0,-200,0,0,-4,0],ops:[]};
const rotate=(p,a)=>[p[0]*Math.cos(a)-p[1]*Math.sin(a),p[0]*Math.sin(a)+p[1]*Math.cos(a)];
for(let turn=0;turn<4;turn++){
 const angle=turn*Math.PI/2;
 const walls=[wall,west].map(w=>{const s=rotate([w.sx,w.sy],angle),e=rotate([w.ex,w.ey],angle);return {...w,sx:s[0],sy:s[1],ex:e[0],ey:e[1],corners:w.corners.flatMap((v,i,ar)=>i%2?[]:rotate(ar.slice(i,i+2),angle))};});
 const moving=H.rowAt(cornerRow,{x:4,y:-5,angle:0,handedness:1});
 const r={...moving,basis:moving.basis.map(p=>rotate(p,angle)),polygon:moving.polygon.map(p=>rotate(p,angle))};
 const hit=H.propose(r,[0,0],walls,5);
 assert(hit.corner&&!hit.error,`Corner ${turn}: ${hit.error}`);
 assert(Math.hypot(...hit.row.basis[0])<1e-6);
 assert(hit.row.polygon.every(p=>{const q=rotate(p,-angle);return q[0]>=-.001&&q[1]<=.001;}));
}
const atCorner=H.rowAt(cornerRow,{x:3,y:-3,angle:0,handedness:1});
const doorWest={...west,ops:[[182,30]],kitchen_openings:[[182,30,0,84,'door']]};
assert(H.propose(atCorner,[0,0],[wall,doorWest],5).error);
console.log('PASS: two-wall corner snap in four orientations; second-wall door clearance.');
