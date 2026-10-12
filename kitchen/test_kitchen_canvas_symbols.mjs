import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
let points=[],fills=[],saves=0,restores=0;
const ctx={save(){saves++},restore(){restores++},setLineDash(){},beginPath(){},moveTo(x,y){points.push([x,y])},lineTo(x,y){points.push([x,y])},closePath(){},fill(){fills.push(this.fillStyle)},stroke(){}};
const sandbox={window:{KP:{load(){sandbox.window.KP.draw()}}},ctx,activePage:0,sx:x=>x*2,sy:y=>-y*2};vm.createContext(sandbox);
vm.runInContext('(function(){'+fs.readFileSync('cabinet_fronts.js','utf8')+fs.readFileSync('kitchen_canvas_symbols.js','utf8')+'})();',sandbox);
const base={kind:'doors',width:36,depth:24,height:34.5,handle:'brass',finish:'ivory',z:0};
function load(c,basis=[[0,0],[1,0],[0,-1]]){points=[];sandbox.window.KP.load({cabinets:[{cabinet:c,basis}]});assert(points.every(p=>p.every(Number.isFinite)));assert.equal(saves,restores);return points.map(p=>p.slice());}
const a=load(base),b=load(base,[[100,200],[100,201],[101,200]]);assert.equal(a.length,b.length);a.forEach((p,i)=>{assert(Math.abs(b[i][0]-(200+p[1]))<1e-7);assert(Math.abs(b[i][1]-(-400-p[0]))<1e-7)});
assert(a.length>40,'Door swings and handles missing');
for(const kind of ['drawers','corner_base','corner_upper','oven','fridge','dishwasher','hood','microwave'])load({...base,kind});
load({...base,kind:'sink',sink:{type:'double',faucet:'arched'}});assert(fills.includes('#82969e'));
load({...base,kind:'doors',appliance_parts:[{shape:'cylinder',x:2,y:-8,width:4,depth:4,color:'#123456'}]});assert(fills.includes('#123456'));
sandbox.activePage=1;points=[];sandbox.window.KP.draw();assert.equal(points.length,0);
console.log('PASS: detailed symbols, shared front layouts, rotated world projection, sink/appliance parts, finite points, house-page isolation.');
sandbox.activePage=0;
sandbox.window.KitchenShowDoorSwings=false;const without=load(base);
sandbox.window.KitchenShowDoorSwings=true;const withSwings=load(base);
assert(withSwings.length>without.length,'Swing toggle did not change rendering');
sandbox.window.KitchenShowDoorSwings=false;assert.equal(load(base).length,without.length);
console.log('PASS: opening marks toggle on/off while cabinet and hardware remain.');
const signatures=[];
for(const category of ['range','cooktop','fridge','dishwasher','hood','wall_oven','microwave']){
 const item={...base,kind:category==='range'?'oven':category==='cooktop'?'doors':category,appliance:{category,dimensions:{width:30,depth:21,height:4}}};
 const original=JSON.stringify(item),normal=load(item),turned=load(item,[[100,200],[100,201],[101,200]]);
 assert.equal(normal.length,turned.length);normal.forEach((p,i)=>{assert(Math.abs(turned[i][0]-(200+p[1]))<1e-7);assert(Math.abs(turned[i][1]-(-400-p[0]))<1e-7);});
 assert.equal(JSON.stringify(item),original,'Rendering changed model');signatures.push(JSON.stringify(normal));
 if(category==='hood'){fills=[];load(item);assert.equal(fills.length,0,'Overhead hood obscures range');}
}
assert.equal(new Set(signatures).size,7,'Appliance categories are visually identical');
console.log('PASS: seven distinct plan symbols; rotation, immutable data and transparent overhead hood.');
