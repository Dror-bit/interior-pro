import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const box={};vm.createContext(box);vm.runInContext(fs.readFileSync(new URL('./kitchen_house_placement.js',import.meta.url),'utf8'),box);const H=box.KitchenHousePlacement;
function row(id,x,width,owner){const c={id,kind:owner?'filler':'microwave',width,depth:24,height:30,surround_for:owner};return H.rowAt({id,cabinet:c,base_z:0,height:30},{x,y:0,angle:0,handedness:1});}
const rows=[row('owner',1,30),row('left',0,1,'owner'),row('right',31,1,'owner')];
for(const r of rows){const group=H.bundle(r,rows);assert.equal(group.row.cabinet.width,32);assert.equal(group.members.length,3);
 const next=H.rowAt(group.row,{x:100,y:200,angle:90,handedness:1});const moved=H.moveBundle(group,next);assert.equal(moved.length,3);assert.equal(H.bundleError(moved,rows,[]),null);
 for(let i=0;i<3;i++){assert(Math.abs(moved[i].basis[0][0]-100)<1e-7);assert(Math.abs(moved[i].basis[0][1]-(200+rows[i].basis[0][0]))<1e-7);}
 const obstacle={...moved[0],id:'other',cabinet:{...moved[0].cabinet,id:'other'}};assert.equal(H.bundleError(moved,[...rows,obstacle],[]),'Cabinets overlap');
}
const single=H.bundle(row('single',80,24),rows);assert.equal(single.members.length,1);
console.log('PASS: selecting any part moves whole preview, uses exterior bounds, preserves rigid offsets and blocks collisions');
