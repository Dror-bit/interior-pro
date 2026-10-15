const fs=require('fs'),vm=require('vm'),assert=require('assert');
vm.runInThisContext(fs.readFileSync(__dirname+'/pantry_layout.js','utf8'));
vm.runInThisContext(fs.readFileSync(__dirname+'/cabinet_fronts.js','utf8'));
let count=0;
for(const top of ['single','double','lift'])for(const middle of ['single','double'])for(const bottom of ['combo_single','combo_double','drawers'])for(let n=1;n<=5;n++){
 const c={kind:'tall',width:30,height:90,depth:24,toe_height:4,pantry:{...PantryLayouts.defaults(),top,middle,bottom,drawers:n}};
 const rows=FrontLayouts.rows(c);assert(Math.abs(rows.reduce((v,r)=>v+r.height,0)+.125*(rows.length-1)-85.75)<1e-8);count++;
}
const a={category:'microwave',dimensions:{width:29.75,height:19.625,depth:21.75},cutout:{width:28.5,height:19.25,depth:19.25},appearance:{installation:'built_in'}};
const c={kind:'tall',width:30,height:90,depth:24,toe_height:4,pantry:{...PantryLayouts.defaults(),middle:'microwave',appliance:a}};
assert(PantryLayouts.fits(a,c,30,'microwave'));assert(!PantryLayouts.fits(a,{...c,width:16},30,'microwave'));assert(!PantryLayouts.fits(a,{...c,depth:18},30,'microwave'));assert(!PantryLayouts.fits(a,c,18,'microwave'));
assert(!PantryLayouts.fits({...a,cutout:null},c,30,'microwave'));
assert(!PantryLayouts.fits({...a,appearance:{door:'drawer'}},c,30,'microwave'));
assert(!PantryLayouts.fits({...a,appearance:{installation:'over_range'}},c,30,'microwave'));
assert.deepStrictEqual(FrontLayouts.rows(c),FrontLayouts.rows(JSON.parse(JSON.stringify(c))));
assert.throws(()=>FrontLayouts.rows({...c,width:16}));
const custom={...c,pantry:{...PantryLayouts.defaults(),bottom:'drawers',drawers:4,drawer_heights:[5,6,7,9.625]}};
assert.deepStrictEqual(FrontLayouts.rows(custom).filter(r=>r.zone==='bottom').map(r=>r.height),[5,6,7,9.625]);
assert.deepStrictEqual(FrontLayouts.rows(JSON.parse(JSON.stringify(custom))),FrontLayouts.rows(custom));
for(const heights of [[5,6,7,8],[5,6],[2,6,7,12.625]])assert.throws(()=>FrontLayouts.rows({...custom,pantry:{...custom.pantry,drawer_heights:heights}}));
console.log(count+' pantry layouts, incompatible sizes and JSON round trip passed');
