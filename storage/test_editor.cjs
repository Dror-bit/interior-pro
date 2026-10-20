const fs=require('fs'),vm=require('vm'),assert=require('assert');
const html=fs.readFileSync(__dirname+'/editor.html','utf8');
const script=html.match(/<script>([\s\S]*?)<\/script>/)[1];
class Element {
 constructor(){this.value='';this.options=[];this.disabled=false;this.attrs={};}
 replaceChildren(...items){this.options=items;}
 add(item){this.options.push(item);}
 append(...items){this.options.push(...items);}
 setAttribute(k,v){this.attrs[k]=v;}
 reportValidity(){return true;}
}
const elements={},messages=[];
const context=vm.createContext({document:{getElementById:id=>elements[id]??=(new Element()),createElement:()=>new Element()},Option:function(text,value){return {text,value};},window:{sketchup:{action:s=>messages.push(JSON.parse(s)),ready:()=>{}},addEventListener:()=>{}}});
vm.runInContext(script,context);
const run=s=>vm.runInContext(s,context);
run(`render({domain:'laundry',assembly_id:'one',revision:7,cabinets:[{id:'same',product_id:'base',width:30,height:34.5,depth:24,front:'double',style:'slab',finish:'white',handle:'none',position:{x:5,y:6,z:0,angle:90}}]},'same')`);
run(`send('save')`);
assert.deepStrictEqual([messages[0].domain,messages[0].assembly_id,messages[0].revision,messages[0].id],['laundry','one',7,'same']);
assert.deepStrictEqual(messages[0].values.position,{x:5,y:6,z:0,angle:90});
run(`switchMode('wardrobe')`);assert.equal(messages.at(-1).mode,'wardrobe');assert.equal(messages.at(-1).assembly,undefined);
run(`render({domain:'wardrobe',assembly_id:'main',revision:2,cabinets:[]})`);
assert.equal(elements.fields.disabled,false);assert.equal(elements.laundry.hidden,false);assert.equal(elements.wardrobe.hidden,false);
run(`preset('drawers');send('place')`);const wardrobe=messages.at(-1);assert.equal(wardrobe.domain,'wardrobe');assert.deepStrictEqual(wardrobe.values.sections.slice(0,4).map(s=>s.height),[7,7,7,7]);assert.equal(wardrobe.values.sections.reduce((n,s)=>n+s.height,0),78.5);assert.equal(wardrobe.values.front,'open');assert.equal(run(`inches(7.125)`),'7 1/8″');assert.equal(run(`JSON.stringify(divide(28,4))`),'[7,7,7,7]');assert.throws(()=>run(`divide(28,0)`));
run(`render({domain:'wardrobe',assembly_id:'main',revision:2,cabinets:[]},null,false)`);const count=messages.length;run(`send('place')`);assert.equal(messages.length,count,'Kill switch ignored');
run(`render({domain:'laundry',assembly_id:'two',revision:0,cabinets:[]})`);assert.equal(elements.cabinet.value,'');assert.equal(elements.save.disabled,true);
elements.assembly.value='second';run(`loadAssembly()`);assert.deepStrictEqual(messages.at(-1),{action:'switch',mode:'laundry',assembly:'second'});
run(`showError('<img src=x>')`);assert.equal(elements.error.textContent,'<img src=x>');
console.log('PASS: request identity/revision, position, wardrobe editing, exact drawer fractions/sums, kill switch, mode/design isolation, errors as text.');
