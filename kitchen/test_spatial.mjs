import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const P=vm.runInNewContext(fs.readFileSync('placement.js','utf8')+';KitchenPlacement');
const c={id:'one',wall:'I',x:0,z:0,width:36,depth:24,height:34.5,kind:'doors'};
const close=(a,b)=>assert.ok(Math.abs(a-b)<1e-7,`${a} != ${b}`);
P.island={x:100,y:80,angle:90};
let p=P.point('I',36,-24);close(p[0],124);close(p[1],-44);
close(P.along('I',...p),36);
const adjacent={...c,id:'two',x:36};assert.equal(P.overlap(c,adjacent),false);
assert.equal(P.overlap(c,{...adjacent,x:35}),true);
assert.equal(P.overlap(c,{...c,z:54}),false);
P.pose={x:-200,y:50,z:106,angle:37,level:2};p=P.point('I',72,-24);close(P.along('I',...p),72);
assert.equal(P.overlap(c,adjacent),false);
assert.deepEqual(Array.from(P.point('A',3,-8,true)),[3,-8]);
// Ruby and JS must agree for arbitrary angles, reflections and floor poses.
const cases=[];
for(const angle of [0,30,45,90,180,-90,271])for(const wall of ['A','B','I']){
 P.island={x:48,y:84,angle};P.pose={x:-123,y:57,z:106,angle:23,level:2};
 const a={...c,wall,x:12},b={...c,id:'two',wall:'A',x:40};
 cases.push({settings:{island_x:48,island_y:84,island_angle:angle,kitchen_pose:P.pose},a,b,polygon:P.polygon(a),overlap:P.overlap(a,b)});
}
fs.mkdirSync('.kitchen-connection',{recursive:true});
fs.writeFileSync('.kitchen-connection/spatial-cases.json',JSON.stringify(cases));
console.log('Spatial tests passed: rotation, inverse drag, touching vs overlap, height separation, local preview.');
